#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=http-contract-checks.sh
source "${SCRIPT_DIR}/http-contract-checks.sh"

curl --fail --silent --show-error http://127.0.0.1:7111/healthz >/dev/null

curl --fail --silent --show-error http://127.0.0.1:7112/healthz >/dev/null
curl --fail --silent --show-error http://127.0.0.1:7112/status >/dev/null

curl --fail --silent --show-error http://127.0.0.1:7113/healthz >/dev/null
curl --fail --silent --show-error http://127.0.0.1:7113/v1/auth/status >/dev/null

curl --fail --silent --show-error http://127.0.0.1:7114/healthz >/dev/null
curl --fail --silent --show-error http://127.0.0.1:7114/status >/dev/null

curl --fail --silent --show-error http://127.0.0.1:7115/healthz >/dev/null
curl --fail --silent --show-error \
  http://127.0.0.1:7115/v1/ecosystems/ghf-studios/vapor \
  >/dev/null

check_unauthenticated_http_contracts \
  --homepage-base http://127.0.0.1:7111 \
  --docs-base http://127.0.0.1:7112 \
  --identity-base http://127.0.0.1:7113 \
  --diagnostics-base http://127.0.0.1:7114

systemctl is-enabled --quiet vapor-state-export.timer
systemctl is-active --quiet vapor-state-export.timer

echo "health: all Vapor services responded locally"