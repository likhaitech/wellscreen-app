from __future__ import annotations

from typing import Any

from pydantic import BaseModel


class SystemLogResponse(BaseModel):
    id: str
    level: str
    action: str
    message: str
    actor_uid: str | None = None
    details: dict[str, Any] | None = None
    timestamp: Any | None = None