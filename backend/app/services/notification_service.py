from __future__ import annotations

from typing import Any

from firebase_admin import messaging

from .firebase_service import get_firestore_client


class NotAuthorizedError(Exception):
    """Raised when the caller isn't the recipient or a child paired to them."""


class NoDeviceTokenError(Exception):
    """Raised when the recipient has no fcmToken on file yet."""


def caller_may_notify(*, caller_uid: str, parent_uid: str) -> bool:
    """A caller may notify parent_uid if they ARE parent_uid (self), or if
    they're a child account whose users/{caller_uid}.pairedParentId matches
    parent_uid (child_home_screen.dart's pairWithParent() sets this field).
    Real Firestore-backed check, not a trust-the-client assumption.
    """

    if caller_uid == parent_uid:
        return True

    db = get_firestore_client()
    caller_doc = db.collection("users").document(caller_uid).get()
    caller_data = caller_doc.to_dict() or {}

    return caller_data.get("pairedParentId") == parent_uid


def send_alert_notification(
    *,
    caller_uid: str,
    parent_uid: str,
    title: str,
    body: str,
    data: dict[str, Any] | None = None,
) -> dict[str, Any]:
    if not caller_may_notify(caller_uid=caller_uid, parent_uid=parent_uid):
        raise NotAuthorizedError(
            "Caller is not the recipient and is not a child paired to them."
        )

    db = get_firestore_client()
    recipient_doc = db.collection("users").document(parent_uid).get()
    recipient_data = recipient_doc.to_dict() or {}
    fcm_token = recipient_data.get("fcmToken")

    if not fcm_token:
        raise NoDeviceTokenError(
            "Recipient has no registered device (fcmToken) for push "
            "notifications yet."
        )

    # FCM data payloads must be flat string->string maps.
    string_data = {str(key): str(value) for key, value in (data or {}).items()}

    message = messaging.Message(
        notification=messaging.Notification(title=title, body=body),
        data=string_data,
        token=fcm_token,
        android=messaging.AndroidConfig(
            priority="high",
            notification=messaging.AndroidNotification(
                channel_id="wellscreen_alerts",
            ),
        ),
    )

    try:
        message_id = messaging.send(message)
        return {"status": "sent", "message_id": message_id, "error": None}
    except messaging.UnregisteredError:
        # The token is no longer valid (app uninstalled, token rotated
        # without the new one being saved yet, etc.) - clear it so future
        # sends don't keep failing the same way.
        db.collection("users").document(parent_uid).update({"fcmToken": None})
        return {
            "status": "failed",
            "message_id": None,
            "error": "Device token is no longer registered.",
        }
    except Exception as exc:
        return {"status": "failed", "message_id": None, "error": str(exc)}
