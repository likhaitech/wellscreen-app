"""Covers user_admin_service.py - specifically the revoke-before-disable
and revoke-before-delete fixes (see the FIX comments in the source): an
admin "disable" or "delete" action must invalidate any already-issued ID
token immediately, not just stop new ones from being minted. A regression
here silently reopens the "disabled account still has up to an hour of
access" bug the fix closed.
"""

from __future__ import annotations

from typing import Any
from unittest.mock import MagicMock

import pytest

from app.services import user_admin_service


class _FakeUserRecord:
    """Minimal stand-in for firebase_admin.auth.UserRecord."""

    def __init__(
        self,
        uid: str = "uid-1",
        email: str = "user@example.com",
        disabled: bool = False,
        custom_claims: dict[str, Any] | None = None,
    ):
        self.uid = uid
        self.email = email
        self.display_name = "Test User"
        self.disabled = disabled
        self.email_verified = True
        self.custom_claims = custom_claims
        self.user_metadata = None


@pytest.fixture(autouse=True)
def _stub_initialize_firebase(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(user_admin_service, "initialize_firebase", MagicMock())


@pytest.fixture(autouse=True)
def _stub_firestore(monkeypatch: pytest.MonkeyPatch, fake_firestore) -> None:
    monkeypatch.setattr(
        user_admin_service, "get_firestore_client", lambda: fake_firestore
    )


def test_update_user_disabling_revokes_refresh_tokens(
    fake_auth_module: MagicMock,
):
    fake_auth_module.get_user.return_value = _FakeUserRecord(disabled=True)

    user_admin_service.update_user("uid-1", disabled=True)

    fake_auth_module.revoke_refresh_tokens.assert_called_once_with("uid-1")


def test_update_user_enabling_does_not_revoke_tokens(fake_auth_module: MagicMock):
    fake_auth_module.get_user.return_value = _FakeUserRecord(disabled=False)

    user_admin_service.update_user("uid-1", disabled=False)

    fake_auth_module.revoke_refresh_tokens.assert_not_called()


def test_update_user_with_no_disabled_argument_does_not_revoke_tokens(
    fake_auth_module: MagicMock,
):
    # disabled=None (the default / "not being changed") must not be
    # treated as disabled=False-triggers-nothing vs. accidentally
    # treated as truthy - this pins `disabled is True` specifically.
    fake_auth_module.get_user.return_value = _FakeUserRecord()

    user_admin_service.update_user("uid-1", display_name="New Name")

    fake_auth_module.revoke_refresh_tokens.assert_not_called()
    fake_auth_module.update_user.assert_called_once_with(
        "uid-1", display_name="New Name"
    )


def test_update_user_setting_role_admin_sets_matching_claims(
    fake_auth_module: MagicMock,
):
    fake_auth_module.get_user.return_value = _FakeUserRecord(custom_claims=None)

    user_admin_service.update_user("uid-1", role="admin")

    fake_auth_module.set_custom_user_claims.assert_called_once_with(
        "uid-1", {"role": "admin", "admin": True}
    )


def test_update_user_setting_role_non_admin_clears_admin_flag(
    fake_auth_module: MagicMock,
):
    fake_auth_module.get_user.return_value = _FakeUserRecord(
        custom_claims={"role": "admin", "admin": True}
    )

    user_admin_service.update_user("uid-1", role="user")

    fake_auth_module.set_custom_user_claims.assert_called_once_with(
        "uid-1", {"role": "user", "admin": False}
    )


def test_update_user_writes_firestore_mirror_with_merge(
    fake_auth_module: MagicMock, fake_firestore
):
    fake_auth_module.get_user.return_value = _FakeUserRecord(
        email="new@example.com"
    )

    user_admin_service.update_user(
        "uid-1", email="new@example.com", disabled=True
    )

    doc_ref = fake_firestore.collection("users").document("uid-1")
    set_calls = [call for call in doc_ref.calls if call[0] == "set"]

    assert len(set_calls) == 1
    written = set_calls[0][1]["data"]
    assert set_calls[0][1]["merge"] is True
    assert written["email"] == "new@example.com"
    assert written["disabled"] is True


def test_delete_user_revokes_tokens_before_deleting(fake_auth_module: MagicMock):
    call_order: list[str] = []

    fake_auth_module.revoke_refresh_tokens.side_effect = (
        lambda uid: call_order.append("revoke")
    )
    fake_auth_module.delete_user.side_effect = (
        lambda uid: call_order.append("delete")
    )

    user_admin_service.delete_user("uid-1")

    # Order matters here, not just that both were called: revoking after
    # delete would be a no-op (the account and its tokens are already
    # gone), so this pins revoke-then-delete specifically.
    assert call_order == ["revoke", "delete"]


def test_delete_user_removes_firestore_mirror(
    fake_auth_module: MagicMock, fake_firestore
):
    user_admin_service.delete_user("uid-1")

    doc_ref = fake_firestore.collection("users").document("uid-1")
    assert ("delete", None) in doc_ref.calls


def test_create_user_sets_admin_claim_false_for_default_role(
    fake_auth_module: MagicMock,
):
    fake_auth_module.create_user.return_value = _FakeUserRecord(uid="new-uid")
    fake_auth_module.get_user.return_value = _FakeUserRecord(uid="new-uid")

    user_admin_service.create_user(
        email="new@example.com", password="password123"
    )

    fake_auth_module.set_custom_user_claims.assert_called_once_with(
        "new-uid", {"role": "user", "admin": False}
    )


def test_create_user_writes_firestore_profile(
    fake_auth_module: MagicMock, fake_firestore
):
    fake_auth_module.create_user.return_value = _FakeUserRecord(
        uid="new-uid", email="new@example.com"
    )
    fake_auth_module.get_user.return_value = _FakeUserRecord(
        uid="new-uid", email="new@example.com"
    )

    user_admin_service.create_user(
        email="new@example.com",
        password="password123",
        display_name="New Person",
        role="admin",
    )

    doc_ref = fake_firestore.collection("users").document("new-uid")
    set_calls = [call for call in doc_ref.calls if call[0] == "set"]

    assert len(set_calls) == 1
    written = set_calls[0][1]["data"]
    assert written["uid"] == "new-uid"
    assert written["role"] == "admin"
    assert written["fullName"] == "New Person"
