from fastapi import APIRouter

from inknest_server.api.v1.assets import router as assets_router
from inknest_server.api.v1.auth import router as auth_router
from inknest_server.api.v1.health import router as health_router
from inknest_server.api.v1.sync import router as sync_router

router = APIRouter()
router.include_router(health_router)
router.include_router(auth_router)
router.include_router(assets_router)
router.include_router(sync_router)
