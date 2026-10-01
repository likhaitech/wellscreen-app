from __future__ import annotations

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from firebase_admin import auth

from .firebase_service import initialize_firebase


bearer_scheme = HTTPBearer(auto_error=False)


def require_admin(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
) -> dict:
    if credentials is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authentication required",
        )

    initialize_firebase()

    try:
        # check_revoked=True: without this, verify_id_token only checks the
        # JWT's signature/expiry, not whether the account was disabled or
        # deleted since this token was issued (see user_admin_service.py's
        # revoke_refresh_tokens() calls, which this checks against).
        decoded_token = auth.verify_id_token(
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

    is_admin = (
        decoded_token.get("admin") is True
        or decoded_token.get("role") == "admin"
    )

    if not is_admin:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Administrator access required",
        )

    return decoded_token