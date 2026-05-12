"""
ASGI middleware stack for the PFAS Enterprise 5 API.

Layered (outer to inner):

    1. RequestContextMiddleware   - assigns X-Request-Id, sets per-request state,
                                    catches stray exceptions, writes JSON access log
    2. RateLimitMiddleware        - in-process per-API-key token bucket
                                    (skipped for unauthenticated routes like /health)

Authentication itself is NOT a middleware: it is enforced as a FastAPI
dependency on each protected route (api.security.authenticate_request).
That keeps unauthenticated routes (/health, /openapi.json, /docs) trivially
accessible while still emitting full access logs for them.
"""

from __future__ import annotations

import logging
import time
import uuid
from typing import Any

from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import JSONResponse, Response
from starlette.types import ASGIApp

from api.rate_limit import RateLimiter
from api.settings import settings

LOGGER = logging.getLogger("pfas.api")


class RequestContextMiddleware(BaseHTTPMiddleware):
    """Assign request_id, capture latency, and emit one access-log line."""

    async def dispatch(self, request: Request, call_next: Any) -> Response:
        incoming = request.headers.get(settings.request_id_header)
        request_id = incoming if incoming else str(uuid.uuid4())

        request.state.request_id = request_id
        request.state.api_key_id = ""
        request.state.lane = ""
        request.state.ad_status = ""
        request.state.prediction_refused = False
        request.state.model_version = ""
        request.state.threshold_version = ""
        request.state.access_log_extra = {}

        t0 = time.perf_counter()
        try:
            response: Response = await call_next(request)
        except Exception as exc:  # noqa: BLE001
            elapsed_ms = int((time.perf_counter() - t0) * 1000)
            LOGGER.error(
                "request_exception",
                extra={
                    "request_id": request_id,
                    "method": request.method,
                    "path": request.url.path,
                    "status_code": 500,
                    "response_ms": elapsed_ms,
                    "api_key_id": request.state.api_key_id,
                    "exception": type(exc).__name__,
                },
                exc_info=exc,
            )
            response = JSONResponse(
                status_code=500,
                content={
                    "error": "internal_server_error",
                    "request_id": request_id,
                    "message": "An unexpected error occurred; see server logs.",
                },
            )

        elapsed_ms = int((time.perf_counter() - t0) * 1000)

        response.headers[settings.request_id_header] = request_id
        response.headers["X-PFAS-API-Version"] = settings.api_version
        if response.status_code >= 400:
            response.headers["X-Screening-Use-Only"] = "true" if settings.screening_use_only else "false"

        extra: dict[str, Any] = {
            "request_id": request_id,
            "method": request.method,
            "path": request.url.path,
            "status_code": response.status_code,
            "response_ms": elapsed_ms,
            "api_key_id": getattr(request.state, "api_key_id", "") or "",
            "lane": getattr(request.state, "lane", "") or "",
            "ad_status": getattr(request.state, "ad_status", "") or "",
            "prediction_refused": bool(getattr(request.state, "prediction_refused", False)),
            "model_version": getattr(request.state, "model_version", "") or "",
            "threshold_version": getattr(request.state, "threshold_version", "") or "",
        }
        extra.update(getattr(request.state, "access_log_extra", {}) or {})

        LOGGER.info("access", extra=extra)
        return response


class RateLimitMiddleware(BaseHTTPMiddleware):
    """In-process per-API-key token bucket. No-op for whitelisted paths.

    Authentication is performed AFTER this middleware (as a route
    dependency), so we use the presented X-API-Key header as the bucket
    key. Unauthenticated requests fall into a single "anon" bucket — this
    is intentional, because rate-limiting before auth protects the auth
    path itself from brute force.
    """

    UNGATED_PATHS = frozenset({"/health", "/healthz", "/openapi.json",
                               "/docs", "/redoc", "/favicon.ico"})

    def __init__(self, app: ASGIApp, limiter: RateLimiter) -> None:
        super().__init__(app)
        self.limiter = limiter

    async def dispatch(self, request: Request, call_next: Any) -> Response:
        if not settings.rate_limit_enabled:
            return await call_next(request)
        if request.url.path in self.UNGATED_PATHS:
            return await call_next(request)

        presented = request.headers.get(settings.auth_header_name, "") or "anon"
        bucket_key = f"k:{presented[:32]}"

        allowed, retry_after, remaining = self.limiter.try_acquire(bucket_key)
        if not allowed:
            return JSONResponse(
                status_code=429,
                content={
                    "error": "rate_limit_exceeded",
                    "retry_after_seconds": round(retry_after, 3),
                    "tokens_remaining": round(remaining, 3),
                    "limit_per_minute": settings.rate_limit_per_minute,
                    "burst": settings.rate_limit_burst,
                    "request_id": getattr(request.state, "request_id", ""),
                },
                headers={
                    "Retry-After": str(max(1, int(retry_after))),
                    "X-RateLimit-Limit": str(settings.rate_limit_per_minute),
                    "X-RateLimit-Burst": str(settings.rate_limit_burst),
                    "X-RateLimit-Remaining": str(int(remaining)),
                },
            )

        response = await call_next(request)
        response.headers["X-RateLimit-Limit"] = str(settings.rate_limit_per_minute)
        response.headers["X-RateLimit-Burst"] = str(settings.rate_limit_burst)
        response.headers["X-RateLimit-Remaining"] = str(int(remaining))
        return response
