from typing import Any, cast

from fastapi import APIRouter, Request

from inknest_server.services.readiness import ReadinessChecker

router = APIRouter(prefix="/health", tags=["health"])


@router.get("/live")
async def live() -> dict[str, str]:
    return {"status": "ok", "service": "inknest-server"}


@router.get("/ready")
async def ready(request: Request) -> dict[str, Any]:
    checker = cast(ReadinessChecker, request.app.state.readiness_checker)
    checks = await checker.check()
    return {"status": "ready", "checks": checks}
