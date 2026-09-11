"""Route-level tests for GET/PATCH /admin/settings, run against the real
FastAPI app with TestClient. The 401 case is genuine end-to-end behavior;
authenticated cases override require_admin and patch the underlying
service functions since this sandbox has no Firebase credentials.
"""
from __future__ import annotations

from unittest.mock import patch

from fastapi.testclient import TestClient

from app.main import app
from app.services.admin_auth_service import require_admin

client = TestClient(app)


def test_get_without_auth_header_is_rejected():
    response = client.get("/admin/settings/")
    assert response.status_code == 401


def test_get_returns_current_settings():
    app.dependency_overrides[require_admin] = lambda: {"uid": "admin-1", "admin": True}
    try:
        with patch(
            "app.routes.admin_settings.get_system_settings",
            return_value={"default_daily_limit_minutes": 180},
        ):
            response = client.get("/admin/settings/")
    finally:
        app.dependency_overrides.pop(require_admin, None)

    assert response.status_code == 200
    assert response.json() == {"default_daily_limit_minutes": 180}


def test_get_service_error_becomes_500():
    app.dependency_overrides[require_admin] = lambda: {"uid": "admin-1", "admin": True}
    try:
        with patch(
            "app.routes.admin_settings.get_system_settings",
            side_effect=RuntimeError("boom"),
        ):
            response = client.get("/admin/settings/")
    finally:
        app.dependency_overrides.pop(require_admin, None)

    assert response.status_code == 500


def test_patch_without_auth_header_is_rejected():
    response = client.patch("/admin/settings/", json={"app_blocking_enabled": False})
    assert response.status_code == 401


def test_patch_applies_changes_and_writes_an_audit_log():
    app.dependency_overrides[require_admin] = lambda: {"uid": "admin-1", "admin": True}
    try:
        with patch(
            "app.routes.admin_settings.update_system_settings",
            return_value={"app_blocking_enabled": False},
        ) as mock_update, patch(
            "app.routes.admin_settings.create_system_log"
        ) as mock_log:
            response = client.patch(
                "/admin/settings/", json={"app_blocking_enabled": False}
            )
    finally:
        app.dependency_overrides.pop(require_admin, None)

    assert response.status_code == 200
    assert response.json() == {"app_blocking_enabled": False}
    mock_update.assert_called_once_with(
        {"app_blocking_enabled": False}, updated_by="admin-1"
    )
    mock_log.assert_called_once()
    assert mock_log.call_args.kwargs["action"] == "system_settings_updated"
    assert mock_log.call_args.kwargs["actor_uid"] == "admin-1"


def test_patch_with_no_fields_sends_empty_changes():
    app.dependency_overrides[require_admin] = lambda: {"uid": "admin-1", "admin": True}
    try:
        with patch(
            "app.routes.admin_settings.update_system_settings", return_value={}
        ) as mock_update, patch("app.routes.admin_settings.create_system_log"):
            response = client.patch("/admin/settings/", json={})
    finally:
        app.dependency_overrides.pop(require_admin, None)

    assert response.status_code == 200
    mock_update.assert_called_once_with({}, updated_by="admin-1")


def test_patch_service_error_becomes_500():
    app.dependency_overrides[require_admin] = lambda: {"uid": "admin-1", "admin": True}
    try:
        with patch(
            "app.routes.admin_settings.update_system_settings",
            side_effect=RuntimeError("boom"),
        ):
            response = client.patch(
                "/admin/settings/", json={"app_blocking_enabled": True}
            )
    finally:
        app.dependency_overrides.pop(require_admin, None)

    assert response.status_code == 500
