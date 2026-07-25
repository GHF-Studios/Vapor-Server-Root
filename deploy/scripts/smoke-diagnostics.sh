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

v1_payload="$(mktemp)"
v2_payload="$(mktemp)"
download_body="$(mktemp)"
trap 'rm -f "${v1_payload}" "${v2_payload}" "${download_body}"' EXIT

v2_password="v2-password-value-should-disappear"
v2_token="v2-token-value-should-disappear"
v2_github_token="ghp_abcdefghijklmnopqrstuvwxyz123456"
legacy_token="legacy-token-value-should-disappear"

cat > "${v2_payload}" <<EOF
{
  "schema_version": 2,
  "consent": true,
  "client_version": "diagnostics-smoke",
  "platform": {
    "os_family": "linux",
    "arch": "x86_64",
    "memory_mb_bucket": "unknown",
    "steam_deck": false
  },
  "artifacts": [
    {
      "name": "vapor.log",
      "content": "event = diagnostics v2 smoke test\npassword = \"${v2_password}\"\ntoken=${v2_token}\nAuthorization: Bearer ${v2_token}\ngithub = ${v2_github_token}\nmessage = pre-DNS diagnostics v2 upload path is alive"
    }
  ]
}
EOF

v2_response="$(curl --fail --silent --show-error \
  --request POST \
  --header "content-type: application/json" \
  --data-binary "@${v2_payload}" \
  http://127.0.0.1:7114/v2/reports)"

v2_run_id="$(printf '%s\n' "${v2_response}" | sed -n 's/.*"run_id":"\([^"]*\)".*/\1/p')"
if [ -z "${v2_run_id}" ]; then
  echo "error: failed to parse diagnostics v2 run id" >&2
  exit 1
fi

curl --fail --silent --show-error \
  --header "Authorization: Bearer ${VAPOR_DIAGNOSTICS_ADMIN_TOKEN}" \
  "http://127.0.0.1:7114/v1/runs/${v2_run_id}" \
  > "${download_body}"

grep --quiet '<redacted>' "${download_body}"
for sensitive in "${v2_password}" "${v2_token}" "${v2_github_token}"; do
  if grep --quiet --fixed-strings "${sensitive}" "${download_body}"; then
    echo "error: diagnostics v2 download retained sensitive value" >&2
    exit 1
  fi
done
grep --quiet 'schema_version = 2' "${download_body}"

cat > "${v1_payload}" <<EOF
event = "diagnostics smoke test"
password = "this should be redacted"
token = "${legacy_token}"
message = "pre-DNS diagnostics upload path is alive"
EOF

v1_response="$(curl --fail --silent --show-error \
  --request POST \
  --data-binary "@${v1_payload}" \
  http://127.0.0.1:7114/v1/runs)"

v1_run_id="$(printf '%s\n' "${v1_response}" | sed -n 's/^diagnostics: uploaded run //p' | tr -d '\r\n')"
if [ -z "${v1_run_id}" ]; then
  echo "error: failed to parse diagnostics run id" >&2
  exit 1
fi
if [ "${v1_run_id}" = "${v2_run_id}" ]; then
  echo "error: diagnostics uploads returned duplicate run ids" >&2
  exit 1
fi

curl --fail --silent --show-error \
  --header "Authorization: Bearer ${VAPOR_DIAGNOSTICS_ADMIN_TOKEN}" \
  "http://127.0.0.1:7114/v1/runs/${v1_run_id}" \
  > "${download_body}"

grep --quiet '<redacted>' "${download_body}"
if grep --quiet --fixed-strings "${legacy_token}" "${download_body}"; then
  echo "error: diagnostics v1 download retained sensitive value" >&2
  exit 1
fi

for path in /v1/runs /v1/export /v2/reports; do
  status="$(curl --silent --show-error --output /dev/null --write-out "%{http_code}" \
    "http://127.0.0.1:7114${path}")"
  if [ "${status}" != "401" ]; then
    echo "error: expected unauthenticated diagnostics ${path} to return 401, got ${status}" >&2
    exit 1
  fi
done

echo "diagnostics-smoke: uploaded v2 ${v2_run_id} and legacy v1 ${v1_run_id}; redaction verified"
