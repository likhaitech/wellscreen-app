"""Tests for app/services/system_log_service.py - the audit trail every
admin action (settings changes, user create/update/delete) writes through,
and that GET /admin/logs reads back. Firestore is mocked (get_firestore_client
patched); this exercises the real create_system_log/list_system_logs logic:
what gets written, what query is built, and how missing/partial fields in
a stored document are defaulted when read back.
"""
from __future__ import annotations

from unittest.mock import MagicMock, patch

from firebase_admin import firestore

from app.services import system_log_service as svc


class TestCreateSystemLog:
    def test_writes_all_fields_including_server_timestamp(self):
        fake_db = MagicMock()

        with patch.object(svc, "get_firestore_client", return_value=fake_db):
            svc.create_system_log(
                level="info",
                action="admin_user_created",
                message="Admin created a user account",
                actor_uid="admin-1",
                details={"target_uid": "u2"},
            )

        fake_db.collection.assert_called_once_with("system_logs")
        written = fake_db.collection.return_value.add.call_args[0][0]

        assert written["level"] == "info"
        assert written["action"] == "admin_user_created"
        assert written["message"] == "Admin created a user account"
        assert written["actor_uid"] == "admin-1"
        assert written["details"] == {"target_uid": "u2"}
        assert written["timestamp"] is firestore.SERVER_TIMESTAMP

    def test_actor_uid_and_details_default_to_none(self):
        fake_db = MagicMock()

        with patch.object(svc, "get_firestore_client", return_value=fake_db):
            svc.create_system_log(
                level="error",
                action="something_failed",
                message="it broke",
            )

        written = fake_db.collection.return_value.add.call_args[0][0]
        assert written["actor_uid"] is None
        assert written["details"] is None


class TestListSystemLogs:
    def _fake_doc(self, doc_id: str, data: dict):
        doc = MagicMock()
        doc.id = doc_id
        doc.to_dict.return_value = data
        return doc

    def test_orders_by_timestamp_descending_and_applies_limit(self):
        fake_db = MagicMock()
        query = fake_db.collection.return_value.order_by.return_value
        query.limit.return_value.stream.return_value = []

        with patch.object(svc, "get_firestore_client", return_value=fake_db):
            svc.list_system_logs(limit=42)

        fake_db.collection.assert_called_once_with("system_logs")
        fake_db.collection.return_value.order_by.assert_called_once_with(
            "timestamp", direction=firestore.Query.DESCENDING
        )
        query.limit.assert_called_once_with(42)

    def test_maps_documents_to_dicts_with_id(self):
        fake_db = MagicMock()
        docs = [
            self._fake_doc(
                "log-1",
                {
                    "level": "warning",
                    "action": "admin_user_updated",
                    "message": "changed role",
                    "actor_uid": "admin-1",
                    "details": {"target_uid": "u2"},
                    "timestamp": "2024-01-01T00:00:00Z",
                },
            )
        ]
        fake_db.collection.return_value.order_by.return_value.limit.return_value.stream.return_value = docs

        with patch.object(svc, "get_firestore_client", return_value=fake_db):
            result = svc.list_system_logs(limit=10)

        assert result == [
            {
                "id": "log-1",
                "level": "warning",
                "action": "admin_user_updated",
                "message": "changed role",
                "actor_uid": "admin-1",
                "details": {"target_uid": "u2"},
                "timestamp": "2024-01-01T00:00:00Z",
            }
        ]

    def test_missing_fields_are_defaulted_not_a_key_error(self):
        # A partially-written or legacy log document must not crash the
        # admin logs screen - level defaults to "info", action/message to
        # empty strings, actor_uid/details/timestamp to None.
        fake_db = MagicMock()
        docs = [self._fake_doc("log-2", {})]
        fake_db.collection.return_value.order_by.return_value.limit.return_value.stream.return_value = docs

        with patch.object(svc, "get_firestore_client", return_value=fake_db):
            result = svc.list_system_logs()

        assert result == [
            {
                "id": "log-2",
                "level": "info",
                "action": "",
                "message": "",
                "actor_uid": None,
                "details": None,
                "timestamp": None,
            }
        ]

    def test_document_with_no_dict_data_does_not_crash(self):
        # document.to_dict() can return None for a deleted-but-still-listed
        # doc snapshot - must fall back to the same defaults, not raise.
        fake_db = MagicMock()
        doc = MagicMock()
        doc.id = "log-3"
        doc.to_dict.return_value = None
        fake_db.collection.return_value.order_by.return_value.limit.return_value.stream.return_value = [doc]

        with patch.object(svc, "get_firestore_client", return_value=fake_db):
            result = svc.list_system_logs()

        assert result[0]["id"] == "log-3"
        assert result[0]["level"] == "info"
