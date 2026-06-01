"""
Export governed literature integration backlog payloads for CI handoff.

This script calls:
  POST /v1/literature/integration-backlog/export

and writes tracker-ready artifacts (Linear/Jira JSON) to disk.

Examples:
  python scripts/export_literature_backlog.py \
    --base-url http://127.0.0.1:8000 \
    --api-key <token>

  python scripts/export_literature_backlog.py \
    --targets linear jira \
    --include-deferred \
    --out-dir results/literature_exports
"""

from __future__ import annotations

import argparse
import json
import os
import sys
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


def _fetch_export_payload(
    *,
    client: httpx.Client,
    base_url: str,
    api_key: str,
    target: str,
    include_deferred: bool,
) -> dict[str, Any]:
    url = (
        f"{base_url.rstrip('/')}/v1/literature/integration-backlog/export"
        f"?target={target}&include_deferred={'true' if include_deferred else 'false'}"
    )
    resp = client.post(url, headers={"X-API-Key": api_key})
    if resp.status_code != 200:
        detail = ""
        try:
            detail = json.dumps(resp.json(), ensure_ascii=True)
        except Exception:
            detail = resp.text[:500]
        raise RuntimeError(
            f"export call failed for target={target}: status={resp.status_code} detail={detail}"
        )
    payload = resp.json()
    if not isinstance(payload, dict):
        raise RuntimeError(f"export payload was not an object for target={target}")
    return payload


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Export literature integration backlog as tracker JSON files."
    )
    parser.add_argument(
        "--base-url",
        default=os.environ.get("PFAS_EXPORT_BASE_URL", "http://127.0.0.1:8000"),
        help="API base URL (default: http://127.0.0.1:8000 or PFAS_EXPORT_BASE_URL).",
    )
    parser.add_argument(
        "--api-key",
        default=os.environ.get("PFAS_EXPORT_API_KEY", ""),
        help="API key. If omitted, first key from PFAS_API_KEYS is used.",
    )
    parser.add_argument(
        "--targets",
        nargs="+",
        default=["linear", "jira"],
        help="One or more targets: linear jira",
    )
    parser.add_argument(
        "--include-deferred",
        action="store_true",
        help="Include blocked deferred-review tasks in exports.",
    )
    parser.add_argument(
        "--out-dir",
        default="results/literature_exports",
        help="Output directory for JSON artifacts.",
    )
    parser.add_argument(
        "--timeout",
        type=float,
        default=20.0,
        help="HTTP timeout seconds per request.",
    )
    args = parser.parse_args()

    api_key = args.api_key or _first_api_key_secret(os.environ.get("PFAS_API_KEYS"))
    if not api_key:
        print(
            "ERROR: no API key found; pass --api-key or set PFAS_API_KEYS/PFAS_EXPORT_API_KEY",
            file=sys.stderr,
        )
        return 2

    raw_targets = [str(t).strip().lower() for t in args.targets]
    targets = [t for t in raw_targets if t in {"linear", "jira"}]
    invalid = [t for t in raw_targets if t not in {"linear", "jira"}]
    if invalid:
        print(f"ERROR: invalid targets: {', '.join(invalid)} (allowed: linear,jira)", file=sys.stderr)
        return 2
    if not targets:
        print("ERROR: no valid targets supplied", file=sys.stderr)
        return 2

    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    with httpx.Client(timeout=args.timeout) as client:
        for target in targets:
            payload = _fetch_export_payload(
                client=client,
                base_url=args.base_url,
                api_key=api_key,
                target=target,
                include_deferred=args.include_deferred,
            )
            path = out_dir / f"{target}.json"
            path.write_text(
                json.dumps(payload, indent=2, ensure_ascii=True) + "\n",
                encoding="utf-8",
            )
            tasks_exported = (
                payload.get("summary", {}).get("tasks_exported")
                if isinstance(payload.get("summary"), dict)
                else "unknown"
            )
            print(f"[ok] wrote {path} (tasks_exported={tasks_exported})")

    print("Export complete.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
