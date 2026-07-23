#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat >&2 <<'USAGE'
usage: deploy-vapor-root-docs.sh --vapor-root PATH --base-url URL [--token-env NAME] [--token-file PATH]

Builds the curated Vapor-Root docs bundle and deploys it to the public Vapor
docs route over HTTP.

Before DNS is ready, use:

  --base-url http://82.165.77.104/docs
USAGE
}

VAPOR_ROOT=""
BASE_URL=""
TOKEN_ENV="VAPOR_DOCS_ADMIN_TOKEN"
TOKEN_FILE=""

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
    --base-url)
      if [ "$#" -lt 2 ]; then
        usage
        exit 2
      fi
      BASE_URL="$2"
      shift 2
      ;;
    --token-env)
      if [ "$#" -lt 2 ]; then
        usage
        exit 2
      fi
      TOKEN_ENV="$2"
      shift 2
      ;;
    --token-file)
      if [ "$#" -lt 2 ]; then
        usage
        exit 2
      fi
      TOKEN_FILE="$2"
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

if [ -z "${VAPOR_ROOT}" ] || [ -z "${BASE_URL}" ]; then
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
  --base-url "${BASE_URL}"
  --token-env "${TOKEN_ENV}"
)
if [ -n "${TOKEN_FILE}" ]; then
  UPLOAD_ARGS+=(--token-file "${TOKEN_FILE}")
fi

"${SCRIPT_DIR}/upload-docs-via-http.sh" "${UPLOAD_ARGS[@]}"
