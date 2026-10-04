#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT_PATH="${ROOT_DIR}/scripts/publish-schemas.sh"
RELEASES_REPO="Lychee-Technology/ltbase-releases"
VALIDATOR_ASSET="ltbase-schema-registry-seed.zip"
# A release that ships the schema validator, and one that predates it.
CURRENT_RELEASE="v2.0.0"
LEGACY_RELEASE="v1.0.30"

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

assert_contains() {
  local haystack="$1"
  local needle="$2"
  if [[ "${haystack}" != *"${needle}"* ]]; then
    fail "expected output to contain '${needle}', got: ${haystack}"
  fi
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  if [[ "${haystack}" == *"${needle}"* ]]; then
    fail "expected output to not contain '${needle}', got: ${haystack}"
  fi
}

temp_dir="$(mktemp -d)"
fake_bin="${temp_dir}/bin"
bucket_dir="${temp_dir}/bucket"
schema_dir="${temp_dir}/schemas"
releases_root="${temp_dir}/releases"
log_file="${temp_dir}/aws.log"
gh_log="${temp_dir}/gh.log"
validator_log="${temp_dir}/validator.log"
lead_schema="${schema_dir}/lead.json"
visit_schema="${schema_dir}/visit.json"
order_schema="${schema_dir}/order.json"
invalid_schema="${schema_dir}/broken.json"

cleanup() {
  rm -rf "${temp_dir}"
}
trap cleanup EXIT

mkdir -p "${fake_bin}" "${bucket_dir}" "${schema_dir}" "${releases_root}"
touch "${log_file}" "${gh_log}" "${validator_log}"

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

# Serves `gh release download <id> --repo <repo> --pattern <asset> --dir <dir>`
# from ${FAKE_RELEASES_ROOT}/<repo>/<id>/<asset>.
cat >"${fake_bin}/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf 'gh %s\n' "$*" >>"${GH_LOG:?}"

if [[ "${1:-}" != "release" || "${2:-}" != "download" ]]; then
  printf 'unsupported gh invocation: %s\n' "$*" >&2
  exit 1
fi

release_id="$3"
shift 3
repo=""
pattern=""
dir=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) repo="$2"; shift 2 ;;
    --pattern) pattern="$2"; shift 2 ;;
    --dir) dir="$2"; shift 2 ;;
    --clobber) shift ;;
    *) printf 'unsupported gh argument: %s\n' "$1" >&2; exit 1 ;;
  esac
done

source_path="${FAKE_RELEASES_ROOT:?}/${repo}/${release_id}/${pattern}"
if [[ ! -f "${source_path}" ]]; then
  printf 'no assets match the file pattern\n' >&2
  exit 1
fi

mkdir -p "${dir}"
cp "${source_path}" "${dir}/"
EOF
chmod +x "${fake_bin}/gh"

# Stands in for `schema-registry-seed validate --schema-dir <dir>`: records the
# files it was shown, and refuses a $ref to a file the bundle does not contain.
fake_validator="${temp_dir}/fake-validator"
cat >"${fake_validator}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 || "$1" != "validate" || "$2" != "--schema-dir" ]]; then
  printf 'unsupported validator invocation: %s\n' "$*" >&2
  exit 2
fi

bundle="$3"
{
  printf 'validate %s\n' "${bundle}"
  printf 'files %s\n' "$(cd "${bundle}" && find . -mindepth 1 | sort | tr '\n' ' ')"
} >>"${VALIDATOR_LOG:?}"

if [[ -n "${FAKE_VALIDATOR_EXIT_STATUS:-}" ]]; then
  printf 'simulated validator crash\n' >&2
  exit "${FAKE_VALIDATOR_EXIT_STATUS}"
fi

python3 - "${bundle}" <<'PY'
import json
import sys
from pathlib import Path

bundle = Path(sys.argv[1])
findings = []


def walk(node, name):
    if isinstance(node, dict):
        ref = node.get('$ref')
        if isinstance(ref, str):
            target = ref.split('#', 1)[0]
            if target and not (bundle / target).is_file():
                findings.append(f'{name}: $ref "{ref}": no such file {target}')
        for value in node.values():
            walk(value, name)
    elif isinstance(node, list):
        for value in node:
            walk(value, name)


for path in sorted(bundle.glob('*.json')):
    walk(json.loads(path.read_text(encoding='utf-8')), path.name)

if findings:
    print(f'result: FAILED — {len(findings)} finding(s)')
    for finding in findings:
        print(f'  - {finding}')
    sys.exit(1)

print('result: OK — every cross-file reference resolves')
PY
EOF

# make_release <release id> <repo> <with validator: yes|no|tampered>
make_release() {
  local release_id="$1"
  local repo="$2"
  local validator="$3"
  local release_dir="${releases_root}/${repo}/${release_id}"
  mkdir -p "${release_dir}"
  python3 - "${release_dir}" "${release_id}" "${VALIDATOR_ASSET}" "${validator}" "${fake_validator}" <<'PY'
import hashlib
import json
import sys
import zipfile
from pathlib import Path

release_dir, release_id, asset, validator, fake_validator = sys.argv[1:6]
artifacts = [{'name': 'data-plane', 'file': 'ltbase-dataplane-lambda.zip', 'sha256': 'a' * 64}]

if validator != 'no':
    zip_path = Path(release_dir) / asset
    with zipfile.ZipFile(zip_path, 'w') as archive:
        for arch in ('arm64', 'amd64'):
            archive.write(fake_validator, arcname=f'schema-registry-seed-linux-{arch}')
    digest = hashlib.sha256(zip_path.read_bytes()).hexdigest()
    if validator == 'tampered':
        digest = 'b' * 64
    artifacts.append({'name': 'schema-registry-seed', 'file': asset, 'sha256': digest})

manifest = {'release_id': release_id, 'artifacts': artifacts}
(Path(release_dir) / 'manifest.json').write_text(json.dumps(manifest), encoding='utf-8')
PY
}

make_release "${CURRENT_RELEASE}" "${RELEASES_REPO}" yes
make_release "${LEGACY_RELEASE}" "${RELEASES_REPO}" no
make_release "v2.9.0" "${RELEASES_REPO}" tampered
make_release "v2.0.1" "customer/releases-mirror" yes

# run_publish <args>...  — sets ${status} and ${output} (stdout and stderr).
run_publish() {
  status=0
  output="$(PATH="${fake_bin}:$PATH" COMMAND_LOG="${log_file}" FAKE_S3_ROOT="${bucket_dir}" GH_LOG="${gh_log}" FAKE_RELEASES_ROOT="${releases_root}" VALIDATOR_LOG="${validator_log}" "${PUBLISH_SCRIPT:-${SCRIPT_PATH}}" "$@" 2>&1)" || status=$?
}

# Everything a publish could have changed: the bucket contents and the aws calls.
bucket_state() {
  (cd "${bucket_dir}" && find . -type f -exec cksum {} + | sort)
  wc -l <"${log_file}"
}

# expect_refused <description> <needle>  — the run failed, said why, and left
# the bucket exactly as ${state_before} recorded it.
expect_refused() {
  local description="$1"
  local needle="$2"
  if [[ "${status}" -eq 0 ]]; then
    fail "${description}: expected publish-schemas.sh to fail, got: ${output}"
  fi
  assert_contains "${output}" "${needle}"
  if [[ "${state_before}" != "$(bucket_state)" ]]; then
    fail "${description}: the schema bucket was written to"
  fi
}

published_version() {
  python3 - <<'PY' "$1"
import json
import sys

with open(sys.argv[1], 'r', encoding='utf-8') as handle:
    manifest = json.load(handle)

print(manifest['version'])
PY
}

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

# Neighbours that are never published, so must not be validated either.
printf 'working notes\n' >"${schema_dir}/notes.txt"
mkdir "${schema_dir}/drafts"
printf '{"name": "draft"}\n' >"${schema_dir}/drafts/draft.json"

if [[ ! -x "${SCRIPT_PATH}" ]]; then
  fail "missing executable script: ${SCRIPT_PATH}"
fi

# ---------- a clean bundle is validated, then published ----------

state_before="$(bucket_state)"
LTBASE_RELEASE_ID="${CURRENT_RELEASE}" run_publish --dry-run --schema-dir "${schema_dir}" --schema-bucket test-schema-bucket
if [[ "${status}" -ne 0 ]]; then
  fail "expected the dry run to succeed, got: ${output}"
fi
assert_contains "${output}" "validated schema bundle"
assert_file_contains "${validator_log}" "files ./lead.json ./visit.json "
assert_equals "${state_before}" "$(bucket_state)"

: >"${validator_log}"
PUBLISH_SCHEMAS_GENERATED_AT="2026-04-18T00:00:00Z" run_publish --schema-dir "${schema_dir}" --schema-bucket test-schema-bucket --release-id "${CURRENT_RELEASE}"
if [[ "${status}" -ne 0 ]]; then
  fail "expected publish-schemas.sh to succeed, got: ${output}"
fi

manifest_path="${bucket_dir}/test-schema-bucket/schemas/published/manifest.json"
assert_file_exists "${manifest_path}"

version="$(published_version "${manifest_path}")"

assert_file_exists "${bucket_dir}/test-schema-bucket/schemas/releases/${version}/manifest.json"
assert_file_exists "${bucket_dir}/test-schema-bucket/schemas/releases/${version}/lead.json"
assert_file_exists "${bucket_dir}/test-schema-bucket/schemas/releases/${version}/visit.json"
assert_file_missing "${bucket_dir}/test-schema-bucket/schemas/releases/${version}/notes.txt"
assert_file_contains "${manifest_path}" '"generated_at": "2026-04-18T00:00:00Z"'
assert_file_contains "${manifest_path}" '"name": "schemas/releases/'
assert_file_contains "${manifest_path}" '/lead.json"'
assert_file_contains "${manifest_path}" '/visit.json"'
assert_file_contains "${log_file}" "aws s3 cp"
assert_file_contains "${log_file}" "s3://test-schema-bucket/schemas/releases/${version}/manifest.json"
assert_file_contains "${log_file}" "s3://test-schema-bucket/schemas/published/manifest.json"

release_manifest="${bucket_dir}/test-schema-bucket/schemas/releases/${version}/manifest.json"
assert_equals "${version}" "$(published_version "${release_manifest}")"

# The validator saw the files that were published and nothing else, as a copy:
# what it checked is byte for byte what reached the bucket.
assert_contains "${output}" "with the validator of release ${CURRENT_RELEASE}"
assert_equals "1" "$(grep -c '^validate ' "${validator_log}")"
assert_file_contains "${validator_log}" "files ./lead.json ./visit.json "
if grep -Fq "validate ${schema_dir}" "${validator_log}"; then
  fail "the validator ran over the working directory instead of the published copy"
fi
if grep -Fq "aws s3 cp ${schema_dir}/" "${log_file}"; then
  fail "schemas were uploaded from the working directory instead of the validated copy"
fi
cmp -s "${lead_schema}" "${bucket_dir}/test-schema-bucket/schemas/releases/${version}/lead.json" || fail "published lead.json differs from its source"
cmp -s "${visit_schema}" "${bucket_dir}/test-schema-bucket/schemas/releases/${version}/visit.json" || fail "published visit.json differs from its source"

# ---------- a dangling cross-file $ref is refused before anything is uploaded ----------

cat >"${order_schema}" <<'EOF'
{
  "name": "order",
  "properties": {
    "shipping_address": {
      "$ref": "address.json#/$defs/address"
    }
  }
}
EOF

state_before="$(bucket_state)"
run_publish --schema-dir "${schema_dir}" --schema-bucket test-schema-bucket --release-id "${CURRENT_RELEASE}"
expect_refused "dangling \$ref" "nothing was published"
assert_contains "${output}" "result: FAILED"
# The refusal says what to do about the bundle the stacks already serve.
assert_contains "${output}" "roll the corrected bundle out with the release that stack runs now before deploying ${CURRENT_RELEASE}"
assert_contains "${output}" "docs/onboarding/08-day-2-operations.md"
# shellcheck disable=SC2016
assert_contains "${output}" 'order.json: $ref "address.json#/$defs/address"'

run_publish --dry-run --schema-dir "${schema_dir}" --schema-bucket test-schema-bucket --release-id "${CURRENT_RELEASE}"
expect_refused "dangling \$ref in a dry run" "failed validation for release ${CURRENT_RELEASE}"
assert_not_contains "${output}" "validated schema bundle"

# A validator that dies is not a validator that passed.
for validator_status in 2 126 137; do
  FAKE_VALIDATOR_EXIT_STATUS="${validator_status}" run_publish --schema-dir "${schema_dir}" --schema-bucket test-schema-bucket --release-id "${CURRENT_RELEASE}"
  expect_refused "validator exiting ${validator_status}" "nothing was published"
done

# ---------- the release decides whether there is a check, and only the release ----------

run_publish --schema-dir "${schema_dir}" --schema-bucket test-schema-bucket
expect_refused "missing release id" "release id is required"

run_publish --schema-dir "${schema_dir}" --schema-bucket test-schema-bucket --release-id v9.9.9
expect_refused "unknown release" "could not resolve the schema validator of release v9.9.9"
assert_not_contains "${output}" "does not ship a schema validator"

run_publish --schema-dir "${schema_dir}" --schema-bucket test-schema-bucket --release-id v2.9.0
expect_refused "validator failing its checksum" "checksum mismatch for ${VALIDATOR_ASSET}"
assert_not_contains "${output}" "does not ship a schema validator"

# The releases repository is configurable, by flag or by environment.
: >"${gh_log}"
run_publish --dry-run --schema-dir "${schema_dir}" --schema-bucket test-schema-bucket --release-id v2.0.1 --releases-repo customer/releases-mirror
expect_refused "dangling \$ref against a mirrored release" "failed validation for release v2.0.1"
assert_file_contains "${gh_log}" "gh release download v2.0.1 --repo customer/releases-mirror"

: >"${gh_log}"
LTBASE_RELEASES_REPO="customer/releases-mirror" run_publish --dry-run --schema-dir "${schema_dir}" --schema-bucket test-schema-bucket --release-id v2.0.1
expect_refused "dangling \$ref against a mirrored release from the environment" "failed validation for release v2.0.1"
assert_file_contains "${gh_log}" "gh release download v2.0.1 --repo customer/releases-mirror"

# Only an answer the publish script recognises lets it continue.
stub_scripts="${temp_dir}/stub/scripts"
mkdir -p "${stub_scripts}"
cp "${SCRIPT_PATH}" "${stub_scripts}/publish-schemas.sh"
cat >"${stub_scripts}/fetch-schema-validator.sh" <<'EOF'
#!/usr/bin/env bash
printf '%b' "${FAKE_FETCH_ANSWER:-}"
EOF
chmod +x "${stub_scripts}/fetch-schema-validator.sh"

for answer in '' 'maybe\n' 'absent\nvalidator /bin/true\n' 'validator\n' "validator ${temp_dir}/no-such-validator\\n"; do
  PUBLISH_SCRIPT="${stub_scripts}/publish-schemas.sh" FAKE_FETCH_ANSWER="${answer}" run_publish --schema-dir "${schema_dir}" --schema-bucket test-schema-bucket --release-id "${CURRENT_RELEASE}"
  expect_refused "fetch answer '${answer}'" "nothing was published"
done

# A release that predates the validator also predates eager resolution: it
# publishes as before, and says the reference check did not run.
: >"${validator_log}"
run_publish --schema-dir "${schema_dir}" --schema-bucket test-schema-bucket --release-id "${LEGACY_RELEASE}"
if [[ "${status}" -ne 0 ]]; then
  fail "expected a release without the validator to publish, got: ${output}"
fi
assert_contains "${output}" "release ${LEGACY_RELEASE} does not ship a schema validator"
assert_contains "${output}" "published schema bundle"
assert_equals "" "$(<"${validator_log}")"
legacy_version="$(published_version "${manifest_path}")"
assert_file_exists "${bucket_dir}/test-schema-bucket/schemas/releases/${legacy_version}/order.json"

# ---------- the fixed bundle publishes ----------

cat >"${schema_dir}/address.json" <<'EOF'
{
  "name": "address",
  "$defs": {
    "address": {
      "type": "object"
    }
  }
}
EOF

run_publish --schema-dir "${schema_dir}" --schema-bucket test-schema-bucket --release-id "${CURRENT_RELEASE}"
if [[ "${status}" -ne 0 ]]; then
  fail "expected the fixed bundle to publish, got: ${output}"
fi
fixed_version="$(published_version "${manifest_path}")"
assert_file_exists "${bucket_dir}/test-schema-bucket/schemas/releases/${fixed_version}/address.json"
assert_file_exists "${bucket_dir}/test-schema-bucket/schemas/releases/${fixed_version}/order.json"

# ---------- malformed JSON never reaches the validator ----------

cat >"${invalid_schema}" <<'EOF'
{
  "name": "broken",
EOF

: >"${validator_log}"
state_before="$(bucket_state)"
run_publish --schema-dir "${schema_dir}" --schema-bucket test-schema-bucket --release-id "${CURRENT_RELEASE}"
expect_refused "invalid JSON" "invalid schema JSON"
assert_contains "${output}" "broken.json"
assert_equals "" "$(<"${validator_log}")"

printf 'PASS: publish schema tests\n'
