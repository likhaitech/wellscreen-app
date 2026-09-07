"""Shared pytest fixtures for the backend test suite.

Nothing here talks to real Firebase. Every test mocks firebase_admin's
`auth`/`firestore` surfaces (or the app's own `get_firestore_client()`
seam) directly - there is no service account on this machine, and there
never should be one for a test run.
"""

from __future__ import annotations

import sys
from pathlib import Path
from typing import Any
from unittest.mock import MagicMock

import pytest

# Make `app.*` importable regardless of the cwd pytest was invoked from -
# mirrors how app/main.py itself is imported (uvicorn app.main:app from
# the backend/ directory), so tests don't silently depend on being run
# from exactly one working directory.
_BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(_BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(_BACKEND_DIR))


class FakeDocumentSnapshot:
    """Stands in for a google.cloud.firestore DocumentSnapshot."""

    def __init__(self, data: dict[str, Any] | None, *, doc_id: str = "fake-id"):
        self._data = data
        self.id = doc_id
        self.exists = data is not None

    def to_dict(self) -> dict[str, Any] | None:
        return self._data


class FakeDocumentReference:
    """Stands in for a google.cloud.firestore DocumentReference.

    Records every set()/update()/delete() call on `.calls` so tests can
    assert on exactly what was written, not just that *something* was.
    """

    def __init__(self, data: dict[str, Any] | None = None):
        self._data = data
        self.calls: list[tuple[str, Any]] = []

    def get(self) -> FakeDocumentSnapshot:
        return FakeDocumentSnapshot(self._data)

    def set(self, data: dict[str, Any], merge: bool = False) -> None:
        self.calls.append(("set", {"data": data, "merge": merge}))

        if merge and self._data:
            self._data = {**self._data, **data}
        else:
            self._data = dict(data)

    def update(self, data: dict[str, Any]) -> None:
        self.calls.append(("update", data))

    def delete(self) -> None:
        self.calls.append(("delete", None))
        self._data = None


class FakeQuery:
    """Stands in for the chained .order_by().limit().stream() query API."""

    def __init__(self, documents: list[FakeDocumentSnapshot]):
        self._documents = documents

    def order_by(self, *_args, **_kwargs) -> "FakeQuery":
        return self

    def limit(self, count: int) -> "FakeQuery":
        return FakeQuery(self._documents[:count])

    def stream(self):
        return iter(self._documents)


class FakeCollectionReference:
    """Stands in for a google.cloud.firestore CollectionReference.

    Holds a fixed set of documents (for reads) and records every add()
    call (for writes) - enough surface for system_log_service and
    system_settings_service without pulling in a real Firestore emulator.
    """

    def __init__(self, documents: dict[str, dict[str, Any]] | None = None):
        self._documents = documents or {}
        self.added: list[dict[str, Any]] = []
        self._doc_refs: dict[str, FakeDocumentReference] = {
            doc_id: FakeDocumentReference(data)
            for doc_id, data in self._documents.items()
        }

    def document(self, doc_id: str) -> FakeDocumentReference:
        if doc_id not in self._doc_refs:
            self._doc_refs[doc_id] = FakeDocumentReference(None)

        return self._doc_refs[doc_id]

    def add(self, data: dict[str, Any]) -> None:
        self.added.append(data)

    def order_by(self, *args, **kwargs) -> FakeQuery:
        snapshots = [
            FakeDocumentSnapshot(data, doc_id=doc_id)
            for doc_id, data in self._documents.items()
        ]
        return FakeQuery(snapshots).order_by(*args, **kwargs)


class FakeFirestoreClient:
    """Stands in for firestore.client() - a dict of named collections."""

    def __init__(self):
        self._collections: dict[str, FakeCollectionReference] = {}

    def collection(self, name: str) -> FakeCollectionReference:
        if name not in self._collections:
            self._collections[name] = FakeCollectionReference()

        return self._collections[name]


@pytest.fixture
def fake_firestore() -> FakeFirestoreClient:
    return FakeFirestoreClient()


@pytest.fixture
def fake_auth_module(monkeypatch: pytest.MonkeyPatch) -> MagicMock:
    """Replaces firebase_admin.auth's callable surface with a MagicMock.

    Service modules do `from firebase_admin import auth`, i.e. they hold a
    reference to the *module object* itself - so patching attributes on
    the real firebase_admin.auth module (rather than on each importing
    module) is visible everywhere without having to patch N call sites.
    """

    from firebase_admin import auth as real_auth_module

    mock = MagicMock()

    for attr in (
        "verify_id_token",
        "list_users",
        "get_user",
        "create_user",
        "update_user",
        "set_custom_user_claims",
        "revoke_refresh_tokens",
        "delete_user",
    ):
        monkeypatch.setattr(real_auth_module, attr, getattr(mock, attr))

    # RevokedIdTokenError is a real exception class on the module - tests
    # raise it via mock.side_effect, so expose it on the mock for
    # readability at call sites instead of re-importing firebase_admin.auth.
    mock.RevokedIdTokenError = real_auth_module.RevokedIdTokenError

    return mock
