#!/usr/bin/env bash

# Resolves the schema bundle validator that ships with an official LTBase
# release, so publish-schemas.sh checks cross-file $refs with the same build
# that will load the bundle.
#
# Answers on stdout with exactly one line:
#
#   validator <path>   the release carries the validator; <path> runs on this machine
#   absent             the release manifest does not list the validator asset: the
#                      release predates eager $ref resolution, so there is nothing
#                      to check with and nothing that would refuse the bundle
#
# Every other outcome is a non-zero exit. "absent" is a positive answer read from
# the release's own manifest, never a fallback: a failed download, a checksum
# mismatch or an unsupported platform must stop the caller, not let it publish
# unchecked. That is also why the answer is a line on stdout rather than a
# special exit status, which a failing tool could produce by accident.

set -euo pipefail

VALIDATOR_ASSET="ltbase-schema-registry-seed.zip"
VALIDATOR_BINARY_PREFIX="schema-registry-seed-linux-"

RELEASE_ID="${LTBASE_RELEASE_ID:-}"
RELEASES_REPO="${LTBASE_RELEASES_REPO:-Lychee-Technology/ltbase-releases}"
OUTPUT_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --release-id)
      RELEASE_ID="$2"
      shift 2
      ;;
    --releases-repo)
      RELEASES_REPO="$2"
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    *)
      printf 'unknown argument: %s\n' "$1" >&2
      exit 1
      ;;
  esac
done

die() {
  printf '%s\n' "$1" >&2
  exit 1
}

if [[ -z "${RELEASE_ID}" ]]; then
  die 'release id is required (--release-id or LTBASE_RELEASE_ID)'
fi

if [[ -z "${OUTPUT_DIR}" ]]; then
  die 'output directory is required (--output-dir)'
fi

if ! command -v gh >/dev/null 2>&1; then
  die 'gh (GitHub CLI) is required to download the release validator'
fi

mkdir -p "${OUTPUT_DIR}"
OUTPUT_DIR="$(cd "${OUTPUT_DIR}" && pwd)"

download_asset() {
  local asset="$1"
  # gh output goes to stderr: stdout carries the answer and nothing else.
  if ! gh release download "${RELEASE_ID}" --repo "${RELEASES_REPO}" --pattern "${asset}" --dir "${OUTPUT_DIR}" --clobber >&2; then
    die "failed to download ${asset} from release ${RELEASE_ID} in ${RELEASES_REPO}"
  fi
  if [[ ! -f "${OUTPUT_DIR}/${asset}" ]]; then
    die "release ${RELEASE_ID} in ${RELEASES_REPO} did not provide ${asset}"
  fi
}

download_asset "manifest.json"

# The asset is looked up by file name, the way infra/internal/artifact resolves
# every other release artifact. Prints the asset's recorded sha256, or "absent".
if ! expected_sha256="$(python3 - "${OUTPUT_DIR}/manifest.json" "${RELEASE_ID}" "${VALIDATOR_ASSET}" <<'PY'
import json
import re
import sys

manifest_path, release_id, asset = sys.argv[1:4]

try:
    with open(manifest_path, 'r', encoding='utf-8') as handle:
        manifest = json.load(handle)
except (OSError, ValueError) as exc:
    raise SystemExit(f'release manifest is unreadable: {exc}')

if not isinstance(manifest, dict):
    raise SystemExit('release manifest is not a JSON object')

if manifest.get('release_id') != release_id:
    raise SystemExit(
        f"release manifest names release {manifest.get('release_id')!r}, expected {release_id!r}"
    )

artifacts = manifest.get('artifacts')
if not isinstance(artifacts, list) or not artifacts:
    raise SystemExit('release manifest lists no artifacts')

entries = [item for item in artifacts if isinstance(item, dict) and item.get('file') == asset]
if not entries:
    print('absent')
    sys.exit(0)

if len(entries) > 1:
    raise SystemExit(f'release manifest lists {asset} more than once')

sha256 = entries[0].get('sha256')
if not isinstance(sha256, str) or not re.fullmatch(r'[0-9a-f]{64}', sha256):
    raise SystemExit(f'release manifest records no usable sha256 for {asset}')

print(sha256)
PY
)"; then
  die "could not read the manifest of release ${RELEASE_ID} in ${RELEASES_REPO}"
fi

if [[ "${expected_sha256}" == "absent" ]]; then
  printf 'absent\n'
  exit 0
fi

# Checked only once the release is known to carry the validator, so a release
# with nothing to run answers "absent" on any machine.
os_name="$(uname -s)"
machine="$(uname -m)"

if [[ "${os_name}" != "Linux" ]]; then
  die "the release validator is built for Linux only and this machine runs ${os_name}; run the Preview workflow to validate the bundle instead"
fi

case "${machine}" in
  aarch64 | arm64)
    arch="arm64"
    ;;
  x86_64 | amd64)
    arch="amd64"
    ;;
  *)
    die "the release validator is built for arm64 and amd64 only, not ${machine}"
    ;;
esac

download_asset "${VALIDATOR_ASSET}"

binary_name="${VALIDATOR_BINARY_PREFIX}${arch}"
binary_path="${OUTPUT_DIR}/${binary_name}"

if ! python3 - "${OUTPUT_DIR}/${VALIDATOR_ASSET}" "${expected_sha256}" "${binary_name}" "${binary_path}" <<'PY'; then
import hashlib
import os
import sys
import zipfile

zip_path, expected_sha256, member, destination = sys.argv[1:5]
asset = os.path.basename(zip_path)

with open(zip_path, 'rb') as handle:
    actual_sha256 = hashlib.sha256(handle.read()).hexdigest()

if actual_sha256 != expected_sha256:
    raise SystemExit(
        f'checksum mismatch for {asset}: manifest records {expected_sha256}, downloaded {actual_sha256}'
    )

try:
    with zipfile.ZipFile(zip_path) as archive:
        try:
            binary = archive.read(member)
        except KeyError:
            raise SystemExit(f'{asset} does not contain {member}')
except zipfile.BadZipFile as exc:
    raise SystemExit(f'{asset} is not a readable zip archive: {exc}')

with open(destination, 'wb') as handle:
    handle.write(binary)
os.chmod(destination, 0o755)
PY
  die "could not unpack the validator from release ${RELEASE_ID} in ${RELEASES_REPO}"
fi

printf 'validator %s\n' "${binary_path}"
