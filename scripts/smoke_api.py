"""
End-to-end smoke test for the PFAS Enterprise 5 operational API.
Exit code 0 on full PASS; 1 on any failure.
"""

from __future__ import annotations

import io
import json
import logging
import os
import sys
import time
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[1]
os.chdir(REPO_ROOT)
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

# Avoid shadow imports of unrelated top-level `api` packages on PYTHONPATH.
for _name in list(sys.modules):
    if _name == "api" or _name.startswith("api."):
        _mod_file = getattr(sys.modules[_name], "__file__", "") or ""
        _norm = _mod_file.replace("\\", "/")
        if _norm and not str(REPO_ROOT).replace("\\", "/") in _norm:
            del sys.modules[_name]

os.environ["APP_ENV"] = "test"
os.environ["PFAS_API_KEYS"] = "ci:ci_smoke_secret_token,ops:ops_smoke_secret_token"
os.environ["PFAS_API_AUTH_OPEN"] = "false"
os.environ["PFAS_API_RATE_LIMIT_ENABLED"] = "true"
os.environ["PFAS_API_RATE_LIMIT_PER_MINUTE"] = "300"
os.environ["PFAS_API_RATE_LIMIT_BURST"] = "16"
os.environ["PFAS_API_LOG_JSON"] = "true"
os.environ["PFAS_API_LOG_LEVEL"] = "INFO"
os.environ["PFAS_API_AD_STRICT_REFUSAL"] = "true"

from fastapi.testclient import TestClient  # noqa: E402
from api import main as api_main  # noqa: E402
from api.rate_limit import BucketState  # noqa: E402

LOG_BUF = io.StringIO()


def _attach_log_buffer() -> None:
    """Attach a StringIO handler so emitted JSON records can be asserted."""
    logger = logging.getLogger("pfas.api")

    if not logger.handlers:
        logger = getattr(api_main, "LOGGER", logger)

    if logger.handlers:
        formatter = logger.handlers[0].formatter
    else:
        formatter = logging.Formatter("%(levelname)s:%(name)s:%(message)s")

    h = logging.StreamHandler(LOG_BUF)
    h.setFormatter(formatter)
    h.setLevel(logging.DEBUG)
    logger.addHandler(h)
    logger.setLevel(logging.DEBUG)


def _response_json(response: Any) -> dict[str, Any]:
    try:
        data = response.json()
    except Exception:
        return {}
    return data if isinstance(data, dict) else {}


def _detail_error(body: dict[str, Any], key: str) -> Any:
    detail = body.get("detail")
    if isinstance(detail, dict):
        return detail.get(key)
    return None


def _route_paths(app: Any) -> set[str]:
    paths: set[str] = set()
    for route in getattr(app, "routes", []):
        path = getattr(route, "path", None)
        if isinstance(path, str):
            paths.add(path)
    return paths


_attach_log_buffer()

_route_set = _route_paths(api_main.app)
if "/v1/whoami" not in _route_set:
    print("ERROR: /v1/whoami not registered on api.main.app", file=sys.stderr)
    print(f"  api.main file: {getattr(api_main, '__file__', '?')}", file=sys.stderr)
    print(f"  sample routes: {sorted(_route_set)[:20]}", file=sys.stderr)
    sys.exit(2)

client = TestClient(api_main.app)
HEADERS_OK = {"X-API-Key": "ci_smoke_secret_token"}

results: list[tuple[str, bool, str]] = []


def check(label: str, ok: bool, detail: str = "") -> None:
    results.append((label, ok, detail))
    flag = "PASS" if ok else "FAIL"
    print(f"  [{flag}] {label}  {detail}")


print(">>> 1. Unauthenticated /v1/whoami should be 401")
r = client.get("/v1/whoami")
check("unauth 401", r.status_code == 401, f"got {r.status_code}")
body = r.json()
detail = body.get("detail") if isinstance(body, dict) else None

if isinstance(detail, dict):
    unauth_error_ok = detail.get("error") == "missing_api_key"
else:
    unauth_error_ok = "missing_api_key" in str(detail)

check(
    "unauth error code",
    unauth_error_ok,
    f"detail={detail}",
)
check("unauth response_id header present", r.headers.get("X-Request-Id") is not None)


print(">>> 2. /v1/whoami with valid key")
r = client.get("/v1/whoami", headers=HEADERS_OK)
check("whoami 200", r.status_code == 200, f"got {r.status_code}")
body = _response_json(r)
check(
    "whoami returns api_key_id 'ci'",
    body.get("api_key_id") == "ci",
    f"got {body.get('api_key_id')}",
)
check("whoami has request_id", bool(body.get("request_id")))


print(">>> 3. /health is unauthenticated and rich")
r = client.get("/health")
check("health 200", r.status_code == 200, f"got {r.status_code}")
body = _response_json(r)
check(
    "health has ad.available_lanes",
    isinstance(body.get("ad", {}).get("available_lanes"), list)
    and len(body["ad"]["available_lanes"]) >= 1,
    f"lanes={body.get('ad', {}).get('available_lanes')}",
)
check("health has registry_verification", isinstance(body.get("registry_verification"), dict))
check("health does NOT include paths by default", "paths" not in body)
check(
    "health has literature_priority_registry manifest boolean",
    isinstance(body.get("manifests", {}).get("literature_priority_registry"), bool),
)


print(">>> 4. /v1/literature/priorities returns governed subset")
r = client.get("/v1/literature/priorities", headers=HEADERS_OK)
check("literature priorities 200", r.status_code == 200, f"got {r.status_code}")
body = _response_json(r)
check(
    "literature priorities include_now only by default",
    body.get("summary", {}).get("returned") == body.get("summary", {}).get("include_now"),
)
papers = body.get("papers")
first = papers[0] if isinstance(papers, list) and papers else {}
check(
    "literature priorities has expected top DOI",
    isinstance(first, dict) and first.get("doi") == "10.1021/acs.chemrestox.6c00057",
)

r = client.get("/v1/literature/priorities?include_deferred=true", headers=HEADERS_OK)
body = _response_json(r)
check(
    "literature priorities deferred expansion works",
    body.get("summary", {}).get("returned") == body.get("summary", {}).get("total_papers"),
)


print(">>> 5. /v1/literature/integration-backlog generates actionable tasks")
r = client.get("/v1/literature/integration-backlog", headers=HEADERS_OK)
check("integration backlog 200", r.status_code == 200, f"got {r.status_code}")
body = _response_json(r)
tasks = body.get("tasks")
check(
    "integration backlog default has ready tasks",
    isinstance(tasks, list) and len(tasks) >= 1 and all(t.get("status") == "ready" for t in tasks if isinstance(t, dict)),
)
check(
    "integration backlog includes PFAS Structure Registry task",
    isinstance(tasks, list)
    and any(
        isinstance(t, dict) and t.get("module") == "PFAS Structure Registry"
        for t in tasks
    ),
)

r = client.get("/v1/literature/integration-backlog?include_deferred=true", headers=HEADERS_OK)
body = _response_json(r)
tasks = body.get("tasks")
check(
    "integration backlog deferred mode exposes blocked tasks",
    isinstance(tasks, list)
    and any(
        isinstance(t, dict) and t.get("status") == "blocked_pending_full_text_review"
        for t in tasks
    ),
)


print(">>> 6. /v1/literature/integration-backlog/export emits tracker payloads")
r = client.post(
    "/v1/literature/integration-backlog/export?target=linear",
    headers=HEADERS_OK,
)
check("integration export linear 200", r.status_code == 200, f"got {r.status_code}")
body = _response_json(r)
issues = body.get("issues")
check(
    "integration export linear has title/metadata",
    isinstance(issues, list)
    and len(issues) >= 1
    and isinstance(issues[0], dict)
    and bool(issues[0].get("title"))
    and isinstance(issues[0].get("metadata"), dict),
)

r = client.post(
    "/v1/literature/integration-backlog/export?target=jira&include_deferred=true",
    headers=HEADERS_OK,
)
check("integration export jira 200", r.status_code == 200, f"got {r.status_code}")
body = _response_json(r)
issues = body.get("issues")
check(
    "integration export jira has summary/custom_fields",
    isinstance(issues, list)
    and len(issues) >= 1
    and isinstance(issues[0], dict)
    and bool(issues[0].get("summary"))
    and isinstance(issues[0].get("custom_fields"), dict),
)


print(">>> 7. /v1/predict in-domain")
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
body = _response_json(r)
check("in-dom ad_status == in_domain", body.get("ad_status") == "in_domain")
check("in-dom prediction_refused == false", body.get("prediction_refused") is False)
check("in-dom threshold_version present", bool(body.get("threshold_version")))
check("in-dom request_id echoed in header", r.headers.get("X-Request-Id") == body.get("request_id"))


print(">>> 8. /v1/predict out-of-envelope -> 422 + refusal")
out = dict(in_dom, sample_id="smoke-out-env", result_value_numeric=5000.0)
r = client.post("/v1/predict", json=out, headers=HEADERS_OK)
check("oob 422", r.status_code == 422, f"got {r.status_code}")
body = _response_json(r)
check("oob ad_status == reject", body.get("ad_status") == "reject")
check("oob prediction_refused == true", body.get("prediction_refused") is True)
check(
    "oob ad_reason contains value_out_of_range",
    "value_out_of_range" in str(body.get("ad_reason", "")),
)


print(">>> 9. /v1/predict analyte_unseen -> 422")
fake = dict(in_dom, sample_id="smoke-fake", analyte="MadeUpPFAS")
r = client.post("/v1/predict", json=fake, headers=HEADERS_OK)
check("fake-analyte 422", r.status_code == 422, f"got {r.status_code}")
check("fake-analyte ad_reason analyte_unseen", _response_json(r).get("ad_reason") == "analyte_unseen")


print(">>> 10. burst overrun returns 429 with Retry-After")
limiter = api_main._rate_limiter
bucket_key = f"k:{HEADERS_OK['X-API-Key'][:32]}"

with limiter._lock:
    limiter._buckets[bucket_key] = BucketState(
        tokens=0.0, last_refill=time.monotonic() + 3600.0
    )

r = client.get("/v1/whoami", headers=HEADERS_OK)
saw_429 = r.status_code == 429
saw_retry_after = "Retry-After" in r.headers if saw_429 else False

check("rate limit triggers 429", saw_429, f"got {r.status_code}")
check("rate limit response has Retry-After", saw_retry_after)


print(">>> 11. Access log contains structured fields")
lines = [ln for ln in LOG_BUF.getvalue().splitlines() if ln.strip().startswith("{")]

have_pred_log = False
for line in lines:
    try:
        rec = json.loads(line)
    except Exception:
        continue

    if rec.get("path") == "/v1/predict" and rec.get("status_code") == 422:
        if rec.get("lane") == "drinking_water" and rec.get("prediction_refused") is True:
            have_pred_log = True
            break

check(
    "JSON access log captured /v1/predict refusal with structured fields",
    have_pred_log,
    f"total_log_lines={len(lines)}",
)


print("\n=== SUMMARY ===")
total = len(results)
passed = sum(1 for _, ok, _ in results if ok)

for label, ok, _ in results:
    print(f"  {'PASS' if ok else 'FAIL'}  {label}")

print(f"\nOverall: {passed}/{total} {'PASS' if passed == total else 'FAIL'}")

sys.exit(0 if passed == total else 1)
