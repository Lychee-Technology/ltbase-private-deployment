#!/usr/bin/env bash

set -euo pipefail

UPSTREAM_NAME="upstream"
UPSTREAM_URL="https://github.com/Lychee-Technology/ltbase-private-deployment.git"
BRANCH="main"
ARCHIVE_PATH="sync-template-upstream.tar"

build_fingerprint() {
  local root="$1"

  {
    find "${root}/infra" -type f | LC_ALL=C sort
    printf '%s\n' "${root}/.github/workflows/build-infra-binary.yml"
  } | while read -r path; do
    printf '== %s ==\n' "${path#${root}/}"
    cat "${path}"
    printf '\n'
  done | shasum -a 256 | awk '{print "sha256:" $1}'
}

required_source_paths=(
  ".github/workflows"
  "docs"
  "scripts"
  "test"
  "infra"
  "env.template"
  ".gitignore"
  "__ref__"
)

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
  echo "working tree is not clean; commit or stash your changes before syncing" >&2
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
upstream_commit="$(git rev-parse "${UPSTREAM_NAME}/${BRANCH}")"

temp_root="$(mktemp -d)"
trap 'rm -rf "${temp_root}" "${ARCHIVE_PATH}"' EXIT

git archive --format=tar --output "${ARCHIVE_PATH}" "${UPSTREAM_NAME}/${BRANCH}"
mkdir -p "${temp_root}"
tar -xf "${ARCHIVE_PATH}" -C "${temp_root}"

for path in "${required_source_paths[@]}"; do
  if [[ ! -e "${temp_root}/${path}" ]]; then
    echo "missing upstream path: ${path}" >&2
    exit 1
  fi
done

fingerprint="$(build_fingerprint "${temp_root}")"

mkdir -p "${temp_root}/__ref__"
jq -n \
  --arg template_repository "Lychee-Technology/ltbase-private-deployment" \
  --arg template_ref "${BRANCH}" \
  --arg template_commit "${upstream_commit}" \
  --arg build_fingerprint "${fingerprint}" \
  --arg generated_at "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
  --arg generator "scripts/sync-template-upstream.sh" \
  '{template_repository:$template_repository,template_ref:$template_ref,template_commit:$template_commit,build_fingerprint:$build_fingerprint,generated_at:$generated_at,generator:$generator}' \
  > "${temp_root}/__ref__/template-provenance.json"

rsync -a --delete \
  --exclude '.git/' \
  --exclude 'dist/' \
  --exclude '.DS_Store' \
  --exclude '.env' \
  --exclude '.env.*' \
  --exclude 'infra/Pulumi.*.yaml' \
  --exclude 'infra/auth-providers.*.json' \
  --exclude 'scripts/sync-template-upstream.sh' \
  --exclude 'test/sync-template-upstream-test.sh' \
  "${temp_root}/" "./"

printf 'synced %s/%s into %s\n' "${UPSTREAM_NAME}" "${BRANCH}" "${BRANCH}"
