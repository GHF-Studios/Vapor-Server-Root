#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

require_root

if [ ! -r /etc/os-release ]; then
  echo "error: /etc/os-release is missing; expected Ubuntu" >&2
  exit 1
fi

# shellcheck disable=SC1091
source /etc/os-release
if [ "${ID:-}" != "ubuntu" ]; then
  echo "error: expected Ubuntu, got ${PRETTY_NAME:-unknown OS}" >&2
  exit 1
fi

if [ "${VERSION_ID:-}" != "26.04" ]; then
  echo "warning: expected Ubuntu 26.04, got ${PRETTY_NAME:-unknown Ubuntu}" >&2
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y \
  build-essential \
  ca-certificates \
  cargo \
  caddy \
  curl \
  git \
  libsqlite3-dev \
  openssl \
  pkg-config \
  rustc

if ! getent group "${VAPOR_GROUP}" >/dev/null; then
  groupadd --system "${VAPOR_GROUP}"
fi

if ! id -u "${VAPOR_USER}" >/dev/null 2>&1; then
  useradd \
    --system \
    --gid "${VAPOR_GROUP}" \
    --home-dir "${VAPOR_STATE_ROOT}" \
    --shell /usr/sbin/nologin \
    "${VAPOR_USER}"
fi

install_dir root root 0755 /opt
install_dir root root 0755 "${VAPOR_DEPLOY_ROOT}"
install_dir "${VAPOR_USER}" "${VAPOR_GROUP}" 0750 "${VAPOR_STATE_ROOT}"
install_dir "${VAPOR_USER}" "${VAPOR_GROUP}" 0750 "${VAPOR_STATE_ROOT}/homepage"
install_dir "${VAPOR_USER}" "${VAPOR_GROUP}" 0750 "${VAPOR_STATE_ROOT}/docs"
install_dir "${VAPOR_USER}" "${VAPOR_GROUP}" 0750 "${VAPOR_STATE_ROOT}/identity"
install_dir "${VAPOR_USER}" "${VAPOR_GROUP}" 0750 "${VAPOR_STATE_ROOT}/diagnostics"
install_dir root "${VAPOR_GROUP}" 0750 "${VAPOR_CONFIG_DIR}"

chown -R "${VAPOR_USER}:${VAPOR_GROUP}" "${VAPOR_STATE_ROOT}"
find "${VAPOR_STATE_ROOT}" -type d -exec chmod 0750 {} +
find "${VAPOR_STATE_ROOT}" -type f -exec chmod 0640 {} +

install_secret_env "${VAPOR_CONFIG_DIR}/homepage.env" \
"VAPOR_HOMEPAGE_BIND=127.0.0.1:7111"

install_secret_env "${VAPOR_CONFIG_DIR}/docs.env" \
"VAPOR_DOCS_BIND=127.0.0.1:7112
VAPOR_DOCS_STATE=${VAPOR_STATE_ROOT}/docs
VAPOR_DOCS_ADMIN_TOKEN=$(random_token)"

install_secret_env "${VAPOR_CONFIG_DIR}/identity.env" \
"VAPOR_IDENTITY_BIND=127.0.0.1:7113
VAPOR_IDENTITY_STATE=${VAPOR_STATE_ROOT}/identity
VAPOR_IDENTITY_DB=${VAPOR_STATE_ROOT}/identity/identity.sqlite3
VAPOR_IDENTITY_ADMIN_TOKEN=$(random_token)"

install_secret_env "${VAPOR_CONFIG_DIR}/diagnostics.env" \
"VAPOR_DIAGNOSTICS_BIND=127.0.0.1:7114
VAPOR_DIAGNOSTICS_STATE=${VAPOR_STATE_ROOT}/diagnostics
VAPOR_DIAGNOSTICS_ADMIN_TOKEN=$(random_token)"

echo "bootstrap: completed for ${PRETTY_NAME}"
echo "bootstrap: deploy root ${VAPOR_DEPLOY_ROOT}"
echo "bootstrap: state root ${VAPOR_STATE_ROOT}"
echo "bootstrap: config dir ${VAPOR_CONFIG_DIR}"
