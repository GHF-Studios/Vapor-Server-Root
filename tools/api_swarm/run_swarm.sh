#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="${VAPOR_API_SWARM_VENV:-/tmp/vapor-api-swarm-venv}"

python3 -m venv "${VENV_DIR}"
"${VENV_DIR}/bin/python" -m pip install --upgrade pip
"${VENV_DIR}/bin/python" -m pip install -r "${SCRIPT_DIR}/requirements.txt"

exec "${VENV_DIR}/bin/python" "${SCRIPT_DIR}/vapor_api_swarm.py" "$@"
