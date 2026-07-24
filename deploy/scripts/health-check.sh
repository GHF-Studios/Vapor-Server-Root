#!/usr/bin/env bash
set -euo pipefail

curl --fail --silent --show-error http://127.0.0.1:7111/healthz >/dev/null
curl --fail --silent --show-error http://127.0.0.1:7112/healthz >/dev/null
curl --fail --silent --show-error http://127.0.0.1:7112/v1/status >/dev/null
curl --fail --silent --show-error http://127.0.0.1:7113/healthz >/dev/null
curl --fail --silent --show-error http://127.0.0.1:7113/v1/auth/status >/dev/null
identity_audit_status="$(
  curl --silent --show-error --output /dev/null --write-out "%{http_code}" \
    http://127.0.0.1:7113/v1/admin/audit
)"
if [ "${identity_audit_status}" != "401" ]; then
  echo "health: expected unauthenticated identity audit to return 401, got ${identity_audit_status}" >&2
  exit 1
fi
identity_revoke_status="$(
  curl --silent --show-error --output /dev/null --write-out "%{http_code}" \
    --request POST \
    --header "content-type: application/json" \
    --data '{"role":"root","steam_id64":"76561190000000000","github_login":"nobody"}' \
    http://127.0.0.1:7113/v1/admin/roles/revoke
)"
if [ "${identity_revoke_status}" != "401" ]; then
  echo "health: expected unauthenticated identity role revoke to return 401, got ${identity_revoke_status}" >&2
  exit 1
fi
curl --fail --silent --show-error http://127.0.0.1:7114/healthz >/dev/null
curl --fail --silent --show-error http://127.0.0.1:7114/v1/status >/dev/null

echo "health: all Vapor services responded locally"
