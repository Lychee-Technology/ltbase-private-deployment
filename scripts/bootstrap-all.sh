#!/usr/bin/env bash

set -euo pipefail

ENV_FILE=""
MODE="apply"
INFRA_DIR="infra"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env-file)
      ENV_FILE="$2"
      shift 2
      ;;
    --mode)
      MODE="$2"
      shift 2
      ;;
    --infra-dir)
      INFRA_DIR="$2"
      shift 2
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "${ENV_FILE}" ]]; then
  echo "--env-file is required" >&2
  exit 1
fi

script_dir="$(cd "$(dirname "$0")" && pwd)"

if [[ "${MODE}" != "apply" ]]; then
  echo "unsupported mode: ${MODE}" >&2
  exit 1
fi

create-deployment-repo.sh --env-file "${ENV_FILE}"
render-bootstrap-policies.sh --env-file "${ENV_FILE}"
bootstrap-aws-foundation.sh --env-file "${ENV_FILE}"
bootstrap-deployment-repo.sh --env-file "${ENV_FILE}" --stack devo --infra-dir "${INFRA_DIR}"
bootstrap-deployment-repo.sh --env-file "${ENV_FILE}" --stack prod --infra-dir "${INFRA_DIR}"
