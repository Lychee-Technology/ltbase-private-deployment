#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "${script_dir}/lib/bootstrap-env.sh"

capture_stdout_quiet() {
  local destination_var="$1"
  local stderr_file output status
  shift

  stderr_file="$(mktemp)"
  if output="$("$@" 2>"${stderr_file}")"; then
    printf -v "${destination_var}" '%s' "${output}"
    rm -f "${stderr_file}"
    return 0
  else
    status=$?
  fi

  if [[ -s "${stderr_file}" ]]; then
    while IFS= read -r line; do
      printf '%s\n' "${line}" >&2
    done <"${stderr_file}"
  fi
  rm -f "${stderr_file}"
  return "${status}"
}

UPSTREAM_NAME="upstream"
UPSTREAM_URL="https://github.com/Lychee-Technology/ltbase-private-deployment.git"
BRANCH="main"
ARCHIVE_PATH="sync-template-upstream.tar"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --upstream-name)
      UPSTREAM_NAME="$2"
      shift 2
      ;;
    --upstream-url)
      UPSTREAM_URL="$2"
      shift 2
      ;;
    --branch)
      BRANCH="$2"
      shift 2
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "current directory is not a git repository" >&2
  exit 1
fi

capture_stdout_quiet git_status git status --porcelain
if [[ -n "${git_status}" ]]; then
  echo "working tree is not clean; commit or stash your changes before updating sync tooling" >&2
  exit 1
fi

capture_stdout_quiet current_branch git rev-parse --abbrev-ref HEAD
if [[ "${current_branch}" != "${BRANCH}" ]]; then
  echo "current branch must be ${BRANCH}; found ${current_branch}" >&2
  exit 1
fi

if existing_url="$(git remote get-url "${UPSTREAM_NAME}" 2>/dev/null)"; then
  if [[ "${existing_url}" != "${UPSTREAM_URL}" ]]; then
    echo "remote ${UPSTREAM_NAME} already exists with unexpected URL: ${existing_url}" >&2
    exit 1
  fi
else
  bootstrap_env_run_quiet git remote add "${UPSTREAM_NAME}" "${UPSTREAM_URL}"
fi

bootstrap_env_info "fetching upstream template from ${UPSTREAM_NAME}/${BRANCH}"
bootstrap_env_run_quiet git fetch "${UPSTREAM_NAME}"

temp_root="$(mktemp -d)"
trap 'rm -rf "${temp_root}" "${ARCHIVE_PATH}"' EXIT

bootstrap_env_run_quiet git archive --format=tar --output "${ARCHIVE_PATH}" "${UPSTREAM_NAME}/${BRANCH}"
mkdir -p "${temp_root}"
bootstrap_env_run_quiet tar -xf "${ARCHIVE_PATH}" -C "${temp_root}"

for path in scripts/sync-template-upstream.sh test/sync-template-upstream-test.sh; do
  if [[ ! -e "${temp_root}/${path}" ]]; then
    echo "missing upstream path: ${path}" >&2
    exit 1
  fi
done

repo_root="$(cd "${script_dir}/.." && pwd)"

bootstrap_env_info "updating local sync helper files"
bootstrap_env_run_quiet cp "${temp_root}/scripts/sync-template-upstream.sh" "${repo_root}/scripts/sync-template-upstream.sh"
bootstrap_env_run_quiet cp "${temp_root}/test/sync-template-upstream-test.sh" "${repo_root}/test/sync-template-upstream-test.sh"

printf 'updated sync tooling from %s/%s\n' "${UPSTREAM_NAME}" "${BRANCH}"
