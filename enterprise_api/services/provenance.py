from datetime import datetime, timezone

def governance_event(
    event_type: str,
    message: str,
    severity: str = "info"
) -> dict:

    return {
        "event_type": event_type,
        "event_message": message,
        "severity": severity,
        "created_at": datetime.now(timezone.utc).isoformat()
    }
