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
        return auth.verify_id_token(credentials.credentials)
    except Exception:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired authentication token",
        )
