#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage:
  upload-docs-via-http.sh --bundle PATH --base-url URL [--token-env NAME] [--token-file PATH]
  upload-docs-via-http.sh --promote-release RELEASE_ID --base-url URL [--token-env NAME] [--token-file PATH]

Uploads a docs tar.gz bundle to a public Vapor docs route, for example:

  http://82.165.77.104/docs

The script posts to BASE_URL/v1/current.tar.gz. The docs admin token is read
from an environment variable by default; do not pass it on the command line.

With --promote-release, the script promotes an existing release through
BASE_URL/v1/releases/RELEASE_ID/promote. Promotion can be used for rollback.
USAGE
}

BUNDLE=""
BASE_URL=""
TOKEN_ENV="VAPOR_DOCS_ADMIN_TOKEN"
TOKEN_FILE=""
PROMOTE_RELEASE=""

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
    --promote-release)
      if [ "$#" -lt 2 ]; then
        usage
        exit 2
      fi
      PROMOTE_RELEASE="$2"
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

if [ -z "${BASE_URL}" ]; then
  usage
  exit 2
fi

if [ -z "${BUNDLE}" ] && [ -z "${PROMOTE_RELEASE}" ]; then
  usage
  exit 2
fi

if [ -n "${BUNDLE}" ] && [ -n "${PROMOTE_RELEASE}" ]; then
  echo "error: use either --bundle or --promote-release, not both" >&2
  exit 2
fi

if [ -n "${BUNDLE}" ] && [ ! -f "${BUNDLE}" ]; then
  echo "error: bundle does not exist: ${BUNDLE}" >&2
  exit 1
fi

if [ -n "${PROMOTE_RELEASE}" ]; then
  if [[ ! "${PROMOTE_RELEASE}" =~ ^([A-Za-z0-9]|[A-Za-z0-9][A-Za-z0-9._-]{0,94}[A-Za-z0-9])$ ]]; then
    echo "error: invalid release id: ${PROMOTE_RELEASE}" >&2
    exit 2
  fi
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

if [ -n "${PROMOTE_RELEASE}" ]; then
  curl -fsS \
    -X POST \
    -H "Authorization: Bearer ${TOKEN}" \
    "${BASE_URL}/v1/releases/${PROMOTE_RELEASE}/promote"
else
  curl -fsS \
    -X POST \
    -H "Authorization: Bearer ${TOKEN}" \
    --data-binary "@${BUNDLE}" \
    "${BASE_URL}/v1/current.tar.gz"
fi
