from __future__ import annotations

from typing import Any

from pydantic import BaseModel


class AlertNotifyRequest(BaseModel):
    """Request to push a real-time alert notification to a parent's device.

    parent_uid is the Firebase uid of the recipient (a users/{uid} document
    with an fcmToken field, saved by the Flutter app's
    PushNotificationService). The caller must be either that same parent, or
    a child account paired to that parent (see notification_service.py's
    authorization check) - this prevents any authenticated user from
    notifying an arbitrary other user.
    """

    parent_uid: str
    title: str
    body: str
    alert_type: str
    data: dict[str, Any] | None = None


class AlertNotifyResponse(BaseModel):
    status: str
    message_id: str | None = None
    error: str | None = None
