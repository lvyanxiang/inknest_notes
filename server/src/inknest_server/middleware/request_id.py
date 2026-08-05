from collections.abc import Awaitable, Callable
from contextvars import ContextVar, Token
from time import perf_counter
from uuid import uuid4

import structlog
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import Response

request_id_context: ContextVar[str | None] = ContextVar(
    "request_id",
    default=None,
)
logger = structlog.get_logger(__name__)


class RequestIdMiddleware(BaseHTTPMiddleware):
    async def dispatch(
        self,
        request: Request,
        call_next: Callable[[Request], Awaitable[Response]],
    ) -> Response:
        request_id = request.headers.get("x-request-id") or str(uuid4())
        request.state.request_id = request_id
        token: Token[str | None] = request_id_context.set(request_id)
        structlog.contextvars.bind_contextvars(request_id=request_id)
        started_at = perf_counter()

        try:
            response = await call_next(request)
            response.headers["x-request-id"] = request_id
            await logger.ainfo(
                "request_completed",
                method=request.method,
                path=request.url.path,
                status_code=response.status_code,
                duration_ms=round((perf_counter() - started_at) * 1000, 2),
            )
            return response
        finally:
            structlog.contextvars.unbind_contextvars("request_id")
            request_id_context.reset(token)
