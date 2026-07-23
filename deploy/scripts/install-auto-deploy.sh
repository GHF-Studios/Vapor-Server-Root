#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

require_root

if ! command -v flock >/dev/null 2>&1; then
  echo "error: flock is required for automatic deploy locking" >&2
  exit 1
fi

install -m 0644 "${DEPLOY_DIR}/systemd/vapor-deploy.service" /etc/systemd/system/vapor-deploy.service
install -m 0644 "${DEPLOY_DIR}/systemd/vapor-deploy.timer" /etc/systemd/system/vapor-deploy.timer

systemctl daemon-reload
systemctl enable --now vapor-deploy.timer

echo "auto-deploy: installed and enabled vapor-deploy.timer"
