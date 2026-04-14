#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LIB_PATH="${ROOT_DIR}/scripts/lib/bootstrap-env.sh"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local message="$3"
  if [[ "${actual}" != "${expected}" ]]; then
    fail "${message}: expected [${expected}], got [${actual}]"
  fi
}

assert_file_eq() {
  local expected="$1"
  local path="$2"
  local message="$3"
  local actual
  actual="$(<"${path}")"
  assert_eq "${expected}" "${actual}" "${message}"
}

source "${LIB_PATH}"

temp_dir="$(mktemp -d)"
trap 'rm -rf "${temp_dir}"' EXIT

stdout_file="${temp_dir}/stdout"
stderr_file="${temp_dir}/stderr"

bootstrap_env_info 'hello world' >"${stdout_file}" 2>"${stderr_file}"
assert_file_eq '[info] hello world' "${stdout_file}" 'bootstrap_env_info should write info logs to stdout'
assert_file_eq '' "${stderr_file}" 'bootstrap_env_info should not write to stderr'

: >"${stdout_file}"
: >"${stderr_file}"
bootstrap_env_run_quiet bash -c 'printf "visible stdout\n"; printf "visible stderr\n" >&2' >"${stdout_file}" 2>"${stderr_file}"
assert_file_eq '' "${stdout_file}" 'bootstrap_env_run_quiet should suppress stdout on success'
assert_file_eq '' "${stderr_file}" 'bootstrap_env_run_quiet should suppress stderr on success'

: >"${stdout_file}"
: >"${stderr_file}"
set +e
bootstrap_env_run_quiet bash -c 'printf "failed stdout\n"; printf "failed stderr\n" >&2; exit 23' >"${stdout_file}" 2>"${stderr_file}"
status=$?
set -e
assert_eq '23' "${status}" 'bootstrap_env_run_quiet should preserve failing exit status'
assert_file_eq '' "${stdout_file}" 'bootstrap_env_run_quiet should not replay output to stdout on failure'
assert_file_eq $'failed stdout\nfailed stderr' "${stderr_file}" 'bootstrap_env_run_quiet should replay combined output to stderr on failure'

captured=''
: >"${stdout_file}"
: >"${stderr_file}"
bootstrap_env_capture_quiet captured bash -c 'printf "captured stdout\n"; printf "captured stderr\n" >&2' >"${stdout_file}" 2>"${stderr_file}"
assert_eq $'captured stdout\ncaptured stderr' "${captured}" 'bootstrap_env_capture_quiet should capture combined output on success'
assert_file_eq '' "${stdout_file}" 'bootstrap_env_capture_quiet should stay silent on success stdout'
assert_file_eq '' "${stderr_file}" 'bootstrap_env_capture_quiet should stay silent on success stderr'

captured='unchanged'
: >"${stdout_file}"
: >"${stderr_file}"
set +e
bootstrap_env_capture_quiet captured bash -c 'printf "capture failed stdout\n"; printf "capture failed stderr\n" >&2; exit 17' >"${stdout_file}" 2>"${stderr_file}"
status=$?
set -e
assert_eq '17' "${status}" 'bootstrap_env_capture_quiet should preserve failing exit status'
assert_eq 'unchanged' "${captured}" 'bootstrap_env_capture_quiet should not overwrite the destination variable on failure'
assert_file_eq '' "${stdout_file}" 'bootstrap_env_capture_quiet should not replay output to stdout on failure'
assert_file_eq $'capture failed stdout\ncapture failed stderr' "${stderr_file}" 'bootstrap_env_capture_quiet should replay combined output to stderr on failure'

printf 'PASS: bootstrap-env tests\n'
