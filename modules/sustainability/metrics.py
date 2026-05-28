from typing import Any, Dict, List


def _confidence_is_high(confidence: Any) -> bool:
    """Match string 'high' or numeric confidence >= 0.8 (aligns with screening tier labels)."""
    if confidence is None:
        return False
    if isinstance(confidence, (int, float)):
        return float(confidence) >= 0.8
    return str(confidence).strip().lower() == "high"


def calculate_sustainability_metrics(
    predictions: List[Dict[str, Any]],
    cost_per_lab_analysis: float = 350.0,
    kg_co2_per_sample: float = 2.5,
) -> Dict[str, Any]:
    avoided = [
        p
        for p in predictions
        if str(p.get("prediction", "")).lower() in ["non-detect", "below_limit", "screening_pass"]
        and _confidence_is_high(p.get("confidence"))
    ]

    n_avoided = len(avoided)

    return {
        "n_samples_screened": len(predictions),
        "n_lab_analyses_potentially_avoided": n_avoided,
        "estimated_cost_avoided_usd": n_avoided * cost_per_lab_analysis,
        "estimated_co2_avoided_kg": n_avoided * kg_co2_per_sample,
        "assumptions": {
            "cost_per_lab_analysis_usd": cost_per_lab_analysis,
            "kg_co2_per_sample": kg_co2_per_sample,
            "note": "Decision-support estimate only. Confirm locally with lab, shipping, and client policy.",
        },
    }
