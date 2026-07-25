#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

if [ ! -r "${VAPOR_CONFIG_DIR}/docs.env" ]; then
  echo "error: missing ${VAPOR_CONFIG_DIR}/docs.env" >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "${VAPOR_CONFIG_DIR}/docs.env"
set +a

html="$(mktemp)"
response="$(mktemp)"
served="$(mktemp)"
status_body="$(mktemp)"
trap 'rm -f "${html}" "${response}" "${served}" "${status_body}"' EXIT

cat > "${html}" <<'EOF'
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <title>Vapor Docs</title>
  </head>
  <body>
    <h1>Vapor Docs</h1>
    <p>Docs upload smoke test succeeded. Replace this with generated docs.</p>
  </body>
</html>
EOF

curl --fail --silent --show-error \
  --request POST \
  --header "Authorization: Bearer ${VAPOR_DOCS_ADMIN_TOKEN}" \
  --data-binary "@${html}" \
  http://127.0.0.1:7112/v1/current \
  > "${response}"

release_id="$(sed -n 's/^release_id = "\([^"]*\)"/\1/p' "${response}")"
if [ -z "${release_id}" ]; then
  echo "error: failed to parse docs release id" >&2
  exit 1
fi

curl --fail --silent --show-error http://127.0.0.1:7112/v1/status > "${status_body}"
grep --quiet 'current_index_ready = true' "${status_body}"
grep --quiet "current_release_id = \"${release_id}\"" "${status_body}"

curl --fail --silent --show-error http://127.0.0.1:7112/ > "${served}"
grep --quiet 'Docs upload smoke test succeeded' "${served}"

unauth_status="$(curl --silent --show-error --output /dev/null --write-out "%{http_code}" \
  --request POST \
  --data-binary "@${html}" \
  http://127.0.0.1:7112/v1/current)"
if [ "${unauth_status}" != "401" ]; then
  echo "error: expected unauthenticated docs upload to return 401, got ${unauth_status}" >&2
  exit 1
fi

echo "docs-smoke: uploaded and promoted release ${release_id}"
