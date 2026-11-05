#!/usr/bin/env python3
"""Signs the update feed: writes <manifest>.sig = base64(Ed25519(manifest bytes)).

The app refuses any latest.json whose signature doesn't verify against a
public key compiled into it (UpdateService.trustedKeys), so a compromised
download server can't push a malicious update — the private key never
leaves the release pipeline.

Usage:
  UPDATE_SIGNING_KEY="$(cat key.pem)" tool/sign_update_manifest.py dist/latest.json
  tool/sign_update_manifest.py dist/latest.json --key-file ~/.config/hypermed/update-signing-key.pem
"""
import argparse
import base64
import os
import pathlib
import sys

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives.serialization import load_pem_private_key


def main():
    p = argparse.ArgumentParser()
    p.add_argument("manifest")
    p.add_argument("--key-file")
    a = p.parse_args()

    pem = pathlib.Path(a.key_file).read_bytes() if a.key_file else os.environ.get("UPDATE_SIGNING_KEY", "").encode()
    if not pem.strip():
        sys.exit("No signing key: set UPDATE_SIGNING_KEY or pass --key-file")
    key = load_pem_private_key(pem, password=None)
    if not isinstance(key, Ed25519PrivateKey):
        sys.exit("Signing key must be Ed25519")

    data = pathlib.Path(a.manifest).read_bytes()
    sig = base64.b64encode(key.sign(data)).decode()
    out = pathlib.Path(a.manifest + ".sig")
    out.write_text(sig + "\n")
    print(f"signed {a.manifest} -> {out}")


if __name__ == "__main__":
    main()
