#!/usr/bin/env python3
"""Replace the exposed local development key without displaying private material."""

import base64
import json
import os

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

from build_pack import canonical_json, signing_payload
from prepare_expert_catalog import catalog_signing_payload
from publish_r2_models import ROOT


def main():
    root = ROOT / ".trailguard/development"
    key_path = root / "package-signing-key.pem"
    keyring_path = ROOT / "Resources/Packages/development_trusted_package_keys.json"
    keyring = json.loads(keyring_path.read_text())
    key_id = "development-2026-07"
    entry = next(item for item in keyring if item["id"] == key_id)
    private = Ed25519PrivateKey.generate()
    pending = []
    for path in root.rglob("*.json"):
        if path.is_symlink():
            continue
        try:
            value = json.loads(path.read_bytes())
        except (ValueError, UnicodeDecodeError):
            continue
        if not isinstance(value, dict) or value.get("keyID") != key_id:
            continue
        if "manifest" in value:
            payload = signing_payload(value["manifest"])
        elif "catalog" in value and value["catalog"].get("schemaVersion") == 1:
            payload = catalog_signing_payload(value["catalog"])
        else:
            continue
        value["signature"] = base64.b64encode(private.sign(payload)).decode()
        pending.append((path, canonical_json(value)))
    temporary = key_path.with_suffix(".new")
    with os.fdopen(os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), "wb") as handle:
        handle.write(private.private_bytes(serialization.Encoding.PEM,
                     serialization.PrivateFormat.PKCS8, serialization.NoEncryption()))
    os.replace(temporary, key_path)
    entry["publicKeyBase64"] = base64.b64encode(private.public_key().public_bytes(
        serialization.Encoding.Raw, serialization.PublicFormat.Raw)).decode()
    keyring_path.write_bytes(canonical_json(keyring))
    for path, data in pending:
        path.write_bytes(data)
    print(f"Rotated development key and re-signed {len(pending)} local envelopes/catalogs.")
    print("Previously distributed development-signed packages are no longer trusted by rebuilt apps.")


if __name__ == "__main__":
    main()
