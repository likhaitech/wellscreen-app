from fastapi import APIRouter, Depends, HTTPException, status

from app.models.system_settings import SystemSettingsUpdate
from app.services.admin_auth_service import require_admin
from app.services.system_settings_service import (
    get_system_settings,
    update_system_settings,
)


router = APIRouter(
    prefix="/admin/settings",
    tags=["Admin Settings"],
)


@router.get("/")
def read_system_settings(
    current_admin: dict = Depends(require_admin),
):
    try:
        return get_system_settings()

    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=str(exc),
        )


@router.patch("/")
def edit_system_settings(
    request: SystemSettingsUpdate,
    current_admin: dict = Depends(require_admin),
):
    changes = request.model_dump(exclude_none=True)

    try:
        return update_system_settings(
            changes,
            updated_by=current_admin.get("uid", "unknown"),
        )

    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=str(exc),
        )