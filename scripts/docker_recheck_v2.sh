#!/usr/bin/env bash
# V2 cross-cycle recheck — native Ubuntu / WSL / Docker bind-mount at /app.
#
# Standalone:
#   bash scripts/docker_recheck_v2.sh
#
# Docker (after building pfas-linux-verify):
#   docker run --rm --entrypoint bash -v "$(pwd):/app" -w /app \
#     pfas-linux-verify scripts/docker_recheck_v2.sh
#
# Windows PowerShell:
#   docker run --rm --entrypoint bash -v "${PWD}:/app" -w /app `
#     pfas-linux-verify scripts/docker_recheck_v2.sh

set -euo pipefail

if [ -f "/app/LatestPFAS.R" ]; then
  ROOT="/app"
elif [ -n "${PFAS_VERIFY_ROOT:-}" ] && [ -f "${PFAS_VERIFY_ROOT}/LatestPFAS.R" ]; then
  ROOT="$(cd "${PFAS_VERIFY_ROOT}" && pwd)"
else
  ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi
cd "$ROOT"

if [ -n "${VIRTUAL_ENV:-}" ] && [ -x "${VIRTUAL_ENV}/bin/python" ]; then
  PYTHON="${VIRTUAL_ENV}/bin/python"
elif [ -x "$ROOT/.venv/bin/python" ]; then
  PYTHON="$ROOT/.venv/bin/python"
else
  PYTHON="${PFAS_PYTHON:-python3}"
fi

export PFAS_PYTHON="$PYTHON"
export PFAS_SMOKE_PROJECT_ROOT="$ROOT"
export PYTHONPATH="$ROOT"

FIXTURE="$ROOT/data/v1/fixtures/nhanes_j_governed_v1_input.csv"
if [ ! -f "$FIXTURE" ]; then
  echo "ERROR: missing V2 fixture: $FIXTURE" >&2
  exit 1
fi

echo "=== V2 recheck: host ==="
uname -a
echo "=== V2 recheck: repo root ==="
echo "$ROOT"
echo "=== V2 recheck: Python ==="
echo "$("$PYTHON" -c "import sys; print(sys.executable)")"

echo "=== V2 CLI ==="
"$PYTHON" -m src.v2.cli \
  --input "$FIXTURE" \
  --output-dir "$ROOT/data/v2/outputs/docker_recheck"

echo ""
echo "=== V1.1 race-aware column assertion (Docker guard) ==="
"$PYTHON" -m src.v1.cli --v1-1 \
  --input "$FIXTURE" \
  --output-dir "$ROOT/data/v1/outputs/docker_recheck_v11_assert" >/tmp/v11_assert_summary.json
"$PYTHON" - <<'PY'
import csv
import glob
from pathlib import Path

report_paths = sorted(glob.glob("data/v1/outputs/docker_recheck_v11_assert/v1_report_*.csv"))
if not report_paths:
    raise SystemExit("ERROR: no V1.1 report generated for race-aware assertion")
report = Path(report_paths[-1])
required = [
    "race_ethnicity_requested",
    "race_ethnicity_lookup",
    "race_ethnicity_stratum",
    "race_stratum_fallback",
]
with report.open("r", encoding="utf-8", newline="") as fh:
    reader = csv.reader(fh)
    header = next(reader)
missing = [c for c in required if c not in header]
if missing:
    raise SystemExit(f"ERROR: V1.1 Docker race-aware assertion failed; missing columns: {missing}")
print("V1.1_RACE_COLUMNS_ASSERT_PASS")
PY

echo ""
echo "=== V2 Python tests (pytest-style functions) ==="
"$PYTHON" -c "
from src.v2.tests.test_temporal import test_temporal_flags_shift, test_cross_cycle_smoke
test_temporal_flags_shift()
test_cross_cycle_smoke()
print('V2_PY_TESTS_OK')
"

echo ""
echo "=== V1.1 reference table SHA ==="
sha256sum "$ROOT/data/reference_tables/nhanes_pfas_weighted_reference_tables_v1_1.csv"

echo ""
echo "=== R smoke V2 (run_v2_contextualization.R) ==="
if ! Rscript -e 'quit(status=if (requireNamespace("jsonlite", quietly=TRUE)) 0 else 1)'; then
  echo "ERROR: R package jsonlite required for V2 R smoke." >&2
  echo "  Docker: rebuild pfas-linux-verify (r-cran-jsonlite in Dockerfile.linux-verify)." >&2
  echo "  Ubuntu: sudo apt-get install -y r-cran-jsonlite" >&2
  exit 1
fi
Rscript "$ROOT/scripts/smoke_v2_shiny_integration.R"

if [ "${PFAS_V2_SKIP_R_PARSE:-0}" != "1" ]; then
  echo ""
  echo "=== R parse LatestPFAS.R ==="
  Rscript -e "invisible(parse('LatestPFAS.R')); cat('PARSE_OK\n')"
fi

echo ""
echo "=== V2 RECHECK PASS ==="
