from __future__ import annotations

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from firebase_admin import auth

from .firebase_service import initialize_firebase


bearer_scheme = HTTPBearer(auto_error=False)


def require_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
) -> dict:
    """Verifies the caller is a real, signed-in Firebase user - unlike
    require_admin in admin_auth_service.py, this does NOT require an admin
    claim. Used by routes any authenticated parent/child account may call,
    such as /alerts/notify.
    """

    if credentials is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authentication required",
        )

    initialize_firebase()

    try:
        # check_revoked=True: matches require_admin in admin_auth_service.py
        # - see that file's comment. Needed here too since /alerts/notify is
        # reachable by any signed-in parent/child account, including ones an
        # admin just disabled.
        return auth.verify_id_token(
            credentials.credentials,
            check_revoked=True,
        )
    except auth.RevokedIdTokenError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="This session has been revoked. Please sign in again.",
        )
    except Exception:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired authentication token",
        )
