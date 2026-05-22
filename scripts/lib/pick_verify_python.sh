# shellcheck shell=bash
# Choose a Python interpreter that can import FastAPI + httpx for verify scripts.

pick_verify_python() {
  local root="${1:?repo root}"
  local py cand

  for cand in \
    "${PFAS_PYTHON:-}" \
    "${VIRTUAL_ENV:+$VIRTUAL_ENV/bin/python}" \
    "${root}/.venv/bin/python" \
    python3; do
    [ -n "${cand}" ] || continue
    [ -x "${cand}" ] || command -v "${cand}" >/dev/null 2>&1 || continue
    if "${cand}" -c "import sys" >/dev/null 2>&1 \
        && "${cand}" -c "import fastapi, httpx" >/dev/null 2>&1; then
      py="${cand}"
      break
    fi
  done

  if [ -z "${py:-}" ]; then
    return 1
  fi
  echo "${py}"
}

pick_verify_python_or_die() {
  local root="${1:?repo root}"
  local py
  if ! py="$(pick_verify_python "${root}")"; then
    echo "" >&2
    echo "ERROR: no Python with FastAPI + httpx found for verify." >&2
    case "${root}" in
      *docker-desktop-bind-mounts*|/mnt/*)
        echo "  WSL bind-mount detected. System python3 lacks project deps." >&2
        echo "  Recommended (matches CI):" >&2
        echo "    docker build -f Dockerfile.linux-verify -t pfas-linux-verify ." >&2
        echo "    docker run --rm -e CI=true -v \"\$(pwd):/app\" -w /app pfas-linux-verify" >&2
        echo "  Or create a Linux venv on a native ext4 path (~/clone), not /mnt/c/." >&2
        ;;
      *)
        echo "  Fix:" >&2
        echo "    cd ${root}" >&2
        echo "    python3 -m venv .venv && source .venv/bin/activate" >&2
        echo "    pip install -r requirements.txt" >&2
        echo "    bash scripts/docker_verify_linux.sh" >&2
        ;;
    esac
    echo "  Or use Docker (see scripts/docker_verify_linux.sh header)." >&2
    exit 1
  fi
  echo "${py}"
}
