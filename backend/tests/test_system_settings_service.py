"""Covers system_settings_service.py - in particular that
update_system_settings() only ever writes keys already declared in
DEFAULT_SYSTEM_SETTINGS. That allow-list is the only thing stopping an
admin-settings PATCH body from writing arbitrary fields into the global
settings document (see admin_settings.py's route, which passes the raw
request body straight through to this function).
"""

from __future__ import annotations

import pytest

from app.services import system_settings_service


@pytest.fixture(autouse=True)
def _stub_firestore(monkeypatch: pytest.MonkeyPatch, fake_firestore) -> None:
    monkeypatch.setattr(
        system_settings_service, "get_firestore_client", lambda: fake_firestore
    )


def test_get_system_settings_returns_defaults_when_no_document_exists():
    settings = system_settings_service.get_system_settings()

    assert settings["default_daily_limit_minutes"] == 180
    assert settings["app_blocking_enabled"] is True
    assert settings["updated_at"] is None
    assert settings["updated_by"] is None


def test_get_system_settings_merges_stored_values_over_defaults(fake_firestore):
    doc_ref = fake_firestore.collection("system_settings").document("global")
    doc_ref.set(
        {
            "default_daily_limit_minutes": 90,
            "updated_at": "2026-01-01T00:00:00Z",
            "updated_by": "admin-uid",
        }
    )

    settings = system_settings_service.get_system_settings()

    assert settings["default_daily_limit_minutes"] == 90
    # Untouched keys keep their defaults, not silently disappear.
    assert settings["app_blocking_enabled"] is True
    assert settings["updated_by"] == "admin-uid"


def test_get_system_settings_ignores_unknown_stored_keys(fake_firestore):
    doc_ref = fake_firestore.collection("system_settings").document("global")
    doc_ref.set({"some_field_from_a_future_version": "unexpected"})

    settings = system_settings_service.get_system_settings()

    assert "some_field_from_a_future_version" not in settings


def test_update_system_settings_filters_out_unknown_keys(fake_firestore):
    system_settings_service.update_system_settings(
        {
            "default_daily_limit_minutes": 60,
            "not_a_real_setting": "should be dropped",
        },
        updated_by="admin-uid",
    )

    doc_ref = fake_firestore.collection("system_settings").document("global")
    set_calls = [call for call in doc_ref.calls if call[0] == "set"]

    assert len(set_calls) == 1
    written = set_calls[0][1]["data"]
    assert written["default_daily_limit_minutes"] == 60
    assert "not_a_real_setting" not in written
    assert set_calls[0][1]["merge"] is True


def test_update_system_settings_with_no_allowed_changes_does_not_write(
    fake_firestore,
):
    system_settings_service.update_system_settings(
        {"not_a_real_setting": "x"}, updated_by="admin-uid"
    )

    doc_ref = fake_firestore.collection("system_settings").document("global")
    assert doc_ref.calls == []


def test_update_system_settings_returns_the_refreshed_settings(fake_firestore):
    result = system_settings_service.update_system_settings(
        {"scheduled_lock_enabled": True}, updated_by="admin-uid"
    )

    assert result["scheduled_lock_enabled"] is True
