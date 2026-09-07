"""Covers system_log_service.py - the write/read path admin_users.py's
_safe_create_system_log() and the /admin/logs route depend on. Also
guards list_system_logs()'s field defaults, since admin_logs_screen.dart
renders these directly and a missing/None field there should degrade
gracefully, not crash the admin UI.
"""

from __future__ import annotations

from unittest.mock import MagicMock

import pytest

from app.services import system_log_service


@pytest.fixture(autouse=True)
def _stub_firestore(monkeypatch: pytest.MonkeyPatch, fake_firestore) -> None:
    monkeypatch.setattr(
        system_log_service, "get_firestore_client", lambda: fake_firestore
    )


def test_create_system_log_writes_all_fields(fake_firestore):
    system_log_service.create_system_log(
        level="warning",
        action="user.disable",
        message="Disabled user uid-1",
        actor_uid="admin-uid",
        details={"reason": "policy violation"},
    )

    added = fake_firestore.collection("system_logs").added

    assert len(added) == 1
    assert added[0]["level"] == "warning"
    assert added[0]["action"] == "user.disable"
    assert added[0]["message"] == "Disabled user uid-1"
    assert added[0]["actor_uid"] == "admin-uid"
    assert added[0]["details"] == {"reason": "policy violation"}


def test_create_system_log_allows_optional_fields_to_be_none(fake_firestore):
    system_log_service.create_system_log(
        level="info", action="startup", message="Backend started"
    )

    added = fake_firestore.collection("system_logs").added

    assert added[0]["actor_uid"] is None
    assert added[0]["details"] is None


def test_list_system_logs_maps_documents_with_defaults(fake_firestore):
    collection = fake_firestore.collection("system_logs")
    collection._documents = {
        "log-1": {
            "level": "error",
            "action": "user.delete",
            "message": "Deleted uid-2",
            "actor_uid": "admin-uid",
            "details": {"uid": "uid-2"},
            "timestamp": "2026-01-01T00:00:00Z",
        },
        # A log missing every optional field - list_system_logs() must
        # not raise, it must fall back to the same defaults the .get()
        # calls in the source declare.
        "log-2": {},
    }

    logs = system_log_service.list_system_logs()

    by_id = {log["id"]: log for log in logs}

    assert by_id["log-1"]["level"] == "error"
    assert by_id["log-1"]["actor_uid"] == "admin-uid"

    assert by_id["log-2"]["level"] == "info"
    assert by_id["log-2"]["action"] == ""
    assert by_id["log-2"]["message"] == ""
    assert by_id["log-2"]["actor_uid"] is None


def test_list_system_logs_respects_limit(fake_firestore):
    collection = fake_firestore.collection("system_logs")
    collection._documents = {
        f"log-{i}": {"level": "info", "action": "x", "message": "x"}
        for i in range(5)
    }

    logs = system_log_service.list_system_logs(limit=2)

    assert len(logs) == 2
