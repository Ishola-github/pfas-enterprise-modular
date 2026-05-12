"""
Operational settings for the PFAS Enterprise 5 API.

Source of truth: environment variables, with safe development defaults and
a one-shot .env loader at import time (python-dotenv).

This module is intentionally **lightweight**:
- no enterprise RBAC
- no multi-tenant isolation
- no remote secret stores
- no kubernetes-specific config

The goal is "safe to run before paying users exist": API key auth,
deterministic config, no committed secrets.

All settings are exposed via the module-level `settings` singleton built
from the current environment. Importing this module loads `.env` from the
project root if present (additive; existing env vars win).
"""

from __future__ import annotations

import os
import secrets
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

try:
    from dotenv import load_dotenv

    _project_root = Path(__file__).resolve().parent.parent
    _env_file = _project_root / ".env"
    if _env_file.is_file():
        load_dotenv(_env_file, override=False)
except Exception:
    pass

API_VERSION = "5.0.0"
API_TITLE = "PFAS Enterprise 5.0 — operational screening API"

_AD_LANES = (
    "drinking_water",
    "serum",
    "biosolids_sludge",
    "afff",
    "methanol_standards",
    "air_emissions",
)


def _env_bool(key: str, default: bool) -> bool:
    raw = os.environ.get(key)
    if raw is None:
        return default
    return raw.strip().lower() in ("1", "true", "yes", "y", "on")


def _env_int(key: str, default: int) -> int:
    raw = os.environ.get(key)
    if raw is None or not raw.strip():
        return default
    try:
        return int(raw.strip())
    except ValueError:
        return default


def _env_float(key: str, default: float) -> float:
    raw = os.environ.get(key)
    if raw is None or not raw.strip():
        return default
    try:
        return float(raw.strip())
    except ValueError:
        return default


def _parse_api_keys(raw: str | None) -> dict[str, str]:
    """Parse PFAS_API_KEYS into {key_id: secret}.

    Accepts two formats:
        "alice:s3cr3t,bob:hunter2"   - csv of id:secret pairs
        "s3cr3t,hunter2"              - csv of plain secrets (id == "key_<idx>")

    Returns an empty mapping if the env var is missing or empty (the
    middleware will block all requests in that state unless explicitly in
    open mode — see `auth_open_mode`).
    """

    if not raw:
        return {}
    out: dict[str, str] = {}
    for i, token in enumerate(raw.split(",")):
        token = token.strip()
        if not token:
            continue
        if ":" in token:
            key_id, secret = token.split(":", 1)
            key_id = key_id.strip()
            secret = secret.strip()
        else:
            key_id = f"key_{i:02d}"
            secret = token
        if secret:
            out[key_id] = secret
    return out


@dataclass(frozen=True)
class Settings:
    """Immutable snapshot of runtime configuration."""

    app_env: str
    screening_use_only: bool
    project_root: Path
    api_title: str
    api_version: str

    # Authentication
    api_keys: dict[str, str]
    auth_open_mode: bool          # if True, requests with no key are accepted (DEV only)
    auth_header_name: str         # default: X-API-Key

    # Rate limiting (per-API-key, in-process token bucket)
    rate_limit_per_minute: int
    rate_limit_burst: int
    rate_limit_enabled: bool

    # Request logging
    log_level: str
    log_json: bool                # if False, fall back to plain text (dev only)
    access_log_path: Path | None  # None -> stdout only

    # AD enforcement (the API gates predictions on the AD framework)
    ad_strict_refusal: bool       # if True, AD reject -> HTTP 422; if False, soft 200 with prediction_refused=true
    ad_models_dir: Path
    apply_ad_guard_path: Path

    # Health endpoint
    expose_internal_paths: bool   # if False, /health hides paths (only versions + booleans)

    # Misc
    request_id_header: str        # default: X-Request-Id

    def safe_dump(self) -> dict[str, Any]:
        """Dictionary safe for /health and logs (no secrets, no internal paths
        unless explicitly enabled)."""
        return {
            "app_env": self.app_env,
            "screening_use_only": self.screening_use_only,
            "api_version": self.api_version,
            "auth_header": self.auth_header_name,
            "auth_open_mode": self.auth_open_mode,
            "num_api_keys": len(self.api_keys),
            "rate_limit_enabled": self.rate_limit_enabled,
            "rate_limit_per_minute": self.rate_limit_per_minute,
            "rate_limit_burst": self.rate_limit_burst,
            "log_level": self.log_level,
            "log_json": self.log_json,
            "ad_strict_refusal": self.ad_strict_refusal,
            "request_id_header": self.request_id_header,
            "expose_internal_paths": self.expose_internal_paths,
        }


def load_settings(project_root: Path | None = None) -> Settings:
    """Build a Settings snapshot from os.environ."""

    if project_root is None:
        project_root = Path(__file__).resolve().parent.parent

    api_keys = _parse_api_keys(os.environ.get("PFAS_API_KEYS"))
    auth_open_mode = _env_bool("PFAS_API_AUTH_OPEN", False)
    if not api_keys and not auth_open_mode and os.environ.get("APP_ENV", "development").lower() == "development":
        # Dev convenience: print a one-shot generated key. NOT for prod.
        gen = secrets.token_urlsafe(24)
        api_keys = {"dev": gen}
        print(
            "[pfas-api] WARNING: PFAS_API_KEYS not set; generated a dev key "
            f"(X-API-Key: {gen}). Set PFAS_API_KEYS in .env to lock in a value."
        )

    return Settings(
        app_env=os.environ.get("APP_ENV", "development"),
        screening_use_only=_env_bool("SCREENING_USE_ONLY", True),
        project_root=project_root,
        api_title=os.environ.get("PFAS_API_TITLE", API_TITLE),
        api_version=os.environ.get("PFAS_API_VERSION", API_VERSION),
        api_keys=api_keys,
        auth_open_mode=auth_open_mode,
        auth_header_name=os.environ.get("PFAS_API_AUTH_HEADER", "X-API-Key"),
        rate_limit_per_minute=_env_int("PFAS_API_RATE_LIMIT_PER_MINUTE", 60),
        rate_limit_burst=_env_int("PFAS_API_RATE_LIMIT_BURST", 20),
        rate_limit_enabled=_env_bool("PFAS_API_RATE_LIMIT_ENABLED", True),
        log_level=os.environ.get("PFAS_API_LOG_LEVEL", "INFO").upper(),
        log_json=_env_bool("PFAS_API_LOG_JSON", True),
        access_log_path=(
            Path(os.environ["PFAS_API_ACCESS_LOG"]).resolve()
            if os.environ.get("PFAS_API_ACCESS_LOG") else None
        ),
        ad_strict_refusal=_env_bool("PFAS_API_AD_STRICT_REFUSAL", True),
        ad_models_dir=project_root / "data" / "ad_models",
        apply_ad_guard_path=project_root / "scripts" / "apply_ad_guard.py",
        expose_internal_paths=_env_bool("PFAS_API_EXPOSE_PATHS", False),
        request_id_header=os.environ.get("PFAS_API_REQUEST_ID_HEADER", "X-Request-Id"),
    )


settings: Settings = load_settings()
