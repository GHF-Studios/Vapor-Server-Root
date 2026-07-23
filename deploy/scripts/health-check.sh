#!/usr/bin/env bash
set -euo pipefail

curl --fail --silent --show-error http://127.0.0.1:7111/healthz >/dev/null
curl --fail --silent --show-error http://127.0.0.1:7112/healthz >/dev/null
curl --fail --silent --show-error http://127.0.0.1:7113/healthz >/dev/null
curl --fail --silent --show-error http://127.0.0.1:7114/healthz >/dev/null

echo "health: all Vapor services responded locally"
