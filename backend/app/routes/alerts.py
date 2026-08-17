from fastapi import APIRouter, Depends, HTTPException, status

from app.models.alert import AlertNotifyRequest, AlertNotifyResponse
from app.services.notification_service import (
    NoDeviceTokenError,
    NotAuthorizedError,
    send_alert_notification,
)
from app.services.user_auth_service import require_user

router = APIRouter(prefix="/alerts", tags=["Alerts"])


@router.post("/notify", response_model=AlertNotifyResponse)
def notify(
    payload: AlertNotifyRequest,
    current_user: dict = Depends(require_user),
):
    caller_uid = current_user.get("uid")

    try:
        result = send_alert_notification(
            caller_uid=caller_uid,
            parent_uid=payload.parent_uid,
            title=payload.title,
            body=payload.body,
            data={"alertType": payload.alert_type, **(payload.data or {})},
        )
        return AlertNotifyResponse(**result)
    except NotAuthorizedError as exc:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=str(exc),
        )
    except NoDeviceTokenError as exc:
        # Not a server error - the parent just hasn't opened the app with
        # notifications set up yet. 200 with a "failed" status lets the
        # caller distinguish "we tried and it didn't work" from "the server
        # is broken", matching AlertNotifyResponse's shape either way.
        return AlertNotifyResponse(status="failed", error=str(exc))
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=str(exc),
        )
