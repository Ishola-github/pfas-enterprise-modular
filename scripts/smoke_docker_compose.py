"""
End-to-end smoke for `docker compose up` against the operational API.

What this asserts (using the same matrix the in-process test asserts so the
deployed image cannot diverge from local):

    1. Container is reachable on http://localhost:8000
    2. GET /healthz                          -> 200
    3. GET /health                           -> 200, ad.available_lanes has 6 lanes,
                                                manifests dict present, config dict present
    4. GET /v1/whoami no key                 -> 401 + missing_api_key
    5. GET /v1/whoami with valid key         -> 200 + api_key_id echoed
    6. POST /v1/predict in-domain row        -> 200 + ad_status=in_domain + prediction_refused=false
    7. POST /v1/predict out-of-envelope      -> 422 + ad_status=reject + prediction_refused=true
    8. Burst of GETs                          -> at least one 429 with Retry-After

This script does NOT bring the stack up or down — that is the operator's
responsibility (so we don't accidentally restart a running pilot). Use:

    docker compose up -d --build
    python scripts/smoke_docker_compose.py
    docker compose down

If you want the orchestration too, pass --manage:

    python scripts/smoke_docker_compose.py --manage

The script reads PFAS_API_KEYS from .env in the current working directory
(via python-dotenv) so it picks up exactly what compose handed to the
container. Override the base URL or key with:

    --base-url   default http://localhost:8000
    --api-key    default first value parsed from PFAS_API_KEYS (after ':' if id:secret)
    --timeout    seconds for each HTTP request (default 15)

Exit codes:
    0  all PASS
    1  one or more FAIL
    2  pre-flight error (container not reachable, no API key, etc.)
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

import httpx

try:
    from dotenv import load_dotenv

    _envp = Path(__file__).resolve().parent.parent / ".env"
    if _envp.is_file():
        load_dotenv(_envp, override=False)
except Exception:
    pass


def _first_api_key_secret(raw: str | None) -> str:
    if not raw:
        return ""
    token = raw.split(",", 1)[0].strip()
    if ":" in token:
        return token.split(":", 1)[1].strip()
    return token


def _compose_cmd(*args: str) -> list[str]:
    return ["docker", "compose", *args]


def _compose_up_and_wait(base_url: str, timeout: float) -> None:
    print("[manage] docker compose up -d --build ...")
    subprocess.run(_compose_cmd("up", "-d", "--build"), check=True)
    deadline = time.time() + timeout
    last_err = ""
    while time.time() < deadline:
        try:
            r = httpx.get(f"{base_url}/healthz", timeout=3.0)
            if r.status_code == 200:
                print(f"[manage] healthz 200 after {timeout - (deadline - time.time()):.1f}s")
                return
            last_err = f"status={r.status_code}"
        except Exception as exc:
            last_err = f"{type(exc).__name__}: {exc}"
        time.sleep(1.0)
    raise SystemExit(f"[manage] /healthz never reached 200 within {timeout:.0f}s ({last_err})")


def _compose_down() -> None:
    print("[manage] docker compose down ...")
    subprocess.run(_compose_cmd("down"), check=False)


# --------------------------------------------------------------------- #
# Assertions                                                            #
# --------------------------------------------------------------------- #

_results: list[tuple[str, bool, str]] = []


def check(label: str, ok: bool, detail: str = "") -> None:
    _results.append((label, ok, detail))
    flag = "PASS" if ok else "FAIL"
    print(f"  [{flag}] {label}  {detail}")


def main() -> int:
    p = argparse.ArgumentParser(description="Smoke the deployed compose stack.")
    p.add_argument("--base-url", default=os.environ.get("PFAS_SMOKE_BASE_URL", "http://localhost:8000"))
    p.add_argument("--api-key", default=os.environ.get("PFAS_SMOKE_API_KEY", ""))
    p.add_argument("--timeout", type=float, default=15.0)
    p.add_argument("--manage", action="store_true",
                   help="Run `docker compose up -d --build` and `down` around the smoke.")
    p.add_argument("--manage-wait", type=float, default=90.0,
                   help="When --manage is set: max seconds to wait for /healthz=200.")
    args = p.parse_args()

    api_key = args.api_key or _first_api_key_secret(os.environ.get("PFAS_API_KEYS"))
    if not api_key:
        print("ERROR: no API key available. Set PFAS_API_KEYS in .env or pass --api-key.", file=sys.stderr)
        return 2

    if args.manage:
        try:
            _compose_up_and_wait(args.base_url, args.manage_wait)
        except SystemExit as e:
            print(str(e), file=sys.stderr)
            _compose_down()
            return 2

    client = httpx.Client(timeout=args.timeout)
    headers_ok = {"X-API-Key": api_key, "Content-Type": "application/json"}

    try:
        print(f">>> probing {args.base_url}/healthz")
        r = client.get(f"{args.base_url}/healthz")
        check("healthz 200", r.status_code == 200, f"got {r.status_code}")

        print(">>> /health rich")
        r = client.get(f"{args.base_url}/health")
        check("health 200", r.status_code == 200, "")
        body = r.json() if r.status_code == 200 else {}
        lanes = (body.get("ad") or {}).get("available_lanes") or []
        check("health lists 6 AD lanes", len(lanes) == 6, f"lanes={lanes}")
        check("health has manifests dict", isinstance(body.get("manifests"), dict), "")
        check("health has registry_verification dict",
              isinstance(body.get("registry_verification"), dict), "")
        check("health does NOT include paths by default",
              "paths" not in body, "")

        print(">>> /v1/whoami unauth")
        r = client.get(f"{args.base_url}/v1/whoami")
        check("unauth 401", r.status_code == 401, f"got {r.status_code}")
        body = r.json() if r.status_code == 401 else {}
        check("unauth error=missing_api_key",
              (body.get("detail") or {}).get("error") == "missing_api_key",
              f"detail={body.get('detail')}")
        check("unauth X-Request-Id header present",
              r.headers.get("X-Request-Id") is not None, "")

        print(">>> /v1/whoami auth")
        r = client.get(f"{args.base_url}/v1/whoami", headers=headers_ok)
        check("auth 200", r.status_code == 200, f"got {r.status_code}")
        body = r.json() if r.status_code == 200 else {}
        check("auth api_key_id present", bool(body.get("api_key_id")), f"got {body.get('api_key_id')}")

        print(">>> /v1/predict in-domain")
        in_dom = {
            "sample_id": "compose-smoke-in",
            "matrix_lane": "drinking_water",
            "matrix": "drinking water",
            "analyte": "PFOA",
            "result_value_numeric": 7.5,
            "result_unit": "ng/L",
            "method_id": "EPA_UCMR5_method",
            "state": "CA",
            "model_version": "compose_smoke_v0.1",
        }
        r = client.post(f"{args.base_url}/v1/predict", headers=headers_ok,
                        content=json.dumps(in_dom))
        check("in-dom 200", r.status_code == 200, f"got {r.status_code}")
        body = r.json() if r.status_code == 200 else {}
        check("in-dom ad_status == in_domain",
              body.get("ad_status") == "in_domain", f"got {body.get('ad_status')}")
        check("in-dom prediction_refused == false",
              body.get("prediction_refused") is False, "")
        check("in-dom request_id echoed in header",
              r.headers.get("X-Request-Id") == body.get("request_id"), "")

        print(">>> /v1/predict out-of-envelope")
        oob = dict(in_dom, sample_id="compose-smoke-oob", result_value_numeric=5000.0)
        r = client.post(f"{args.base_url}/v1/predict", headers=headers_ok,
                        content=json.dumps(oob))
        check("oob 422 (hard refusal)", r.status_code == 422, f"got {r.status_code}")
        body = r.json() if r.status_code == 422 else {}
        check("oob ad_status == reject",
              body.get("ad_status") == "reject", f"got {body.get('ad_status')}")
        check("oob prediction_refused == true",
              body.get("prediction_refused") is True, "")
        check("oob ad_reason contains value_out_of_range",
              "value_out_of_range" in str(body.get("ad_reason", "")), "")

        print(">>> rate limit burst")
        saw_429 = False
        saw_retry_after = False
        # 25 quick calls should overrun any reasonable burst capacity.
        for _ in range(25):
            r = client.get(f"{args.base_url}/v1/whoami", headers=headers_ok)
            if r.status_code == 429:
                saw_429 = True
                saw_retry_after = "Retry-After" in r.headers
                break
        check("burst triggers 429", saw_429, "")
        check("429 carries Retry-After header", saw_retry_after, "")
    finally:
        try:
            client.close()
        except Exception:
            pass
        if args.manage:
            _compose_down()

    total = len(_results)
    passed = sum(1 for _, ok, _ in _results if ok)
    print("\n=== SUMMARY ===")
    for label, ok, _ in _results:
        print(f"  {'PASS' if ok else 'FAIL'}  {label}")
    print(f"\nOverall: {passed}/{total} {'PASS' if passed == total else 'FAIL'}")
    return 0 if passed == total else 1


if __name__ == "__main__":
    sys.exit(main())
