#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT_PATH="${ROOT_DIR}/scripts/fetch-schema-validator.sh"
DEFAULT_REPO="Lychee-Technology/ltbase-releases"
VALIDATOR_ASSET="ltbase-schema-registry-seed.zip"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_equals() {
  local expected="$1"
  local actual="$2"
  if [[ "${expected}" != "${actual}" ]]; then
    fail "expected '${expected}', got '${actual}'"
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
releases_root="${temp_dir}/releases"
gh_log="${temp_dir}/gh.log"
stderr_file="${temp_dir}/stderr"

cleanup() {
  rm -rf "${temp_dir}"
}
trap cleanup EXIT

mkdir -p "${fake_bin}" "${releases_root}"
touch "${gh_log}"

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
  exit "${FAKE_GH_EXIT_STATUS:-1}"
fi

mkdir -p "${dir}"
cp "${source_path}" "${dir}/"
# Chatter on stdout, which the script must keep out of its one-line answer.
printf 'downloaded %s\n' "${pattern}"
EOF
chmod +x "${fake_bin}/gh"

cat >"${fake_bin}/uname" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  -s) printf '%s\n' "${FAKE_UNAME_S:-Linux}" ;;
  -m) printf '%s\n' "${FAKE_UNAME_M:-aarch64}" ;;
  *) printf 'unsupported uname invocation: %s\n' "$*" >&2; exit 1 ;;
esac
EOF
chmod +x "${fake_bin}/uname"

sha256_of() {
  python3 -c 'import hashlib, sys; print(hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest())' "$1"
}

# make_validator_zip <zip path> <arch>...  — each member prints its own name.
make_validator_zip() {
  local zip_path="$1"
  shift
  local staging member
  staging="$(mktemp -d "${temp_dir}/zip.XXXXXX")"
  for arch in "$@"; do
    member="schema-registry-seed-linux-${arch}"
    printf '#!/usr/bin/env bash\nprintf "%s\\n"\n' "${member}" >"${staging}/${member}"
  done
  python3 - "${zip_path}" "${staging}" <<'PY'
import os
import sys
import zipfile

zip_path, staging = sys.argv[1:3]
with zipfile.ZipFile(zip_path, 'w') as archive:
    for name in sorted(os.listdir(staging)):
        archive.write(os.path.join(staging, name), arcname=name)
PY
}

# write_manifest <release dir> <release id recorded in the manifest> [<validator sha256>]
write_manifest() {
  local release_dir="$1"
  local recorded_id="$2"
  local validator_sha256="${3:-}"
  python3 - "${release_dir}/manifest.json" "${recorded_id}" "${VALIDATOR_ASSET}" "${validator_sha256}" <<'PY'
import json
import sys

manifest_path, release_id, asset, validator_sha256 = sys.argv[1:5]
artifacts = [{'name': 'data-plane', 'file': 'ltbase-dataplane-lambda.zip', 'sha256': 'a' * 64}]
if validator_sha256:
    artifacts.append({'name': 'schema-registry-seed', 'file': asset, 'sha256': validator_sha256})
with open(manifest_path, 'w', encoding='utf-8') as handle:
    json.dump({'release_id': release_id, 'artifacts': artifacts}, handle)
PY
}

# make_release <release id> [<repo>]  — a release that carries the validator.
make_release() {
  local release_id="$1"
  local repo="${2:-${DEFAULT_REPO}}"
  local release_dir="${releases_root}/${repo}/${release_id}"
  mkdir -p "${release_dir}"
  make_validator_zip "${release_dir}/${VALIDATOR_ASSET}" arm64 amd64
  write_manifest "${release_dir}" "${release_id}" "$(sha256_of "${release_dir}/${VALIDATOR_ASSET}")"
}

# run_fetch <args>...  — sets ${status}, ${output} (stdout only), ${errors}.
run_fetch() {
  status=0
  output="$(PATH="${fake_bin}:${PATH}" GH_LOG="${gh_log}" FAKE_RELEASES_ROOT="${releases_root}" "${SCRIPT_PATH}" "$@" 2>"${stderr_file}")" || status=$?
  errors="$(<"${stderr_file}")"
}

expect_failure() {
  local description="$1"
  local needle="$2"
  if [[ "${status}" -eq 0 ]]; then
    fail "${description}: expected a failure, got: ${output}"
  fi
  assert_contains "${errors}" "${needle}"
  # A failure must never be readable as an answer.
  assert_equals "" "${output}"
}

if [[ ! -x "${SCRIPT_PATH}" ]]; then
  fail "missing executable script: ${SCRIPT_PATH}"
fi

# ---------- a release that carries the validator ----------

make_release "v2.0.0"

run_fetch --release-id v2.0.0 --output-dir "${temp_dir}/out-arm64"
assert_equals "0" "${status}"
assert_equals "validator ${temp_dir}/out-arm64/schema-registry-seed-linux-arm64" "${output}"
assert_equals "schema-registry-seed-linux-arm64" "$("${output#validator }")"
assert_contains "$(<"${gh_log}")" "gh release download v2.0.0 --repo ${DEFAULT_REPO} --pattern manifest.json"
assert_contains "$(<"${gh_log}")" "gh release download v2.0.0 --repo ${DEFAULT_REPO} --pattern ${VALIDATOR_ASSET}"

FAKE_UNAME_M="x86_64" run_fetch --release-id v2.0.0 --output-dir "${temp_dir}/out-amd64"
assert_equals "0" "${status}"
assert_equals "validator ${temp_dir}/out-amd64/schema-registry-seed-linux-amd64" "${output}"
assert_equals "schema-registry-seed-linux-amd64" "$("${output#validator }")"

# The release id and the releases repository may come from the environment, and
# a relative output directory still answers with an absolute path.
make_release "v2.0.1" "customer/releases-mirror"
: >"${gh_log}"
status=0
output="$(cd "${temp_dir}" && PATH="${fake_bin}:${PATH}" GH_LOG="${gh_log}" FAKE_RELEASES_ROOT="${releases_root}" LTBASE_RELEASE_ID="v2.0.1" LTBASE_RELEASES_REPO="customer/releases-mirror" "${SCRIPT_PATH}" --output-dir out-env 2>"${stderr_file}")" || status=$?
assert_equals "0" "${status}"
assert_equals "validator ${temp_dir}/out-env/schema-registry-seed-linux-arm64" "${output}"
assert_contains "$(<"${gh_log}")" "gh release download v2.0.1 --repo customer/releases-mirror"

# The flag wins over the environment.
: >"${gh_log}"
LTBASE_RELEASES_REPO="customer/not-this-one" run_fetch --release-id v2.0.1 --releases-repo customer/releases-mirror --output-dir "${temp_dir}/out-flag"
assert_equals "0" "${status}"
assert_equals "validator ${temp_dir}/out-flag/schema-registry-seed-linux-arm64" "${output}"
assert_not_contains "$(<"${gh_log}")" "customer/not-this-one"

# ---------- a release that predates the validator ----------

legacy_dir="${releases_root}/${DEFAULT_REPO}/v1.0.30"
mkdir -p "${legacy_dir}"
write_manifest "${legacy_dir}" "v1.0.30"

: >"${gh_log}"
run_fetch --release-id v1.0.30 --output-dir "${temp_dir}/out-legacy"
assert_equals "0" "${status}"
assert_equals "absent" "${output}"
assert_not_contains "$(<"${gh_log}")" "${VALIDATOR_ASSET}"

# "absent" is a property of the release, not of the machine asking.
FAKE_UNAME_S="Darwin" run_fetch --release-id v1.0.30 --output-dir "${temp_dir}/out-legacy-darwin"
assert_equals "0" "${status}"
assert_equals "absent" "${output}"

# ---------- failures are never an answer ----------

run_fetch --output-dir "${temp_dir}/out-none"
expect_failure "missing release id" "release id is required"

run_fetch --release-id v2.0.0
expect_failure "missing output directory" "output directory is required"

run_fetch --release-id v9.9.9 --output-dir "${temp_dir}/out-missing"
expect_failure "unknown release" "failed to download manifest.json from release v9.9.9"

# Whatever status the download tool fails with, it is a failure.
for gh_status in 2 3 4; do
  FAKE_GH_EXIT_STATUS="${gh_status}" run_fetch --release-id v9.9.9 --output-dir "${temp_dir}/out-missing"
  expect_failure "download failing with status ${gh_status}" "failed to download manifest.json"
  assert_equals "1" "${status}"
done

mismatch_dir="${releases_root}/${DEFAULT_REPO}/v2.1.0"
mkdir -p "${mismatch_dir}"
make_validator_zip "${mismatch_dir}/${VALIDATOR_ASSET}" arm64 amd64
write_manifest "${mismatch_dir}" "v2.0.0" "$(sha256_of "${mismatch_dir}/${VALIDATOR_ASSET}")"
run_fetch --release-id v2.1.0 --output-dir "${temp_dir}/out-mismatch"
expect_failure "manifest for another release" "release manifest names release 'v2.0.0', expected 'v2.1.0'"

tampered_dir="${releases_root}/${DEFAULT_REPO}/v2.2.0"
mkdir -p "${tampered_dir}"
make_validator_zip "${tampered_dir}/${VALIDATOR_ASSET}" arm64 amd64
write_manifest "${tampered_dir}" "v2.2.0" "$(printf 'b%.0s' {1..64})"
run_fetch --release-id v2.2.0 --output-dir "${temp_dir}/out-tampered"
expect_failure "checksum mismatch" "checksum mismatch for ${VALIDATOR_ASSET}"

unhashed_dir="${releases_root}/${DEFAULT_REPO}/v2.3.0"
mkdir -p "${unhashed_dir}"
make_validator_zip "${unhashed_dir}/${VALIDATOR_ASSET}" arm64 amd64
write_manifest "${unhashed_dir}" "v2.3.0" "not-a-digest"
run_fetch --release-id v2.3.0 --output-dir "${temp_dir}/out-unhashed"
expect_failure "unusable digest" "release manifest records no usable sha256 for ${VALIDATOR_ASSET}"

missing_asset_dir="${releases_root}/${DEFAULT_REPO}/v2.4.0"
mkdir -p "${missing_asset_dir}"
write_manifest "${missing_asset_dir}" "v2.4.0" "$(printf 'c%.0s' {1..64})"
run_fetch --release-id v2.4.0 --output-dir "${temp_dir}/out-missing-asset"
expect_failure "listed asset not downloadable" "failed to download ${VALIDATOR_ASSET} from release v2.4.0"

one_arch_dir="${releases_root}/${DEFAULT_REPO}/v2.5.0"
mkdir -p "${one_arch_dir}"
make_validator_zip "${one_arch_dir}/${VALIDATOR_ASSET}" amd64
write_manifest "${one_arch_dir}" "v2.5.0" "$(sha256_of "${one_arch_dir}/${VALIDATOR_ASSET}")"
run_fetch --release-id v2.5.0 --output-dir "${temp_dir}/out-one-arch"
expect_failure "binary for this architecture missing" "${VALIDATOR_ASSET} does not contain schema-registry-seed-linux-arm64"

not_a_zip_dir="${releases_root}/${DEFAULT_REPO}/v2.6.0"
mkdir -p "${not_a_zip_dir}"
printf 'not a zip\n' >"${not_a_zip_dir}/${VALIDATOR_ASSET}"
write_manifest "${not_a_zip_dir}" "v2.6.0" "$(sha256_of "${not_a_zip_dir}/${VALIDATOR_ASSET}")"
run_fetch --release-id v2.6.0 --output-dir "${temp_dir}/out-not-a-zip"
expect_failure "asset is not a zip" "${VALIDATOR_ASSET} is not a readable zip archive"

empty_dir="${releases_root}/${DEFAULT_REPO}/v2.7.0"
mkdir -p "${empty_dir}"
printf '{"release_id": "v2.7.0", "artifacts": []}\n' >"${empty_dir}/manifest.json"
run_fetch --release-id v2.7.0 --output-dir "${temp_dir}/out-empty"
expect_failure "manifest without artifacts" "release manifest lists no artifacts"

garbled_dir="${releases_root}/${DEFAULT_REPO}/v2.8.0"
mkdir -p "${garbled_dir}"
printf '{"release_id": "v2.8.0",\n' >"${garbled_dir}/manifest.json"
run_fetch --release-id v2.8.0 --output-dir "${temp_dir}/out-garbled"
expect_failure "unparseable manifest" "release manifest is unreadable"

FAKE_UNAME_S="Darwin" run_fetch --release-id v2.0.0 --output-dir "${temp_dir}/out-darwin"
expect_failure "unsupported operating system" "built for Linux only and this machine runs Darwin"

FAKE_UNAME_M="riscv64" run_fetch --release-id v2.0.0 --output-dir "${temp_dir}/out-riscv"
expect_failure "unsupported architecture" "built for arm64 and amd64 only, not riscv64"

run_fetch --release-id v2.0.0 --output-dir "${temp_dir}/out-unknown" --validator /bin/true
expect_failure "unknown argument" "unknown argument: --validator"

printf 'PASS: fetch schema validator tests\n'
