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
curl --fail --silent --show-error "${base}/api/identity/healthz" >/dev/null
curl --fail --silent --show-error "${base}/api/diagnostics/healthz" >/dev/null
curl --fail --silent --show-error "${base}/login" >/dev/null
curl --fail --silent --show-error "${base}/admin" >/dev/null

echo "public-http: health checks passed for ${base}"
