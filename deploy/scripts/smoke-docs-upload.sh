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
trap 'rm -f "${html}"' EXIT

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
  http://127.0.0.1:7112/v1/current

curl --fail --silent --show-error http://127.0.0.1:7112/ >/dev/null

echo "docs-smoke: uploaded current docs placeholder"
