#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

usage() {
  cat <<'USAGE'
Usage:
  deploy/scripts/revoke-identity-role.sh --role ROLE --steam-id64 ID --github-login LOGIN [options]

Identity arguments:
  --steam-id64 ID            Linked SteamID64 for the target developer/root.
  --github-login LOGIN       Linked GitHub login for the same target profile.

Options:
  --role root|content-developer
  --base URL                 Identity service base URL. Default:
                             http://127.0.0.1:7113
  --admin-token VALUE        Use an explicit admin token.
  --admin-token-file PATH    Read the admin token from the first line of PATH.
  -h, --help                 Show this help.

Notes:
  - If no admin token is provided, the script reads
    /etc/vapor-server/identity.env when readable.
  - The token is used only as an Authorization header and is never printed.
  - Role revocation uses the same external identity target model as grants:
    the SteamID64 and GitHub login must already be linked to the same profile.
  - The identity service refuses to revoke the last active root role.
USAGE
}

role=""
steam_id64=""
github_login=""
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

validate_role() {
  case "$1" in
    root|content-developer) ;;
    *)
      echo "error: --role must be root or content-developer" >&2
      exit 1
      ;;
  esac
}

validate_steam_id64() {
  if [ "${#1}" -ne 17 ] || [ -n "${1//[0123456789]/}" ]; then
    echo "error: invalid SteamID64" >&2
    exit 1
  fi
}

validate_github_login() {
  if [ -z "$1" ] || [ "${#1}" -gt 39 ]; then
    echo "error: invalid GitHub login" >&2
    exit 1
  fi
  if [ -n "${1//[abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-]/}" ]; then
    echo "error: invalid GitHub login" >&2
    exit 1
  fi
  case "$1" in
    -*|*-)
      echo "error: invalid GitHub login" >&2
      exit 1
      ;;
    *--*)
      echo "error: invalid GitHub login" >&2
      exit 1
      ;;
  esac
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
    --role)
      [ "$#" -ge 2 ] || { echo "error: missing value for $1" >&2; exit 1; }
      role="$2"
      shift 2
      ;;
    --steam-id64)
      [ "$#" -ge 2 ] || { echo "error: missing value for $1" >&2; exit 1; }
      steam_id64="$2"
      shift 2
      ;;
    --github-login)
      [ "$#" -ge 2 ] || { echo "error: missing value for $1" >&2; exit 1; }
      github_login="$2"
      shift 2
      ;;
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

if [ -z "$role" ]; then
  echo "error: --role is required" >&2
  exit 1
fi
if [ -z "$steam_id64" ]; then
  echo "error: --steam-id64 is required" >&2
  exit 1
fi
if [ -z "$github_login" ]; then
  echo "error: --github-login is required" >&2
  exit 1
fi

validate_role "$role"
validate_base_url "$base_url"
validate_steam_id64 "$steam_id64"
validate_github_login "$github_login"

if [ -n "$admin_token_file" ]; then
  admin_token="$(read_first_line "$admin_token_file")"
fi
if [ -z "$admin_token" ]; then
  admin_token="$(read_env_value "$identity_env" "VAPOR_IDENTITY_ADMIN_TOKEN")"
fi
validate_header_value "$admin_token"

base_url="${base_url%/}"
body="{\"role\":\"${role}\",\"steam_id64\":\"${steam_id64}\",\"github_login\":\"${github_login}\"}"

curl --fail-with-body --silent --show-error \
  --request POST \
  --header "Authorization: Bearer ${admin_token}" \
  --header "Content-Type: application/json" \
  --data "$body" \
  "${base_url}/v1/admin/roles/revoke"
printf '\n'
