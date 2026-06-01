# PFAS Enterprise 5 — Operational API

This directory contains the **operational** prediction layer. The Shiny
app (`LatestPFAS.R`) remains the analyst / research console. They are
intentionally distinct surfaces:

| Surface | Audience | Purpose |
| --- | --- | --- |
| `LatestPFAS.R` (Shiny) | analysts, scientists | exploratory, lane-aware UX, validation reviews |
| `api/` (FastAPI)       | pipelines, CI, pilots | refusal-aware, AD-gated, request-id'd predictions |

The API is **lightweight on purpose**. The current SaaS phase covers
only operational safety controls:

- API-key authentication (`api/security.py`)
- Per-key rate limiting via in-process token bucket (`api/rate_limit.py`)
- Structured JSON access logs (`api/logging_setup.py`, `api/middleware.py`)
- Request-id assignment, propagation, and echo (`api/middleware.py`)
- `.env` based secret loading (`api/settings.py`)
- Rich `/health` endpoint (no internal paths by default)
- AD-gated `/v1/predict` with **hard refusal propagation** into both
  HTTP status and JSON body (`api/ad_integration.py` → `scripts/apply_ad_guard.py`)

Explicitly **out of scope** for this phase:

> enterprise RBAC, billing, multi-tenant isolation, Kubernetes,
> autoscaling, SOC 2 / FedRAMP claims, cloud overengineering, JWT issuer.

The full, authoritative list of in-scope and out-of-scope SaaS controls
is in **[../SCOPE_AND_INTENDED_USE.md](../SCOPE_AND_INTENDED_USE.md)**,
Section 16 ("SaaS Operational Limitations"). Operators standing up a
pilot should read that document end-to-end before exposing the API.

## Run locally

```powershell
cp .env.example .env
# generate two real keys
python -c "import secrets; print('PFAS_API_KEYS=ops:' + secrets.token_urlsafe(24) + ',ci:' + secrets.token_urlsafe(24))"
# paste into .env, then:
python -m uvicorn api.main:app --host 0.0.0.0 --port 8000
```

In development with **no** `PFAS_API_KEYS` set, the API will print a
one-shot generated key at startup:

```
[pfas-api] WARNING: PFAS_API_KEYS not set; generated a dev key
(X-API-Key: <token>). Set PFAS_API_KEYS in .env to lock in a value.
```

That dev-only behaviour is suppressed when `APP_ENV != development`.

## Run with Docker Compose (reproducible)

The repository root ships a pinned `Dockerfile` and `docker-compose.yml`
that bring up exactly the AD-gated API verified by `scripts/smoke_api.py`.
No source bind mount, no Shiny — only the operational layer.

```powershell
# 1) Create .env from the example and inject a real key.
cp .env.example .env
python -c "import secrets, pathlib, io
key = 'ops:' + secrets.token_urlsafe(24)
src = pathlib.Path('.env').read_text(encoding='utf-8').splitlines()
out = [(line if not line.startswith('PFAS_API_KEYS=') else 'PFAS_API_KEYS=' + key) for line in src]
pathlib.Path('.env').write_bytes(('\n'.join(out) + '\n').encode('utf-8'))
print('PFAS_API_KEYS rewritten with id=ops')"

# 2) Build + start (port 8000 published on the host).
docker compose up -d --build

# 3) Verify (21/21 PASS — auth, /health, AD in-domain, AD reject, rate limit).
python scripts/smoke_docker_compose.py

# 4) Tear down.
docker compose down
```

What lands in the image (see `.dockerignore`):

| Path | Why it must be in the image |
| --- | --- |
| `api/` | FastAPI application |
| `scripts/apply_ad_guard.py`, `scripts/verify_reference_registry.py` | imported / invoked at runtime |
| `modules/` | sustainability metrics for legacy `/predict` |
| `data/ad_models/<lane>/ad_model.json` | per-lane refusal models |
| `data/config/ucmr_analyte_limits_ngl.csv` | drinking_water `threshold_version` hash |
| `data/config/matrix_pipeline_sop.csv` | `/health.manifests.matrix_pipeline_sop` boolean |
| `data/reference/registry/reference_registry.csv` | `/health.registry_verification` block |
| `data/reference/literature/acs_chemrestox_priority_registry.json` | `/v1/literature/priorities` governed triage feed |

Heavy training corpora (`data/raw/`, `data/processed/`, `data/training/`,
`validation/`, `legacy/`, `LatestPFAS.R`, the SQLite DB) are **deliberately
excluded** from the operational image: they are not needed for AD-gated
prediction and would balloon the image.

Reproducibility notes:

- Image tag is fixed at `pfas-enterprise/api:5.0.0`.
- Python base is `python:3.11-slim-bookworm`; pin to a digest for stricter
  reproducibility (`FROM python:3.11-slim-bookworm@sha256:<...>`).
- `requirements.txt` is pinned to the exact versions verified on
  2026-05-12 across Windows + RStudio + Docker Ubuntu + native WSL Ubuntu.
- Service runs as non-root user `pfas` (UID 10001).
- Container has a Python-based `HEALTHCHECK` hitting `/healthz` every 20 s;
  `docker compose ps` reports `health: healthy` when the API is ready.
- `restart: unless-stopped` so the container survives Docker Desktop
  reboots but does not race a deliberate `docker compose down`.

## Environment variables

| Variable | Default | Purpose |
| --- | --- | --- |
| `APP_ENV` | `development` | Marker only; gates dev-only conveniences. |
| `SCREENING_USE_ONLY` | `true` | Echoed in `intended_use` disclaimers. |
| `PFAS_API_KEYS` | (empty) | Comma-separated `id:secret` (or just `secret`) pairs. |
| `PFAS_API_AUTH_OPEN` | `false` | Dev loopback — accept *all* requests. NEVER on in staging/prod. |
| `PFAS_API_AUTH_HEADER` | `X-API-Key` | Header name for the API key. |
| `PFAS_API_RATE_LIMIT_ENABLED` | `true` | Master switch for the in-process limiter. |
| `PFAS_API_RATE_LIMIT_PER_MINUTE` | `60` | Sustained rate (token refill = N / 60 / sec). |
| `PFAS_API_RATE_LIMIT_BURST` | `20` | Token-bucket capacity. |
| `PFAS_API_LOG_LEVEL` | `INFO` | Logger level for `pfas.api`. |
| `PFAS_API_LOG_JSON` | `true` | False switches to plain-text (dev only). |
| `PFAS_API_ACCESS_LOG` | (unset) | Optional file sink alongside stdout. |
| `PFAS_API_AD_STRICT_REFUSAL` | `true` | AD `reject` → HTTP 422 (vs HTTP 200 with `prediction_refused=true`). |
| `PFAS_API_EXPOSE_PATHS` | `false` | Show internal paths under `/health.paths`. |
| `PFAS_API_REQUEST_ID_HEADER` | `X-Request-Id` | Incoming/outgoing header name. |

## Endpoint reference

### `GET /health` (unauthenticated)

Returns liveness, AD-framework availability, manifest availability, and
registry-verification status. No secrets are emitted; internal filesystem
paths are hidden unless `PFAS_API_EXPOSE_PATHS=true`.

### `GET /healthz` (unauthenticated)

Tiny liveness probe (`{"status":"ok",...}`) for load balancers.

### `GET /v1/whoami` (authenticated)

Echoes the authenticated `api_key_id`, request id, and effective rate
limit. Useful as a credentials smoke test.

### `GET /v1/ad/{lane}` (authenticated)

Returns the AD model metadata (version, method, thresholds, training
range hash, training row count, refusal rules) for one lane.

### `GET /v1/literature/priorities` (authenticated)

Returns governed literature triage decisions mapped to PFAS Enterprise
module priorities.

- Default (`include_deferred=false`) returns only papers marked
  `decision=include_now`.
- `include_deferred=true` includes queued items marked
  `defer_pending_full_text_review`.

### `GET /v1/literature/integration-backlog` (authenticated)

Returns module-level implementation tasks derived from the governed
literature triage registry.

- Default (`include_deferred=false`) emits only `ready` tasks built from
  papers with `decision=include_now`.
- `include_deferred=true` also emits
  `blocked_pending_full_text_review` tasks so roadmap tooling can track
  queued work without treating it as implementation-ready.

### `POST /v1/literature/integration-backlog/export` (authenticated)

Returns tracker-ingest payloads generated from the same governed
literature backlog.

- `target=linear` (default): emits issue items with `title`,
  `description`, `labels`, `priority`, `state`, `metadata`.
- `target=jira`: emits issue items with `summary`, `description`,
  `labels`, `priority`, and `custom_fields`.
- `include_deferred=true`: includes blocked items sourced from deferred
  papers so planning systems can keep them visible.

CI export helper:

```bash
python scripts/export_literature_backlog.py \
  --base-url http://127.0.0.1:8000 \
  --api-key "<token>" \
  --targets linear jira \
  --out-dir results/literature_exports
```

### `POST /v1/predict` (authenticated, AD-gated)

Single-row screening request. The API runs the **same** AD decision
function used by `scripts/apply_ad_guard.py`, so the API and the offline
guard cannot disagree on identical inputs.

Request body:

```json
{
  "sample_id": "demo-001",
  "matrix_lane": "drinking_water",
  "matrix": "drinking water",
  "analyte": "PFOA",
  "result_value_numeric": 7.5,
  "result_unit": "ng/L",
  "method_id": "EPA_UCMR5_method",
  "state": "CA",
  "model_version": "demo_model_v0.1"
}
```

Response (in-domain, HTTP 200):

```json
{
  "request_id": "...",
  "sample_id": "demo-001",
  "matrix_lane": "drinking_water",
  "ad_status": "in_domain",
  "ad_distance": "0.42",
  "ad_reason": "value_in_envelope:log10_z=0.42",
  "ad_method": "per_analyte_envelope_v1",
  "ad_model_version": "1.0.0",
  "training_range_version": "<sha-prefix>",
  "ad_threshold": "3.0",
  "reference_lane": "drinking_water",
  "nearest_training_source": "EPA_UCMR5",
  "prediction_refused": false,
  "threshold_version": "<sha-prefix>",
  "model_version": "demo_model_v0.1",
  "intended_use": "Screening decision-support only. ...",
  "prediction": {
    "label": null, "score": null,
    "rationale": "AD-only gate; no production classifier wired"
  }
}
```

Refusal response (out-of-envelope, `PFAS_API_AD_STRICT_REFUSAL=true`, HTTP **422**):

```json
{
  "ad_status": "reject",
  "ad_reason": "value_out_of_range:log10_z=8.40",
  "prediction_refused": true,
  "prediction": {
    "label": null, "score": null,
    "rationale": "Refused: outside validated applicability domain. ..."
  }
}
```

`X-Request-Id` is set on **every** response (including 401 / 429 / 422
errors) and equals `request_id` in the body.

### `POST /predict` (legacy, authenticated, **NOT** AD-gated)

Kept for back-compat with the original screening stub. Carries a
deprecation note in the response body. Prefer `/v1/predict`.

## Access log shape

Every request emits one JSON line at `INFO` level on the `pfas.api`
logger (stdout, plus optional file via `PFAS_API_ACCESS_LOG`):

```json
{
  "timestamp": "2026-05-12T10:00:47.080Z",
  "level": "INFO",
  "logger": "pfas.api",
  "message": "access",
  "request_id": "b4c876bf-aadf-4a2c-b2f9-46a0ac63c81e",
  "method": "POST",
  "path": "/v1/predict",
  "status_code": 422,
  "response_ms": 2,
  "api_key_id": "ci",
  "lane": "drinking_water",
  "ad_status": "reject",
  "prediction_refused": true,
  "model_version": "smoke_model_v0.1",
  "threshold_version": "f88fb8f613e6"
}
```

Empty strings (instead of nulls) are used for inapplicable fields so
that downstream log-aggregation pipelines can treat every record as
having the same schema.

## Authentication semantics

- Auth happens **after** rate limiting on a per-presented-key basis,
  so brute-force attempts hit the limiter before the cryptographic
  compare.
- All key comparisons use `hmac.compare_digest` (constant time) over
  the full configured key dictionary. Match time does not leak which
  key matched first.
- An empty key pool with `PFAS_API_AUTH_OPEN=false` returns
  **HTTP 503 `api_key_pool_empty`** for every authenticated route,
  on purpose — the operator must explicitly choose between "open
  dev mode" and "configured keys".

## Refusal semantics (the most important rule)

Predictions are gated by per-lane applicability-domain enforcement
(`data/ad_models/<lane>/ad_model.json`). When AD returns `reject`:

- **HTTP status** is 422 (default; controlled by `PFAS_API_AD_STRICT_REFUSAL`)
- **Response body** carries `prediction_refused: true` and the full
  AD column contract (`ad_status`, `ad_distance`, `ad_reason`,
  `ad_method`, `ad_model_version`, `training_range_version`,
  `ad_threshold`, `reference_lane`, `nearest_training_source`)
- **Access log line** carries `prediction_refused: true` and
  `ad_status: reject`
- **Response header** `X-Request-Id` matches the body `request_id`
  so external systems can join the API event to its log line

Refusal is *not* an error condition (in the colloquial sense); it is a
governance outcome and is treated as a first-class result.

## Smoke test

```powershell
python scripts/smoke_api.py
```

Drives the full middleware stack via Starlette's `TestClient`:
unauthenticated → 401, valid key → 200, AD in-domain → 200,
AD out-of-envelope → 422 + `prediction_refused`, unknown analyte → 422,
burst overrun → 429 + `Retry-After`, and asserts that the structured
JSON access log captured `request_id` / `lane` / `ad_status` /
`prediction_refused` / `model_version` / `threshold_version` for the
prediction call.

Expected output ends with:

```
Overall: 24/24 PASS
```

## Not done on purpose (yet)

- Per-tenant keys / RBAC roles
- Distributed rate limiting (Redis)
- WebAuthn / OAuth / SSO
- Billing / metering / quota enforcement
- mTLS / private link
- Autoscaling / Kubernetes
- SOC 2 audit theatre

These slot in **after** pilot users surface real workflow pain — not
before.
