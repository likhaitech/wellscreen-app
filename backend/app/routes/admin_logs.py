from fastapi import APIRouter, Depends, HTTPException, Query, status

from app.services.admin_auth_service import require_admin
from app.services.system_log_service import list_system_logs

router = APIRouter(prefix="/admin/logs", tags=["Admin Logs"])


@router.get("/")
def read_system_logs(
    limit: int = Query(default=100, ge=1, le=500),
    current_admin: dict = Depends(require_admin),
):
    try:
        return list_system_logs(limit=limit)
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=str(exc),
        )