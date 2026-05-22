#!/usr/bin/env bash
# Linux verification (native Ubuntu / WSL / Docker bind-mount).
#
# You can run this script from ANY working directory — it locates the repo
# from the script path. Do NOT use a literal "/path/to/pfas-toxicology"; use
# the real folder where you cloned or copied the project, e.g.:
#   bash ~/Downloads/pfas-toxicology/pfas-toxicology/scripts/docker_verify_linux.sh
#
# Or first:
#   cd ~/Downloads/pfas-toxicology/pfas-toxicology
#   bash scripts/docker_verify_linux.sh
#
# Docker (mount full repo — root .dockerignore omits data/ + LatestPFAS.R from image COPY):
#   docker build -f Dockerfile.linux-verify -t pfas-linux-verify .
#   docker run --rm -v "$(pwd):/app" -w /app pfas-linux-verify
#
# Windows PowerShell:
#   docker build -f Dockerfile.linux-verify -t pfas-linux-verify .
#   docker run --rm -v "${PWD}:/app" -w /app pfas-linux-verify
#
# If V2 CLI fails with PermissionError under docker-desktop-bind-mounts, pull
# latest scripts (outputs go to /tmp/pfas_verify_outputs when repo is not writable).
# Best practice on WSL: clone the repo under ~/ (native Linux ext4), not /mnt/c/.
#
# Native Ubuntu / WSL — PEP 668 blocks "pip3 install" system-wide. Use a venv:
#   sudo apt-get update && sudo apt-get install -y r-base python3 python3-venv python3-pip
#   cd ~/Downloads/pfas-toxicology/pfas-toxicology   # <-- your real path
#   python3 -m venv .venv
#   source .venv/bin/activate
#   pip install -r requirements.txt
#   bash scripts/docker_verify_linux.sh

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/pick_verify_python.sh
source "${SCRIPT_DIR}/lib/pick_verify_python.sh"
# Docker image installs this script under /usr/local/bin; the repo is bind-mounted at /app.
# Native / WSL: script lives in <repo>/scripts/docker_verify_linux.sh — parent dir is repo root.
if [ -f "/app/LatestPFAS.R" ]; then
  ROOT="/app"
elif [ -n "${PFAS_VERIFY_ROOT:-}" ] && [ -f "${PFAS_VERIFY_ROOT}/LatestPFAS.R" ]; then
  ROOT="$(cd "${PFAS_VERIFY_ROOT}" && pwd)"
else
  ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
fi
cd "$ROOT"

if [ ! -f "$ROOT/LatestPFAS.R" ]; then
  echo "ERROR: LatestPFAS.R not found under: $ROOT" >&2
  echo "  Native: run from repo root or set PFAS_VERIFY_ROOT to the checkout." >&2
  echo "  Docker: mount the full repo at /app (see Dockerfile.linux-verify header)." >&2
  exit 1
fi

PYTHON="$(pick_verify_python_or_die "$ROOT")"

echo "=== Linux verify: host ==="
uname -a
echo "=== Linux verify: repo root ==="
echo "$ROOT"
echo "=== Linux verify: Python ==="
echo "$("$PYTHON" -c "import sys; print(sys.executable)")"

echo "=== R: parse LatestPFAS.R ==="
Rscript -e "invisible(parse('LatestPFAS.R')); cat('PARSE_OK\n')"

echo "=== R: smoke_icis_air_upload_banner.R ==="
Rscript scripts/smoke_icis_air_upload_banner.R

export PFAS_PYTHON="$PYTHON"
export PFAS_SMOKE_PROJECT_ROOT="$ROOT"
export PYTHONPATH="$ROOT"
export PFAS_V2_SKIP_R_PARSE=1
echo "=== V2: docker_recheck_v2.sh (CLI + Python tests + R smoke) ==="
bash "$ROOT/scripts/docker_recheck_v2.sh"

echo "=== Python: verify_reference_registry.py ==="
"$PYTHON" scripts/verify_reference_registry.py

echo "=== Python: governance_operational_snapshot.py (JSON roll-up; exit always 0) ==="
# head closes the pipe early; do not fail the verify script on SIGPIPE (exit 141).
"$PYTHON" scripts/governance_operational_snapshot.py --project-root "$ROOT" --pretty | head -n 120 || true

echo "=== Python: smoke_api.py ==="
"$PYTHON" scripts/smoke_api.py

echo ""
echo "=== Linux verify: ALL PASS ==="
