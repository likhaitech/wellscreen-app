"""Route-level tests for GET /admin/logs, run against the real FastAPI app
with TestClient - matching the pattern in test_alerts_route.py. The 401
case is genuine end-to-end behavior (no auth header at all); the
authenticated cases override require_admin and patch list_system_logs
since this sandbox has no Firebase credentials.
"""
from __future__ import annotations

from unittest.mock import patch

from fastapi.testclient import TestClient

from app.main import app
from app.services.admin_auth_service import require_admin

client = TestClient(app)


def test_without_auth_header_is_rejected():
    response = client.get("/admin/logs/")
    assert response.status_code == 401


def test_authenticated_admin_gets_the_log_list():
    app.dependency_overrides[require_admin] = lambda: {"uid": "admin-1", "admin": True}
    try:
        with patch(
            "app.routes.admin_logs.list_system_logs",
            return_value=[{"id": "log-1", "level": "info", "action": "x", "message": "y"}],
        ) as mock_list:
            response = client.get("/admin/logs/?limit=25")
    finally:
        app.dependency_overrides.pop(require_admin, None)

    assert response.status_code == 200
    assert response.json() == [{"id": "log-1", "level": "info", "action": "x", "message": "y"}]
    mock_list.assert_called_once_with(limit=25)


def test_limit_out_of_range_is_rejected_before_reaching_the_service():
    app.dependency_overrides[require_admin] = lambda: {"uid": "admin-1", "admin": True}
    try:
        response = client.get("/admin/logs/?limit=9999")
    finally:
        app.dependency_overrides.pop(require_admin, None)

    assert response.status_code == 422


def test_service_error_becomes_500():
    app.dependency_overrides[require_admin] = lambda: {"uid": "admin-1", "admin": True}
    try:
        with patch(
            "app.routes.admin_logs.list_system_logs",
            side_effect=RuntimeError("firestore unavailable"),
        ):
            response = client.get("/admin/logs/")
    finally:
        app.dependency_overrides.pop(require_admin, None)

    assert response.status_code == 500
