#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

if [ ! -r "${VAPOR_CONFIG_DIR}/diagnostics.env" ]; then
  echo "error: missing ${VAPOR_CONFIG_DIR}/diagnostics.env" >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "${VAPOR_CONFIG_DIR}/diagnostics.env"
set +a

payload="$(mktemp)"
trap 'rm -f "${payload}"' EXIT

cat > "${payload}" <<'EOF'
event = "diagnostics smoke test"
password = "this should be redacted"
token = "this should also be redacted"
message = "pre-DNS diagnostics upload path is alive"
EOF

upload_response="$(curl --fail --silent --show-error \
  --request POST \
  --data-binary "@${payload}" \
  http://127.0.0.1:7114/v1/runs)"

run_id="$(printf '%s\n' "${upload_response}" | sed -n 's/^diagnostics: uploaded run //p' | tr -d '\r\n')"
if [ -z "${run_id}" ]; then
  echo "error: failed to parse diagnostics run id" >&2
  exit 1
fi

curl --fail --silent --show-error \
  --header "Authorization: Bearer ${VAPOR_DIAGNOSTICS_ADMIN_TOKEN}" \
  "http://127.0.0.1:7114/v1/runs/${run_id}" \
  | grep --quiet '<redacted>'

echo "diagnostics-smoke: uploaded and verified redacted run ${run_id}"
