#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

usage() {
  cat <<'USAGE'
Usage:
  deploy/scripts/smoke-identity-auth.sh [options]

Options:
  --base URL                 Public identity base, for example http://82.165.77.104/api/identity.
  --steam-ticket-hex HEX     Steam Web API auth ticket as hexadecimal text.
  --github-token-file PATH   Use an existing GitHub access token from a file instead of Device Flow.
  --bootstrap-first-root     Allow first-root bootstrap. Requires VAPOR_IDENTITY_ADMIN_TOKEN.
  --admin-token-file PATH    Read server-local admin token from file.
  --no-wait                  Start GitHub Device Flow and print instructions, but do not poll.
  --poll-timeout SECONDS     Maximum Device Flow polling time. Default: 900.
  -h, --help                 Show this help.

Behavior:
  - Starts a 5-minute root-dashboard auth attempt.
  - Attaches Steam proof when --steam-ticket-hex is provided.
  - Attaches GitHub proof through Device Flow unless --github-token-file is used.
  - Finishes into a 5-minute dashboard session only when both proofs exist and the profile is root.
  - Does not print provider tokens or session cookies.
USAGE
}

base=""
steam_ticket_hex=""
github_token=""
github_token_set=false
bootstrap_first_root=false
admin_token="${VAPOR_IDENTITY_ADMIN_TOKEN:-}"
no_wait=false
poll_timeout=900

if [ -n "${VAPOR_PUBLIC_IDENTITY_BASE:-}" ]; then
  base="${VAPOR_PUBLIC_IDENTITY_BASE%/}"
elif [ -n "${VAPOR_PUBLIC_HTTP_BASE:-}" ]; then
  base="${VAPOR_PUBLIC_HTTP_BASE%/}/api/identity"
elif [ -n "${VAPOR_HTTP_FALLBACK_HOST}" ]; then
  base="http://${VAPOR_HTTP_FALLBACK_HOST}/api/identity"
fi

read_single_line_file() {
  local path="$1"
  if [ ! -r "$path" ]; then
    echo "error: cannot read ${path}" >&2
    exit 1
  fi
  sed -n '1p' "$path"
}

json_get() {
  local key="$1"
  python3 -c '
import json
import sys

key = sys.argv[1]
try:
    value = json.load(sys.stdin)
except json.JSONDecodeError:
    sys.exit(2)

for part in key.split("."):
    if isinstance(value, dict) and part in value:
        value = value[part]
    else:
        sys.exit(1)

if value is None:
    sys.exit(1)
if isinstance(value, bool):
    print("true" if value else "false")
else:
    print(value)
' "$key"
}

post_json() {
  local url="$1"
  local json="$2"
  local body_file="$3"
  shift 3
  curl \
    --silent \
    --show-error \
    --output "$body_file" \
    --write-out "%{http_code}" \
    -X POST \
    -H "content-type: application/json" \
    "$@" \
    -d "$json" \
    "$url"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --base)
      [ "$#" -ge 2 ] || { echo "error: missing value for $1" >&2; exit 1; }
      base="${2%/}"
      shift 2
      ;;
    --steam-ticket-hex)
      [ "$#" -ge 2 ] || { echo "error: missing value for $1" >&2; exit 1; }
      steam_ticket_hex="$2"
      shift 2
      ;;
    --github-token-file)
      [ "$#" -ge 2 ] || { echo "error: missing value for $1" >&2; exit 1; }
      github_token="$(read_single_line_file "$2")"
      github_token_set=true
      shift 2
      ;;
    --bootstrap-first-root)
      bootstrap_first_root=true
      shift
      ;;
    --admin-token-file)
      [ "$#" -ge 2 ] || { echo "error: missing value for $1" >&2; exit 1; }
      admin_token="$(read_single_line_file "$2")"
      shift 2
      ;;
    --no-wait)
      no_wait=true
      shift
      ;;
    --poll-timeout)
      [ "$#" -ge 2 ] || { echo "error: missing value for $1" >&2; exit 1; }
      poll_timeout="$2"
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

if [ -z "$base" ]; then
  echo "error: set --base, VAPOR_PUBLIC_IDENTITY_BASE, VAPOR_PUBLIC_HTTP_BASE, or VAPOR_HTTP_FALLBACK_HOST" >&2
  exit 1
fi

if ! command -v python3 >/dev/null; then
  echo "error: python3 is required for JSON parsing" >&2
  exit 1
fi

if [ "$bootstrap_first_root" = true ] && [ -z "$admin_token" ] && [ -r "${VAPOR_CONFIG_DIR}/identity.env" ]; then
  set -a
  # shellcheck disable=SC1090
  source "${VAPOR_CONFIG_DIR}/identity.env"
  set +a
  admin_token="${VAPOR_IDENTITY_ADMIN_TOKEN:-}"
fi

tmp_dir="$(mktemp -d /tmp/vapor-identity-auth-smoke.XXXXXX)"
trap 'rm -rf "$tmp_dir"' EXIT

status_file="${tmp_dir}/status.json"
curl --fail --silent --show-error "${base}/v1/auth/status" > "$status_file"
steam_ready="$(json_get steam_identity_ready < "$status_file" || true)"
github_ready="$(json_get github_identity_ready < "$status_file" || true)"
echo "identity-auth: steam_ready=${steam_ready} github_ready=${github_ready}"

attempt_file="${tmp_dir}/attempt.json"
attempt_code="$(post_json "${base}/v1/auth/session/start" '{}' "$attempt_file")"
if [ "$attempt_code" != "201" ]; then
  echo "error: auth attempt creation failed with HTTP ${attempt_code}" >&2
  sed -n '1,40p' "$attempt_file" >&2
  exit 1
fi
auth_attempt_id="$(json_get auth_attempt_id < "$attempt_file")"
expires_at="$(json_get expires_at_unix < "$attempt_file")"
echo "identity-auth: created attempt ${auth_attempt_id}, expires_at_unix=${expires_at}"

if [ -n "$steam_ticket_hex" ]; then
  steam_file="${tmp_dir}/steam.json"
  steam_code="$(post_json \
    "${base}/v1/auth/session/steam/ticket" \
    "{\"auth_attempt_id\":\"${auth_attempt_id}\",\"ticket_hex\":\"${steam_ticket_hex}\"}" \
    "$steam_file")"
  if [ "$steam_code" != "200" ]; then
    echo "error: Steam proof failed with HTTP ${steam_code}" >&2
    sed -n '1,40p' "$steam_file" >&2
    exit 1
  fi
  steam_id64="$(json_get steam_id64 < "$steam_file")"
  echo "identity-auth: attached Steam proof for steam_id64=${steam_id64}"
else
  echo "identity-auth: Steam proof skipped; provide --steam-ticket-hex from Steamworks/Vapor client"
fi

github_attached=false
if [ "$github_token_set" = true ]; then
  github_file="${tmp_dir}/github.json"
  github_code="$(post_json \
    "${base}/v1/auth/session/github/token" \
    "{\"auth_attempt_id\":\"${auth_attempt_id}\",\"access_token\":\"${github_token}\"}" \
    "$github_file")"
  if [ "$github_code" != "200" ]; then
    echo "error: GitHub token proof failed with HTTP ${github_code}" >&2
    sed -n '1,40p' "$github_file" >&2
    exit 1
  fi
  github_login="$(json_get github_login < "$github_file")"
  echo "identity-auth: attached GitHub proof for login=${github_login}"
  github_attached=true
else
  device_file="${tmp_dir}/github-device.json"
  device_code="$(post_json \
    "${base}/v1/auth/session/github/device/start" \
    "{\"auth_attempt_id\":\"${auth_attempt_id}\"}" \
    "$device_file")"
  if [ "$device_code" != "201" ]; then
    echo "error: GitHub Device Flow start failed with HTTP ${device_code}" >&2
    sed -n '1,40p' "$device_file" >&2
    exit 1
  fi
  verification_uri="$(json_get verification_uri < "$device_file")"
  verification_uri_complete="$(json_get verification_uri_complete < "$device_file" || true)"
  user_code="$(json_get user_code < "$device_file")"
  interval="$(json_get poll_interval_seconds < "$device_file")"
  echo "identity-auth: open ${verification_uri_complete:-$verification_uri}"
  echo "identity-auth: GitHub user code ${user_code}"

  if [ "$no_wait" = true ]; then
    echo "identity-auth: no-wait requested; rerun without --no-wait to poll and finish"
    exit 0
  fi

  deadline=$(( $(date +%s) + poll_timeout ))
  while [ "$(date +%s)" -lt "$deadline" ]; do
    sleep "$interval"
    poll_file="${tmp_dir}/github-poll.json"
    poll_code="$(post_json \
      "${base}/v1/auth/session/github/device/poll" \
      "{\"auth_attempt_id\":\"${auth_attempt_id}\"}" \
      "$poll_file")"
    poll_status="$(json_get status < "$poll_file" || true)"
    case "$poll_code:$poll_status" in
      200:authorized)
        github_login="$(json_get github_login < "$poll_file")"
        echo "identity-auth: attached GitHub proof for login=${github_login}"
        github_attached=true
        break
        ;;
      202:pending|425:pending)
        next_interval="$(json_get poll_interval_seconds < "$poll_file" || true)"
        if [ -n "$next_interval" ]; then
          interval="$next_interval"
        fi
        echo "identity-auth: waiting for GitHub authorization"
        ;;
      *)
        echo "error: GitHub Device Flow poll failed with HTTP ${poll_code}, status=${poll_status:-unknown}" >&2
        sed -n '1,40p' "$poll_file" >&2
        exit 1
        ;;
    esac
  done

  if [ "$github_attached" != true ]; then
    echo "error: GitHub Device Flow polling timed out" >&2
    exit 1
  fi
fi

if [ -z "$steam_ticket_hex" ]; then
  echo "identity-auth: not finishing; Steam proof is still missing"
  exit 0
fi

if [ "$github_attached" != true ]; then
  echo "identity-auth: not finishing; GitHub proof is still missing"
  exit 0
fi

finish_file="${tmp_dir}/finish.json"
finish_headers="${tmp_dir}/finish.headers"
auth_header=()
if [ "$bootstrap_first_root" = true ]; then
  if [ -z "$admin_token" ]; then
    echo "error: --bootstrap-first-root requires VAPOR_IDENTITY_ADMIN_TOKEN or --admin-token-file" >&2
    exit 1
  fi
  auth_header=(-H "authorization: Bearer ${admin_token}")
fi

finish_code="$(curl \
  --silent \
  --show-error \
  --dump-header "$finish_headers" \
  --output "$finish_file" \
  --write-out "%{http_code}" \
  -X POST \
  -H "content-type: application/json" \
  "${auth_header[@]}" \
  -d "{\"auth_attempt_id\":\"${auth_attempt_id}\",\"bootstrap_first_root\":${bootstrap_first_root}}" \
  "${base}/v1/auth/session/finish")"
if [ "$finish_code" != "200" ]; then
  echo "error: finish failed with HTTP ${finish_code}" >&2
  sed -n '1,80p' "$finish_file" >&2
  exit 1
fi

profile_id="$(json_get profile_id < "$finish_file")"
session_expires_at="$(json_get expires_at_unix < "$finish_file")"
echo "identity-auth: session issued for profile=${profile_id}, expires_at_unix=${session_expires_at}"

cookie="$(sed -n 's/^[Ss]et-[Cc]ookie: \([^;]*\).*/\1/p' "$finish_headers")"
if [ -n "$cookie" ]; then
  dashboard_code="$(curl \
    --silent \
    --show-error \
    --output /dev/null \
    --write-out "%{http_code}" \
    -H "cookie: ${cookie}" \
    "${base}/admin")"
  echo "identity-auth: dashboard_with_session_http=${dashboard_code}"
fi
