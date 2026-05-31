def validate_applicability(row: dict) -> dict:
    if str(row.get("matrix", "")).lower() != "serum":
        return {
            "status": "REJECTED",
            "severity": "critical",
            "reason": "Only serum matrix is supported in V1."
        }

    if str(row.get("units", "")) != "ng/mL":
        return {
            "status": "REJECTED",
            "severity": "critical",
            "reason": "Only ng/mL is supported in V1. No silent unit conversion."
        }

    if str(row.get("analyte", "")).upper() not in ["PFOS", "PFOA", "PFOS_TOTAL", "PFOA_TOTAL"]:
        return {
            "status": "REJECTED",
            "severity": "critical",
            "reason": "Only PFOS/PFOA are supported in V1."
        }

    value = float(row.get("value", 0))
    if value < 0:
        return {
            "status": "REJECTED",
            "severity": "critical",
            "reason": "Negative PFAS concentration is invalid."
        }

    return {
        "status": "VALID",
        "severity": "none",
        "reason": "Input passed V1 applicability checks."
    }
