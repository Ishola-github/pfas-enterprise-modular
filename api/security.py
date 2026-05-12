"""
Lightweight authentication for the PFAS Enterprise 5 API.

Contract:

    Every non-trivial route requires one of:
        - X-API-Key: <secret>          (header configurable via PFAS_API_AUTH_HEADER)

    Unauthenticated requests are rejected with HTTP 401 unless the API is
    running in **open mode** (PFAS_API_AUTH_OPEN=true, intended for local
    development only). Open mode is logged at startup.

    Constant-time secret comparison via secrets.compare_digest prevents
    timing-side-channel leaks.

No JWT issuer, no OAuth, no enterprise RBAC. A future authentication
upgrade slots in by replacing `authenticate_request` only.
"""

from __future__ import annotations

import hmac
from typing import Any

from fastapi import Header, HTTPException, Request, status

from api.settings import settings


def _constant_time_match(candidate: str, secrets_by_id: dict[str, str]) -> str | None:
    """Return the matching key_id (or None) using constant-time comparison
    over the full dict so total compare time does not leak which key
    matched first."""
    matched: str | None = None
    for key_id, secret in secrets_by_id.items():
        if hmac.compare_digest(candidate, secret):
            matched = matched or key_id
    return matched


def authenticate_request(request: Request) -> dict[str, Any]:
    """Validate request auth; return the auth context.

    Auth context is a dict:
        {"api_key_id": "<id>", "auth_mode": "api_key" | "open"}
    """
    if settings.auth_open_mode:
        return {"api_key_id": "", "auth_mode": "open"}

    presented = request.headers.get(settings.auth_header_name)
    if not presented:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={
                "error": "missing_api_key",
                "expected_header": settings.auth_header_name,
                "message": "Authentication required.",
            },
            headers={"WWW-Authenticate": f"ApiKey realm=\"pfas-enterprise\""},
        )

    if not settings.api_keys:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail={
                "error": "api_key_pool_empty",
                "message": (
                    "Server has no API keys configured. Set PFAS_API_KEYS or "
                    "PFAS_API_AUTH_OPEN=true for development."
                ),
            },
        )

    matched_id = _constant_time_match(presented, settings.api_keys)
    if matched_id is None:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={
                "error": "invalid_api_key",
                "message": "API key not recognized.",
            },
        )
    return {"api_key_id": matched_id, "auth_mode": "api_key"}
