#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

usage() {
  cat >&2 <<'USAGE'
usage: install-github-actions-deploy-user.sh --public-key-file PATH [--user USER]

Creates a restricted VPS user for GitHub Actions deployment triggers. The user
can run only:

  sudo -n /usr/bin/systemctl start vapor-deploy.service
  sudo -n /usr/bin/systemctl status --no-pager vapor-deploy.service

The private key must be stored outside this repository, for example as the
GitHub Actions secret VAPOR_DEPLOY_SSH_KEY.
USAGE
}

DEPLOY_USER="vapor-gh-actions"
PUBLIC_KEY_FILE=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --public-key-file)
      if [ "$#" -lt 2 ]; then
        usage
        exit 2
      fi
      PUBLIC_KEY_FILE="$2"
      shift 2
      ;;
    --user)
      if [ "$#" -lt 2 ]; then
        usage
        exit 2
      fi
      DEPLOY_USER="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage
      exit 2
      ;;
  esac
done

if [ -z "${PUBLIC_KEY_FILE}" ]; then
  usage
  exit 2
fi

require_root

if [ ! -r "${PUBLIC_KEY_FILE}" ]; then
  echo "error: public key file does not exist or is not readable: ${PUBLIC_KEY_FILE}" >&2
  exit 1
fi

PUBLIC_KEY="$(sed -n '1p' "${PUBLIC_KEY_FILE}")"
case "${PUBLIC_KEY}" in
  ssh-ed25519\ *|ssh-rsa\ *|ecdsa-sha2-nistp256\ *|ecdsa-sha2-nistp384\ *|ecdsa-sha2-nistp521\ *)
    ;;
  *)
    echo "error: public key file does not contain a supported SSH public key" >&2
    exit 1
    ;;
esac

if ! id -u "${DEPLOY_USER}" >/dev/null 2>&1; then
  useradd \
    --system \
    --create-home \
    --home-dir "/var/lib/${DEPLOY_USER}" \
    --shell /bin/bash \
    "${DEPLOY_USER}"
fi

USER_HOME="$(getent passwd "${DEPLOY_USER}" | cut -d: -f6)"
install -d -o "${DEPLOY_USER}" -g "${DEPLOY_USER}" -m 0700 "${USER_HOME}/.ssh"
printf '%s\n' "${PUBLIC_KEY}" > "${USER_HOME}/.ssh/authorized_keys"
chown "${DEPLOY_USER}:${DEPLOY_USER}" "${USER_HOME}/.ssh/authorized_keys"
chmod 0600 "${USER_HOME}/.ssh/authorized_keys"

cat > /etc/sudoers.d/vapor-github-actions-deploy <<EOF
${DEPLOY_USER} ALL=(root) NOPASSWD: /usr/bin/systemctl start vapor-deploy.service
${DEPLOY_USER} ALL=(root) NOPASSWD: /usr/bin/systemctl status --no-pager vapor-deploy.service
EOF
chmod 0440 /etc/sudoers.d/vapor-github-actions-deploy
visudo -cf /etc/sudoers.d/vapor-github-actions-deploy >/dev/null

echo "github-actions-deploy-user: installed ${DEPLOY_USER}"
