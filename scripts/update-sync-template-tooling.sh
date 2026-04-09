#!/usr/bin/env bash

set -euo pipefail

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

if [[ -n "$(git status --porcelain)" ]]; then
  echo "working tree is not clean; commit or stash your changes before updating sync tooling" >&2
  exit 1
fi

current_branch="$(git rev-parse --abbrev-ref HEAD)"
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
  git remote add "${UPSTREAM_NAME}" "${UPSTREAM_URL}"
fi

git fetch "${UPSTREAM_NAME}"

temp_root="$(mktemp -d)"
trap 'rm -rf "${temp_root}" "${ARCHIVE_PATH}"' EXIT

git archive --format=tar --output "${ARCHIVE_PATH}" "${UPSTREAM_NAME}/${BRANCH}"
mkdir -p "${temp_root}"
tar -xf "${ARCHIVE_PATH}" -C "${temp_root}"

for path in scripts/sync-template-upstream.sh test/sync-template-upstream-test.sh; do
  if [[ ! -e "${temp_root}/${path}" ]]; then
    echo "missing upstream path: ${path}" >&2
    exit 1
  fi
done

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"

cp "${temp_root}/scripts/sync-template-upstream.sh" "${repo_root}/scripts/sync-template-upstream.sh"
cp "${temp_root}/test/sync-template-upstream-test.sh" "${repo_root}/test/sync-template-upstream-test.sh"

printf 'updated sync tooling from %s/%s\n' "${UPSTREAM_NAME}" "${BRANCH}"
