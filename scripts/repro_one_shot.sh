#!/usr/bin/env bash
# Independent Reproducibility Pilot — one-shot verification (RUO).
#
# From a clean clone at tag serum-v2.0.0-temporal:
#   bash scripts/repro_one_shot.sh
#
# PASS = exit 0 and printed V2 output_csv_sha256 matches canonical.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CANONICAL_V2_SHA="87c8b97e8a2c9002b183b0fabe161f531f1b933dd95e9ef4f4df980666310b67"
CANONICAL_V2_RUN="2bda057f5ab18ff6"

echo "=== PFAS Enterprise 5.0 — one-shot reproducibility ==="
echo "Repo: $ROOT"
echo ""

echo "=== Step 1/2: Docker full verify (governance + schema guards) ==="
docker build -f Dockerfile.linux-verify -t pfas-linux-verify .
docker run --rm -e CI=true -e GITHUB_ACTIONS=true -v "${ROOT}:/app" -w /app pfas-linux-verify

echo ""
echo "=== Step 2/2: Canonical V2 run (single hash gate) ==="
docker run --rm -v "${ROOT}:/app" -w /app pfas-linux-verify bash -c "
  set -euo pipefail
  export PYTHONPATH=/app
  python -m src.v2.cli \
    --input data/v1/fixtures/nhanes_j_governed_v1_input.csv \
    --output-dir data/v2/outputs/one_shot_repro \
    > /app/data/v2/outputs/one_shot_repro/_one_shot_summary.json
  python - <<'PY'
import json
from pathlib import Path
p = Path('data/v2/outputs/one_shot_repro/_one_shot_summary.json')
d = json.loads(p.read_text(encoding='utf-8'))
print('V2 run_id:', d.get('run_id', ''))
print('V2 output_csv_sha256:', d.get('output_csv_sha256', ''))
PY
" | tee /tmp/pfas_one_shot_v2.txt

V2_SHA="$(grep '^V2 output_csv_sha256:' /tmp/pfas_one_shot_v2.txt | awk '{print $NF}')"
V2_RUN="$(grep '^V2 run_id:' /tmp/pfas_one_shot_v2.txt | awk '{print $NF}')"

echo ""
echo "=== RESULT ==="
echo "V2 run_id:              ${V2_RUN}"
echo "V2 output_csv_sha256:   ${V2_SHA}"
echo "Expected run_id:        ${CANONICAL_V2_RUN}"
echo "Expected output SHA:    ${CANONICAL_V2_SHA}"

if [ "${V2_SHA}" = "${CANONICAL_V2_SHA}" ] && [ "${V2_RUN}" = "${CANONICAL_V2_RUN}" ]; then
  echo ""
  echo "ONE_SHOT_REPRO: PASS"
  echo "Sign REVIEWER_ATTESTATION_MINIMAL.txt and return to program operator."
  exit 0
fi

echo ""
echo "ONE_SHOT_REPRO: FAIL — do not sign attestation; report divergence in template."
exit 1
