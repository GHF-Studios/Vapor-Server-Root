#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

run_clippy=false
require_caddy=false

usage() {
  cat <<'USAGE'
Usage: deploy/scripts/local-qa.sh [--quick] [--clippy] [--caddy]

Runs repository-local checks that require no SSH, secrets, DNS, systemd, or VPS
mutation.

  --quick   syntax, rustfmt, and tests (default)
  --clippy  include cargo clippy for service crates
  --caddy   require local caddy validate against deploy/caddy/Caddyfile.example
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --quick)
      shift
      ;;
    --clippy)
      run_clippy=true
      shift
      ;;
    --caddy)
      require_caddy=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "local-qa: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

run_bash_syntax() {
  local script
  while IFS= read -r script; do
    bash -n "${script}"
  done < <(find "${REPO_ROOT}/deploy/scripts" -maxdepth 1 -type f -name '*.sh' | sort)
}

run_cargo_fmt() {
  local manifest
  for manifest in \
    "${REPO_ROOT}/Vapor-Homepage-Server/Cargo.toml" \
    "${REPO_ROOT}/Vapor-Docs-Server/Cargo.toml" \
    "${REPO_ROOT}/Vapor-Identity-Server/Cargo.toml" \
    "${REPO_ROOT}/Vapor-Diagnostics-Server/Cargo.toml"
  do
    cargo fmt --manifest-path "${manifest}" --check
  done
}

run_cargo_tests() {
  local manifest
  for manifest in \
    "${REPO_ROOT}/Vapor-Homepage-Server/Cargo.toml" \
    "${REPO_ROOT}/Vapor-Docs-Server/Cargo.toml" \
    "${REPO_ROOT}/Vapor-Identity-Server/Cargo.toml" \
    "${REPO_ROOT}/Vapor-Diagnostics-Server/Cargo.toml"
  do
    cargo test --manifest-path "${manifest}" --locked
  done
}

run_python_tests() {
  if [ -d "${REPO_ROOT}/deploy/tests" ]; then
    python3 -m unittest discover -s "${REPO_ROOT}/deploy/tests" -p 'test_*.py'
  fi
}

run_cargo_clippy() {
  local manifest
  for manifest in \
    "${REPO_ROOT}/Vapor-Homepage-Server/Cargo.toml" \
    "${REPO_ROOT}/Vapor-Docs-Server/Cargo.toml" \
    "${REPO_ROOT}/Vapor-Identity-Server/Cargo.toml" \
    "${REPO_ROOT}/Vapor-Diagnostics-Server/Cargo.toml"
  do
    cargo clippy --manifest-path "${manifest}" --locked --all-targets -- -D warnings
  done
}

run_caddy_validation() {
  if ! command -v caddy >/dev/null 2>&1; then
    if [ "${require_caddy}" = true ]; then
      echo "local-qa: caddy not found but --caddy was requested" >&2
      exit 1
    fi
    echo "local-qa: skipping optional caddy validation; caddy not found"
    return
  fi
  caddy validate --config "${REPO_ROOT}/deploy/caddy/Caddyfile.example"
}

run_bash_syntax
python3 -m py_compile "${REPO_ROOT}/deploy/scripts/state-bundle-validate.py"
run_python_tests
run_cargo_fmt
run_cargo_tests
if [ "${run_clippy}" = true ]; then
  run_cargo_clippy
fi
run_caddy_validation

echo "local-qa: checks passed"
