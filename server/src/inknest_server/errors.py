from typing import Any

import structlog
from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException

logger = structlog.get_logger(__name__)


class ApiError(Exception):
    def __init__(
        self,
        *,
        code: str,
        message: str,
        status_code: int,
        details: dict[str, Any] | None = None,
        headers: dict[str, str] | None = None,
    ) -> None:
        super().__init__(message)
        self.code = code
        self.message = message
        self.status_code = status_code
        self.details = details
        self.headers = headers


class DependenciesUnavailableError(ApiError):
    def __init__(self, checks: dict[str, dict[str, str]]) -> None:
        super().__init__(
            code="dependencies_unavailable",
            message="One or more required services are unavailable.",
            status_code=503,
            details={"checks": checks},
        )


def _payload(
    request: Request,
    *,
    code: str,
    message: str,
    details: dict[str, Any] | None = None,
) -> dict[str, Any]:
    error: dict[str, Any] = {
        "code": code,
        "message": message,
        "requestId": getattr(request.state, "request_id", None),
    }
    if details is not None:
        error["details"] = details
    return {"error": error}


def register_error_handlers(app: FastAPI) -> None:
    @app.exception_handler(ApiError)
    async def handle_api_error(request: Request, error: ApiError) -> JSONResponse:
        return JSONResponse(
            status_code=error.status_code,
            content=_payload(
                request,
                code=error.code,
                message=error.message,
                details=error.details,
            ),
            headers=error.headers,
        )

    @app.exception_handler(RequestValidationError)
    async def handle_validation_error(
        request: Request,
        error: RequestValidationError,
    ) -> JSONResponse:
        issues = [
            {
                "location": [str(part) for part in issue["loc"]],
                "message": issue["msg"],
                "type": issue["type"],
            }
            for issue in error.errors()
        ]
        return JSONResponse(
            status_code=422,
            content=_payload(
                request,
                code="validation_error",
                message="The request is invalid.",
                details={"issues": issues},
            ),
        )

    @app.exception_handler(HTTPException)
    async def handle_http_error(
        request: Request,
        error: HTTPException,
    ) -> JSONResponse:
        code = "not_found" if error.status_code == 404 else "http_error"
        message = str(error.detail) if error.detail else "The request failed."
        return JSONResponse(
            status_code=error.status_code,
            content=_payload(request, code=code, message=message),
            headers=error.headers,
        )

    @app.exception_handler(Exception)
    async def handle_unexpected_error(
        request: Request,
        error: Exception,
    ) -> JSONResponse:
        await logger.aerror(
            "unhandled_request_error",
            error_type=type(error).__name__,
        )
        return JSONResponse(
            status_code=500,
            content=_payload(
                request,
                code="internal_error",
                message="An unexpected error occurred.",
            ),
        )
