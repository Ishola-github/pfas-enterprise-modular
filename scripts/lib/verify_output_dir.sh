# shellcheck shell=bash
# Pick a writable output directory for Linux verify / V2 recheck.
# Docker Desktop WSL bind mounts (docker-desktop-bind-mounts, /mnt/c) are often
# not writable from Linux even when reads work.

verify_pick_output_dir() {
  local rel="${1:?relative output path under repo, e.g. data/v2/outputs/docker_recheck}"
  local repo_path="${ROOT}/${rel}"

  if [ -n "${PFAS_VERIFY_OUTPUT_ROOT:-}" ]; then
    mkdir -p "${PFAS_VERIFY_OUTPUT_ROOT}/${rel}"
    echo "${PFAS_VERIFY_OUTPUT_ROOT}/${rel}"
    return 0
  fi

  case "${ROOT}" in
    *docker-desktop-bind-mounts*|/mnt/*)
      mkdir -p "/tmp/pfas_verify_outputs/${rel}"
      echo "/tmp/pfas_verify_outputs/${rel}"
      return 0
      ;;
  esac

  if mkdir -p "${repo_path}" 2>/dev/null && [ -w "${repo_path}" ]; then
    echo "${repo_path}"
    return 0
  fi

  mkdir -p "/tmp/pfas_verify_outputs/${rel}"
  echo "/tmp/pfas_verify_outputs/${rel}"
}
