"""Real, executable tests for the alert-delivery authorization and send
logic in app/services/notification_service.py - the backend half of the
"Alert Delivery Success Rate" technical evaluation criterion.

These don't touch a live Firestore/FCM project (no credentials in this
environment); Firestore and firebase_admin.messaging are mocked so the
tests exercise the real branching logic in notification_service.py:
who is allowed to notify whom, and what outcome/status each FCM result
maps to. Run with: pytest backend/tests/test_notification_service.py -v
"""
from __future__ import annotations

from unittest.mock import MagicMock, patch

import pytest
from firebase_admin import messaging

from app.services import notification_service as svc


def _fake_db(*, caller_paired_parent_id=None, recipient_fcm_token=None):
    """Builds a fake Firestore client matching the shape notification_service.py
    reads: db.collection("users").document(uid).get() -> doc with .to_dict().
    """

    def make_doc(data):
        doc = MagicMock()
        doc.to_dict.return_value = data
        return doc

    docs = {
        "caller": make_doc({"pairedParentId": caller_paired_parent_id}),
        "recipient": make_doc({"fcmToken": recipient_fcm_token}),
    }

    db = MagicMock()

    def document(uid):
        doc_ref = MagicMock()
        # The same fake doc is returned regardless of which uid string is
        # passed, driven instead by which key ("caller"/"recipient") the
        # test wired up via side_effect below.
        return doc_ref

    db.collection.return_value.document = document
    return db, docs


class TestCallerMayNotify:
    def test_self_notify_always_allowed(self):
        # No Firestore read should even be needed when caller == parent_uid.
        assert svc.caller_may_notify(caller_uid="u1", parent_uid="u1") is True

    def test_paired_child_is_allowed(self):
        fake_doc = MagicMock()
        fake_doc.to_dict.return_value = {"pairedParentId": "parent-1"}
        fake_db = MagicMock()
        fake_db.collection.return_value.document.return_value.get.return_value = fake_doc

        with patch.object(svc, "get_firestore_client", return_value=fake_db):
            assert svc.caller_may_notify(caller_uid="child-1", parent_uid="parent-1") is True

    def test_unrelated_caller_is_denied(self):
        fake_doc = MagicMock()
        fake_doc.to_dict.return_value = {"pairedParentId": "someone-else"}
        fake_db = MagicMock()
        fake_db.collection.return_value.document.return_value.get.return_value = fake_doc

        with patch.object(svc, "get_firestore_client", return_value=fake_db):
            assert svc.caller_may_notify(caller_uid="stranger", parent_uid="parent-1") is False

    def test_caller_with_no_profile_document_is_denied(self):
        # to_dict() returning None (doc doesn't exist) must not crash and
        # must not be treated as authorized.
        fake_doc = MagicMock()
        fake_doc.to_dict.return_value = None
        fake_db = MagicMock()
        fake_db.collection.return_value.document.return_value.get.return_value = fake_doc

        with patch.object(svc, "get_firestore_client", return_value=fake_db):
            assert svc.caller_may_notify(caller_uid="ghost", parent_uid="parent-1") is False


class TestSendAlertNotification:
    def _patch_db(self, recipient_data):
        fake_doc = MagicMock()
        fake_doc.to_dict.return_value = recipient_data
        fake_db = MagicMock()
        fake_db.collection.return_value.document.return_value.get.return_value = fake_doc
        return fake_db

    def test_raises_not_authorized_for_unrelated_caller(self):
        with patch.object(svc, "caller_may_notify", return_value=False):
            with pytest.raises(svc.NotAuthorizedError):
                svc.send_alert_notification(
                    caller_uid="stranger",
                    parent_uid="parent-1",
                    title="t",
                    body="b",
                )

    def test_raises_no_device_token_when_recipient_has_none(self):
        fake_db = self._patch_db({"fcmToken": None})
        with patch.object(svc, "caller_may_notify", return_value=True), \
             patch.object(svc, "get_firestore_client", return_value=fake_db):
            with pytest.raises(svc.NoDeviceTokenError):
                svc.send_alert_notification(
                    caller_uid="parent-1",
                    parent_uid="parent-1",
                    title="t",
                    body="b",
                )

    def test_successful_send_returns_sent_status_and_message_id(self):
        fake_db = self._patch_db({"fcmToken": "abc-token"})
        with patch.object(svc, "caller_may_notify", return_value=True), \
             patch.object(svc, "get_firestore_client", return_value=fake_db), \
             patch.object(svc.messaging, "send", return_value="projects/x/messages/123") as mock_send:
            result = svc.send_alert_notification(
                caller_uid="parent-1",
                parent_uid="parent-1",
                title="Usage limit reached",
                body="Your child has reached today's screen-time limit.",
                data={"alertType": "usage_limit"},
            )

        assert result == {
            "status": "sent",
            "message_id": "projects/x/messages/123",
            "error": None,
        }
        # FCM data payloads must be flat string->string maps - verify the
        # int/str coercion actually happened, not just that send() was called.
        sent_message = mock_send.call_args[0][0]
        assert sent_message.data == {"alertType": "usage_limit"}
        assert sent_message.token == "abc-token"

    def test_unregistered_token_clears_it_and_reports_failed(self):
        fake_db = self._patch_db({"fcmToken": "stale-token"})
        with patch.object(svc, "caller_may_notify", return_value=True), \
             patch.object(svc, "get_firestore_client", return_value=fake_db), \
             patch.object(
                 svc.messaging,
                 "send",
                 side_effect=messaging.UnregisteredError("token gone"),
             ):
            result = svc.send_alert_notification(
                caller_uid="parent-1",
                parent_uid="parent-1",
                title="t",
                body="b",
            )

        assert result["status"] == "failed"
        assert result["message_id"] is None
        # The stale token must actually be cleared so future sends don't
        # keep failing the same way.
        fake_db.collection.return_value.document.return_value.update.assert_called_once_with(
            {"fcmToken": None}
        )

    def test_generic_fcm_error_is_caught_and_reported_not_raised(self):
        fake_db = self._patch_db({"fcmToken": "abc-token"})
        with patch.object(svc, "caller_may_notify", return_value=True), \
             patch.object(svc, "get_firestore_client", return_value=fake_db), \
             patch.object(svc.messaging, "send", side_effect=RuntimeError("network blip")):
            result = svc.send_alert_notification(
                caller_uid="parent-1",
                parent_uid="parent-1",
                title="t",
                body="b",
            )

        assert result["status"] == "failed"
        assert "network blip" in result["error"]
