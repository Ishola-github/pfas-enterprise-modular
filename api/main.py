"""PFAS Enterprise 5.0 - demo FastAPI service for screening stub and health checks."""

from __future__ import annotations

import os
import uuid
from typing import Any

from fastapi import FastAPI
from pydantic import BaseModel, Field

from modules.sustainability import calculate_sustainability_metrics

app = FastAPI(
    title="PFAS Enterprise 5.0",
    version="5.0.0",
    description="Screening decision-support API (demo stub). Not a certified laboratory result.",
)


class PredictRequest(BaseModel):
    sample_id: str
    dtxsid: str = Field(..., description="CompTox or internal substance identifier")
    method_id: str
    matrix: str


def _env_float(key: str, default: str) -> float:
    try:
        return float(os.environ.get(key, default))
    except (TypeError, ValueError):
        return float(default)


@app.get("/healthz")
def healthz() -> dict[str, str]:
    return {"status": "ok", "service": "pfas-enterprise-5"}


@app.post("/predict")
def predict(req: PredictRequest) -> dict[str, Any]:
    """Return a deterministic-shaped payload for Shiny and integration tests."""

    run_id = str(uuid.uuid4())
    screening_only = os.environ.get("SCREENING_USE_ONLY", "true").lower() in ("1", "true", "yes")

    intended = (
        "Screening decision-support only. "
        "Not EPA-approved, ISO-accredited, or a certified laboratory method."
    )
    if not screening_only:
        intended += " (SCREENING_USE_ONLY is false - production wiring required.)"

    prediction = "borderline"
    confidence = 0.72

    cost_lab = _env_float("COST_PER_LAB_ANALYSIS_USD", "350")
    kg_co2 = _env_float("KG_CO2_PER_SAMPLE", "2.5")
    sustainability = calculate_sustainability_metrics(
        [{"prediction": prediction, "confidence": confidence}],
        cost_per_lab_analysis=cost_lab,
        kg_co2_per_sample=kg_co2,
    )

    return {
        "run_id": run_id,
        "sample_id": req.sample_id,
        "dtxsid": req.dtxsid,
        "method_id": req.method_id,
        "matrix": req.matrix,
        "prediction": prediction,
        "confidence": confidence,
        "ad_warning": "Inside applicability domain (demo stub). Confirm critical results analytically.",
        "intended_use": intended,
        "sustainability": sustainability,
    }
