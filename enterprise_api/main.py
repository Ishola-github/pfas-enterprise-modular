from fastapi import FastAPI
from pydantic import BaseModel
from pathlib import Path
from datetime import datetime, timezone
import sqlite3
import json
import hashlib

from enterprise_api.services.applicability import validate_applicability
from enterprise_api.services.provenance import governance_event
from scripts.contextualize_serum_pfas import contextualize_serum_pfas


app = FastAPI(title="PFAS Enterprise 5.0 Governed API")

DB = Path("enterprise_api/pfas_enterprise_v1.sqlite")
SCHEMA = Path("enterprise_api/db/schema.sql")


class ContextualizationRequest(BaseModel):
    analyte: str
    value: float
    age: int
    sex: str
    matrix: str
    units: str


def utc_now():
    return datetime.now(timezone.utc).isoformat()


def stable_payload_hash(payload: dict) -> str:
    encoded = json.dumps(payload, sort_keys=True).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def init_db():
    conn = sqlite3.connect(DB)
    conn.executescript(SCHEMA.read_text())
    conn.commit()
    conn.close()


@app.on_event("startup")
def startup():
    init_db()


@app.get("/health")
def health():
    return {
        "status": "ok",
        "system": "PFAS Enterprise 5.0",
        "mode": "RUO_CONTEXTUALIZATION_ONLY",
        "generated_at_utc": utc_now()
    }


@app.get("/governance")
def governance():
    return {
        "status": "SUCCESS",
        "v1_scope": {
            "matrix": "serum only",
            "analytes": ["PFOS", "PFOA", "PFOS_TOTAL", "PFOA_TOTAL"],
            "units": "ng/mL",
            "clinical_interpretation": "prohibited",
            "cross_matrix_contextualization": "blocked",
            "mode": "Research Use Only"
        }
    }


@app.post("/contextualize")
def contextualize(req: ContextualizationRequest):
    payload = req.model_dump()
    payload_hash = stable_payload_hash(payload)

    applicability = validate_applicability(payload)

    conn = sqlite3.connect(DB)
    cur = conn.cursor()

    cur.execute("""
        INSERT INTO uploads (
            project_id,
            filename,
            input_sha256,
            created_at
        )
        VALUES (?, ?, ?, ?)
    """, (
        1,
        "api_request",
        payload_hash,
        utc_now()
    ))

    upload_id = cur.lastrowid

    if applicability["status"] == "REJECTED":
        cur.execute("""
            INSERT INTO governance_events (
                run_id,
                event_type,
                event_message,
                severity,
                created_at
            )
            VALUES (?, ?, ?, ?, ?)
        """, (
            None,
            "APPLICABILITY_REJECTION",
            applicability["reason"],
            applicability["severity"],
            utc_now()
        ))

        conn.commit()
        conn.close()

        return {
            "status": "REJECTED",
            "payload_sha256": payload_hash,
            "governance": applicability,
            "payload": payload
        }

    result = contextualize_serum_pfas(
        analyte=req.analyte,
        value=req.value,
        age=req.age,
        sex=req.sex,
        matrix=req.matrix,
        units=req.units
    )

    cur.execute("""
        INSERT INTO runs (
            upload_id,
            engine_version,
            reference_version,
            status,
            created_at
        )
        VALUES (?, ?, ?, ?, ?)
    """, (
        upload_id,
        "enterprise_api_v1",
        "NHANES_J_WEIGHTED_STRATIFIED_V1",
        result["status"],
        utc_now()
    ))

    run_id = cur.lastrowid

    gov = governance_event(
        event_type="CONTEXTUALIZATION_COMPLETED",
        message="Governed serum PFAS contextualization executed.",
        severity="info"
    )

    cur.execute("""
        INSERT INTO governance_events (
            run_id,
            event_type,
            event_message,
            severity,
            created_at
        )
        VALUES (?, ?, ?, ?, ?)
    """, (
        run_id,
        gov["event_type"],
        gov["event_message"],
        gov["severity"],
        gov["created_at"]
    ))

    conn.commit()
    conn.close()

    return {
        "status": "SUCCESS",
        "payload_sha256": payload_hash,
        "payload": payload,
        "contextualization": result,
        "governance_event": gov
    }


@app.get("/governance-events")
def governance_events():
    conn = sqlite3.connect(DB)
    conn.row_factory = sqlite3.Row
    cur = conn.cursor()

    cur.execute("""
        SELECT
            id,
            run_id,
            event_type,
            event_message,
            severity,
            created_at
        FROM governance_events
        ORDER BY id DESC
    """)

    rows = [dict(row) for row in cur.fetchall()]
    conn.close()

    return {
        "status": "SUCCESS",
        "count": len(rows),
        "events": rows
    }
@app.get("/runs")
def runs():
    conn = sqlite3.connect(DB)
    conn.row_factory = sqlite3.Row
    cur = conn.cursor()

    cur.execute("""
        SELECT
            runs.id,
            runs.upload_id,
            runs.engine_version,
            runs.reference_version,
            runs.status,
            runs.created_at,
            uploads.input_sha256
        FROM runs
        LEFT JOIN uploads ON uploads.id = runs.upload_id
        ORDER BY runs.id DESC
    """)

    rows = [dict(row) for row in cur.fetchall()]
    conn.close()

    return {
        "status": "SUCCESS",
        "count": len(rows),
        "runs": rows
    }
@app.get("/uploads")
def uploads():
    conn = sqlite3.connect(DB)
    conn.row_factory = sqlite3.Row
    cur = conn.cursor()

    cur.execute("""
        SELECT
            id,
            project_id,
            filename,
            input_sha256,
            created_at
        FROM uploads
        ORDER BY id DESC
    """)

    rows = [dict(row) for row in cur.fetchall()]
    conn.close()

    return {
        "status": "SUCCESS",
        "count": len(rows),
        "uploads": rows
    }
