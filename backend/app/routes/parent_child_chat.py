"""WellScreen parent-child chat API routes.

Handles:
- Parent approval and rejection of app access requests
- Child activation of approved temporary access
- Chat message and access-request notification dispatch
- Scheduled notification processing
- Firebase Cloud Messaging registration diagnostics
- Diagnostic logging for HTTP 403 errors
"""

from __future__ import annotations

import logging
import os

from fastapi import APIRouter, Header, HTTPException
from pydantic import BaseModel, Field

from ..services.chat_access_service import (
    ChatAccessError,
    activate_grant,
    authenticated_uid,
    chat_push_status,
    dispatch_chat_event,
    respond_to_request,
    sweep_chat_notifications,
)

router = APIRouter(tags=["Parent-child chat"])
LOGGER = logging.getLogger(__name__)


class DecisionBody(BaseModel):
    approve: bool
    approvedMinutes: int | None = Field(default=None, ge=1, le=180)


@router.post("/chat/requests/{profile_id}/{request_id}/decision")
def decide(
    profile_id: str,
    request_id: str,
    body: DecisionBody,
    authorization: str | None = Header(default=None),
):
    try:
        uid = authenticated_uid(authorization)
        LOGGER.info(
            "WellScreen approval attempt: parent=%s profile=%s request=%s approve=%s",
            uid[-6:],
            profile_id[-6:],
            request_id[-6:],
            body.approve,
        )

        result = respond_to_request(
            parent_uid=uid,
            profile_id=profile_id,
            request_id=request_id,
            approve=body.approve,
            approved_minutes=body.approvedMinutes,
        )
        LOGGER.info(
            "WellScreen approval succeeded: profile=%s request=%s approve=%s",
            profile_id[-6:],
            request_id[-6:],
            body.approve,
        )
        return result

    except ChatAccessError as error:
        LOGGER.warning(
            "WellScreen approval rejected: profile=%s request=%s approve=%s reason=%s",
            profile_id[-6:],
            request_id[-6:],
            body.approve,
            str(error),
        )
        raise HTTPException(status_code=403, detail=str(error)) from error


@router.post("/chat/grants/{profile_id}/{package_name}/activate")
def activate(
    profile_id: str,
    package_name: str,
    authorization: str | None = Header(default=None),
):
    try:
        uid = authenticated_uid(authorization)
        return activate_grant(
            child_uid=uid,
            profile_id=profile_id,
            package_name=package_name,
        )
    except ChatAccessError as error:
        LOGGER.warning("WellScreen grant activation rejected: reason=%s", str(error))
        raise HTTPException(status_code=403, detail=str(error)) from error


@router.post("/internal/chat/notifications/sweep")
def sweep(x_chat_cron_secret: str | None = Header(default=None)):
    expected = os.environ.get("CHAT_CRON_SECRET")
    if not expected or not x_chat_cron_secret or x_chat_cron_secret != expected:
        LOGGER.warning("WellScreen chat notification sweep rejected")
        raise HTTPException(status_code=403, detail="Unauthorized")
    return sweep_chat_notifications()


@router.get("/chat/health")
def chat_health():
    """Unauthenticated deployment probe; exposes no user data."""
    return {
        "status": "ok",
        "feature": "parent_child_chat",
        "apiVersion": 2,
    }


@router.post("/chat/events/{profile_id}/{kind}/{event_id}/dispatch")
def dispatch_event(
    profile_id: str,
    kind: str,
    event_id: str,
    authorization: str | None = Header(default=None),
):
    try:
        uid = authenticated_uid(authorization)
        result = dispatch_chat_event(
            caller_uid=uid,
            profile_id=profile_id,
            kind=kind,
            event_id=event_id,
        )
        LOGGER.info(
            "WellScreen chat dispatch: kind=%s result=%s",
            kind,
            result.get("status"),
        )
        return result
    except ChatAccessError as error:
        LOGGER.warning(
            "WellScreen chat dispatch rejected: kind=%s reason=%s",
            kind,
            str(error),
        )
        raise HTTPException(status_code=403, detail=str(error)) from error


@router.get("/chat/push/status")
def push_status(authorization: str | None = Header(default=None)):
    """Report the signed-in user's FCM registration without exposing tokens."""
    try:
        uid = authenticated_uid(authorization)
        return chat_push_status(caller_uid=uid)
    except ChatAccessError as error:
        LOGGER.warning(
            "WellScreen FCM status request rejected: reason=%s",
            str(error),
        )
        raise HTTPException(status_code=403, detail=str(error)) from error
