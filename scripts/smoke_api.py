"""
End-to-end smoke test for the PFAS Enterprise 5 operational API.

Uses Starlette's TestClient (no network port, no separate uvicorn process)
to drive the full middleware stack:

    * unauthenticated request -> 401 + missing_api_key
    * /health (unauthenticated allowed) -> 200 + version + manifest + registry
    * /v1/whoami with valid key -> 200 + api_key_id + request_id
    * /v1/predict in-domain row -> 200 + ad_status=in_domain + prediction_refused=false
    * /v1/predict out-of-envelope row -> 422 (strict refusal) + ad_status=reject + prediction_refused=true
    * /v1/predict analyte_unseen -> 422 + ad_reason=analyte_unseen
    * Rate limit -> burst overrun returns 429 with Retry-After header
    * Access log records all the structured fields (request_id / lane /
      ad_status / prediction_refused / model_version / threshold_version)

The test sets env vars before importing api.main so settings pick them up.
It does NOT pollute any real .env or audit log.

Exit code 0 on full PASS; 1 on any failure.
"""

from __future__ import annotations

import io
import json
import logging
import os
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

os.environ["APP_ENV"] = "test"
os.environ["PFAS_API_KEYS"] = "ci:ci_smoke_secret_token,ops:ops_smoke_secret_token"
os.environ["PFAS_API_AUTH_OPEN"] = "false"
os.environ["PFAS_API_RATE_LIMIT_ENABLED"] = "true"
os.environ["PFAS_API_RATE_LIMIT_PER_MINUTE"] = "300"
os.environ["PFAS_API_RATE_LIMIT_BURST"] = "5"
os.environ["PFAS_API_LOG_JSON"] = "true"
os.environ["PFAS_API_LOG_LEVEL"] = "INFO"
os.environ["PFAS_API_AD_STRICT_REFUSAL"] = "true"

from fastapi.testclient import TestClient  # noqa: E402

from api import main as api_main  # noqa: E402

LOG_BUF = io.StringIO()


def _attach_log_buffer() -> None:
    """Attach a StringIO handler so we can assert on emitted JSON records."""
    logger = logging.getLogger("pfas.api")
    h = logging.StreamHandler(LOG_BUF)
    h.setFormatter(api_main.LOGGER.handlers[0].formatter)
    h.setLevel(logging.DEBUG)
    logger.addHandler(h)


_attach_log_buffer()
client = TestClient(api_main.app)
HEADERS_OK = {"X-API-Key": "ci_smoke_secret_token"}

results: list[tuple[str, bool, str]] = []


def check(label: str, ok: bool, detail: str = "") -> None:
    results.append((label, ok, detail))
    flag = "PASS" if ok else "FAIL"
    print(f"  [{flag}] {label}  {detail}")


# ----- 1. Unauthenticated /v1/whoami -> 401 ---------------------------------
print(">>> 1. Unauthenticated /v1/whoami should be 401")
r = client.get("/v1/whoami")
check("unauth 401", r.status_code == 401, f"got {r.status_code}")
body = r.json()
check("unauth error code", body.get("detail", {}).get("error") == "missing_api_key",
      f"detail={body.get('detail')}")
check("unauth response_id header present",
      r.headers.get("X-Request-Id") is not None, "")

# ----- 2. Valid /v1/whoami -> 200 -------------------------------------------
print(">>> 2. /v1/whoami with valid key")
r = client.get("/v1/whoami", headers=HEADERS_OK)
check("whoami 200", r.status_code == 200, f"got {r.status_code}")
body = r.json()
check("whoami returns api_key_id 'ci'", body.get("api_key_id") == "ci",
      f"got {body.get('api_key_id')}")
check("whoami has request_id", bool(body.get("request_id")), "")

# ----- 3. /health (unauthenticated allowed) ---------------------------------
print(">>> 3. /health is unauthenticated and rich")
r = client.get("/health")
check("health 200", r.status_code == 200, "")
body = r.json()
check("health has ad.available_lanes",
      isinstance(body.get("ad", {}).get("available_lanes"), list)
      and len(body["ad"]["available_lanes"]) >= 1,
      f"lanes={body.get('ad', {}).get('available_lanes')}")
check("health has registry_verification",
      isinstance(body.get("registry_verification"), dict), "")
check("health does NOT include paths by default",
      "paths" not in body, "")

# ----- 4. AD-gated in-domain prediction ------------------------------------
print(">>> 4. /v1/predict in-domain (drinking_water PFOA 7.5 ng/L)")
in_dom = {
    "sample_id": "smoke-in-dom-1",
    "matrix_lane": "drinking_water",
    "matrix": "drinking water",
    "analyte": "PFOA",
    "result_value_numeric": 7.5,
    "result_unit": "ng/L",
    "method_id": "EPA_UCMR5_method",
    "state": "CA",
    "model_version": "smoke_model_v0.1",
}
r = client.post("/v1/predict", json=in_dom, headers=HEADERS_OK)
check("in-dom 200", r.status_code == 200, f"got {r.status_code}")
body = r.json()
check("in-dom ad_status == in_domain",
      body.get("ad_status") == "in_domain", f"got {body.get('ad_status')}")
check("in-dom prediction_refused == false",
      body.get("prediction_refused") is False, "")
check("in-dom threshold_version present",
      bool(body.get("threshold_version")), f"got {body.get('threshold_version')}")
check("in-dom request_id echoed in header",
      r.headers.get("X-Request-Id") == body.get("request_id"), "")

# ----- 5. AD-gated reject prediction ----------------------------------------
print(">>> 5. /v1/predict out-of-envelope -> 422 + refusal")
out = dict(in_dom, sample_id="smoke-out-env", result_value_numeric=5000.0)
r = client.post("/v1/predict", json=out, headers=HEADERS_OK)
check("oob 422", r.status_code == 422, f"got {r.status_code}")
body = r.json()
check("oob ad_status == reject",
      body.get("ad_status") == "reject", f"got {body.get('ad_status')}")
check("oob prediction_refused == true",
      body.get("prediction_refused") is True, "")
check("oob ad_reason contains value_out_of_range",
      "value_out_of_range" in str(body.get("ad_reason", "")), "")

# ----- 6. Analyte unseen -----------------------------------------------------
print(">>> 6. /v1/predict analyte_unseen -> 422")
fake = dict(in_dom, sample_id="smoke-fake", analyte="MadeUpPFAS")
r = client.post("/v1/predict", json=fake, headers=HEADERS_OK)
check("fake-analyte 422", r.status_code == 422, f"got {r.status_code}")
check("fake-analyte ad_reason analyte_unseen",
      r.json().get("ad_reason") == "analyte_unseen", "")

# ----- 7. Rate-limit burst overrun ------------------------------------------
print(">>> 7. burst overrun returns 429 with Retry-After")
saw_429 = False
saw_retry_after = False
for i in range(20):
    r = client.get("/v1/whoami", headers=HEADERS_OK)
    if r.status_code == 429:
        saw_429 = True
        saw_retry_after = "Retry-After" in r.headers
        break
check("rate limit triggers 429", saw_429, "")
check("rate limit response has Retry-After", saw_retry_after, "")

# ----- 8. Structured access log has our fields ------------------------------
print(">>> 8. Access log contains structured fields")
lines = [ln for ln in LOG_BUF.getvalue().splitlines() if ln.strip().startswith("{")]
have_pred_log = False
for line in lines:
    try:
        rec = json.loads(line)
    except Exception:
        continue
    if rec.get("path") == "/v1/predict" and rec.get("status_code") == 422:
        # the out-of-envelope or fake-analyte call
        if rec.get("lane") == "drinking_water" and rec.get("prediction_refused") is True:
            have_pred_log = True
            break
check("JSON access log captured /v1/predict refusal with structured fields",
      have_pred_log,
      f"total_log_lines={len(lines)}")

# ----- summary --------------------------------------------------------------
print("\n=== SUMMARY ===")
total = len(results)
passed = sum(1 for _, ok, _ in results if ok)
for label, ok, _ in results:
    print(f"  {'PASS' if ok else 'FAIL'}  {label}")
print(f"\nOverall: {passed}/{total} {'PASS' if passed == total else 'FAIL'}")

sys.exit(0 if passed == total else 1)
