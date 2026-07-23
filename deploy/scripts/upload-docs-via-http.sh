#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: upload-docs-via-http.sh --bundle PATH --base-url URL [--token-env NAME] [--token-file PATH]

Uploads a docs tar.gz bundle to a public Vapor docs route, for example:

  http://82.165.77.104/docs

The script posts to BASE_URL/v1/current.tar.gz. The docs admin token is read
from an environment variable by default; do not pass it on the command line.
USAGE
}

BUNDLE=""
BASE_URL=""
TOKEN_ENV="VAPOR_DOCS_ADMIN_TOKEN"
TOKEN_FILE=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --bundle)
      if [ "$#" -lt 2 ]; then
        usage
        exit 2
      fi
      BUNDLE="$2"
      shift 2
      ;;
    --base-url)
      if [ "$#" -lt 2 ]; then
        usage
        exit 2
      fi
      BASE_URL="${2%/}"
      shift 2
      ;;
    --token-env)
      if [ "$#" -lt 2 ]; then
        usage
        exit 2
      fi
      TOKEN_ENV="$2"
      shift 2
      ;;
    --token-file)
      if [ "$#" -lt 2 ]; then
        usage
        exit 2
      fi
      TOKEN_FILE="$2"
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

if [ -z "${BUNDLE}" ] || [ -z "${BASE_URL}" ]; then
  usage
  exit 2
fi

if [ ! -f "${BUNDLE}" ]; then
  echo "error: bundle does not exist: ${BUNDLE}" >&2
  exit 1
fi

if [ -n "${TOKEN_FILE}" ]; then
  if [ ! -r "${TOKEN_FILE}" ]; then
    echo "error: token file does not exist or is not readable: ${TOKEN_FILE}" >&2
    exit 1
  fi
  IFS= read -r TOKEN < "${TOKEN_FILE}"
else
  TOKEN="${!TOKEN_ENV:-}"
fi

if [ -z "${TOKEN}" ]; then
  echo "error: docs admin token is empty; set ${TOKEN_ENV} or pass --token-file" >&2
  exit 1
fi

curl -fsS \
  -X POST \
  -H "Authorization: Bearer ${TOKEN}" \
  --data-binary "@${BUNDLE}" \
  "${BASE_URL}/v1/current.tar.gz"
