#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat >&2 <<'USAGE'
usage: publish-vapor-root-docs.sh --vapor-root PATH --host HOST [--user USER] [--ssh-key PATH] [--ssh-option OPTION]

Builds the curated Vapor-Root docs bundle and uploads it to the Vapor docs
service over SSH.
USAGE
}

VAPOR_ROOT=""
HOST=""
SSH_USER="root"
SSH_KEY=""
SSH_OPTIONS=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    --vapor-root)
      if [ "$#" -lt 2 ]; then
        usage
        exit 2
      fi
      VAPOR_ROOT="$2"
      shift 2
      ;;
    --host)
      if [ "$#" -lt 2 ]; then
        usage
        exit 2
      fi
      HOST="$2"
      shift 2
      ;;
    --user)
      if [ "$#" -lt 2 ]; then
        usage
        exit 2
      fi
      SSH_USER="$2"
      shift 2
      ;;
    --ssh-key)
      if [ "$#" -lt 2 ]; then
        usage
        exit 2
      fi
      SSH_KEY="$2"
      shift 2
      ;;
    --ssh-option)
      if [ "$#" -lt 2 ]; then
        usage
        exit 2
      fi
      SSH_OPTIONS+=("$2")
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage
      exit 2
      ;;
  esac
done

if [ -z "${VAPOR_ROOT}" ] || [ -z "${HOST}" ]; then
  usage
  exit 2
fi

BUNDLE="$(mktemp --suffix=.tar.gz vapor-root-docs.XXXXXXXXXX)"
cleanup() {
  rm -f "${BUNDLE}"
}
trap cleanup EXIT

"${SCRIPT_DIR}/build-vapor-root-docs-bundle.sh" \
  --vapor-root "${VAPOR_ROOT}" \
  --output "${BUNDLE}" >/dev/null

UPLOAD_ARGS=(
  --bundle "${BUNDLE}"
  --host "${HOST}"
  --user "${SSH_USER}"
)
if [ -n "${SSH_KEY}" ]; then
  UPLOAD_ARGS+=(--ssh-key "${SSH_KEY}")
fi
for option in "${SSH_OPTIONS[@]}"; do
  UPLOAD_ARGS+=(--ssh-option "${option}")
done

"${SCRIPT_DIR}/upload-docs-via-ssh.sh" "${UPLOAD_ARGS[@]}"
