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

import csv
import datetime as dt
import hashlib
import json
import logging
import os
import subprocess
import sys
from pathlib import Path
from typing import Any

from fastapi import Depends, FastAPI, HTTPException, Query, Request, status
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


class QAQCRow(BaseModel):
    batch_id: str = Field(..., min_length=1, max_length=128)
    qc_type: str = Field(..., min_length=1, max_length=64)
    mdl: float | None = None
    loq: float | None = None
    blank_pass: bool | None = None
    duplicate_rpd: float | None = None
    calibration_pass: bool | None = None
    eis_pass: bool | None = None
    nis_pass: bool | None = None
    notes: str | None = None


class QAQCValidateRequest(BaseModel):
    batch_id: str = Field(..., min_length=1, max_length=128)
    method_source: str = Field(default="EPA_1633A", min_length=1, max_length=128)
    matrix: str | None = None
    strict: bool = Field(
        default=True,
        description="When true, hard-fail batch QC violations with HTTP 422.",
    )
    rows: list[QAQCRow] = Field(..., min_length=1)
    evidence_tag: str | None = Field(default=None, max_length=128)


class BiomonitoringAnalyteValue(BaseModel):
    analyte: str = Field(..., min_length=1, max_length=128)
    value: float = Field(..., ge=0.0)
    unit: str = Field(default="ng/mL", min_length=1, max_length=16)
    qualifier: str = Field(default="measured", min_length=1, max_length=64)


class BiomonitoringPercentileContext(BaseModel):
    analyte: str = Field(..., min_length=1, max_length=128)
    reference_population: str = Field(..., min_length=1, max_length=256)
    percentile: float = Field(..., ge=0.0, le=100.0)
    band: str = Field(default="typical", min_length=1, max_length=32)


class BiomonitoringPathwayFlag(BaseModel):
    pathway_name: str = Field(..., min_length=1, max_length=256)
    direction: str = Field(default="mixed_or_unclear", min_length=1, max_length=64)
    evidence_level: str = Field(default="exploratory", min_length=1, max_length=64)
    rationale: str = Field(..., min_length=10, max_length=4000)


class BiomonitoringInterpretRequest(BaseModel):
    subject_id: str = Field(..., min_length=1, max_length=120)
    matrix_lane: str = Field(default="serum", min_length=1, max_length=64)
    source_dataset: str = Field(..., min_length=1, max_length=256)
    analyte_values: list[BiomonitoringAnalyteValue] = Field(..., min_length=1)
    percentile_context: list[BiomonitoringPercentileContext] = Field(..., min_length=1)
    pathway_flags: list[BiomonitoringPathwayFlag] = Field(default_factory=list)
    overall_interpretation_override: str | None = Field(default=None, max_length=4000)
    confidence_tier: str | None = Field(default=None, max_length=64)
    human_review_status: str = Field(default="pending", min_length=1, max_length=64)
    claim_boundary: dict[str, str] | None = None
    provenance: dict[str, Any] | None = None
    strict_claim_boundary: bool = Field(default=True)


class QAQCExplainRequest(BaseModel):
    reason_code: str = Field(..., min_length=1, max_length=128)
    context: dict[str, Any] | None = None


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
        "literature_priority_registry": (
            settings.project_root
            / "data"
            / "reference"
            / "literature"
            / "acs_chemrestox_priority_registry.json"
        ).is_file(),
        "qaqc_limits_1633a": (
            settings.project_root / "data" / "reference" / "epa_1633a_qc_limits.csv"
        ).is_file(),
        "qaqc_batch_schema_1633a": (
            settings.project_root / "data" / "reference" / "epa_1633a_qc_batch_schema.csv"
        ).is_file(),
        "qaqc_method_metadata_1633a": (
            settings.project_root / "data" / "reference" / "epa_1633a_method_metadata.csv"
        ).is_file(),
        "pfas_nta_qaqc_schema_v1": (
            settings.project_root / "validation" / "PFAS_NTA_QAQC_SCHEMA_v1.json"
        ).is_file(),
        "fair_env_metadata_profile_v1": (
            settings.project_root / "validation" / "fair_env_metadata_profile_v1.json"
        ).is_file(),
        "qaqc_reason_code_taxonomy_v1": (
            settings.project_root / "validation" / "qaqc_reason_code_taxonomy_v1.json"
        ).is_file(),
        "biomonitoring_interpretation_v0": (
            settings.project_root / "validation" / "biomonitoring_interpretation_v0.json"
        ).is_file(),
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


def _load_literature_priority_registry() -> dict[str, Any]:
    """Load governed literature-triage decisions from the reference pack."""
    path = (
        settings.project_root
        / "data"
        / "reference"
        / "literature"
        / "acs_chemrestox_priority_registry.json"
    )
    if not path.is_file():
        raise HTTPException(
            status_code=503,
            detail={
                "error": "literature_registry_missing",
                "path": str(path.relative_to(settings.project_root)),
            },
        )
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(
            status_code=503,
            detail={
                "error": "literature_registry_unreadable",
                "exception": type(exc).__name__,
            },
        ) from exc
    if not isinstance(payload, dict):
        raise HTTPException(
            status_code=503,
            detail={"error": "literature_registry_invalid_shape"},
        )
    return payload


def _build_literature_backlog(
    papers: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    """Convert curated paper decisions into module-level integration tasks."""
    module_index: dict[str, dict[str, Any]] = {}
    for paper in papers:
        doi = str(paper.get("doi", "")).strip()
        decision = str(paper.get("decision", "")).strip()
        mapped_modules = paper.get("mapped_modules", [])
        hypotheses = paper.get("relevance_hypothesis", [])
        if not doi or not isinstance(mapped_modules, list):
            continue
        for module in mapped_modules:
            if not isinstance(module, str) or not module.strip():
                continue
            bucket = module_index.setdefault(
                module.strip(),
                {"dois": set(), "decisions": set(), "hypotheses": set()},
            )
            bucket["dois"].add(doi)
            if decision:
                bucket["decisions"].add(decision)
            if isinstance(hypotheses, list):
                for h in hypotheses:
                    if isinstance(h, str) and h.strip():
                        bucket["hypotheses"].add(h.strip())

    backlog: list[dict[str, Any]] = []
    for module in sorted(module_index):
        item = module_index[module]
        decisions = sorted(item["decisions"])
        dois = sorted(item["dois"])
        hypotheses = sorted(item["hypotheses"])
        ready = "include_now" in item["decisions"]
        task_id = "lit-" + module.lower().replace(" ", "-").replace("/", "-")
        backlog.append(
            {
                "task_id": task_id,
                "module": module,
                "priority": "high" if ready else "medium",
                "status": "ready" if ready else "blocked_pending_full_text_review",
                "source_dois": dois,
                "source_decisions": decisions,
                "action": (
                    f"Design and implement literature-backed feature increments for {module}."
                ),
                "rationale_signals": hypotheses[:5],
            }
        )
    return backlog


def _export_backlog_items(
    tasks: list[dict[str, Any]],
    target: str,
) -> list[dict[str, Any]]:
    """Convert backlog tasks into tracker-friendly payloads."""
    out: list[dict[str, Any]] = []
    for task in tasks:
        module = str(task.get("module", "")).strip()
        if not module:
            continue
        dois = task.get("source_dois", [])
        doi_text = ", ".join(dois) if isinstance(dois, list) else ""
        status = str(task.get("status", "")).strip()
        priority = str(task.get("priority", "")).strip().upper()
        action = str(task.get("action", "")).strip()
        rationale = task.get("rationale_signals", [])
        rationale_text = (
            ", ".join(rationale[:5])
            if isinstance(rationale, list)
            else ""
        )
        title = f"[PFAS Literature] {module}"
        description = (
            f"{action}\n\n"
            f"Source DOIs: {doi_text}\n"
            f"Generated status: {status}\n"
            f"Rationale signals: {rationale_text}"
        )
        labels = [
            "pfas-enterprise",
            "literature-integration",
            module.lower().replace(" ", "-"),
        ]
        if status == "blocked_pending_full_text_review":
            labels.append("blocked")
        if target == "jira":
            out.append(
                {
                    "summary": title,
                    "description": description,
                    "labels": labels,
                    "priority": priority,
                    "custom_fields": {
                        "module": module,
                        "source_dois": dois,
                        "integration_status": status,
                    },
                }
            )
        else:
            out.append(
                {
                    "title": title,
                    "description": description,
                    "labels": labels,
                    "priority": priority,
                    "state": "Todo" if status == "ready" else "Backlog",
                    "metadata": {
                        "module": module,
                        "source_dois": dois,
                        "integration_status": status,
                    },
                }
            )
    return out


def _csv_rows(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8", newline="") as fh:
        reader = csv.DictReader(fh)
        return [
            {str(k): (v or "") for k, v in row.items()}
            for row in reader
            if isinstance(row, dict)
        ]


def _sha256_prefix(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()[:12]


def _load_qaqc_reference_bundle() -> dict[str, Any]:
    ref_dir = settings.project_root / "data" / "reference"
    paths = {
        "qaqc_limits": ref_dir / "epa_1633a_qc_limits.csv",
        "qaqc_batch_schema": ref_dir / "epa_1633a_qc_batch_schema.csv",
        "method_metadata": ref_dir / "epa_1633a_method_metadata.csv",
    }
    missing = [name for name, p in paths.items() if not p.is_file()]
    if missing:
        raise HTTPException(
            status_code=503,
            detail={
                "error": "qaqc_reference_missing",
                "missing": missing,
            },
        )
    rows = {k: _csv_rows(p) for k, p in paths.items()}
    method_sources = sorted(
        {
            str(r.get("method_source", "")).strip()
            for r in rows["method_metadata"]
            if str(r.get("method_source", "")).strip()
        }
    )
    allowed_qc_types = sorted(
        {
            str(r.get("qc_type", "")).strip()
            for r in rows["qaqc_batch_schema"]
            if str(r.get("qc_type", "")).strip()
            and not str(r.get("qc_type", "")).strip().startswith("TEMPLATE_")
        }
    )
    return {
        "rows": rows,
        "paths": {k: str(v.relative_to(settings.project_root)) for k, v in paths.items()},
        "hashes": {k: _sha256_prefix(v) for k, v in paths.items()},
        "method_sources": method_sources,
        "allowed_qc_types": allowed_qc_types,
    }


def _load_json_artifact(path: Path, missing_error: str, unreadable_error: str) -> dict[str, Any]:
    if not path.is_file():
        raise HTTPException(
            status_code=503,
            detail={"error": missing_error, "path": str(path.relative_to(settings.project_root))},
        )
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(
            status_code=503,
            detail={"error": unreadable_error, "exception": type(exc).__name__},
        ) from exc
    if not isinstance(payload, dict):
        raise HTTPException(status_code=503, detail={"error": unreadable_error + "_shape"})
    return payload


def _load_qaqc_governance_bundle() -> dict[str, Any]:
    base = settings.project_root / "validation"
    paths = {
        "nta_qaqc_schema": base / "PFAS_NTA_QAQC_SCHEMA_v1.json",
        "fair_env_metadata_profile": base / "fair_env_metadata_profile_v1.json",
        "reason_code_taxonomy": base / "qaqc_reason_code_taxonomy_v1.json",
    }
    artifacts = {
        "nta_qaqc_schema": _load_json_artifact(
            paths["nta_qaqc_schema"],
            missing_error="nta_qaqc_schema_missing",
            unreadable_error="nta_qaqc_schema_unreadable",
        ),
        "fair_env_metadata_profile": _load_json_artifact(
            paths["fair_env_metadata_profile"],
            missing_error="fair_env_metadata_profile_missing",
            unreadable_error="fair_env_metadata_profile_unreadable",
        ),
        "reason_code_taxonomy": _load_json_artifact(
            paths["reason_code_taxonomy"],
            missing_error="qaqc_reason_code_taxonomy_missing",
            unreadable_error="qaqc_reason_code_taxonomy_unreadable",
        ),
    }
    return {
        "artifacts": artifacts,
        "paths": {k: str(v.relative_to(settings.project_root)) for k, v in paths.items()},
        "hashes": {k: _sha256_prefix(v) for k, v in paths.items()},
    }


def _derive_taxonomy_reason_codes(
    failures: list[dict[str, str]],
    warnings: list[dict[str, str]],
) -> list[str]:
    code_map = {
        "batch_id_mismatch": "metadata_incomplete",
        "unknown_qc_type": "metadata_incomplete",
        "method_blank_failed": "method_blank_contamination_detected",
        "calibration_failed": "calibration_fit_out_of_range",
        "recovery_gate_failed": "surrogate_recovery_out_of_range",
        "required_qc_type_missing": "metadata_incomplete",
        "duplicate_rpd_missing": "replicate_precision_out_of_range",
        "mdl_loq_missing": "metadata_incomplete",
    }
    out: list[str] = []
    for item in failures + warnings:
        src = str(item.get("code", "")).strip()
        mapped = code_map.get(src)
        if mapped:
            out.append(mapped)
    if not out:
        out.append("human_review_required")
    return sorted(set(out))


def _load_biomonitoring_schema_bundle() -> dict[str, Any]:
    path = settings.project_root / "validation" / "biomonitoring_interpretation_v0.json"
    payload = _load_json_artifact(
        path=path,
        missing_error="biomonitoring_schema_missing",
        unreadable_error="biomonitoring_schema_unreadable",
    )
    return {
        "path": str(path.relative_to(settings.project_root)),
        "hash": _sha256_prefix(path),
        "schema": payload,
    }


def _contains_forbidden_language(text: str, terms: list[str]) -> str | None:
    text_norm = text.lower()
    for term in terms:
        needle = str(term).strip().lower()
        if needle and needle in text_norm:
            return needle
    return None


QAQC_EXPLANATIONS: dict[str, dict[str, str]] = {
    "METHOD_BLANK_FAILED": {
        "severity": "fail",
        "explanation": (
            "Method blank criteria were not met, indicating possible contamination "
            "during preparation or analysis. Human review is required before result release."
        ),
    },
    "LCS_RECOVERY_LOW": {
        "severity": "fail",
        "explanation": (
            "Laboratory control sample recovery was below acceptance criteria, suggesting "
            "possible low bias in the batch. Human review is required."
        ),
    },
    "LCS_RECOVERY_HIGH": {
        "severity": "fail",
        "explanation": (
            "Laboratory control sample recovery was above acceptance criteria, suggesting "
            "possible high bias or interference. Human review is required."
        ),
    },
    "MS_RECOVERY_LOW": {
        "severity": "warning",
        "explanation": (
            "Matrix spike recovery was low, suggesting matrix effects or recovery loss. "
            "A reviewer should evaluate affected samples."
        ),
    },
    "MS_RECOVERY_HIGH": {
        "severity": "warning",
        "explanation": (
            "Matrix spike recovery was high, suggesting matrix enhancement or interference. "
            "A reviewer should evaluate affected samples."
        ),
    },
    "RPD_EXCEEDED": {
        "severity": "warning",
        "explanation": (
            "Duplicate precision exceeded acceptance limits. The reviewer should assess "
            "sample heterogeneity, preparation records, and replicate performance."
        ),
    },
    "EIS_RECOVERY_LOW": {
        "severity": "warning",
        "explanation": (
            "Extracted internal standard recovery was low, suggesting possible extraction loss, "
            "suppression, or preparation issue. Human review is required."
        ),
    },
    "EIS_RECOVERY_HIGH": {
        "severity": "warning",
        "explanation": (
            "Extracted internal standard recovery was high, suggesting possible enhancement or "
            "integration issue. Human review is required."
        ),
    },
    "NIS_RECOVERY_LOW": {
        "severity": "warning",
        "explanation": (
            "Non-extracted internal standard recovery was low, suggesting possible instrument "
            "response or injection issue. Reviewer assessment is required."
        ),
    },
    "NIS_RECOVERY_HIGH": {
        "severity": "warning",
        "explanation": (
            "Non-extracted internal standard recovery was high, suggesting possible response "
            "enhancement or calibration issue. Reviewer assessment is required."
        ),
    },
    "CALIBRATION_FAILED": {
        "severity": "fail",
        "explanation": (
            "Calibration criteria were not met. Quantitative results should not be released "
            "until calibration performance is reviewed."
        ),
    },
    "CCV_FAILED": {
        "severity": "fail",
        "explanation": (
            "Continuing calibration verification failed, indicating possible instrument drift "
            "or calibration instability. Human review is required."
        ),
    },
    "ION_RATIO_FAILED": {
        "severity": "warning",
        "explanation": (
            "Ion ratio criteria were not met, suggesting possible interference or "
            "identification uncertainty. Reviewer confirmation is required."
        ),
    },
    "RETENTION_TIME_FAILED": {
        "severity": "warning",
        "explanation": (
            "Retention time criteria were not met, suggesting possible identification or "
            "chromatography issue. Human review is required."
        ),
    },
    "SURROGATE_FAILED": {
        "severity": "warning",
        "explanation": (
            "Surrogate recovery criteria were not met, suggesting possible recovery or "
            "matrix-related issue. Reviewer assessment is required."
        ),
    },
    "FIELD_BLANK_DETECTED": {
        "severity": "warning",
        "explanation": (
            "Field blank detection suggests possible field, transport, or handling contamination. "
            "Reviewer assessment is required."
        ),
    },
    "HOLDING_TIME_EXCEEDED": {
        "severity": "warning",
        "explanation": (
            "Holding time was exceeded. Results may require qualification before release."
        ),
    },
    "MISSING_REQUIRED_QC": {
        "severity": "fail",
        "explanation": (
            "Required QC elements were missing from the batch record. The batch cannot be fully "
            "evaluated without human review."
        ),
    },
    "SCHEMA_VALIDATION_FAILED": {
        "severity": "fail",
        "explanation": (
            "The submitted batch record does not match the required schema. The file must be "
            "corrected before automated review can proceed."
        ),
    },
    "UNKNOWN_REASON_CODE": {
        "severity": "warning",
        "explanation": (
            "The reason code is not recognized by the governed taxonomy. Human review is required "
            "before interpretation or release."
        ),
    },
}


def _normalize_reason_code(reason_code: str) -> str:
    text = str(reason_code or "").strip()
    if not text:
        return ""
    # Accept mixed separators/casing from demos and clients:
    # METHOD_BLANK_FAILED / method blank failed / method-blank-failed.
    text = text.replace("-", " ").replace("_", " ")
    parts = [p for p in text.split() if p]
    return "_".join(parts).upper()


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


@app.get("/v1/literature/priorities")
def literature_priorities(
    request: Request,
    include_deferred: bool = Query(
        default=False,
        description=(
            "When false, return only `include_now` decisions. "
            "When true, include `defer_pending_full_text_review` entries."
        ),
    ),
    ctx: dict[str, Any] = Depends(authenticate_request),
) -> dict[str, Any]:
    """Governed literature triage aligned to PFAS Enterprise modules."""
    request.state.api_key_id = ctx["api_key_id"]
    data = _load_literature_priority_registry()
    papers = data.get("papers", [])
    if not isinstance(papers, list):
        papers = []
    filtered = [
        p for p in papers
        if isinstance(p, dict)
        and (
            include_deferred
            or p.get("decision") == "include_now"
        )
    ]
    include_now_count = sum(
        1 for p in papers
        if isinstance(p, dict) and p.get("decision") == "include_now"
    )
    defer_count = sum(
        1 for p in papers
        if isinstance(p, dict) and p.get("decision") == "defer_pending_full_text_review"
    )
    return {
        "registry_id": data.get("registry_id", ""),
        "version": data.get("version", ""),
        "generated_utc": data.get("generated_utc", ""),
        "selection_policy": data.get("selection_policy", []),
        "strategic_categories": data.get("strategic_categories", []),
        "summary": {
            "total_papers": len(papers),
            "include_now": include_now_count,
            "defer_pending_full_text_review": defer_count,
            "returned": len(filtered),
        },
        "papers": filtered,
    }


@app.get("/v1/literature/integration-backlog")
def literature_integration_backlog(
    request: Request,
    include_deferred: bool = Query(
        default=False,
        description=(
            "When false, generate backlog from `include_now` papers only. "
            "When true, include deferred papers as blocked tasks."
        ),
    ),
    ctx: dict[str, Any] = Depends(authenticate_request),
) -> dict[str, Any]:
    """Actionable module backlog generated from governed literature triage."""
    request.state.api_key_id = ctx["api_key_id"]
    data = _load_literature_priority_registry()
    raw = data.get("papers", [])
    papers = [p for p in raw if isinstance(p, dict)] if isinstance(raw, list) else []
    selected = [
        p for p in papers
        if include_deferred or p.get("decision") == "include_now"
    ]
    backlog = _build_literature_backlog(selected)
    return {
        "registry_id": data.get("registry_id", ""),
        "version": data.get("version", ""),
        "generated_utc": data.get("generated_utc", ""),
        "include_deferred": include_deferred,
        "summary": {
            "source_papers_considered": len(selected),
            "tasks_generated": len(backlog),
            "ready_tasks": sum(1 for t in backlog if t.get("status") == "ready"),
            "blocked_tasks": sum(
                1 for t in backlog if t.get("status") == "blocked_pending_full_text_review"
            ),
        },
        "tasks": backlog,
    }


@app.post("/v1/literature/integration-backlog/export")
def export_literature_integration_backlog(
    request: Request,
    target: str = Query(
        default="linear",
        description="Export payload shape. One of: linear, jira.",
    ),
    include_deferred: bool = Query(
        default=False,
        description=(
            "When false, export only implementation-ready tasks. "
            "When true, include blocked deferred-review tasks."
        ),
    ),
    ctx: dict[str, Any] = Depends(authenticate_request),
) -> dict[str, Any]:
    """Export literature backlog tasks into tracker-ingest payloads."""
    request.state.api_key_id = ctx["api_key_id"]
    target_norm = target.strip().lower()
    if target_norm not in {"linear", "jira"}:
        raise HTTPException(
            status_code=400,
            detail={
                "error": "invalid_export_target",
                "allowed_targets": ["linear", "jira"],
            },
        )
    data = _load_literature_priority_registry()
    raw = data.get("papers", [])
    papers = [p for p in raw if isinstance(p, dict)] if isinstance(raw, list) else []
    selected = [
        p for p in papers
        if include_deferred or p.get("decision") == "include_now"
    ]
    tasks = _build_literature_backlog(selected)
    issues = _export_backlog_items(tasks=tasks, target=target_norm)
    return {
        "registry_id": data.get("registry_id", ""),
        "version": data.get("version", ""),
        "generated_utc": data.get("generated_utc", ""),
        "target": target_norm,
        "include_deferred": include_deferred,
        "summary": {
            "source_papers_considered": len(selected),
            "tasks_exported": len(issues),
        },
        "issues": issues,
    }


@app.post("/v1/qaqc/validate")
def qaqc_validate(
    payload: QAQCValidateRequest,
    request: Request,
    ctx: dict[str, Any] = Depends(authenticate_request),
) -> JSONResponse:
    """Validate EPA 1633A-style QC batch rows and emit evidence artifact."""
    request.state.api_key_id = ctx["api_key_id"]
    ref_bundle = _load_qaqc_reference_bundle()
    governance_bundle = _load_qaqc_governance_bundle()
    allowed_qc_types = set(ref_bundle["allowed_qc_types"])
    if payload.method_source not in set(ref_bundle["method_sources"]):
        raise HTTPException(
            status_code=400,
            detail={
                "error": "unknown_method_source",
                "method_source": payload.method_source,
                "allowed_method_sources": ref_bundle["method_sources"],
            },
        )

    failures: list[dict[str, str]] = []
    warnings: list[dict[str, str]] = []
    row_checks: list[dict[str, Any]] = []
    present_qc_types: set[str] = set()

    for i, row in enumerate(payload.rows):
        qc_type = row.qc_type.strip()
        present_qc_types.add(qc_type)
        if row.batch_id != payload.batch_id:
            failures.append(
                {
                    "row": str(i),
                    "code": "batch_id_mismatch",
                    "message": "Row batch_id differs from payload batch_id.",
                }
            )
        if qc_type not in allowed_qc_types:
            failures.append(
                {
                    "row": str(i),
                    "code": "unknown_qc_type",
                    "message": f"qc_type '{qc_type}' not present in governed schema.",
                }
            )
        if qc_type == "method_blank" and row.blank_pass is not True:
            failures.append(
                {
                    "row": str(i),
                    "code": "method_blank_failed",
                    "message": "method_blank requires blank_pass=true.",
                }
            )
        if qc_type == "calibration_check" and row.calibration_pass is not True:
            failures.append(
                {
                    "row": str(i),
                    "code": "calibration_failed",
                    "message": "calibration_check requires calibration_pass=true.",
                }
            )
        if qc_type in {"ipr", "opr", "llopr"} and row.eis_pass is not True:
            failures.append(
                {
                    "row": str(i),
                    "code": "recovery_gate_failed",
                    "message": f"{qc_type} requires eis_pass=true.",
                }
            )
        if qc_type in {"field_duplicate", "lab_duplicate"} and row.duplicate_rpd is None:
            warnings.append(
                {
                    "row": str(i),
                    "code": "duplicate_rpd_missing",
                    "message": f"{qc_type} has no duplicate_rpd; evaluate per method/SOP.",
                }
            )
        if qc_type in {"mdl_study", "loq_study"} and row.mdl is None and row.loq is None:
            warnings.append(
                {
                    "row": str(i),
                    "code": "mdl_loq_missing",
                    "message": f"{qc_type} missing mdl/loq numeric values.",
                }
            )
        row_checks.append(
            {
                "row": i,
                "batch_id": row.batch_id,
                "qc_type": qc_type,
                "blank_pass": row.blank_pass,
                "calibration_pass": row.calibration_pass,
                "eis_pass": row.eis_pass,
                "nis_pass": row.nis_pass,
                "duplicate_rpd": row.duplicate_rpd,
                "mdl": row.mdl,
                "loq": row.loq,
            }
        )

    for required in ("method_blank", "calibration_check", "ipr", "opr"):
        if required not in present_qc_types:
            failures.append(
                {
                    "row": "global",
                    "code": "required_qc_type_missing",
                    "message": f"Required qc_type '{required}' not present in payload rows.",
                }
            )

    validation_status = (
        "fail" if failures else
        ("pass_with_warnings" if warnings else "pass")
    )

    taxonomy = governance_bundle["artifacts"]["reason_code_taxonomy"]
    taxonomy_catalog = taxonomy.get("reason_codes", [])
    taxonomy_allowed = {
        str(item.get("code", "")).strip()
        for item in taxonomy_catalog
        if isinstance(item, dict) and str(item.get("code", "")).strip()
    }
    reason_codes = _derive_taxonomy_reason_codes(failures=failures, warnings=warnings)
    reason_codes = [code for code in reason_codes if code in taxonomy_allowed]
    if not reason_codes:
        reason_codes = ["human_review_required"] if "human_review_required" in taxonomy_allowed else []
    if not reason_codes:
        raise HTTPException(
            status_code=503,
            detail={"error": "qaqc_reason_code_taxonomy_invalid"},
        )

    allowed_code_sets = taxonomy.get("allowed_code_sets", {})
    pass_codes = set(allowed_code_sets.get("pass", []))
    warning_codes = set(allowed_code_sets.get("warning", []))
    defer_codes = set(allowed_code_sets.get("defer_review", []))
    fail_codes = set(allowed_code_sets.get("fail", []))
    reason_code_set = set(reason_codes)
    if reason_code_set & fail_codes:
        decision_class = "fail"
    elif reason_code_set & defer_codes:
        decision_class = "defer_review"
    elif reason_code_set & warning_codes:
        decision_class = "warning"
    else:
        decision_class = "pass" if reason_code_set & pass_codes else "defer_review"

    schema_payload = governance_bundle["artifacts"]["nta_qaqc_schema"]
    allowed_decision_statuses = set(schema_payload.get("field_spec", {}).get(
        "decision_status", {}
    ).get("allowed_values", []))
    allowed_conf_levels = set(schema_payload.get("field_spec", {}).get(
        "confidence_level", {}
    ).get("allowed_values", []))
    decision_status = (
        "candidate_reject" if decision_class == "fail"
        else ("candidate_accept" if decision_class == "pass" else "candidate_defer_review")
    )
    confidence_level = (
        "low" if decision_class == "fail"
        else ("high" if decision_class == "pass" else "moderate")
    )
    if decision_status not in allowed_decision_statuses:
        raise HTTPException(
            status_code=503,
            detail={"error": "qaqc_schema_decision_status_mismatch", "decision_status": decision_status},
        )
    if confidence_level not in allowed_conf_levels:
        raise HTTPException(
            status_code=503,
            detail={"error": "qaqc_schema_confidence_level_mismatch", "confidence_level": confidence_level},
        )

    fair_profile = governance_bundle["artifacts"]["fair_env_metadata_profile"]
    required_sections = fair_profile.get("required_sections", [])
    metadata_profile = {
        "dataset_identity": {
            "dataset_id": f"qaqc_{payload.batch_id}",
            "dataset_title": f"QAQC validation artifact for {payload.batch_id}",
            "dataset_version": "v1.0.0",
            "dataset_created_utc": _utcnow_iso(),
            "dataset_owner": "PFAS Enterprise 5.0",
            "persistent_identifier": f"sha256:{governance_bundle['hashes']['nta_qaqc_schema']}",
            "keywords": ["PFAS", "QAQC", payload.method_source],
        },
        "provenance": {
            "source_program": "PFAS Enterprise API",
            "source_dataset_name": payload.batch_id,
            "source_url_or_registry": "internal_api_request",
            "ingestion_timestamp_utc": _utcnow_iso(),
            "pipeline_id": "qaqc_validate",
            "pipeline_version": settings.api_version,
            "code_commit": "unknown",
            "input_artifact_hashes": {
                **ref_bundle["hashes"],
                **governance_bundle["hashes"],
            },
        },
        "measurement_context": {
            "sample_matrix": payload.matrix or "other",
            "matrix_category": "environmental",
            "result_unit": "not_applicable",
            "analytical_method_key": payload.method_source,
            "instrument_class": "not_captured",
            "target_mode": "targeted",
            "analyte_registry_version": "not_captured",
        },
        "quality_context": {
            "qaqc_profile_version": "qaqc_reason_code_taxonomy_v1",
            "blank_summary": {"has_method_blank_failure": any(f.get("code") == "method_blank_failed" for f in failures)},
            "calibration_summary": {"has_calibration_failure": any(f.get("code") == "calibration_failed" for f in failures)},
            "isotope_internal_standard_policy": "eis_pass gate used when provided",
            "surrogate_recovery_summary": {"has_recovery_gate_failure": any(f.get("code") == "recovery_gate_failed" for f in failures)},
            "review_status": "human_review_pending" if validation_status != "pass" else "machine_screened",
        },
        "governance_context": {
            "governance_lane": "pfas_enterprise_v5_qaqc",
            "governance_version": "v1.0.0",
            "scope_classification": "screening_support",
            "regulatory_use_flag": False,
            "ruo_disclaimer_applied": True,
        },
        "access_and_use": {
            "access_tier": "internal_restricted",
            "license": "internal_use",
            "contains_sensitive_data": False,
            "retention_policy": "project_default",
            "contact_point": "pfas-enterprise-api",
        },
    }
    missing_sections = [
        section for section in required_sections
        if section not in metadata_profile
    ]
    if missing_sections:
        raise HTTPException(
            status_code=503,
            detail={"error": "fair_metadata_profile_sections_missing", "missing_sections": missing_sections},
        )

    evidence_dir = settings.project_root / "results" / "qaqc_evidence"
    evidence_dir.mkdir(parents=True, exist_ok=True)
    evidence_path = evidence_dir / f"{payload.batch_id}_{request.state.request_id}.json"
    evidence_body = {
        "request_id": request.state.request_id,
        "generated_utc": _utcnow_iso(),
        "batch_id": payload.batch_id,
        "method_source": payload.method_source,
        "matrix": payload.matrix,
        "strict": payload.strict,
        "evidence_tag": payload.evidence_tag or "",
        "validation_status": validation_status,
        "decision_class": decision_class,
        "decision_status": decision_status,
        "confidence_level": confidence_level,
        "reason_codes": reason_codes,
        "summary": {
            "rows_received": len(payload.rows),
            "failures": len(failures),
            "warnings": len(warnings),
        },
        "failures": failures,
        "warnings": warnings,
        "row_checks": row_checks,
        "reference_bundle": {
            "paths": ref_bundle["paths"],
            "hashes": ref_bundle["hashes"],
            "allowed_qc_types": sorted(allowed_qc_types),
            "allowed_method_sources": ref_bundle["method_sources"],
        },
        "governance_bundle": {
            "paths": governance_bundle["paths"],
            "hashes": governance_bundle["hashes"],
            "schema_version": schema_payload.get("version", ""),
            "reason_taxonomy_version": taxonomy.get("version", ""),
            "fair_profile_version": fair_profile.get("version", ""),
        },
        "metadata_profile": metadata_profile,
        "intended_use": (
            "Screening QA/QC automation support only. Not EPA-approved, "
            "ISO-accredited, or a certified laboratory method."
        ),
    }
    evidence_path.write_text(
        json.dumps(evidence_body, indent=2, ensure_ascii=True) + "\n",
        encoding="utf-8",
    )

    response_body = {
        "request_id": request.state.request_id,
        "batch_id": payload.batch_id,
        "method_source": payload.method_source,
        "validation_status": validation_status,
        "decision_class": decision_class,
        "decision_status": decision_status,
        "confidence_level": confidence_level,
        "reason_codes": reason_codes,
        "summary": evidence_body["summary"],
        "failures": failures,
        "warnings": warnings,
        "evidence_artifact_path": str(evidence_path.relative_to(settings.project_root)),
        "reference_hashes": ref_bundle["hashes"],
        "governance_hashes": governance_bundle["hashes"],
    }

    if payload.strict and validation_status == "fail":
        return JSONResponse(status_code=422, content=response_body)
    return JSONResponse(status_code=200, content=response_body)


@app.post("/v1/qaqc/explain")
def qaqc_explain(
    payload: QAQCExplainRequest,
    request: Request,
    ctx: dict[str, Any] = Depends(authenticate_request),
) -> JSONResponse:
    """Deterministic governed explanation for QA/QC reason codes."""
    request.state.api_key_id = ctx["api_key_id"]
    normalized = _normalize_reason_code(payload.reason_code)
    item = QAQC_EXPLANATIONS.get(normalized, QAQC_EXPLANATIONS["UNKNOWN_REASON_CODE"])
    response_body = {
        "request_id": request.state.request_id,
        "reason_code": normalized,
        "explanation": item["explanation"],
        "severity": item["severity"],
        "human_review_required": True,
        "claim_safety": {
            "diagnostic_claim": False,
            "regulatory_adjudication": False,
            "release_ready": False,
        },
        "context_echo": payload.context or {},
    }
    return JSONResponse(status_code=200, content=response_body)


@app.post("/v1/biomonitoring/interpret")
def biomonitoring_interpret(
    payload: BiomonitoringInterpretRequest,
    request: Request,
    ctx: dict[str, Any] = Depends(authenticate_request),
) -> JSONResponse:
    """Generate claim-safe biomonitoring interpretation output (serum lane only)."""
    request.state.api_key_id = ctx["api_key_id"]
    schema_bundle = _load_biomonitoring_schema_bundle()
    schema = schema_bundle["schema"]

    matrix_lane = payload.matrix_lane.strip().lower()
    if matrix_lane != "serum":
        return JSONResponse(
            status_code=422,
            content={
                "request_id": request.state.request_id,
                "error": "matrix_lane_unsupported",
                "matrix_lane": payload.matrix_lane,
                "allowed_matrix_lanes": schema.get("scope", {}).get("supported_matrix_lanes", ["serum"]),
            },
        )

    allowed_conf_tiers = set(schema.get("field_spec", {}).get("confidence_tier", {}).get("allowed_values", []))
    allowed_review_status = set(schema.get("field_spec", {}).get("human_review_status", {}).get("allowed_values", []))
    allowed_direction = set(schema.get("field_spec", {}).get("pathway_flags", {}).get(
        "item_field_rules", {}
    ).get("direction", {}).get("allowed_values", []))
    allowed_evidence = set(schema.get("field_spec", {}).get("pathway_flags", {}).get(
        "item_field_rules", {}
    ).get("evidence_level", {}).get("allowed_values", []))

    max_percentile = max(p.percentile for p in payload.percentile_context)
    derived_conf_tier = (
        "high" if max_percentile >= 99.0 else
        ("moderate" if max_percentile >= 90.0 else "exploratory")
    )
    confidence_tier = (payload.confidence_tier or derived_conf_tier).strip().lower()
    if confidence_tier not in allowed_conf_tiers:
        return JSONResponse(
            status_code=422,
            content={
                "request_id": request.state.request_id,
                "error": "confidence_tier_invalid",
                "confidence_tier": confidence_tier,
                "allowed": sorted(allowed_conf_tiers),
            },
        )

    human_review_status = payload.human_review_status.strip().lower()
    if human_review_status not in allowed_review_status:
        return JSONResponse(
            status_code=422,
            content={
                "request_id": request.state.request_id,
                "error": "human_review_status_invalid",
                "human_review_status": human_review_status,
                "allowed": sorted(allowed_review_status),
            },
        )

    pathway_flags = [
        {
            "pathway_name": p.pathway_name,
            "direction": p.direction.strip().lower(),
            "evidence_level": p.evidence_level.strip().lower(),
            "rationale": p.rationale.strip(),
        }
        for p in payload.pathway_flags
    ]
    for pf in pathway_flags:
        if pf["direction"] not in allowed_direction:
            return JSONResponse(
                status_code=422,
                content={
                    "request_id": request.state.request_id,
                    "error": "pathway_direction_invalid",
                    "value": pf["direction"],
                    "allowed": sorted(allowed_direction),
                },
            )
        if pf["evidence_level"] not in allowed_evidence:
            return JSONResponse(
                status_code=422,
                content={
                    "request_id": request.state.request_id,
                    "error": "pathway_evidence_level_invalid",
                    "value": pf["evidence_level"],
                    "allowed": sorted(allowed_evidence),
                },
            )

    required_claim_boundary_text = schema.get("required_claim_boundary_text", {})
    claim_boundary = dict(required_claim_boundary_text)
    if payload.claim_boundary:
        claim_boundary.update({str(k): str(v) for k, v in payload.claim_boundary.items()})

    if payload.strict_claim_boundary:
        for k, v in required_claim_boundary_text.items():
            if claim_boundary.get(k, "").strip() != str(v).strip():
                return JSONResponse(
                    status_code=422,
                    content={
                        "request_id": request.state.request_id,
                        "error": "claim_boundary_mismatch",
                        "field": k,
                    },
                )

    if payload.overall_interpretation_override:
        overall_interpretation = payload.overall_interpretation_override.strip()
    else:
        overall_interpretation = (
            f"Serum PFAS biomonitoring profile for subject {payload.subject_id} was contextualized "
            f"against {payload.source_dataset}. Results indicate a maximum percentile of "
            f"{max_percentile:.1f} with confidence tier '{confidence_tier}'. "
            "This interpretation is intended for research and decision-support with human review."
        )

    forbidden = schema.get("forbidden_language_rules", {})
    forbidden_hit = _contains_forbidden_language(
        overall_interpretation,
        [*forbidden.get("diagnostic_terms", []), *forbidden.get("causal_terms", []), *forbidden.get("treatment_terms", [])],
    )
    if forbidden_hit:
        return JSONResponse(
            status_code=422,
            content={
                "request_id": request.state.request_id,
                "error": "forbidden_language_detected",
                "term": forbidden_hit,
            },
        )
    for pf in pathway_flags:
        forbidden_hit = _contains_forbidden_language(
            pf["rationale"],
            [*forbidden.get("diagnostic_terms", []), *forbidden.get("causal_terms", []), *forbidden.get("treatment_terms", [])],
        )
        if forbidden_hit:
            return JSONResponse(
                status_code=422,
                content={
                    "request_id": request.state.request_id,
                    "error": "forbidden_language_detected",
                    "term": forbidden_hit,
                    "pathway_name": pf["pathway_name"],
                },
            )

    review_policy = schema.get("review_policy", {})
    if (
        review_policy.get("release_block_if_confidence_exploratory_and_pathway_flags_non_empty")
        and confidence_tier == "exploratory"
        and len(pathway_flags) > 0
        and human_review_status == "completed"
    ):
        return JSONResponse(
            status_code=422,
            content={
                "request_id": request.state.request_id,
                "error": "release_blocked_exploratory_with_pathway_flags",
            },
        )

    provenance = {
        "pipeline_id": "biomonitoring_interpret",
        "pipeline_version": settings.api_version,
        "governance_version": schema.get("version", ""),
        "reference_registry_version": "not_captured",
        "input_artifact_hashes": {
            "biomonitoring_schema_hash": schema_bundle["hash"],
        },
    }
    if payload.provenance:
        provenance.update(payload.provenance)

    report_id = f"bio_{payload.subject_id}_{request.state.request_id[:8]}"
    interpretation_body = {
        "report_id": report_id,
        "generated_utc": _utcnow_iso(),
        "subject_id": payload.subject_id,
        "matrix_lane": matrix_lane,
        "source_dataset": payload.source_dataset,
        "analyte_values": [a.model_dump() for a in payload.analyte_values],
        "percentile_context": [p.model_dump() for p in payload.percentile_context],
        "pathway_flags": pathway_flags,
        "overall_interpretation": overall_interpretation,
        "confidence_tier": confidence_tier,
        "human_review_status": human_review_status,
        "claim_boundary": claim_boundary,
        "limitations": [
            "Interpretation is association-based and non-diagnostic.",
            "Individual-level causality cannot be inferred from this output alone.",
        ],
        "provenance": provenance,
    }

    required_fields = schema.get("required_top_level_fields", [])
    missing = [f for f in required_fields if f != "evidence_hash_sha256" and f not in interpretation_body]
    if missing:
        return JSONResponse(
            status_code=422,
            content={"request_id": request.state.request_id, "error": "required_fields_missing", "missing": missing},
        )

    canonical = json.dumps(interpretation_body, sort_keys=True, ensure_ascii=True).encode("utf-8")
    interpretation_body["evidence_hash_sha256"] = hashlib.sha256(canonical).hexdigest()

    evidence_dir = settings.project_root / "results" / "biomonitoring_evidence"
    evidence_dir.mkdir(parents=True, exist_ok=True)
    evidence_path = evidence_dir / f"{report_id}.json"
    evidence_path.write_text(json.dumps(interpretation_body, indent=2, ensure_ascii=True) + "\n", encoding="utf-8")

    return JSONResponse(
        status_code=200,
        content={
            "request_id": request.state.request_id,
            "report_id": report_id,
            "matrix_lane": matrix_lane,
            "confidence_tier": confidence_tier,
            "human_review_status": human_review_status,
            "pathway_flags_count": len(pathway_flags),
            "evidence_artifact_path": str(evidence_path.relative_to(settings.project_root)),
            "schema_hash": schema_bundle["hash"],
        },
    )


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
