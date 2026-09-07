"""Covers firebase_service.initialize_firebase() - the one place every
other service and route depends on (directly or via require_admin) to
reach Firebase at all. None of these tests touch a real service account;
they exercise the three paths the source itself distinguishes: reuse an
already-initialized app, use a service-account file (default path or
FIREBASE_SERVICE_ACCOUNT_PATH), or raise a clear error when neither is
available - rather than letting a confusing SDK-internal exception surface
to whoever's route triggered initialization first.
"""

from __future__ import annotations

import json
from unittest.mock import MagicMock

import firebase_admin
import pytest
from firebase_admin import credentials

from app.services import firebase_service


@pytest.fixture(autouse=True)
def _isolate_firebase_admin_apps(monkeypatch: pytest.MonkeyPatch) -> None:
    # firebase_admin._apps is real, process-global state. Every test in
    # this file controls it explicitly rather than trusting whatever
    # earlier tests (in this file or elsewhere) left behind.
    monkeypatch.setattr(firebase_admin, "_apps", {})


def test_returns_existing_app_without_reinitializing(
    monkeypatch: pytest.MonkeyPatch,
):
    existing_app = MagicMock(name="existing-app")
    monkeypatch.setattr(firebase_admin, "_apps", {"[DEFAULT]": existing_app})
    monkeypatch.setattr(firebase_admin, "get_app", lambda: existing_app)

    initialize_app_mock = MagicMock()
    monkeypatch.setattr(firebase_admin, "initialize_app", initialize_app_mock)

    result = firebase_service.initialize_firebase()

    assert result is existing_app
    initialize_app_mock.assert_not_called()


def test_uses_service_account_file_at_default_path(
    monkeypatch: pytest.MonkeyPatch, tmp_path
):
    service_account_path = tmp_path / "firebase-service-account.json"
    service_account_path.write_text(json.dumps({"type": "service_account"}))

    monkeypatch.setattr(
        firebase_service, "_DEFAULT_SERVICE_ACCOUNT", service_account_path
    )
    monkeypatch.delenv("FIREBASE_SERVICE_ACCOUNT_PATH", raising=False)

    fake_credential = MagicMock(name="fake-credential")
    certificate_mock = MagicMock(return_value=fake_credential)
    monkeypatch.setattr(credentials, "Certificate", certificate_mock)

    sentinel_app = MagicMock(name="initialized-app")
    initialize_app_mock = MagicMock(return_value=sentinel_app)
    monkeypatch.setattr(firebase_admin, "initialize_app", initialize_app_mock)

    result = firebase_service.initialize_firebase()

    certificate_mock.assert_called_once_with(str(service_account_path))
    initialize_app_mock.assert_called_once_with(fake_credential)
    assert result is sentinel_app


def test_prefers_env_var_path_over_default(
    monkeypatch: pytest.MonkeyPatch, tmp_path
):
    default_path = tmp_path / "default-service-account.json"
    default_path.write_text(json.dumps({"type": "service_account"}))

    configured_path = tmp_path / "configured-service-account.json"
    configured_path.write_text(json.dumps({"type": "service_account"}))

    monkeypatch.setattr(
        firebase_service, "_DEFAULT_SERVICE_ACCOUNT", default_path
    )
    monkeypatch.setenv("FIREBASE_SERVICE_ACCOUNT_PATH", str(configured_path))

    certificate_mock = MagicMock(return_value=MagicMock())
    monkeypatch.setattr(credentials, "Certificate", certificate_mock)
    monkeypatch.setattr(firebase_admin, "initialize_app", MagicMock())

    firebase_service.initialize_firebase()

    # Match the source's own Path(...).expanduser().resolve() exactly,
    # rather than assuming tmp_path is already in fully-resolved form
    # (it may not be, e.g. on systems where /tmp is itself a symlink).
    expected_path = str(configured_path.expanduser().resolve())
    certificate_mock.assert_called_once_with(expected_path)


def test_raises_helpful_error_when_no_credentials_are_found(
    monkeypatch: pytest.MonkeyPatch, tmp_path
):
    # No file at the default path, no env var set, and the SDK's own
    # application-default-credentials fallback fails too (as it will on
    # any machine without ambient Google credentials, which is the exact
    # situation this error message exists to explain).
    missing_path = tmp_path / "does-not-exist.json"

    monkeypatch.setattr(firebase_service, "_DEFAULT_SERVICE_ACCOUNT", missing_path)
    monkeypatch.delenv("FIREBASE_SERVICE_ACCOUNT_PATH", raising=False)

    underlying_error = ValueError("no ADC found")
    monkeypatch.setattr(
        firebase_admin,
        "initialize_app",
        MagicMock(side_effect=underlying_error),
    )

    with pytest.raises(RuntimeError) as exc_info:
        firebase_service.initialize_firebase()

    assert "firebase-service-account.json" in str(exc_info.value)
    assert "FIREBASE_SERVICE_ACCOUNT_PATH" in str(exc_info.value)
    # `raise ... from exc` - the original SDK error must stay attached,
    # not get discarded, so whoever debugs this later isn't stuck with
    # only the friendly wrapper message.
    assert exc_info.value.__cause__ is underlying_error
