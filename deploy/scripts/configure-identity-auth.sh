#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

usage() {
  cat <<'USAGE'
Usage:
  sudo deploy/scripts/configure-identity-auth.sh [options]

Options:
  --steam-web-api-key VALUE       Set Steam publisher Web API key.
  --steam-web-api-key-file PATH   Read Steam publisher Web API key from file.
  --prompt-steam-web-api-key      Prompt for Steam publisher Web API key.
  --github-client-id VALUE        Set GitHub OAuth/GitHub App client ID.
  --github-client-id-file PATH    Read GitHub client ID from file.
  --cookie-secure true|false      Set whether dashboard cookies use Secure.
  --cookie-path PATH              Set dashboard cookie path. Default: /api/identity.
  --restart                       Restart vapor-identity.service after changes.
  --status                        Print local identity auth readiness after changes.
  -h, --help                      Show this help.

Notes:
  - This script edits /etc/vapor-server/identity.env by default.
  - It does not print secret values.
  - For pre-DNS HTTP-by-IP testing, use --cookie-secure false.
  - After HTTPS is live, use --cookie-secure true.
USAGE
}

identity_env="${VAPOR_CONFIG_DIR}/identity.env"
steam_web_api_key=""
steam_web_api_key_set=false
github_client_id=""
github_client_id_set=false
cookie_secure=""
cookie_secure_set=false
cookie_path=""
cookie_path_set=false
restart_service=false
show_status=false

read_single_line_file() {
  local path="$1"
  if [ ! -r "$path" ]; then
    echo "error: cannot read ${path}" >&2
    exit 1
  fi
  local value
  value="$(sed -n '1p' "$path")"
  printf '%s' "$value"
}

validate_env_value() {
  local name="$1"
  local value="$2"
  if [ -z "$value" ]; then
    echo "error: ${name} must not be empty" >&2
    exit 1
  fi
  case "$value" in
    *$'\n'*|*$'\r'*)
      echo "error: ${name} must be a single-line value" >&2
      exit 1
      ;;
    *[[:space:]]*)
      echo "error: ${name} must not contain whitespace" >&2
      exit 1
      ;;
  esac
}

validate_cookie_secure() {
  case "$1" in
    true|false) ;;
    *)
      echo "error: --cookie-secure must be true or false" >&2
      exit 1
      ;;
  esac
}

validate_cookie_path() {
  local value="$1"
  if [ -z "$value" ] || [ "${value#/}" = "$value" ]; then
    echo "error: --cookie-path must start with /" >&2
    exit 1
  fi
  case "$value" in
    *";"*|*$'\n'*|*$'\r'*)
      echo "error: --cookie-path must not contain semicolons or newlines" >&2
      exit 1
      ;;
  esac
}

set_env_var() {
  local key="$1"
  local value="$2"
  local tmp

  tmp="$(mktemp /tmp/vapor-identity-env.XXXXXX)"
  chmod 0640 "$tmp"

  local found=false
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      "${key}="*)
        if [ "$found" = false ]; then
          printf '%s=%s\n' "$key" "$value" >> "$tmp"
          found=true
        fi
        ;;
      *)
        printf '%s\n' "$line" >> "$tmp"
        ;;
    esac
  done < "$identity_env"

  if [ "$found" = false ]; then
    printf '%s=%s\n' "$key" "$value" >> "$tmp"
  fi

  chown "root:${VAPOR_GROUP}" "$tmp"
  chmod 0640 "$tmp"
  mv "$tmp" "$identity_env"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --steam-web-api-key)
      [ "$#" -ge 2 ] || { echo "error: missing value for $1" >&2; exit 1; }
      steam_web_api_key="$2"
      steam_web_api_key_set=true
      shift 2
      ;;
    --steam-web-api-key-file)
      [ "$#" -ge 2 ] || { echo "error: missing value for $1" >&2; exit 1; }
      steam_web_api_key="$(read_single_line_file "$2")"
      steam_web_api_key_set=true
      shift 2
      ;;
    --prompt-steam-web-api-key)
      printf 'Steam publisher Web API key: ' >&2
      IFS= read -r -s steam_web_api_key
      printf '\n' >&2
      steam_web_api_key_set=true
      shift
      ;;
    --github-client-id)
      [ "$#" -ge 2 ] || { echo "error: missing value for $1" >&2; exit 1; }
      github_client_id="$2"
      github_client_id_set=true
      shift 2
      ;;
    --github-client-id-file)
      [ "$#" -ge 2 ] || { echo "error: missing value for $1" >&2; exit 1; }
      github_client_id="$(read_single_line_file "$2")"
      github_client_id_set=true
      shift 2
      ;;
    --cookie-secure)
      [ "$#" -ge 2 ] || { echo "error: missing value for $1" >&2; exit 1; }
      cookie_secure="$2"
      cookie_secure_set=true
      shift 2
      ;;
    --cookie-path)
      [ "$#" -ge 2 ] || { echo "error: missing value for $1" >&2; exit 1; }
      cookie_path="$2"
      cookie_path_set=true
      shift 2
      ;;
    --restart)
      restart_service=true
      shift
      ;;
    --status)
      show_status=true
      shift
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

require_root

if [ ! -f "$identity_env" ]; then
  echo "error: identity env file does not exist: ${identity_env}" >&2
  exit 1
fi

if [ "$steam_web_api_key_set" = true ]; then
  validate_env_value "Steam Web API key" "$steam_web_api_key"
  set_env_var "VAPOR_IDENTITY_STEAM_WEB_API_KEY" "$steam_web_api_key"
  echo "identity-auth: set VAPOR_IDENTITY_STEAM_WEB_API_KEY=<redacted>"
fi

if [ "$github_client_id_set" = true ]; then
  validate_env_value "GitHub client ID" "$github_client_id"
  set_env_var "VAPOR_IDENTITY_GITHUB_CLIENT_ID" "$github_client_id"
  echo "identity-auth: set VAPOR_IDENTITY_GITHUB_CLIENT_ID=${github_client_id}"
fi

if [ "$cookie_secure_set" = true ]; then
  validate_cookie_secure "$cookie_secure"
  set_env_var "VAPOR_IDENTITY_COOKIE_SECURE" "$cookie_secure"
  echo "identity-auth: set VAPOR_IDENTITY_COOKIE_SECURE=${cookie_secure}"
fi

if [ "$cookie_path_set" = true ]; then
  validate_cookie_path "$cookie_path"
  set_env_var "VAPOR_IDENTITY_COOKIE_PATH" "$cookie_path"
  echo "identity-auth: set VAPOR_IDENTITY_COOKIE_PATH=${cookie_path}"
fi

chown "root:${VAPOR_GROUP}" "$identity_env"
chmod 0640 "$identity_env"

if [ "$restart_service" = true ]; then
  systemctl restart vapor-identity.service
  echo "identity-auth: restarted vapor-identity.service"
fi

if [ "$show_status" = true ]; then
  curl --fail --silent --show-error http://127.0.0.1:7113/v1/auth/status
  printf '\n'
fi
