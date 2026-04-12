#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PULUMI_PROJECT="${ROOT_DIR}/infra/Pulumi.yaml"
WRAPPER_PATH="${ROOT_DIR}/infra/scripts/pulumi-wrapper.sh"
WORKFLOW_PATH="${ROOT_DIR}/.github/workflows/build-infra-binary.yml"
GITIGNORE_PATH="${ROOT_DIR}/.gitignore"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_file_contains() {
  local path="$1"
  local needle="$2"
  if [[ ! -f "${path}" ]]; then
    fail "missing file: ${path}"
  fi
  if ! grep -Fq "${needle}" "${path}"; then
    fail "expected ${path} to contain: ${needle}"
  fi
}

assert_log_contains() {
  local path="$1"
  local needle="$2"
  if ! grep -Fq "${needle}" "${path}"; then
    fail "expected ${path} to contain: ${needle}"
  fi
}

assert_file_contains "${PULUMI_PROJECT}" "name: go"
assert_file_contains "${PULUMI_PROJECT}" "options:"
assert_file_contains "${PULUMI_PROJECT}" "binary: ./.pulumi/bin/ltbase-infra"
assert_file_contains "${GITIGNORE_PATH}" "infra/.pulumi/"

assert_file_contains "${WORKFLOW_PATH}" "workflow_dispatch:"
assert_file_contains "${WORKFLOW_PATH}" "push:"
assert_file_contains "${WORKFLOW_PATH}" "runs-on: ubuntu-24.04-arm"
assert_file_contains "${WORKFLOW_PATH}" 'name: infra-binary-linux-arm64-${{ github.sha }}'
assert_file_contains "${WORKFLOW_PATH}" "manifest.json"
assert_file_contains "${WORKFLOW_PATH}" ".pulumi/bin/ltbase-infra"

temp_dir="$(mktemp -d)"
trap 'rm -rf "${temp_dir}"' EXIT
fake_bin="${temp_dir}/bin"
log_file="${temp_dir}/commands.log"
mkdir -p "${fake_bin}" "${temp_dir}/infra/.pulumi/bin" "${temp_dir}/infra/scripts"
touch "${log_file}"

cat >"${fake_bin}/go" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'go %s\n' "$*" >>"${COMMAND_LOG}"
output_path=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o)
      output_path="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
if [[ -n "${output_path}" ]]; then
  mkdir -p "$(dirname "${output_path}")"
  printf '#!/usr/bin/env bash\nexit 0\n' >"${output_path}"
  chmod +x "${output_path}"
fi
EOF
chmod +x "${fake_bin}/go"

cat >"${fake_bin}/pulumi" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'pulumi %s\n' "$*" >>"${COMMAND_LOG}"
EOF
chmod +x "${fake_bin}/pulumi"

cp "${WRAPPER_PATH}" "${temp_dir}/infra/scripts/pulumi-wrapper.sh"
chmod +x "${temp_dir}/infra/scripts/pulumi-wrapper.sh"

printf '#!/usr/bin/env bash\nexit 0\n' >"${temp_dir}/infra/.pulumi/bin/ltbase-infra"
chmod +x "${temp_dir}/infra/.pulumi/bin/ltbase-infra"

PATH="${fake_bin}:$PATH" COMMAND_LOG="${log_file}" "${temp_dir}/infra/scripts/pulumi-wrapper.sh" preview --stack devo

assert_log_contains "${log_file}" "pulumi preview --stack devo"
if grep -Fq "go build" "${log_file}"; then
  fail "wrapper should not rebuild when the binary already exists"
fi

: >"${log_file}"
rm -f "${temp_dir}/infra/.pulumi/bin/ltbase-infra"
PATH="${fake_bin}:$PATH" COMMAND_LOG="${log_file}" "${temp_dir}/infra/scripts/pulumi-wrapper.sh" up --stack devo

assert_log_contains "${log_file}" "go build -buildvcs=false -o .pulumi/bin/ltbase-infra ./cmd/ltbase-infra"
assert_log_contains "${log_file}" "pulumi up --stack devo"

printf 'PASS: prebuilt infra binary tests\n'
