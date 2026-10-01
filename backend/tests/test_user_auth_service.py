"""Tests for require_user() in app/services/user_auth_service.py - the
lighter-weight auth gate used by routes any signed-in parent/child account
may call (currently /alerts/notify), as opposed to require_admin's
admin-only gate. Deliberately mirrors test_admin_auth_service.py's cases
for the shared branches, plus the one behavior that's supposed to differ:
require_user must NOT reject a token just because it lacks admin claims.

firebase_admin.auth.verify_id_token and initialize_firebase are mocked -
no real Firebase project is touched.
"""
from __future__ import annotations

from unittest.mock import patch

import pytest
from fastapi import HTTPException
from fastapi.security import HTTPAuthorizationCredentials
from firebase_admin import auth

from app.services import user_auth_service as svc


def _creds(token: str = "some-token") -> HTTPAuthorizationCredentials:
    return HTTPAuthorizationCredentials(scheme="Bearer", credentials=token)


class TestRequireUser:
    def test_missing_credentials_returns_401(self):
        with pytest.raises(HTTPException) as exc_info:
            svc.require_user(credentials=None)

        assert exc_info.value.status_code == 401

    def test_revoked_token_returns_401_with_specific_message(self):
        with patch.object(svc, "initialize_firebase"), patch.object(
            svc.auth,
            "verify_id_token",
            side_effect=auth.RevokedIdTokenError("revoked"),
        ):
            with pytest.raises(HTTPException) as exc_info:
                svc.require_user(credentials=_creds())

        assert exc_info.value.status_code == 401
        assert "revoked" in exc_info.value.detail.lower()

    def test_unparseable_token_returns_401(self):
        with patch.object(svc, "initialize_firebase"), patch.object(
            svc.auth, "verify_id_token", side_effect=ValueError("bad token")
        ):
            with pytest.raises(HTTPException) as exc_info:
                svc.require_user(credentials=_creds())

        assert exc_info.value.status_code == 401

    def test_valid_token_without_any_admin_claim_still_succeeds(self):
        # This is the whole reason require_user exists separately from
        # require_admin: an ordinary parent/child account has no "admin"
        # or "role" claim at all and must still be let through.
        with patch.object(svc, "initialize_firebase"), patch.object(
            svc.auth, "verify_id_token", return_value={"uid": "child-1"}
        ):
            result = svc.require_user(credentials=_creds())

        assert result == {"uid": "child-1"}

    def test_verify_id_token_is_called_with_check_revoked_true(self):
        with patch.object(svc, "initialize_firebase"), patch.object(
            svc.auth, "verify_id_token", return_value={"uid": "u1"}
        ) as mock_verify:
            svc.require_user(credentials=_creds("tok-456"))

        mock_verify.assert_called_once_with("tok-456", check_revoked=True)
