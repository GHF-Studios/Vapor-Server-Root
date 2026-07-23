#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

require_root

install -m 0644 "${DEPLOY_DIR}/systemd/vapor-homepage.service" /etc/systemd/system/vapor-homepage.service
install -m 0644 "${DEPLOY_DIR}/systemd/vapor-docs.service" /etc/systemd/system/vapor-docs.service
install -m 0644 "${DEPLOY_DIR}/systemd/vapor-identity.service" /etc/systemd/system/vapor-identity.service
install -m 0644 "${DEPLOY_DIR}/systemd/vapor-diagnostics.service" /etc/systemd/system/vapor-diagnostics.service

systemctl daemon-reload
systemctl enable vapor-homepage.service
systemctl enable vapor-docs.service
systemctl enable vapor-identity.service
systemctl enable vapor-diagnostics.service

echo "systemd: installed and enabled Vapor service units"
