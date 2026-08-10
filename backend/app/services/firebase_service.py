from __future__ import annotations

import os
from pathlib import Path

import firebase_admin
from firebase_admin import auth, credentials, firestore


_BACKEND_DIR = Path(__file__).resolve().parents[2]
_DEFAULT_SERVICE_ACCOUNT = _BACKEND_DIR / "firebase-service-account.json"


def initialize_firebase() -> firebase_admin.App:
    """Initialize Firebase Admin once and return the default app."""

    if firebase_admin._apps:
        return firebase_admin.get_app()

    configured_path = os.getenv("FIREBASE_SERVICE_ACCOUNT_PATH")

    service_account_path = (
        Path(configured_path).expanduser().resolve()
        if configured_path
        else _DEFAULT_SERVICE_ACCOUNT
    )

    if service_account_path.exists():
        credential = credentials.Certificate(
            str(service_account_path)
        )

        return firebase_admin.initialize_app(credential)

    try:
        return firebase_admin.initialize_app()

    except Exception as exc:
        raise RuntimeError(
            "Firebase Admin credentials were not found. "
            "Place the Firebase service-account JSON at "
            "backend/firebase-service-account.json "
            "or set FIREBASE_SERVICE_ACCOUNT_PATH."
        ) from exc


def get_firestore_client():
    initialize_firebase()
    return firestore.client()


def get_auth_module():
    initialize_firebase()
    return auth