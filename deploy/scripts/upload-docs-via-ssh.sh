#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: upload-docs-via-ssh.sh --bundle PATH --host HOST [--user USER] [--ssh-key PATH] [--ssh-option OPTION]

Uploads a docs tar.gz bundle to the VPS by streaming it over SSH and posting it
from the server to the local Vapor docs service. The docs admin token is read
from /etc/vapor-server/docs.env on the server and is never copied to the client.
USAGE
}

BUNDLE=""
HOST=""
SSH_USER="root"
SSH_KEY=""
SSH_OPTIONS=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    --bundle)
      if [ "$#" -lt 2 ]; then
        usage
        exit 2
      fi
      BUNDLE="$2"
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

if [ -z "${BUNDLE}" ] || [ -z "${HOST}" ]; then
  usage
  exit 2
fi

if [ ! -f "${BUNDLE}" ]; then
  echo "error: bundle does not exist: ${BUNDLE}" >&2
  exit 1
fi

SSH_ARGS=()
if [ -n "${SSH_KEY}" ]; then
  SSH_ARGS+=("-i" "${SSH_KEY}")
fi
for option in "${SSH_OPTIONS[@]}"; do
  SSH_ARGS+=("-o" "${option}")
done

ssh "${SSH_ARGS[@]}" "${SSH_USER}@${HOST}" '
set -eu

if [ ! -r /etc/vapor-server/docs.env ]; then
  echo "error: missing /etc/vapor-server/docs.env" >&2
  exit 1
fi

set -a
# shellcheck disable=SC1091
. /etc/vapor-server/docs.env
set +a

if [ -z "${VAPOR_DOCS_ADMIN_TOKEN:-}" ]; then
  echo "error: VAPOR_DOCS_ADMIN_TOKEN is empty" >&2
  exit 1
fi

tmp="$(mktemp)"
cleanup() {
  rm -f "${tmp}"
}
trap cleanup EXIT

cat > "${tmp}"
curl -fsS \
  -X POST \
  -H "Authorization: Bearer ${VAPOR_DOCS_ADMIN_TOKEN}" \
  --data-binary "@${tmp}" \
  http://127.0.0.1:7112/v1/current.tar.gz
' < "${BUNDLE}"
