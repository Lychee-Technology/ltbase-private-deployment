#!/usr/bin/env bash

set -euo pipefail

SCHEMA_DIR=""
SCHEMA_BUCKET="${SCHEMA_BUCKET:-}"
DRY_RUN="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --schema-dir)
      SCHEMA_DIR="$2"
      shift 2
      ;;
    --schema-bucket)
      SCHEMA_BUCKET="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN="true"
      shift
      ;;
    *)
      printf 'unknown argument: %s\n' "$1" >&2
      exit 1
      ;;
  esac
done

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_dir="$(cd "${script_dir}/.." && pwd)"

if [[ -z "${SCHEMA_DIR}" ]]; then
  SCHEMA_DIR="${repo_dir}/customer-owned/schemas"
fi

if [[ -z "${SCHEMA_BUCKET}" ]]; then
  printf 'schema bucket is required\n' >&2
  exit 1
fi

if [[ ! -d "${SCHEMA_DIR}" ]]; then
  printf 'schema directory does not exist: %s\n' "${SCHEMA_DIR}" >&2
  exit 1
fi

tmp_dir="$(mktemp -d)"
published_manifest_path="${tmp_dir}/published-manifest.json"

cleanup() {
  rm -rf "${tmp_dir}"
}

trap cleanup EXIT

generated_at="${PUBLISH_SCHEMAS_GENERATED_AT:-$(date -u +"%Y-%m-%dT%H:%M:%SZ")}" 
manifest_path="${tmp_dir}/manifest.json"

python3 - <<'PY' "${SCHEMA_DIR}" "${manifest_path}" "${generated_at}"
import hashlib
import json
import os
import sys
from pathlib import Path

schema_dir = Path(sys.argv[1])
manifest_path = Path(sys.argv[2])
generated_at = sys.argv[3]

schema_files = sorted(path for path in schema_dir.glob('*.json') if path.is_file())
if not schema_files:
    raise SystemExit(f'no schema files found in {schema_dir}')

files = []
version_hash = hashlib.sha256()
for path in schema_files:
    raw = path.read_bytes()
    try:
        json.loads(raw)
    except json.JSONDecodeError as exc:
        raise SystemExit(f'invalid schema JSON: {path.name}: {exc}')

    digest = hashlib.sha256(raw).hexdigest()
    version_hash.update(path.name.encode('utf-8'))
    version_hash.update(b'\0')
    version_hash.update(digest.encode('ascii'))
    version_hash.update(b'\0')
    files.append({
        'name': path.name,
        'sha256': digest,
    })

manifest = {
    'version': version_hash.hexdigest(),
    'generated_at': generated_at,
    'files': files,
}
manifest_path.write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
print(manifest['version'])
PY

version="$(python3 - <<'PY' "${manifest_path}"
import json
import sys

with open(sys.argv[1], 'r', encoding='utf-8') as handle:
    manifest = json.load(handle)

print(manifest['version'])
PY
)"

if [[ "${DRY_RUN}" == "true" ]]; then
  printf 'validated schema bundle %s for %s\n' "${version}" "${SCHEMA_BUCKET}"
  exit 0
fi

release_prefix="schemas/releases/${version}"
published_prefix="schemas/published"

for schema_path in "${SCHEMA_DIR}"/*.json; do
  file_name="$(basename "${schema_path}")"
  aws s3 cp "${schema_path}" "s3://${SCHEMA_BUCKET}/${release_prefix}/${file_name}"
done
aws s3 cp "${manifest_path}" "s3://${SCHEMA_BUCKET}/${release_prefix}/manifest.json"

python3 - <<'PY' "${manifest_path}" "${published_manifest_path}" "${release_prefix}"
import json
import sys

with open(sys.argv[1], 'r', encoding='utf-8') as handle:
    manifest = json.load(handle)

for item in manifest.get('files', []):
    item['name'] = f"{sys.argv[3]}/{item['name'].strip()}"

with open(sys.argv[2], 'w', encoding='utf-8') as handle:
    json.dump(manifest, handle, indent=2)
    handle.write('\n')
PY

aws s3 cp "${published_manifest_path}" "s3://${SCHEMA_BUCKET}/${published_prefix}/manifest.json"

printf 'published schema bundle %s to %s\n' "${version}" "${SCHEMA_BUCKET}"
