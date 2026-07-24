#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

if [ -n "${VAPOR_PUBLIC_HTTP_BASE:-}" ]; then
  base="${VAPOR_PUBLIC_HTTP_BASE%/}"
elif [ -n "${VAPOR_HTTP_FALLBACK_HOST}" ]; then
  base="http://${VAPOR_HTTP_FALLBACK_HOST}"
else
  echo "error: set VAPOR_PUBLIC_HTTP_BASE or VAPOR_HTTP_FALLBACK_HOST" >&2
  exit 1
fi

curl --fail --silent --show-error "${base}/healthz" >/dev/null
curl --fail --silent --show-error "${base}/docs/healthz" >/dev/null
curl --fail --silent --show-error "${base}/docs/v1/status" >/dev/null
curl --fail --silent --show-error "${base}/api/identity/healthz" >/dev/null
curl --fail --silent --show-error "${base}/api/identity/v1/auth/status" >/dev/null
identity_audit_status="$(
  curl --silent --show-error --output /dev/null --write-out "%{http_code}" \
    "${base}/api/identity/v1/admin/audit"
)"
if [ "${identity_audit_status}" != "401" ]; then
  echo "public-http: expected unauthenticated identity audit to return 401, got ${identity_audit_status}" >&2
  exit 1
fi
identity_revoke_status="$(
  curl --silent --show-error --output /dev/null --write-out "%{http_code}" \
    --request POST \
    --header "content-type: application/json" \
    --data '{"role":"root","steam_id64":"76561190000000000","github_login":"nobody"}' \
    "${base}/api/identity/v1/admin/roles/revoke"
)"
if [ "${identity_revoke_status}" != "401" ]; then
  echo "public-http: expected unauthenticated identity role revoke to return 401, got ${identity_revoke_status}" >&2
  exit 1
fi
curl --fail --silent --show-error "${base}/api/diagnostics/healthz" >/dev/null
curl --fail --silent --show-error "${base}/api/diagnostics/v1/status" >/dev/null
curl --fail --silent --show-error "${base}/login" >/dev/null
curl --fail --silent --show-error "${base}/admin" >/dev/null

echo "public-http: health/status checks passed for ${base}"
