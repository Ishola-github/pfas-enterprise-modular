#!/usr/bin/env bash
# =============================================================================
# Three-environment confirmation -- Docker / Ubuntu side.
# =============================================================================
#
# Computes SHA-256 of the four serum-lane integrity anchors using
# Linux's native sha256sum (coreutils) inside an ubuntu:22.04
# container and writes the result deterministically to
# validation/serum_h_v1/.confirm_docker.txt.
#
# Output format is the standard `sha256sum` format
# (`<hash>  <path>`), with an extra "(<bytes> bytes)" suffix per
# line so each line is self-describing.
#
# Intended invocation (from the repo root):
#
#   docker run --rm \
#     -v "$(pwd):/workspace" \
#     -w /workspace \
#     ubuntu:22.04 \
#     bash scripts/confirm_anchors_docker.sh
#
# =============================================================================

set -euo pipefail

OUT="validation/serum_h_v1/.confirm_docker.txt"
mkdir -p "$(dirname "${OUT}")"

# coreutils ships in the base image; sha256sum and stat are
# available without an apt install.
FILES=(
  "data/training/serum/nhanes_serum_pfas_2017_2018.csv"
  "data/training/serum_h/nhanes_serum_pfas_h_2013_2014.csv"
  "data/external/nhanes_serum_h/PFAS_H.XPT"
  "data/external/nhanes_serum_h/SSPFAS_H.XPT"
)

{
  echo "# Three-environment confirmation -- Docker/Ubuntu"
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

echo "[confirm_docker] wrote ${OUT}"
cat "${OUT}"
