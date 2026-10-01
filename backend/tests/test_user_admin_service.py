"""Tests for app/services/user_admin_service.py - backs all of
/admin/users. The behaviors worth pinning down here aren't the CRUD
plumbing itself but the two security-relevant FIXes documented inline in
the source: disabling a user or deleting a user must call
auth.revoke_refresh_tokens() so an already-issued token stops working
immediately (see admin_auth_service/user_auth_service's check_revoked=True,
tested separately) - without this, "disable" is close to a no-op for up to
an hour. Also covers create_user's custom-claims + Firestore write, and
that update_user only touches the fields it was actually given.

firebase_admin.auth and the Firestore client are both mocked - no real
Firebase project is touched.
"""
from __future__ import annotations

from unittest.mock import MagicMock, patch

from app.services import user_admin_service as svc


def _fake_user_record(
    uid="u1",
    email="user@example.com",
    display_name="Some User",
    disabled=False,
    email_verified=True,
    custom_claims=None,
):
    record = MagicMock()
    record.uid = uid
    record.email = email
    record.display_name = display_name
    record.disabled = disabled
    record.email_verified = email_verified
    record.custom_claims = custom_claims
    record.user_metadata.creation_timestamp = 1000
    record.user_metadata.last_sign_in_timestamp = 2000
    return record


class TestListUsers:
    def test_serializes_every_user_from_iterate_all(self):
        page = MagicMock()
        page.iterate_all.return_value = [
            _fake_user_record(uid="u1"),
            _fake_user_record(uid="u2", custom_claims={"role": "admin", "admin": True}),
        ]

        with patch.object(svc, "initialize_firebase"), patch.object(
            svc.auth, "list_users", return_value=page
        ):
            result = svc.list_users()

        assert [u["uid"] for u in result] == ["u1", "u2"]
        assert result[0]["role"] == "user"  # no custom_claims -> defaults to "user"
        assert result[1]["role"] == "admin"


class TestGetUser:
    def test_serializes_role_from_custom_claims(self):
        record = _fake_user_record(custom_claims={"role": "admin"})

        with patch.object(svc, "initialize_firebase"), patch.object(
            svc.auth, "get_user", return_value=record
        ):
            result = svc.get_user("u1")

        assert result["uid"] == "u1"
        assert result["role"] == "admin"
        assert result["created_at"] == 1000
        assert result["last_sign_in_at"] == 2000


class TestCreateUser:
    def test_sets_custom_claims_matching_requested_role(self):
        created = _fake_user_record(uid="new-uid")
        fetched = _fake_user_record(uid="new-uid", custom_claims={"role": "admin", "admin": True})
        fake_db = MagicMock()

        with patch.object(svc, "initialize_firebase"), patch.object(
            svc.auth, "create_user", return_value=created
        ), patch.object(svc.auth, "set_custom_user_claims") as mock_claims, patch.object(
            svc, "get_firestore_client", return_value=fake_db
        ), patch.object(
            svc.auth, "get_user", return_value=fetched
        ):
            result = svc.create_user(
                email="new@example.com",
                password="secret123",
                display_name="New User",
                role="admin",
            )

        mock_claims.assert_called_once_with("new-uid", {"role": "admin", "admin": True})
        assert result["role"] == "admin"

    def test_default_role_is_user_with_admin_false(self):
        created = _fake_user_record(uid="new-uid")
        fake_db = MagicMock()

        with patch.object(svc, "initialize_firebase"), patch.object(
            svc.auth, "create_user", return_value=created
        ), patch.object(svc.auth, "set_custom_user_claims") as mock_claims, patch.object(
            svc, "get_firestore_client", return_value=fake_db
        ), patch.object(svc.auth, "get_user", return_value=created):
            svc.create_user(email="new@example.com", password="secret123")

        mock_claims.assert_called_once_with("new-uid", {"role": "user", "admin": False})

    def test_firestore_write_failure_deletes_the_orphaned_auth_account(self):
        # FIX: auth.create_user() already created the Auth account before
        # this Firestore write runs. Without cleanup, a failure here left
        # that account permanently orphaned - no Firestore doc, but the
        # email already taken (a retry would 409 "email already exists").
        created = _fake_user_record(uid="new-uid", email="new@example.com")
        fake_db = MagicMock()
        fake_db.collection.return_value.document.return_value.set.side_effect = (
            RuntimeError("firestore unavailable")
        )

        with patch.object(svc, "initialize_firebase"), patch.object(
            svc.auth, "create_user", return_value=created
        ), patch.object(svc.auth, "set_custom_user_claims"), patch.object(
            svc, "get_firestore_client", return_value=fake_db
        ), patch.object(svc.auth, "delete_user") as mock_delete:
            try:
                svc.create_user(email="new@example.com", password="secret123")
                raised = False
            except RuntimeError:
                raised = True

        assert raised, "the original error must still propagate"
        mock_delete.assert_called_once_with("new-uid")

    def test_custom_claims_failure_also_deletes_the_orphaned_auth_account(self):
        created = _fake_user_record(uid="new-uid", email="new@example.com")

        with patch.object(svc, "initialize_firebase"), patch.object(
            svc.auth, "create_user", return_value=created
        ), patch.object(
            svc.auth,
            "set_custom_user_claims",
            side_effect=RuntimeError("claims service unavailable"),
        ), patch.object(
            svc, "get_firestore_client", return_value=MagicMock()
        ), patch.object(svc.auth, "delete_user") as mock_delete:
            try:
                svc.create_user(email="new@example.com", password="secret123")
            except RuntimeError:
                pass

        mock_delete.assert_called_once_with("new-uid")

    def test_writes_a_users_firestore_document(self):
        created = _fake_user_record(uid="new-uid", email="new@example.com")
        fake_db = MagicMock()

        with patch.object(svc, "initialize_firebase"), patch.object(
            svc.auth, "create_user", return_value=created
        ), patch.object(svc.auth, "set_custom_user_claims"), patch.object(
            svc, "get_firestore_client", return_value=fake_db
        ), patch.object(svc.auth, "get_user", return_value=created):
            svc.create_user(
                email="new@example.com", password="secret123", role="user", disabled=False
            )

        fake_db.collection.assert_called_once_with("users")
        fake_db.collection.return_value.document.assert_called_once_with("new-uid")
        written = fake_db.collection.return_value.document.return_value.set.call_args[0][0]
        assert written["uid"] == "new-uid"
        assert written["email"] == "new@example.com"
        assert written["role"] == "user"


class TestUpdateUser:
    def test_only_provided_fields_are_sent_to_auth_update_user(self):
        with patch.object(svc, "initialize_firebase"), patch.object(
            svc.auth, "update_user"
        ) as mock_update, patch.object(
            svc.auth, "get_user", return_value=_fake_user_record()
        ), patch.object(svc, "get_firestore_client", return_value=MagicMock()):
            svc.update_user("u1", display_name="Renamed")

        mock_update.assert_called_once_with("u1", display_name="Renamed")

    def test_no_changes_at_all_does_not_call_auth_update_user(self):
        with patch.object(svc, "initialize_firebase"), patch.object(
            svc.auth, "update_user"
        ) as mock_update, patch.object(
            svc.auth, "get_user", return_value=_fake_user_record()
        ), patch.object(svc, "get_firestore_client", return_value=MagicMock()):
            svc.update_user("u1")

        mock_update.assert_not_called()

    def test_role_change_preserves_other_existing_custom_claims(self):
        current = _fake_user_record(custom_claims={"role": "user", "admin": False, "extra": "keep-me"})

        with patch.object(svc, "initialize_firebase"), patch.object(
            svc.auth, "update_user"
        ), patch.object(
            svc.auth, "get_user", return_value=current
        ), patch.object(
            svc.auth, "set_custom_user_claims"
        ) as mock_claims, patch.object(
            svc, "get_firestore_client", return_value=MagicMock()
        ):
            svc.update_user("u1", role="admin")

        mock_claims.assert_called_once_with(
            "u1", {"role": "admin", "admin": True, "extra": "keep-me"}
        )

    def test_disabling_a_user_revokes_refresh_tokens(self):
        # This is the security-relevant FIX documented in the source:
        # disabling alone doesn't stop an already-issued token for up to an
        # hour, so revoke_refresh_tokens must be called too.
        with patch.object(svc, "initialize_firebase"), patch.object(
            svc.auth, "update_user"
        ), patch.object(
            svc.auth, "get_user", return_value=_fake_user_record(disabled=True)
        ), patch.object(
            svc.auth, "revoke_refresh_tokens"
        ) as mock_revoke, patch.object(
            svc, "get_firestore_client", return_value=MagicMock()
        ):
            svc.update_user("u1", disabled=True)

        mock_revoke.assert_called_once_with("u1")

    def test_enabling_or_leaving_disabled_untouched_does_not_revoke(self):
        with patch.object(svc, "initialize_firebase"), patch.object(
            svc.auth, "update_user"
        ), patch.object(
            svc.auth, "get_user", return_value=_fake_user_record(disabled=False)
        ), patch.object(
            svc.auth, "revoke_refresh_tokens"
        ) as mock_revoke, patch.object(
            svc, "get_firestore_client", return_value=MagicMock()
        ):
            svc.update_user("u1", disabled=False)
            svc.update_user("u1", display_name="No disabled arg at all")

        mock_revoke.assert_not_called()

    def test_demoting_an_admin_revokes_refresh_tokens(self):
        # Same class of bug as the disabled-path FIX above, for the role
        # path: set_custom_user_claims() only affects tokens issued AFTER
        # the change - a just-demoted admin's already-issued token keeps
        # carrying "admin": true and keeps passing require_admin's claim
        # check (see admin_auth_service.py) until it expires (up to 1h)
        # unless the demotion also revokes it here.
        with patch.object(svc, "initialize_firebase"), patch.object(
            svc.auth, "update_user"
        ), patch.object(
            svc.auth,
            "get_user",
            return_value=_fake_user_record(
                custom_claims={"role": "admin", "admin": True}
            ),
        ), patch.object(
            svc.auth, "set_custom_user_claims"
        ), patch.object(
            svc.auth, "revoke_refresh_tokens"
        ) as mock_revoke, patch.object(
            svc, "get_firestore_client", return_value=MagicMock()
        ):
            svc.update_user("u1", role="user")

        mock_revoke.assert_called_once_with("u1")

    def test_promoting_to_admin_does_not_revoke(self):
        # The hole only exists in one direction (an admin's already-issued
        # token outliving its claims) - a newly-promoted admin's OLD token
        # correctly still lacks the admin claim, so there's nothing stale
        # to revoke on promotion.
        with patch.object(svc, "initialize_firebase"), patch.object(
            svc.auth, "update_user"
        ), patch.object(
            svc.auth,
            "get_user",
            return_value=_fake_user_record(
                custom_claims={"role": "user", "admin": False}
            ),
        ), patch.object(
            svc.auth, "set_custom_user_claims"
        ), patch.object(
            svc.auth, "revoke_refresh_tokens"
        ) as mock_revoke, patch.object(
            svc, "get_firestore_client", return_value=MagicMock()
        ):
            svc.update_user("u1", role="admin")

        mock_revoke.assert_not_called()

    def test_non_admin_role_change_does_not_revoke(self):
        with patch.object(svc, "initialize_firebase"), patch.object(
            svc.auth, "update_user"
        ), patch.object(
            svc.auth,
            "get_user",
            return_value=_fake_user_record(
                custom_claims={"role": "user", "admin": False}
            ),
        ), patch.object(
            svc.auth, "set_custom_user_claims"
        ), patch.object(
            svc.auth, "revoke_refresh_tokens"
        ) as mock_revoke, patch.object(
            svc, "get_firestore_client", return_value=MagicMock()
        ):
            svc.update_user("u1", role="parent")

        mock_revoke.assert_not_called()

    def test_firestore_update_only_contains_provided_fields(self):
        fake_db = MagicMock()

        with patch.object(svc, "initialize_firebase"), patch.object(
            svc.auth, "update_user"
        ), patch.object(
            svc.auth, "get_user", return_value=_fake_user_record()
        ), patch.object(svc, "get_firestore_client", return_value=fake_db):
            svc.update_user("u1", display_name="Renamed Only")

        written = fake_db.collection.return_value.document.return_value.set.call_args[0][0]
        assert written["fullName"] == "Renamed Only"
        assert "email" not in written
        assert "role" not in written
        assert "disabled" not in written
        assert "updatedAt" in written


class TestDeleteUser:
    def test_revokes_tokens_before_deleting_the_auth_account(self):
        fake_db = MagicMock()
        call_order = []

        with patch.object(svc, "initialize_firebase"), patch.object(
            svc.auth,
            "revoke_refresh_tokens",
            side_effect=lambda uid: call_order.append("revoke"),
        ), patch.object(
            svc.auth,
            "delete_user",
            side_effect=lambda uid: call_order.append("delete"),
        ), patch.object(
            svc, "get_firestore_client", return_value=fake_db
        ):
            svc.delete_user("u1")

        assert call_order == ["revoke", "delete"]

    def test_also_deletes_the_users_firestore_document(self):
        fake_db = MagicMock()

        with patch.object(svc, "initialize_firebase"), patch.object(
            svc.auth, "revoke_refresh_tokens"
        ), patch.object(svc.auth, "delete_user"), patch.object(
            svc, "get_firestore_client", return_value=fake_db
        ):
            svc.delete_user("u1")

        fake_db.collection.assert_called_once_with("users")
        fake_db.collection.return_value.document.assert_called_once_with("u1")
        fake_db.collection.return_value.document.return_value.delete.assert_called_once()
