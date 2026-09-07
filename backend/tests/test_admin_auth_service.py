"""Covers require_admin() - the gate every /admin/* route sits behind.

This is the highest-value place in the backend to have tests: it's the
one function standing between an unauthenticated/non-admin caller and
every admin action (list/create/update/delete users, revoke sessions,
read logs, change system settings). The check_revoked=True branch tested
here is also the exact fix applied earlier in this project's
reconciliation work - a regression here would silently let a
disabled/deleted admin's already-issued token keep working for up to an
hour, which is precisely the bug that fix closed.
"""

from __future__ import annotations

from unittest.mock import MagicMock

import pytest
from fastapi import HTTPException
from fastapi.security import HTTPAuthorizationCredentials

from app.services import admin_auth_service


@pytest.fixture(autouse=True)
def _stub_initialize_firebase(monkeypatch: pytest.MonkeyPatch) -> None:
    # require_admin() calls initialize_firebase() before verifying the
    # token - stub it out so tests never attempt a real Firebase Admin
    # SDK initialization (no service account exists on this machine, and
    # every test in this file wants the fake auth.verify_id_token below).
    monkeypatch.setattr(admin_auth_service, "initialize_firebase", MagicMock())


def _credentials(token: str = "fake-token") -> HTTPAuthorizationCredentials:
    return HTTPAuthorizationCredentials(scheme="Bearer", credentials=token)


def test_require_admin_rejects_missing_credentials():
    with pytest.raises(HTTPException) as exc_info:
        admin_auth_service.require_admin(credentials=None)

    assert exc_info.value.status_code == 401
    assert exc_info.value.detail == "Authentication required"


def test_require_admin_passes_check_revoked_true(fake_auth_module: MagicMock):
    # The whole point of the fix this test guards: verify_id_token must be
    # called with check_revoked=True, not just a bare token check, or a
    # revoked/disabled admin's still-valid-by-signature token keeps
    # passing this gate.
    fake_auth_module.verify_id_token.return_value = {"admin": True}

    admin_auth_service.require_admin(credentials=_credentials("tok-123"))

    fake_auth_module.verify_id_token.assert_called_once_with(
        "tok-123",
        check_revoked=True,
    )


def test_require_admin_accepts_admin_claim_true(fake_auth_module: MagicMock):
    fake_auth_module.verify_id_token.return_value = {
        "admin": True,
        "uid": "admin-uid",
    }

    decoded = admin_auth_service.require_admin(credentials=_credentials())

    assert decoded["uid"] == "admin-uid"


def test_require_admin_accepts_role_admin(fake_auth_module: MagicMock):
    # Two independent ways a token can prove admin-ness (legacy `admin`
    # boolean claim vs. newer `role` string claim) - both must work.
    fake_auth_module.verify_id_token.return_value = {"role": "admin"}

    decoded = admin_auth_service.require_admin(credentials=_credentials())

    assert decoded["role"] == "admin"


def test_require_admin_rejects_non_admin_user(fake_auth_module: MagicMock):
    fake_auth_module.verify_id_token.return_value = {
        "admin": False,
        "role": "user",
    }

    with pytest.raises(HTTPException) as exc_info:
        admin_auth_service.require_admin(credentials=_credentials())

    assert exc_info.value.status_code == 403
    assert exc_info.value.detail == "Administrator access required"


def test_require_admin_rejects_token_with_no_admin_claims_at_all(
    fake_auth_module: MagicMock,
):
    # A validly-signed token that simply never had admin/role claims set -
    # must be treated the same as an explicit False, not as a KeyError.
    fake_auth_module.verify_id_token.return_value = {"uid": "some-user"}

    with pytest.raises(HTTPException) as exc_info:
        admin_auth_service.require_admin(credentials=_credentials())

    assert exc_info.value.status_code == 403


def test_require_admin_reports_revoked_token_distinctly(
    fake_auth_module: MagicMock,
):
    # This is the specific regression this test file exists to guard:
    # RevokedIdTokenError must produce its own message telling the caller
    # to sign in again, not be swallowed by the generic
    # "invalid or expired" branch below.
    fake_auth_module.verify_id_token.side_effect = (
        fake_auth_module.RevokedIdTokenError("revoked")
    )

    with pytest.raises(HTTPException) as exc_info:
        admin_auth_service.require_admin(credentials=_credentials())

    assert exc_info.value.status_code == 401
    assert exc_info.value.detail == (
        "This session has been revoked. Please sign in again."
    )


def test_require_admin_reports_generic_verification_failure(
    fake_auth_module: MagicMock,
):
    fake_auth_module.verify_id_token.side_effect = ValueError("bad token")

    with pytest.raises(HTTPException) as exc_info:
        admin_auth_service.require_admin(credentials=_credentials())

    assert exc_info.value.status_code == 401
    assert exc_info.value.detail == "Invalid or expired authentication token"
