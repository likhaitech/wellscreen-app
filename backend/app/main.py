from fastapi import FastAPI

from .routes.admin_users import router as admin_users_router
from .routes.admin_settings import router as admin_settings_router
from .routes.admin_logs import router as admin_logs_router
from .routes.alerts import router as alerts_router

app = FastAPI(
    title="WellScreen Backend",
    version="1.0.0",
    description="Administrative backend API for WellScreen.",
)

@app.get("/health", tags=["Health"])
def health() -> dict[str, str]:
    return {"status": "ok"}

app.include_router(admin_users_router)
app.include_router(admin_settings_router)
app.include_router(admin_logs_router)
app.include_router(alerts_router)