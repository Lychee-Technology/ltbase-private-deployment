#!/usr/bin/env python3
"""Convert a DER-encoded RSA public key to a JWKS document (RFC 7517).

Zero external dependencies — uses only Python 3 stdlib.
Parses the fixed ASN.1 DER layout of SubjectPublicKeyInfo for RSA keys.
"""

import argparse
import base64
import json
import re
import sys

_KMS_ARN_RE = re.compile(r"^arn:aws:kms:[^:]+:\d+:key/(.+)$")


def extract_kms_key_id(key_id):
    """Extract the key UUID from a KMS key ARN, or return as-is if not an ARN."""
    m = _KMS_ARN_RE.match(key_id)
    return m.group(1) if m else key_id


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
    """Base64url encode without padding (RFC 7515 section 2)."""
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
                "kid": extract_kms_key_id(args.key_id),
                "n": base64url_encode(n_bytes),
                "e": base64url_encode(e_bytes),
            }
        ]
    }
    json.dump(jwks, sys.stdout, indent=2)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
