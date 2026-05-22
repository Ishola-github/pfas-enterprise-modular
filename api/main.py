"""PFAS Enterprise 5 — operational screening API.

This is the **operational** layer (intended for programmatic clients,
CI/CD, and pilot integrations). The Shiny app (LatestPFAS.R) remains the
analyst/research console.

What this layer enforces:

    * API key authentication        (api/security.py)
    * Per-key rate limiting          (api/rate_limit.py)
    * Structured JSON access logs    (api/logging_setup.py)
    * Request ID propagation         (api/middleware.py)
    * AD-gated predictions with hard refusal propagation
      (api/ad_integration.py — same decisions as scripts/apply_ad_guard.py)
    * /health endpoint with version + manifest + registry status

Out of scope (per current SaaS phase):

    * billing / metering
    * multi-tenant isolation
    * enterprise RBAC / OAuth
    * Kubernetes / autoscaling
"""

from __future__ import annotations

import datetime as dt
import json
import logging
import os
import subprocess
import sys
from pathlib import Path
from typing import Any

from fastapi import Depends, FastAPI, HTTPException, Request, status
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field

from api.ad_integration import evaluate_with_summary, get_model, list_available_lanes
from api.logging_setup import configure_logger
from api.middleware import RateLimitMiddleware, RequestContextMiddleware
from api.rate_limit import RateLimiter
from api.security import authenticate_request
from api.settings import settings

try:
    from modules.sustainability import calculate_sustainability_metrics
except Exception:  # noqa: BLE001
    calculate_sustainability_metrics = None  # type: ignore[assignment]

LOGGER = configure_logger(
    level=settings.log_level,
    json_format=settings.log_json,
    access_log_path=settings.access_log_path,
)

_rate_limiter = RateLimiter(
    per_minute=settings.rate_limit_per_minute,
    burst=settings.rate_limit_burst,
)

app = FastAPI(
    title=settings.api_title,
    version=settings.api_version,
    description=(
        "Operational screening decision-support API. "
        "Predictions are gated by per-lane applicability-domain enforcement; "
        "rows outside the validated training envelope are REFUSED with HTTP 422 "
        "by default (PFAS_API_AD_STRICT_REFUSAL=true). "
        "Not EPA-approved, ISO-accredited, or a certified laboratory method."
    ),
)

app.add_middleware(RateLimitMiddleware, limiter=_rate_limiter)
app.add_middleware(RequestContextMiddleware)


def _env_float(key: str, default: str) -> float:
    try:
        return float(os.environ.get(key, default))
    except (TypeError, ValueError):
        return float(default)


def _utcnow_iso() -> str:
    return dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


# --------------------------------------------------------------------- #
# Models                                                                 #
# --------------------------------------------------------------------- #


class PredictV1Request(BaseModel):
    sample_id: str = Field(..., min_length=1, max_length=128)
    matrix_lane: str = Field(..., description=(
        "One of: drinking_water, serum, biosolids_sludge, afff, "
        "methanol_standards, air_emissions"
    ))
    matrix: str | None = None
    analyte: str | None = None
    cas_rn: str | None = None
    result_value_numeric: float | None = None
    result_unit: str | None = None
    qualifier: str | None = None
    method_id: str | None = None
    state: str | None = None
    facility_id: str | None = None
    value_type: str | None = None
    model_version: str | None = Field(
        default=None,
        description="Optional caller-supplied identifier of the model that produced "
                    "any downstream prediction (recorded in the access log).",
    )


class LegacyPredictRequest(BaseModel):
    sample_id: str
    dtxsid: str = Field(..., description="CompTox or internal substance identifier")
    method_id: str
    matrix: str


# --------------------------------------------------------------------- #
# Helpers                                                               #
# --------------------------------------------------------------------- #


def _registry_status() -> dict[str, Any]:
    """Run scripts/verify_reference_registry.py and parse the result.

    Returns a status block safe for /health. Failures are reported as
    'failed' rather than raising — health checks must not 500.
    """
    script = settings.project_root / "scripts" / "verify_reference_registry.py"
    if not script.is_file():
        return {"status": "missing_script", "rows": None,
                "last_check_utc": _utcnow_iso()}
    try:
        proc = subprocess.run(
            [sys.executable, str(script), "--project-root", str(settings.project_root)],
            capture_output=True, text=True, timeout=20,
        )
    except Exception as exc:  # noqa: BLE001
        return {"status": "error", "error": type(exc).__name__,
                "last_check_utc": _utcnow_iso()}
    out_text = (proc.stdout or "") + " " + (proc.stderr or "")
    if proc.returncode == 0:
        rows = None
        try:
            for token in out_text.split():
                if token.isdigit():
                    rows = int(token)
                    break
        except Exception:
            pass
        return {"status": "ok", "rows": rows, "last_check_utc": _utcnow_iso()}
    return {"status": "failed", "exit_code": proc.returncode,
            "last_check_utc": _utcnow_iso(),
            "summary": out_text[:500]}


def _manifest_availability() -> dict[str, bool]:
    return {
        "matrix_pipeline_sop": (settings.project_root / "data" / "config" / "matrix_pipeline_sop.csv").is_file(),
        "matrix_pipeline_summary": (settings.project_root / "data" / "training" / "matrix_pipeline_summary.json").is_file(),
        "ad_index": (settings.project_root / "data" / "ad_models" / "index.json").is_file(),
        "blind_validation_dir": (settings.project_root / "validation" / "blind_external").is_dir(),
    }


def _resolve_threshold_version(lane: str) -> str:
    candidates = {"drinking_water": "data/config/ucmr_analyte_limits_ngl.csv"}
    rel = candidates.get(lane)
    if not rel:
        return "none"
    p = settings.project_root / rel
    if not p.is_file():
        return "none"
    import hashlib
    h = hashlib.sha256()
    with p.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()[:12]


# --------------------------------------------------------------------- #
# Public routes                                                          #
# --------------------------------------------------------------------- #


@app.get("/health")
def health() -> dict[str, Any]:
    """Liveness + manifest + registry verification.

    No secrets, no internal paths (unless PFAS_API_EXPOSE_PATHS=true).
    """
    info: dict[str, Any] = {
        "status": "ok",
        "service": "pfas-enterprise-5",
        "api_version": settings.api_version,
        "checked_at_utc": _utcnow_iso(),
        "screening_use_only": settings.screening_use_only,
        "app_env": settings.app_env,
        "ad": {
            "available_lanes": list_available_lanes(),
            "framework_version_per_lane": {
                ln: (get_model(ln) or {}).get("ad_model_version", "")
                for ln in list_available_lanes()
            },
        },
        "manifests": _manifest_availability(),
        "registry_verification": _registry_status(),
        "config": settings.safe_dump(),
    }
    if settings.expose_internal_paths:
        info["paths"] = {
            "project_root": str(settings.project_root),
            "ad_models_dir": str(settings.ad_models_dir),
        }
    return info


@app.get("/healthz")
def healthz() -> dict[str, str]:
    return {"status": "ok", "service": "pfas-enterprise-5",
            "version": settings.api_version}


# --------------------------------------------------------------------- #
# Authenticated v1 endpoints                                            #
# --------------------------------------------------------------------- #


@app.get("/v1/whoami")
def whoami(request: Request, ctx: dict[str, Any] = Depends(authenticate_request)) -> dict[str, Any]:
    request.state.api_key_id = ctx["api_key_id"]
    return {
        "api_key_id": ctx["api_key_id"],
        "auth_mode": ctx["auth_mode"],
        "request_id": request.state.request_id,
        "rate_limit_per_minute": settings.rate_limit_per_minute,
    }


@app.get("/v1/ad/{lane}")
def ad_model_info(
    lane: str,
    request: Request,
    ctx: dict[str, Any] = Depends(authenticate_request),
) -> dict[str, Any]:
    request.state.api_key_id = ctx["api_key_id"]
    request.state.lane = lane
    model = get_model(lane)
    if model is None:
        raise HTTPException(
            status_code=404,
            detail={"error": "ad_model_not_found", "lane": lane,
                    "available_lanes": list_available_lanes()},
        )
    return {
        "pipeline_lane": model.get("pipeline_lane"),
        "ad_model_version": model.get("ad_model_version"),
        "ad_method": model.get("ad_method"),
        "training_range_version": model.get("training_range_version"),
        "training_csv_rows": model.get("training_csv_rows"),
        "thresholds": model.get("thresholds"),
        "global": model.get("global", {}),
        "value_lane": model.get("value_lane", False),
        "refusal_rules": model.get("refusal_rules", []),
    }


@app.post("/v1/predict")
def predict_v1(
    payload: PredictV1Request,
    request: Request,
    ctx: dict[str, Any] = Depends(authenticate_request),
) -> JSONResponse:
    """AD-gated single-row prediction.

    The current pipeline emits AD decisions as the primary scoring signal
    (a downstream production classifier is not yet wired). The response
    shape carries the canonical AD column contract verbatim plus a
    `prediction_refused` flag and an `intended_use` disclaimer.

    When PFAS_API_AD_STRICT_REFUSAL is true (default), AD `reject` returns
    HTTP 422 with the same payload. When false, HTTP 200 with
    `prediction_refused=true` is returned (soft mode; documented in logs).
    """
    request.state.api_key_id = ctx["api_key_id"]
    request.state.lane = payload.matrix_lane
    request.state.model_version = payload.model_version or ""

    row = payload.model_dump(exclude_none=False)
    summary = evaluate_with_summary(payload.matrix_lane, row)
    decision = summary["decision"]
    if "error" in decision:
        request.state.ad_status = ""
        request.state.prediction_refused = True
        raise HTTPException(
            status_code=400,
            detail={
                "error": "ad_lane_unknown",
                "lane": payload.matrix_lane,
                "available_lanes": decision.get("available_lanes", []),
                "request_id": request.state.request_id,
            },
        )

    refused = bool(summary["prediction_refused"])
    threshold_version = _resolve_threshold_version(payload.matrix_lane)
    request.state.ad_status = decision.get("ad_status", "")
    request.state.prediction_refused = refused
    request.state.threshold_version = threshold_version

    intended_use = (
        "Screening decision-support only. Not EPA-approved, ISO-accredited, "
        "or a certified laboratory method."
    )
    if not settings.screening_use_only:
        intended_use += " (SCREENING_USE_ONLY=false — production wiring required.)"

    body: dict[str, Any] = {
        "request_id": request.state.request_id,
        "sample_id": payload.sample_id,
        "matrix_lane": payload.matrix_lane,
        "ad_status": decision.get("ad_status"),
        "ad_distance": decision.get("ad_distance"),
        "ad_reason": decision.get("ad_reason"),
        "ad_method": decision.get("ad_method"),
        "ad_model_version": decision.get("ad_model_version"),
        "training_range_version": decision.get("training_range_version"),
        "ad_threshold": decision.get("ad_threshold"),
        "reference_lane": decision.get("reference_lane"),
        "nearest_training_source": decision.get("nearest_training_source"),
        "prediction_refused": refused,
        "threshold_version": threshold_version,
        "model_version": payload.model_version or "",
        "intended_use": intended_use,
        "prediction": (
            {"label": None, "score": None,
             "rationale": "AD-only gate; no production classifier wired"}
            if not refused else
            {"label": None, "score": None,
             "rationale": (
                 "Refused: outside validated applicability domain. "
                 "Resolve by analytical measurement or by submitting a "
                 "sample within the lane's chemical / matrix space."
             )}
        ),
    }

    if refused and settings.ad_strict_refusal:
        return JSONResponse(status_code=422, content=body)
    return JSONResponse(status_code=200, content=body)


@app.post("/predict")
def predict_legacy(
    req: LegacyPredictRequest,
    request: Request,
    ctx: dict[str, Any] = Depends(authenticate_request),
) -> dict[str, Any]:
    """Legacy demo endpoint (kept for back-compat with the original stub).

    Prefer /v1/predict for new integrations. This route still emits
    structured logs but does not run AD enforcement (no analyte / value
    in the legacy schema).
    """
    request.state.api_key_id = ctx["api_key_id"]
    request.state.lane = req.matrix

    intended = ("Screening decision-support only. Not EPA-approved, ISO-accredited, "
                "or a certified laboratory method.")
    if not settings.screening_use_only:
        intended += " (SCREENING_USE_ONLY=false — production wiring required.)"

    prediction = "borderline"
    confidence = 0.72
    sustainability: dict[str, Any] = {}
    if calculate_sustainability_metrics is not None:
        try:
            sustainability = calculate_sustainability_metrics(
                [{"prediction": prediction, "confidence": confidence}],
                cost_per_lab_analysis=_env_float("COST_PER_LAB_ANALYSIS_USD", "350"),
                kg_co2_per_sample=_env_float("KG_CO2_PER_SAMPLE", "2.5"),
            )
        except Exception:  # noqa: BLE001
            sustainability = {}

    return {
        "run_id": request.state.request_id,
        "sample_id": req.sample_id,
        "dtxsid": req.dtxsid,
        "method_id": req.method_id,
        "matrix": req.matrix,
        "prediction": prediction,
        "confidence": confidence,
        "ad_warning": (
            "Legacy /predict endpoint does NOT enforce applicability-domain "
            "gating. Use /v1/predict for AD-gated predictions."
        ),
        "intended_use": intended,
        "sustainability": sustainability,
        "deprecation_note": (
            "Use /v1/predict (AD-gated, refusal-propagated) for new integrations."
        ),
    }
