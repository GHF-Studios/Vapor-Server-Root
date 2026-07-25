#!/usr/bin/env bash
set -euo pipefail

expect_http_status() {
  local method="$1"
  local url="$2"
  local expected="$3"
  local body="${4:-}"

  local status
  if [ -n "${body}" ]; then
    status="$(curl --silent --show-error --output /dev/null --write-out "%{http_code}" \
      --request "${method}" \
      --header "content-type: application/json" \
      --data "${body}" \
      "${url}")"
  else
    status="$(curl --silent --show-error --output /dev/null --write-out "%{http_code}" \
      --request "${method}" \
      "${url}")"
  fi

  if [ "${status}" != "${expected}" ]; then
    echo "http-contract: expected ${method} ${url} -> ${expected}, got ${status}" >&2
    return 1
  fi
}

check_unauthenticated_http_contracts() {
  local homepage_base=""
  local docs_base=""
  local identity_base=""
  local diagnostics_base=""

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --homepage-base)
        homepage_base="${2%/}"
        shift 2
        ;;
      --docs-base)
        docs_base="${2%/}"
        shift 2
        ;;
      --identity-base)
        identity_base="${2%/}"
        shift 2
        ;;
      --diagnostics-base)
        diagnostics_base="${2%/}"
        shift 2
        ;;
      *)
        echo "http-contract: unknown argument: $1" >&2
        return 2
        ;;
    esac
  done

  if [ -n "${homepage_base}" ]; then
    expect_http_status GET "${homepage_base}/healthz" 200
  fi

  if [ -n "${docs_base}" ]; then
    expect_http_status GET "${docs_base}/healthz" 200
    expect_http_status GET "${docs_base}/v1/status" 200
    expect_http_status POST "${docs_base}/v1/current" 401 '<!doctype html><title>unauthorized</title>'
    expect_http_status GET "${docs_base}/v1/export" 401
  fi

  if [ -n "${identity_base}" ]; then
    expect_http_status GET "${identity_base}/healthz" 200
    expect_http_status GET "${identity_base}/v1/auth/status" 200
    expect_http_status GET "${identity_base}/v1/admin/audit" 401
    expect_http_status POST "${identity_base}/v1/admin/roles/grant" 401 '{"role":"root","steam_id64":"76561190000000000","github_login":"nobody"}'
    expect_http_status POST "${identity_base}/v1/admin/roles/revoke" 401 '{"role":"root","steam_id64":"76561190000000000","github_login":"nobody"}'
    expect_http_status POST "${identity_base}/v1/admin/root/grant" 404 '{"steam_id64":"76561190000000000","github_login":"nobody"}'
  fi

  if [ -n "${diagnostics_base}" ]; then
    expect_http_status GET "${diagnostics_base}/healthz" 200
    expect_http_status GET "${diagnostics_base}/v1/status" 200
    expect_http_status GET "${diagnostics_base}/v1/runs" 401
    expect_http_status GET "${diagnostics_base}/v1/export" 401
    expect_http_status GET "${diagnostics_base}/v2/reports" 401
  fi
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  check_unauthenticated_http_contracts "$@"
fi
