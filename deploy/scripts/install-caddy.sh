#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

require_root

if ! command -v caddy >/dev/null 2>&1; then
  echo "error: caddy is not installed; run bootstrap-ubuntu.sh first" >&2
  exit 1
fi

sed "s/{{VAPOR_DOMAIN}}/${VAPOR_DOMAIN}/g" \
  "${DEPLOY_DIR}/caddy/Caddyfile.template" > /etc/caddy/Caddyfile

caddy fmt --overwrite /etc/caddy/Caddyfile
caddy validate --config /etc/caddy/Caddyfile
systemctl enable caddy.service

echo "caddy: installed config for ${VAPOR_DOMAIN}"
