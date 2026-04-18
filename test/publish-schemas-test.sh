#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT_PATH="${ROOT_DIR}/scripts/publish-schemas.sh"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_file_exists() {
  local path="$1"
  if [[ ! -f "${path}" ]]; then
    fail "missing file: ${path}"
  fi
}

assert_file_contains() {
  local path="$1"
  local needle="$2"
  if ! grep -Fq "${needle}" "${path}"; then
    fail "expected ${path} to contain: ${needle}"
  fi
}

assert_equals() {
  local expected="$1"
  local actual="$2"
  if [[ "${expected}" != "${actual}" ]]; then
    fail "expected '${expected}', got '${actual}'"
  fi
}

assert_file_missing() {
  local path="$1"
  if [[ -e "${path}" ]]; then
    fail "expected missing path: ${path}"
  fi
}

temp_dir="$(mktemp -d)"
fake_bin="${temp_dir}/bin"
bucket_dir="${temp_dir}/bucket"
schema_dir="${temp_dir}/schemas"
log_file="${temp_dir}/aws.log"
lead_schema="${schema_dir}/lead.json"
visit_schema="${schema_dir}/visit.json"
invalid_schema="${schema_dir}/broken.json"

cleanup() {
  rm -rf "${temp_dir}"
}
trap cleanup EXIT

mkdir -p "${fake_bin}" "${bucket_dir}" "${schema_dir}"
touch "${log_file}"

cat >"${fake_bin}/aws" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

bucket_root="${FAKE_S3_ROOT:?}"
log_file="${COMMAND_LOG:?}"

printf 'aws %s\n' "$*" >>"${log_file}"

if [[ "$1" != "s3" ]]; then
  printf 'unsupported aws invocation: %s\n' "$*" >&2
  exit 1
fi

command="$2"

resolve_s3_path() {
  local uri="$1"
  local target bucket key
  target="${uri#s3://}"
  bucket="${target%%/*}"
  key="${target#*/}"
  if [[ "${bucket}" == "${target}" ]]; then
    key=""
  fi
  printf '%s\n' "${bucket_root}/${bucket}/${key}"
}

case "${command}" in
  cp)
    src="$3"
    dest="$4"

    if [[ "${src}" == s3://* && "${dest}" != s3://* ]]; then
      source_path="$(resolve_s3_path "${src}")"
      cp "${source_path}" "${dest}"
      exit 0
    fi

    if [[ "${dest}" != s3://* ]]; then
      printf 'unsupported destination: %s\n' "${dest}" >&2
      exit 1
    fi

    target_path="$(resolve_s3_path "${dest}")"
    mkdir -p "$(dirname "${target_path}")"

    if [[ -n "${FAIL_CURRENT_AFTER:-}" && "${dest}" == *"/schemas/current/"* && "${src}" != *"/current-backup/"* && "${src}" != *"/previous-current-manifest.json" ]]; then
      count_file="${bucket_root}/.current-copy-count"
      count=0
      if [[ -f "${count_file}" ]]; then
        count="$(<"${count_file}")"
      fi
      count=$((count + 1))
      printf '%s' "${count}" >"${count_file}"
      if [[ "${count}" -gt "${FAIL_CURRENT_AFTER}" ]]; then
        printf 'simulated current publish failure for %s\n' "${dest}" >&2
        exit 1
      fi
    fi

    cp "${src}" "${target_path}"
    ;;
  rm)
    target_path="$(resolve_s3_path "$3")"
    rm -f "${target_path}"
    ;;
  *)
    printf 'unsupported aws invocation: %s\n' "$*" >&2
    exit 1
    ;;
esac
EOF
chmod +x "${fake_bin}/aws"

cat >"${lead_schema}" <<'EOF'
{
  "name": "lead",
  "fields": [
    {
      "name": "full_name",
      "type": "string"
    }
  ]
}
EOF

cat >"${visit_schema}" <<'EOF'
{
  "name": "visit",
  "fields": [
    {
      "name": "scheduled_at",
      "type": "datetime"
    }
  ]
}
EOF

if [[ ! -x "${SCRIPT_PATH}" ]]; then
  fail "missing executable script: ${SCRIPT_PATH}"
fi

if ! output="$(PATH="${fake_bin}:$PATH" COMMAND_LOG="${log_file}" FAKE_S3_ROOT="${bucket_dir}" PUBLISH_SCHEMAS_GENERATED_AT="2026-04-18T00:00:00Z" "${SCRIPT_PATH}" --schema-dir "${schema_dir}" --schema-bucket test-schema-bucket 2>&1)"; then
  fail "expected publish-schemas.sh to succeed, got: ${output}"
fi

manifest_path="${bucket_dir}/test-schema-bucket/schemas/published/manifest.json"
assert_file_exists "${manifest_path}"

version="$(python3 - <<'PY' "${manifest_path}"
import json
import sys

with open(sys.argv[1], 'r', encoding='utf-8') as handle:
    manifest = json.load(handle)

print(manifest['version'])
PY
)"

assert_file_exists "${bucket_dir}/test-schema-bucket/schemas/releases/${version}/manifest.json"
assert_file_exists "${bucket_dir}/test-schema-bucket/schemas/releases/${version}/lead.json"
assert_file_exists "${bucket_dir}/test-schema-bucket/schemas/releases/${version}/visit.json"
assert_file_contains "${manifest_path}" '"generated_at": "2026-04-18T00:00:00Z"'
assert_file_contains "${manifest_path}" '"name": "schemas/releases/'
assert_file_contains "${manifest_path}" '/lead.json"'
assert_file_contains "${manifest_path}" '/visit.json"'
assert_file_contains "${log_file}" "aws s3 cp"
assert_file_contains "${log_file}" "s3://test-schema-bucket/schemas/releases/${version}/manifest.json"
assert_file_contains "${log_file}" "s3://test-schema-bucket/schemas/published/manifest.json"

release_manifest="${bucket_dir}/test-schema-bucket/schemas/releases/${version}/manifest.json"
release_version="$(python3 - <<'PY' "${release_manifest}"
import json
import sys

with open(sys.argv[1], 'r', encoding='utf-8') as handle:
    manifest = json.load(handle)

print(manifest['version'])
PY
)"
assert_equals "${version}" "${release_version}"

cat >"${invalid_schema}" <<'EOF'
{
  "name": "broken",
EOF

if output="$(PATH="${fake_bin}:$PATH" COMMAND_LOG="${log_file}" FAKE_S3_ROOT="${bucket_dir}" "${SCRIPT_PATH}" --schema-dir "${schema_dir}" --schema-bucket test-schema-bucket 2>&1)"; then
  fail "expected publish-schemas.sh to fail for invalid JSON"
fi

assert_file_contains <(printf '%s' "${output}") "invalid schema JSON"
assert_file_contains <(printf '%s' "${output}") "broken.json"

printf 'PASS: publish schema tests\n'
