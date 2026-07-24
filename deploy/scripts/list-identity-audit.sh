#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

usage() {
  cat <<'USAGE'
Usage:
  deploy/scripts/list-identity-audit.sh [options]

Options:
  --base URL                 Identity service base URL. Default:
                             http://127.0.0.1:7113
  --admin-token VALUE        Use an explicit admin token.
  --admin-token-file PATH    Read the admin token from the first line of PATH.
  -h, --help                 Show this help.

Notes:
  - If no admin token is provided, the script reads
    /etc/vapor-server/identity.env when readable.
  - The token is used only as an Authorization header and is never printed.
  - Audit output identifies actors and subjects by linked Steam/GitHub
    identities, not by internal profile ids.
USAGE
}

base_url="${VAPOR_IDENTITY_LOCAL_URL:-http://127.0.0.1:7113}"
admin_token="${VAPOR_IDENTITY_ADMIN_TOKEN:-}"
admin_token_file=""
identity_env="${VAPOR_CONFIG_DIR}/identity.env"

read_first_line() {
  local path="$1"
  if [ ! -r "$path" ]; then
    echo "error: cannot read ${path}" >&2
    exit 1
  fi
  sed -n '1p' "$path"
}

read_env_value() {
  local path="$1"
  local key="$2"
  if [ ! -r "$path" ]; then
    return 0
  fi
  sed -n "s/^${key}=//p" "$path" | sed -n '1p'
}

validate_base_url() {
  case "$1" in
    http://*|https://*) ;;
    *)
      echo "error: --base must start with http:// or https://" >&2
      exit 1
      ;;
  esac
  case "$1" in
    *";"*|*$'\n'*|*$'\r'*)
      echo "error: --base must not contain semicolons or newlines" >&2
      exit 1
      ;;
  esac
}

validate_header_value() {
  if [ -z "$1" ]; then
    echo "error: admin token is missing" >&2
    exit 1
  fi
  case "$1" in
    *$'\n'*|*$'\r'*)
      echo "error: admin token must be a single-line value" >&2
      exit 1
      ;;
  esac
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --base)
      [ "$#" -ge 2 ] || { echo "error: missing value for $1" >&2; exit 1; }
      base_url="$2"
      shift 2
      ;;
    --admin-token)
      [ "$#" -ge 2 ] || { echo "error: missing value for $1" >&2; exit 1; }
      admin_token="$2"
      shift 2
      ;;
    --admin-token-file)
      [ "$#" -ge 2 ] || { echo "error: missing value for $1" >&2; exit 1; }
      admin_token_file="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown option $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

validate_base_url "$base_url"

if [ -n "$admin_token_file" ]; then
  admin_token="$(read_first_line "$admin_token_file")"
fi
if [ -z "$admin_token" ]; then
  admin_token="$(read_env_value "$identity_env" "VAPOR_IDENTITY_ADMIN_TOKEN")"
fi
validate_header_value "$admin_token"

base_url="${base_url%/}"

curl --fail-with-body --silent --show-error \
  --header "Authorization: Bearer ${admin_token}" \
  "${base_url}/v1/admin/audit"
