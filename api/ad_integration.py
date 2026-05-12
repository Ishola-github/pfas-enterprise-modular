"""
Applicability-domain integration for the PFAS Enterprise 5 API.

Loads each lane's `data/ad_models/<lane>/ad_model.json` on demand,
caches them in process, and exposes a single `evaluate()` entry point
that returns the canonical AD column contract:

    ad_status               in_domain | warning | reject
    ad_distance             log10 |z| (or 'inf' / 'nan')
    ad_reason               human-readable cause
    reference_lane          governing pipeline_lane
    training_range_version  SHA prefix of the lane's training.csv
    ad_model_version        framework semver
    ad_threshold            applied reject threshold
    nearest_training_source primary source organization
    ad_method               per_analyte_envelope_v1 | categorical_coverage_v1

Reuses the same decision functions used by scripts/apply_ad_guard.py so
the API and the offline guard produce **identical** results for identical
inputs.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path
from threading import Lock
from typing import Any

from api.settings import settings

_scripts_dir = settings.project_root / "scripts"
if str(_scripts_dir) not in sys.path:
    sys.path.insert(0, str(_scripts_dir))

from apply_ad_guard import decide as _ad_decide  # noqa: E402

_MODELS: dict[str, dict[str, Any]] = {}
_LOCK = Lock()
_ALL_LANES = (
    "drinking_water",
    "serum",
    "biosolids_sludge",
    "afff",
    "methanol_standards",
    "air_emissions",
)


def _load_model(lane: str) -> dict[str, Any]:
    p = settings.ad_models_dir / lane / "ad_model.json"
    if not p.is_file():
        raise FileNotFoundError(f"AD model missing for lane '{lane}': {p}")
    return json.loads(p.read_text(encoding="utf-8"))


def get_model(lane: str) -> dict[str, Any] | None:
    with _LOCK:
        m = _MODELS.get(lane)
        if m is not None:
            return m
        try:
            m = _load_model(lane)
            _MODELS[lane] = m
            return m
        except FileNotFoundError:
            return None


def list_available_lanes() -> list[str]:
    out: list[str] = []
    for ln in _ALL_LANES:
        if (settings.ad_models_dir / ln / "ad_model.json").is_file():
            out.append(ln)
    return out


def evaluate(lane: str, row: dict[str, Any]) -> dict[str, Any]:
    """Decide AD status for one row.

    Returns the canonical AD column contract as a dict, or a dict with
    `{"error": "lane_unknown"}` if the lane has no AD model.
    """
    model = get_model(lane)
    if model is None:
        return {
            "error": "lane_unknown",
            "lane": lane,
            "available_lanes": list_available_lanes(),
        }

    serialized: dict[str, str] = {}
    for k, v in row.items():
        if v is None:
            serialized[k] = ""
        elif isinstance(v, (int, float)):
            serialized[k] = "" if v != v else str(v)  # NaN guard
        else:
            serialized[k] = str(v)

    return _ad_decide(model, serialized)


def evaluate_with_summary(lane: str, row: dict[str, Any]) -> dict[str, Any]:
    """Same as evaluate() but also returns whether the request should be
    refused (HTTP 422 territory) for callers that map AD directly to HTTP."""
    decision = evaluate(lane, row)
    refused = decision.get("ad_status") == "reject"
    return {
        "decision": decision,
        "prediction_refused": refused,
    }
