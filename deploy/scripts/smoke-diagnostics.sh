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
download_body="$(mktemp)"
trap 'rm -f "${payload}" "${download_body}"' EXIT

password_value="diagnostics-password-value-should-disappear"
token_value="diagnostics-token-value-should-disappear"
github_token="ghp_abcdefghijklmnopqrstuvwxyz123456"

cat > "${payload}" <<EOF
{
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
      "content": "event = diagnostics smoke test\npassword = \"${password_value}\"\ntoken=${token_value}\nAuthorization: Bearer ${token_value}\ngithub = ${github_token}\nmessage = diagnostics upload path is alive"
    }
  ]
}
EOF

upload_response="$(curl --fail --silent --show-error \
  --request POST \
  --header "content-type: application/json" \
  --data-binary "@${payload}" \
  http://127.0.0.1:7114/reports)"

run_id="$(printf '%s\n' "${upload_response}" | sed -n 's/.*"run_id":"\([^"]*\)".*/\1/p')"
if [ -z "${run_id}" ]; then
  echo "error: failed to parse diagnostics run id" >&2
  exit 1
fi

curl --fail --silent --show-error \
  --header "Authorization: Bearer ${VAPOR_DIAGNOSTICS_ADMIN_TOKEN}" \
  "http://127.0.0.1:7114/reports/${run_id}" \
  > "${download_body}"

grep --quiet '<redacted>' "${download_body}"
for sensitive in "${password_value}" "${token_value}" "${github_token}"; do
  if grep --quiet --fixed-strings "${sensitive}" "${download_body}"; then
    echo "error: diagnostics download retained sensitive value" >&2
    exit 1
  fi
done

for path in /reports /export; do
  status="$(curl --silent --show-error --output /dev/null --write-out "%{http_code}" \
    "http://127.0.0.1:7114${path}")"
  if [ "${status}" != "401" ]; then
    echo "error: expected unauthenticated diagnostics ${path} to return 401, got ${status}" >&2
    exit 1
  fi
done

echo "diagnostics-smoke: uploaded ${run_id}; redaction verified"
