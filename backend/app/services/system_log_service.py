from __future__ import annotations

from typing import Any

from firebase_admin import firestore

from .firebase_service import get_firestore_client


def create_system_log(
    *,
    level: str,
    action: str,
    message: str,
    actor_uid: str | None = None,
    details: dict[str, Any] | None = None,
) -> None:
    db = get_firestore_client()

    db.collection("system_logs").add(
        {
            "level": level,
            "action": action,
            "message": message,
            "actor_uid": actor_uid,
            "details": details,
            "timestamp": firestore.SERVER_TIMESTAMP,
        }
    )


def list_system_logs(limit: int = 100) -> list[dict[str, Any]]:
    db = get_firestore_client()

    documents = (
        db.collection("system_logs")
        .order_by("timestamp", direction=firestore.Query.DESCENDING)
        .limit(limit)
        .stream()
    )

    logs: list[dict[str, Any]] = []

    for document in documents:
        data = document.to_dict() or {}

        logs.append(
            {
                "id": document.id,
                "level": data.get("level", "info"),
                "action": data.get("action", ""),
                "message": data.get("message", ""),
                "actor_uid": data.get("actor_uid"),
                "details": data.get("details"),
                "timestamp": data.get("timestamp"),
            }
        )

    return logs