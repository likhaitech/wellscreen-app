from fastapi import APIRouter, Depends, HTTPException, status
from firebase_admin import auth

from app.models.admin_user import (
    CreateUserRequest,
    UpdateUserRequest,
)
from app.services.admin_auth_service import require_admin
from app.services.user_admin_service import (
    create_user,
    delete_user,
    get_user,
    list_users,
    update_user,
)


router = APIRouter(
    prefix="/admin/users",
    tags=["Admin Users"],
)


@router.get("/")
def get_users(
    current_admin: dict = Depends(require_admin),
):
    try:
        return {
            "users": list_users()
        }

    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=str(exc),
        )


@router.get("/{uid}")
def get_user_by_uid(
    uid: str,
    current_admin: dict = Depends(require_admin),
):
    try:
        return get_user(uid)

    except auth.UserNotFoundError:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found",
        )

    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=str(exc),
        )


@router.post("/", status_code=status.HTTP_201_CREATED)
def create_new_user(
    request: CreateUserRequest,
    current_admin: dict = Depends(require_admin),
):
    if request.role not in {"user", "admin"}:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Role must be either 'user' or 'admin'",
        )

    try:
        return create_user(
            email=request.email,
            password=request.password,
            display_name=request.display_name,
            role=request.role,
            disabled=request.disabled,
        )

    except auth.EmailAlreadyExistsError:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="A user with this email already exists",
        )

    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=str(exc),
        )


@router.patch("/{uid}")
def edit_user(
    uid: str,
    request: UpdateUserRequest,
    current_admin: dict = Depends(require_admin),
):
    current_admin_uid = current_admin.get("uid")

    if request.role is not None and request.role not in {
        "user",
        "admin",
    }:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Role must be either 'user' or 'admin'",
        )

    if uid == current_admin_uid:
        if request.disabled is True:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="You cannot disable your own admin account",
            )

        if request.role is not None and request.role != "admin":
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="You cannot remove your own admin role",
            )

    try:
        return update_user(
            uid,
            email=request.email,
            password=request.password,
            display_name=request.display_name,
            role=request.role,
            disabled=request.disabled,
        )

    except auth.UserNotFoundError:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found",
        )

    except auth.EmailAlreadyExistsError:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="A user with this email already exists",
        )

    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=str(exc),
        )


@router.delete("/{uid}")
def remove_user(
    uid: str,
    current_admin: dict = Depends(require_admin),
):
    current_admin_uid = current_admin.get("uid")

    if uid == current_admin_uid:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="You cannot delete your own admin account",
        )

    try:
        delete_user(uid)

        return {
            "message": "User deleted successfully"
        }

    except auth.UserNotFoundError:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found",
        )

    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=str(exc),
        )