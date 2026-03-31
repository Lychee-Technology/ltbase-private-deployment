# OIDC Discovery Template Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Populate the empty `ltbase-oidc-discovery-template` repo with a workflow, script, and README, then update `ltbase-private-deployment` to include `kms_auth_key_alias` in the OIDC stack config.

**Architecture:** The template repo contains a GitHub Actions workflow that fetches RSA public keys from AWS KMS (via OIDC-federated IAM roles) and generates RFC 7517 JWKS documents. A Python script handles DER-to-JWKS conversion with zero external dependencies. Cloudflare Pages auto-deploys on push. The private-deployment repo's bootstrap script derives the KMS alias from `PULUMI_PROJECT` and stack name and passes it via the `OIDC_DISCOVERY_STACK_CONFIG` repo variable.

**Tech Stack:** Bash, Python 3 (stdlib only), GitHub Actions, AWS KMS, jq

**Spec:** `docs/superpowers/specs/2026-03-31-oidc-discovery-template-design.md`

---

## File Map

### `ltbase-oidc-discovery-template` (all new files)

| File | Responsibility |
|------|---------------|
| `scripts/generate-jwks.py` | Parse DER-encoded RSA public key, output JWKS JSON |
| `.github/workflows/publish-discovery.yml` | Fetch KMS keys per stack, generate discovery docs, commit |
| `test/generate-jwks-test.sh` | Unit test for generate-jwks.py using openssl-generated keys |
| `README.md` | Bilingual docs (EN/CN): purpose, usage, repo variables |

### `ltbase-private-deployment` (modifications)

| File | Change |
|------|--------|
| `scripts/lib/bootstrap-env.sh:118` | Add `PULUMI_PROJECT` default in `bootstrap_env_apply_derivations` |
| `scripts/lib/bootstrap-env.sh:240-263` | Add `kms_auth_key_alias` field to stack config JSON |
| `env.template:36` | Add `PULUMI_PROJECT=ltbase-infra` after `PULUMI_KMS_ALIAS` |
| `test/bootstrap-oidc-discovery-companion-test.sh:138` | Update expected JSON to include `kms_auth_key_alias` |

---

## Phase 1: Template Repo

### Task 1: Clone template repo and initialize workspace

**Files:**
- Clone: `ltbase-oidc-discovery-template` (currently empty on GitHub)

- [ ] **Step 1: Clone the empty repo**

```bash
cd /Users/ruoshi/code/Lychee/LTBase
gh repo clone Lychee-Technology/ltbase-oidc-discovery-template
cd ltbase-oidc-discovery-template
```

If the clone fails because the repo has no commits, initialize locally:

```bash
mkdir -p /Users/ruoshi/code/Lychee/LTBase/ltbase-oidc-discovery-template
cd /Users/ruoshi/code/Lychee/LTBase/ltbase-oidc-discovery-template
git init
git remote add origin git@github.com:Lychee-Technology/ltbase-oidc-discovery-template.git
```

- [ ] **Step 2: Create the directory structure**

```bash
mkdir -p scripts .github/workflows test
```

- [ ] **Step 3: Create an initial commit on main**

```bash
git checkout -b main 2>/dev/null || git checkout main
echo "# ltbase-oidc-discovery-template" > README.md
git add README.md
git commit -m "chore: initialize repository"
```

Do NOT push yet — we will push the complete content in Task 6.

---

### Task 2: Write the generate-jwks.py test

**Files:**
- Create: `test/generate-jwks-test.sh`

- [ ] **Step 1: Write the test script**

```bash
#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GENERATE_SCRIPT="${SCRIPT_DIR}/scripts/generate-jwks.py"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

temp_dir="$(mktemp -d)"
trap 'rm -rf "${temp_dir}"' EXIT

# --- Setup: generate a test RSA key pair with openssl ---

openssl genrsa -out "${temp_dir}/private.pem" 2048 2>/dev/null
openssl rsa -in "${temp_dir}/private.pem" -pubout -outform DER \
  -out "${temp_dir}/public.der" 2>/dev/null

# Extract expected modulus (uppercase hex, no prefix) via openssl
expected_modulus_hex="$(openssl rsa -in "${temp_dir}/private.pem" \
  -pubout -outform DER 2>/dev/null \
  | openssl rsa -pubin -inform DER -modulus -noout 2>/dev/null \
  | sed 's/Modulus=//')"

# Base64-encode the DER key (single line, portable across macOS/Linux)
public_key_b64="$(base64 < "${temp_dir}/public.der" | tr -d '\n')"

test_key_id="arn:aws:kms:us-west-2:123456789012:key/test-key-id-00001"

# --- Test 1: output is valid JSON ---

if ! output="$(python3 "${GENERATE_SCRIPT}" \
    --public-key-b64 "${public_key_b64}" \
    --key-id "${test_key_id}" 2>&1)"; then
  fail "generate-jwks.py exited non-zero: ${output}"
fi

if ! printf '%s' "${output}" | python3 -m json.tool >/dev/null 2>&1; then
  fail "output is not valid JSON: ${output}"
fi

# --- Test 2: required JWKS fields present with correct values ---

python3 - "${test_key_id}" "${expected_modulus_hex}" <<'PYEOF' <<<"${output}"
import json, sys, base64

jwks = json.load(sys.stdin)
key_id = sys.argv[1]
expected_hex = sys.argv[2]

assert "keys" in jwks, "missing 'keys'"
assert len(jwks["keys"]) == 1, f"expected 1 key, got {len(jwks['keys'])}"

k = jwks["keys"][0]

assert k["kty"] == "RSA", f"kty={k['kty']}"
assert k["alg"] == "RS256", f"alg={k['alg']}"
assert k["use"] == "sig", f"use={k['use']}"
assert k["kid"] == key_id, f"kid={k['kid']}"

for field in ("n", "e"):
    v = k[field]
    assert "=" not in v, f"{field} has base64 padding"
    assert "+" not in v, f"{field} has + (not url-safe)"
    assert "/" not in v, f"{field} has / (not url-safe)"

# Round-trip: decode n and verify modulus matches openssl output
n_padded = k["n"] + "=" * (-len(k["n"]) % 4)
n_bytes = base64.urlsafe_b64decode(n_padded)
n_hex = n_bytes.hex().upper()
assert n_hex == expected_hex.upper(), (
    f"modulus mismatch:\n  got:      {n_hex[:40]}...\n  expected: {expected_hex[:40]}..."
)
PYEOF

if [[ $? -ne 0 ]]; then
  fail "field validation failed"
fi

# --- Test 3: different key produces different output ---

openssl genrsa -out "${temp_dir}/private2.pem" 2048 2>/dev/null
openssl rsa -in "${temp_dir}/private2.pem" -pubout -outform DER \
  -out "${temp_dir}/public2.der" 2>/dev/null
public_key_b64_2="$(base64 < "${temp_dir}/public2.der" | tr -d '\n')"

output2="$(python3 "${GENERATE_SCRIPT}" \
  --public-key-b64 "${public_key_b64_2}" \
  --key-id "other-key-id")"

n1="$(printf '%s' "${output}" | python3 -c "import json,sys; print(json.load(sys.stdin)['keys'][0]['n'])")"
n2="$(printf '%s' "${output2}" | python3 -c "import json,sys; print(json.load(sys.stdin)['keys'][0]['n'])")"

if [[ "${n1}" == "${n2}" ]]; then
  fail "two different keys produced the same modulus"
fi

printf 'PASS: generate-jwks tests\n'
```

- [ ] **Step 2: Make the test executable**

```bash
chmod +x test/generate-jwks-test.sh
```

- [ ] **Step 3: Run the test — verify it fails**

```bash
bash test/generate-jwks-test.sh
```

Expected: FAIL — `scripts/generate-jwks.py` does not exist yet.

---

### Task 3: Implement generate-jwks.py

**Files:**
- Create: `scripts/generate-jwks.py`

- [ ] **Step 1: Write the script**

```python
#!/usr/bin/env python3
"""Convert a DER-encoded RSA public key to a JWKS document (RFC 7517).

Zero external dependencies — uses only Python 3 stdlib.
Parses the fixed ASN.1 DER layout of SubjectPublicKeyInfo for RSA keys.
"""

import argparse
import base64
import json
import sys


def _read_der_length(data, offset):
    """Read a DER length field. Returns (length, new_offset)."""
    first = data[offset]
    if first < 0x80:
        return first, offset + 1
    num_bytes = first & 0x7F
    length = 0
    for i in range(num_bytes):
        length = (length << 8) | data[offset + 1 + i]
    return length, offset + 1 + num_bytes


def _read_der_element(data, offset, expected_tag):
    """Read a DER element with the expected tag. Returns (content, new_offset)."""
    if offset >= len(data):
        raise ValueError(f"unexpected end of data at offset {offset}")
    if data[offset] != expected_tag:
        raise ValueError(
            f"expected tag 0x{expected_tag:02x} at offset {offset}, "
            f"got 0x{data[offset]:02x}"
        )
    length, value_offset = _read_der_length(data, offset + 1)
    end = value_offset + length
    if end > len(data):
        raise ValueError(f"element at offset {offset} extends past end of data")
    return data[value_offset:end], end


TAG_SEQUENCE = 0x30
TAG_BIT_STRING = 0x03
TAG_INTEGER = 0x02


def parse_rsa_public_key_der(der_bytes):
    """Extract (modulus_bytes, exponent_bytes) from DER-encoded SubjectPublicKeyInfo.

    The DER structure for RSA is:
        SEQUENCE {
            SEQUENCE { OID rsaEncryption, NULL }
            BIT STRING {
                SEQUENCE {
                    INTEGER modulus
                    INTEGER exponent
                }
            }
        }
    """
    outer, _ = _read_der_element(der_bytes, 0, TAG_SEQUENCE)
    pos = 0

    # Skip algorithm identifier SEQUENCE
    _, pos = _read_der_element(outer, pos, TAG_SEQUENCE)

    # BIT STRING wrapping the RSA public key
    bit_string, _ = _read_der_element(outer, pos, TAG_BIT_STRING)
    if bit_string[0] != 0:
        raise ValueError("unexpected unused bits in BIT STRING")
    inner = bit_string[1:]

    # Inner SEQUENCE: modulus + exponent
    rsa_seq, _ = _read_der_element(inner, 0, TAG_SEQUENCE)
    pos = 0
    n_bytes, pos = _read_der_element(rsa_seq, pos, TAG_INTEGER)
    e_bytes, _ = _read_der_element(rsa_seq, pos, TAG_INTEGER)

    # Strip DER INTEGER leading-zero padding (sign byte)
    if len(n_bytes) > 1 and n_bytes[0] == 0:
        n_bytes = n_bytes[1:]
    if len(e_bytes) > 1 and e_bytes[0] == 0:
        e_bytes = e_bytes[1:]

    return bytes(n_bytes), bytes(e_bytes)


def base64url_encode(data):
    """Base64url encode without padding (RFC 7515 §2)."""
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def main():
    parser = argparse.ArgumentParser(
        description="Generate JWKS from a DER-encoded RSA public key"
    )
    parser.add_argument(
        "--public-key-b64",
        required=True,
        help="Base64-encoded DER SubjectPublicKeyInfo",
    )
    parser.add_argument(
        "--key-id",
        required=True,
        help="Key identifier (typically a KMS key ARN)",
    )
    args = parser.parse_args()

    der_bytes = base64.b64decode(args.public_key_b64)
    n_bytes, e_bytes = parse_rsa_public_key_der(der_bytes)

    jwks = {
        "keys": [
            {
                "kty": "RSA",
                "alg": "RS256",
                "use": "sig",
                "kid": args.key_id,
                "n": base64url_encode(n_bytes),
                "e": base64url_encode(e_bytes),
            }
        ]
    }
    json.dump(jwks, sys.stdout, indent=2)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Run the test — verify it passes**

```bash
bash test/generate-jwks-test.sh
```

Expected: `PASS: generate-jwks tests`

- [ ] **Step 3: Commit**

```bash
git add scripts/generate-jwks.py test/generate-jwks-test.sh
git commit -m "feat: add generate-jwks.py with DER-to-JWKS conversion

Parses DER-encoded SubjectPublicKeyInfo, extracts RSA modulus and
exponent, outputs RFC 7517 JWKS. Zero external dependencies."
```

---

### Task 4: Write the publish-discovery workflow

**Files:**
- Create: `.github/workflows/publish-discovery.yml`

- [ ] **Step 1: Write the workflow**

```yaml
name: Publish OIDC Discovery Documents

on:
  workflow_dispatch:
    inputs:
      target_stack:
        description: "Stack to publish ('all' or a specific stack name)"
        required: false
        default: "all"
        type: string

permissions:
  contents: write
  id-token: write

jobs:
  publish:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Generate discovery documents
        env:
          OIDC_DISCOVERY_DOMAIN: ${{ vars.OIDC_DISCOVERY_DOMAIN }}
          OIDC_DISCOVERY_STACK_CONFIG: ${{ vars.OIDC_DISCOVERY_STACK_CONFIG }}
          TARGET_STACK: ${{ inputs.target_stack }}
        run: |
          set -euo pipefail

          if [[ -z "${OIDC_DISCOVERY_DOMAIN}" ]]; then
            echo "::error::OIDC_DISCOVERY_DOMAIN repo variable is not set"
            exit 1
          fi
          if [[ -z "${OIDC_DISCOVERY_STACK_CONFIG}" ]]; then
            echo "::error::OIDC_DISCOVERY_STACK_CONFIG repo variable is not set"
            exit 1
          fi

          # Determine which stacks to process
          if [[ "${TARGET_STACK}" == "all" ]]; then
            mapfile -t stacks < <(echo "${OIDC_DISCOVERY_STACK_CONFIG}" | jq -r 'keys[]')
          else
            if ! echo "${OIDC_DISCOVERY_STACK_CONFIG}" | jq -e --arg s "${TARGET_STACK}" '.[$s]' >/dev/null 2>&1; then
              echo "::error::Stack '${TARGET_STACK}' not found in OIDC_DISCOVERY_STACK_CONFIG"
              exit 1
            fi
            stacks=("${TARGET_STACK}")
          fi

          # Request a GitHub OIDC token for AWS STS
          oidc_token=$(curl -sS \
            -H "Authorization: bearer ${ACTIONS_ID_TOKEN_REQUEST_TOKEN}" \
            "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=sts.amazonaws.com" | jq -r '.value')

          for stack in "${stacks[@]}"; do
            echo "::group::${stack}"

            aws_region=$(echo "${OIDC_DISCOVERY_STACK_CONFIG}" | jq -r --arg s "${stack}" '.[$s].aws_region')
            aws_role_arn=$(echo "${OIDC_DISCOVERY_STACK_CONFIG}" | jq -r --arg s "${stack}" '.[$s].aws_role_arn')
            kms_alias=$(echo "${OIDC_DISCOVERY_STACK_CONFIG}" | jq -r --arg s "${stack}" '.[$s].kms_auth_key_alias')

            # Assume the stack's IAM role via OIDC federation
            creds=$(AWS_DEFAULT_REGION="${aws_region}" aws sts assume-role-with-web-identity \
              --role-arn "${aws_role_arn}" \
              --role-session-name "oidc-discovery-${stack}" \
              --web-identity-token "${oidc_token}" \
              --duration-seconds 900 \
              --output json)

            export AWS_ACCESS_KEY_ID=$(echo "${creds}" | jq -r '.Credentials.AccessKeyId')
            export AWS_SECRET_ACCESS_KEY=$(echo "${creds}" | jq -r '.Credentials.SecretAccessKey')
            export AWS_SESSION_TOKEN=$(echo "${creds}" | jq -r '.Credentials.SessionToken')
            export AWS_DEFAULT_REGION="${aws_region}"

            # Fetch the RSA public key from KMS
            public_key_json=$(aws kms get-public-key --key-id "${kms_alias}" --output json)
            public_key_b64=$(echo "${public_key_json}" | jq -r '.PublicKey')
            key_id=$(echo "${public_key_json}" | jq -r '.KeyId')

            # Generate JWKS
            mkdir -p "${stack}/.well-known"
            python3 scripts/generate-jwks.py \
              --public-key-b64 "${public_key_b64}" \
              --key-id "${key_id}" \
              > "${stack}/.well-known/jwks.json"

            # Generate openid-configuration
            python3 -c "
          import json, sys
          domain = sys.argv[1]
          stack = sys.argv[2]
          print(json.dumps({
              'issuer': f'https://{domain}/{stack}',
              'jwks_uri': f'https://{domain}/{stack}/.well-known/jwks.json',
              'response_types_supported': ['id_token'],
              'subject_types_supported': ['public'],
              'id_token_signing_alg_values_supported': ['RS256'],
          }, indent=2))" "${OIDC_DISCOVERY_DOMAIN}" "${stack}" \
              > "${stack}/.well-known/openid-configuration"

            echo "Published: ${stack}/.well-known/jwks.json"
            echo "Published: ${stack}/.well-known/openid-configuration"

            # Clear credentials before next iteration
            unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_DEFAULT_REGION

            echo "::endgroup::"
          done

      - name: Commit and push
        run: |
          set -euo pipefail
          git config user.name "github-actions[bot]"
          git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
          git add -A
          if git diff --cached --quiet; then
            echo "No changes to commit"
            exit 0
          fi
          git commit -m "chore: update OIDC discovery documents"
          git push
```

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/publish-discovery.yml
git commit -m "feat: add publish-discovery workflow

Fetches RSA public keys from AWS KMS via OIDC-federated IAM roles,
generates JWKS and openid-configuration per stack, commits to repo.
Cloudflare Pages auto-deploys on push."
```

---

### Task 5: Write the bilingual README

**Files:**
- Modify: `README.md` (replace the placeholder from Task 1)

- [ ] **Step 1: Write the README**

Replace the contents of `README.md` with:

````markdown
# LTBase OIDC Discovery Template

Template repository for LTBase OIDC discovery companion repos. Companion repos serve [OpenID Connect Discovery](https://openid.net/specs/openid-connect-discovery-1_0.html) documents (JWKS and openid-configuration) for each deployment stack via Cloudflare Pages.

This repo is used as a template — do not modify it directly for a specific deployment. Instead, use `bootstrap-oidc-discovery-companion.sh` from your private deployment repo to create a companion repo from this template.

---

**LTBase OIDC Discovery 模板仓库。** 伴随仓库通过 Cloudflare Pages 为每个部署环境提供 OpenID Connect Discovery 文档（JWKS 和 openid-configuration）。

本仓库仅作为模板使用，请勿直接修改。请通过私有部署仓库中的 `bootstrap-oidc-discovery-companion.sh` 脚本创建伴随仓库。

---

## How It Works / 工作原理

The `publish-discovery.yml` workflow:

1. Reads stack configuration from the `OIDC_DISCOVERY_STACK_CONFIG` repo variable
2. For each stack, assumes an IAM role via GitHub OIDC federation (no static credentials)
3. Fetches the RSA public key from the stack's KMS auth signing key
4. Generates `<stack>/.well-known/jwks.json` (RFC 7517) and `<stack>/.well-known/openid-configuration`
5. Commits the generated files — Cloudflare Pages auto-deploys on push

`publish-discovery.yml` 工作流：

1. 从 `OIDC_DISCOVERY_STACK_CONFIG` 仓库变量读取环境配置
2. 对每个环境，通过 GitHub OIDC 联合身份认证获取 IAM 角色（无需静态凭据）
3. 从环境的 KMS 认证签名密钥获取 RSA 公钥
4. 生成 `<stack>/.well-known/jwks.json`（RFC 7517）和 `<stack>/.well-known/openid-configuration`
5. 提交生成的文件 — Cloudflare Pages 自动部署

## Required Repo Variables / 必需的仓库变量

These are set automatically by `bootstrap-oidc-discovery-companion.sh`. Do not set them manually unless troubleshooting.

以下变量由 `bootstrap-oidc-discovery-companion.sh` 自动设置。除非排查问题，否则请勿手动设置。

| Variable | Description |
|----------|-------------|
| `OIDC_DISCOVERY_DOMAIN` | Custom domain for the Cloudflare Pages site (e.g., `oidc.example.com`) |
| `OIDC_DISCOVERY_STACK_CONFIG` | JSON object mapping each stack to its AWS region, IAM role ARN, and KMS key alias |

### `OIDC_DISCOVERY_STACK_CONFIG` format

```json
{
  "devo": {
    "aws_region": "ap-northeast-1",
    "aws_role_arn": "arn:aws:iam::123456789012:role/my-ltbase-oidc-discovery-devo",
    "kms_auth_key_alias": "alias/ltbase-infra-devo-authservice"
  },
  "prod": {
    "aws_region": "us-west-2",
    "aws_role_arn": "arn:aws:iam::210987654321:role/my-ltbase-oidc-discovery-prod",
    "kms_auth_key_alias": "alias/ltbase-infra-prod-authservice"
  }
}
```

## Running the Workflow / 运行工作流

Go to **Actions → Publish OIDC Discovery Documents → Run workflow**.

- **target_stack** = `all` (default): publish all stacks
- **target_stack** = `devo`: publish only the devo stack

前往 **Actions → Publish OIDC Discovery Documents → Run workflow**。

- **target_stack** = `all`（默认）：发布所有环境
- **target_stack** = `devo`：仅发布 devo 环境

## Output / 输出

After the workflow runs, the repo contains:

```
devo/.well-known/jwks.json
devo/.well-known/openid-configuration
prod/.well-known/jwks.json
prod/.well-known/openid-configuration
```

Served at:
- `https://<OIDC_DISCOVERY_DOMAIN>/devo/.well-known/jwks.json`
- `https://<OIDC_DISCOVERY_DOMAIN>/devo/.well-known/openid-configuration`

## Security / 安全

- **No secrets stored.** IAM roles use GitHub OIDC federation — the workflow exchanges a short-lived GitHub token for temporary AWS credentials.
- **KMS keys never leave AWS.** Only the public key is retrieved; private key material stays in KMS.
- **Read-only KMS access.** IAM roles only have `kms:GetPublicKey` and `kms:DescribeKey` permissions.

**无需存储密钥。** IAM 角色使用 GitHub OIDC 联合身份认证。KMS 密钥始终留在 AWS 中，仅获取公钥。IAM 角色仅具有 `kms:GetPublicKey` 和 `kms:DescribeKey` 权限。
````

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: add bilingual README with usage and security docs"
```

---

### Task 6: Push to GitHub and configure repo settings

**Files:** None (GitHub API operations only)

- [ ] **Step 1: Push to main**

```bash
git push -u origin main
```

If the remote has no branch yet, this creates the default branch. If it rejects because a different default branch exists, force-push is acceptable since the repo was empty:

```bash
git push -u origin main --force
```

- [ ] **Step 2: Make the repo public**

```bash
gh repo edit Lychee-Technology/ltbase-oidc-discovery-template --visibility public
```

- [ ] **Step 3: Mark as a template repository**

```bash
gh api -X PATCH repos/Lychee-Technology/ltbase-oidc-discovery-template \
  -f is_template=true
```

- [ ] **Step 4: Verify the repo is configured correctly**

```bash
gh repo view Lychee-Technology/ltbase-oidc-discovery-template --json isTemplate,visibility
```

Expected:
```json
{"isTemplate":true,"visibility":"PUBLIC"}
```

- [ ] **Step 5: Run the test from a clean checkout to verify**

```bash
bash test/generate-jwks-test.sh
```

Expected: `PASS: generate-jwks tests`

---

## Phase 2: Private Deployment Updates

### Task 7: Update bootstrap-env.sh

**Files:**
- Modify: `scripts/lib/bootstrap-env.sh:118` (add PULUMI_PROJECT derivation)
- Modify: `scripts/lib/bootstrap-env.sh:240-263` (add kms_auth_key_alias to stack config)

Working directory: `/Users/ruoshi/code/Lychee/LTBase/ltbase-private-deployment`

- [ ] **Step 1: Create a feature branch**

```bash
git checkout -b codex/issue-13-oidc-template
```

- [ ] **Step 2: Add PULUMI_PROJECT default to bootstrap_env_apply_derivations**

In `scripts/lib/bootstrap-env.sh`, inside `bootstrap_env_apply_derivations()`, add this block immediately before the existing `if [[ -z "${DEPLOYMENT_REPO:-}" ...` block (before line 123):

```bash
  if [[ -z "${PULUMI_PROJECT:-}" ]]; then
    PULUMI_PROJECT="ltbase-infra"
    export PULUMI_PROJECT
  fi
```

After this edit, the function starts with:

```bash
bootstrap_env_apply_derivations() {
  local stack upper_name region account_id role_name
  local role_arn_var provider_var runtime_bucket_var table_name_var
  local discovery_role_name_var discovery_role_arn_var issuer_var jwks_var

  if [[ -z "${PULUMI_PROJECT:-}" ]]; then
    PULUMI_PROJECT="ltbase-infra"
    export PULUMI_PROJECT
  fi

  if [[ -z "${DEPLOYMENT_REPO:-}" && -n "${GITHUB_OWNER:-}" && -n "${DEPLOYMENT_REPO_NAME:-}" ]]; then
```

- [ ] **Step 3: Add kms_auth_key_alias to the stack config JSON function**

Replace the entire `bootstrap_env_oidc_discovery_stack_config_json` function (lines 240-263) with:

```bash
bootstrap_env_oidc_discovery_stack_config_json() {
  while IFS= read -r stack; do
    printf '%s\t%s\t%s\t%s\n' \
      "${stack}" \
      "$(bootstrap_env_resolve_stack_value AWS_REGION "${stack}")" \
      "$(bootstrap_env_resolve_stack_value OIDC_DISCOVERY_AWS_ROLE_ARN "${stack}")" \
      "alias/${PULUMI_PROJECT:-ltbase-infra}-${stack}-authservice"
  done < <(bootstrap_env_each_stack) | python3 -c '
import json
import sys

payload = {}
for line in sys.stdin:
    line = line.rstrip("\n")
    if not line:
        continue
    stack, aws_region, aws_role_arn, kms_auth_key_alias = line.split("\t", 3)
    payload[stack] = {
        "aws_region": aws_region,
        "aws_role_arn": aws_role_arn,
        "kms_auth_key_alias": kms_auth_key_alias,
    }

print(json.dumps(payload, separators=(",", ":")))
'
}
```

---

### Task 8: Update env.template

**Files:**
- Modify: `env.template` (add PULUMI_PROJECT after PULUMI_KMS_ALIAS)

Working directory: `/Users/ruoshi/code/Lychee/LTBase/ltbase-private-deployment`

- [ ] **Step 1: Add PULUMI_PROJECT to env.template**

After the line `PULUMI_KMS_ALIAS=alias/ltbase-pulumi-secrets` (line 36), add:

```
PULUMI_PROJECT=ltbase-infra
```

The section should read:

```
PULUMI_STATE_BUCKET=replace-with-pulumi-state-bucket
PULUMI_KMS_ALIAS=alias/ltbase-pulumi-secrets
PULUMI_PROJECT=ltbase-infra
```

---

### Task 9: Update the companion bootstrap test

**Files:**
- Modify: `test/bootstrap-oidc-discovery-companion-test.sh:138`

Working directory: `/Users/ruoshi/code/Lychee/LTBase/ltbase-private-deployment`

- [ ] **Step 1: Update the expected OIDC_DISCOVERY_STACK_CONFIG assertion**

Replace line 138:

```bash
assert_log_contains "${log_file}" "gh variable set OIDC_DISCOVERY_STACK_CONFIG --repo customer-org/customer-ltbase-oidc-discovery --body {\"devo\":{\"aws_region\":\"ap-northeast-1\",\"aws_role_arn\":\"arn:aws:iam::123456789012:role/customer-ltbase-oidc-discovery-devo\"},\"prod\":{\"aws_region\":\"us-west-2\",\"aws_role_arn\":\"arn:aws:iam::210987654321:role/customer-ltbase-oidc-discovery-prod\"}}"
```

With:

```bash
assert_log_contains "${log_file}" "gh variable set OIDC_DISCOVERY_STACK_CONFIG --repo customer-org/customer-ltbase-oidc-discovery --body {\"devo\":{\"aws_region\":\"ap-northeast-1\",\"aws_role_arn\":\"arn:aws:iam::123456789012:role/customer-ltbase-oidc-discovery-devo\",\"kms_auth_key_alias\":\"alias/ltbase-infra-devo-authservice\"},\"prod\":{\"aws_region\":\"us-west-2\",\"aws_role_arn\":\"arn:aws:iam::210987654321:role/customer-ltbase-oidc-discovery-prod\",\"kms_auth_key_alias\":\"alias/ltbase-infra-prod-authservice\"}}"
```

---

### Task 10: Run tests and commit

Working directory: `/Users/ruoshi/code/Lychee/LTBase/ltbase-private-deployment`

- [ ] **Step 1: Run the companion bootstrap test**

```bash
bash test/bootstrap-oidc-discovery-companion-test.sh
```

Expected: `PASS: bootstrap-oidc-discovery-companion tests`

- [ ] **Step 2: Run the full test suite to check for regressions**

```bash
bash test/bootstrap-env-test.sh
bash test/evaluate-and-continue-test.sh
```

Expected: All tests pass. (The pre-existing `managed-dsql-consistency-test.sh` failure is known and unrelated.)

- [ ] **Step 3: Commit**

```bash
git add scripts/lib/bootstrap-env.sh env.template test/bootstrap-oidc-discovery-companion-test.sh
git commit -m "feat: include kms_auth_key_alias in OIDC discovery stack config

Add PULUMI_PROJECT env var (default: ltbase-infra) and derive
the KMS auth signing key alias per stack. The alias follows
the convention alias/<PULUMI_PROJECT>-<stack>-authservice,
matching what the Pulumi infra layer creates.

Closes #13"
```

- [ ] **Step 4: Push and create PR**

```bash
git push -u origin codex/issue-13-oidc-template
gh pr create \
  --title "feat: include kms_auth_key_alias in OIDC discovery stack config" \
  --body "$(cat <<'EOF'
## Summary

- Add `PULUMI_PROJECT` env var (default `ltbase-infra`) to `bootstrap_env_apply_derivations`
- Include `kms_auth_key_alias` field in `OIDC_DISCOVERY_STACK_CONFIG` JSON (alias format: `alias/<PULUMI_PROJECT>-<stack>-authservice`)
- Add `PULUMI_PROJECT=ltbase-infra` to `env.template`
- Update companion bootstrap test to verify the new field

Companion to the template repo population: https://github.com/Lychee-Technology/ltbase-oidc-discovery-template

Closes #13
EOF
)"
```

---

## Post-Implementation

After both phases are complete:

1. **Verify template repo** — `gh repo view Lychee-Technology/ltbase-oidc-discovery-template --json isTemplate,visibility` shows `{"isTemplate":true,"visibility":"PUBLIC"}`
2. **Merge the private-deployment PR**
3. **Close epic #16** — all child issues should now be resolved
4. **Return to `ltbase.api` PR #3** (managed DSQL endpoint contract)
