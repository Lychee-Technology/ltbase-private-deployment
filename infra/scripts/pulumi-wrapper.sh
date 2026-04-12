#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
infra_dir="$(cd "${script_dir}/.." && pwd)"

cd "${infra_dir}"
mkdir -p .pulumi/bin

if [[ ! -x .pulumi/bin/ltbase-infra ]]; then
  CGO_ENABLED=0 go build -buildvcs=false -o .pulumi/bin/ltbase-infra ./cmd/ltbase-infra
fi

exec pulumi "$@"
