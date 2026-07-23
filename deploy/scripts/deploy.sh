#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

require_root

install -d -o root -g root -m 0755 "${VAPOR_DEPLOY_ROOT}"

if [ ! -d "${VAPOR_DEPLOY_ROOT}/.git" ]; then
  if [ -n "$(find "${VAPOR_DEPLOY_ROOT}" -mindepth 1 -maxdepth 1 -print -quit)" ]; then
    echo "error: ${VAPOR_DEPLOY_ROOT} is not empty and is not a git checkout" >&2
    exit 1
  fi
  git clone --recurse-submodules --branch "${VAPOR_BRANCH}" "${VAPOR_REPO_URL}" "${VAPOR_DEPLOY_ROOT}"
else
  git -C "${VAPOR_DEPLOY_ROOT}" fetch origin "${VAPOR_BRANCH}"
  git -C "${VAPOR_DEPLOY_ROOT}" checkout "${VAPOR_BRANCH}"
  git -C "${VAPOR_DEPLOY_ROOT}" reset --hard "origin/${VAPOR_BRANCH}"
  git -C "${VAPOR_DEPLOY_ROOT}" submodule sync --recursive
  git -C "${VAPOR_DEPLOY_ROOT}" submodule update --init --recursive
fi

cargo build --release --locked \
  --manifest-path "${VAPOR_DEPLOY_ROOT}/Vapor-Homepage-Server/Cargo.toml" \
  --target-dir "${VAPOR_DEPLOY_ROOT}/target"
cargo build --release --locked \
  --manifest-path "${VAPOR_DEPLOY_ROOT}/Vapor-Docs-Server/Cargo.toml" \
  --target-dir "${VAPOR_DEPLOY_ROOT}/target"
cargo build --release --locked \
  --manifest-path "${VAPOR_DEPLOY_ROOT}/Vapor-Identity-Server/Cargo.toml" \
  --target-dir "${VAPOR_DEPLOY_ROOT}/target"
cargo build --release --locked \
  --manifest-path "${VAPOR_DEPLOY_ROOT}/Vapor-Diagnostics-Server/Cargo.toml" \
  --target-dir "${VAPOR_DEPLOY_ROOT}/target"

"${VAPOR_DEPLOY_ROOT}/deploy/scripts/install-systemd.sh"
"${VAPOR_DEPLOY_ROOT}/deploy/scripts/install-caddy.sh"

systemctl restart vapor-homepage.service
systemctl restart vapor-docs.service
systemctl restart vapor-identity.service
systemctl restart vapor-diagnostics.service
systemctl restart caddy.service

"${VAPOR_DEPLOY_ROOT}/deploy/scripts/health-check.sh"

echo "deploy: completed ${VAPOR_REPO_URL}@${VAPOR_BRANCH}"
