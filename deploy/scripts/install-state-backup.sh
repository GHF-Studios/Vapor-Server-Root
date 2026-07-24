#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

require_root

install -m 0644 "${DEPLOY_DIR}/systemd/vapor-state-export.service" /etc/systemd/system/vapor-state-export.service
install -m 0644 "${DEPLOY_DIR}/systemd/vapor-state-export.timer" /etc/systemd/system/vapor-state-export.timer

systemctl daemon-reload
systemctl enable --now vapor-state-export.timer

echo "state-backup: installed and enabled vapor-state-export.timer"
