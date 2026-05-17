#!/usr/bin/env bash
# =============================================================================
# Three-environment confirmation for the NHANES reference tables
# (Docker/Ubuntu side).
# =============================================================================
#
# Hashes the two precomputed reference tables and all 8 raw XPTs
# under data/raw/nhanes/ from inside an ubuntu:22.04 container, using
# native sha256sum (no apt installs).  Output:
#
#   data/reference_tables/.confirm_docker.txt
#
# Invocation (from the repo root, host shell):
#
#   docker run --rm \
#     -v "$(pwd):/workspace" \
#     -w /workspace \
#     ubuntu:22.04 \
#     bash -c "sed -i 's/\r$//' scripts/confirm_reference_tables_docker.sh && bash scripts/confirm_reference_tables_docker.sh"
#
# Windows checkouts may store CRLF; strip before run (see command above).
# =============================================================================

set -euo pipefail

OUT="data/reference_tables/.confirm_docker.txt"
mkdir -p "$(dirname "${OUT}")"

FILES=(
  "data/reference_tables/nhanes_pfas_reference_tables_v1.csv"
  "data/reference_tables/nhanes_pfas_weighted_reference_tables_v1.csv"
  "data/reference_tables/nhanes_pfas_weighted_reference_tables_v1_1.csv"
  "data/raw/nhanes/2013_2014/PFAS_H.XPT"
  "data/raw/nhanes/2013_2014/DEMO_H.XPT"
  "data/raw/nhanes/2015_2016/PFAS_I.XPT"
  "data/raw/nhanes/2015_2016/DEMO_I.XPT"
  "data/raw/nhanes/2017_2018/PFAS_J.XPT"
  "data/raw/nhanes/2017_2018/DEMO_J.XPT"
  "data/raw/nhanes/2017_2020/P_PFAS.XPT"
  "data/raw/nhanes/2017_2020/P_DEMO.XPT"
)

{
  echo "# Three-environment confirmation -- Docker/Ubuntu (reference tables + raw XPTs)"
  echo "# Image:        ubuntu:22.04"
  echo "# Container:    $(uname -a)"
  echo "# Run timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  for f in "${FILES[@]}"; do
    if [ -f "${f}" ]; then
      h=$(sha256sum "${f}" | awk '{print $1}')
      sz=$(stat -c %s "${f}")
      printf "%s  %s  (%s bytes)\n" "${h}" "${f}" "${sz}"
    else
      printf "MISSING  ----------------------------------------------------------------  %s\n" "${f}"
    fi
  done
} > "${OUT}"

echo "[confirm_reference_tables_docker] wrote ${OUT}"
cat "${OUT}"
