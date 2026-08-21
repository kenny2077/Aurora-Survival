#!/usr/bin/env python3
"""Create a signed single-package development catalog for Expert testing."""

from __future__ import annotations

import argparse
import base64
import datetime as dt
import json
import pathlib

from cryptography.hazmat.primitives import serialization

from build_pack import canonical_json


ROOT = pathlib.Path(__file__).resolve().parents[1]
KEY_ID = "development-2026-07"
KEYRING = ROOT / "Resources" / "Packages" / "development_trusted_package_keys.json"


def catalog_signing_payload(catalog: dict) -> bytes:
    fields = ["schema", str(catalog["schemaVersion"]), "generated", catalog["generatedAt"]]
    for entry in sorted(catalog["entries"], key=lambda item: (item["packageID"], item["version"])):
        fields.extend([
            "package", entry["packageID"],
            "version", entry["version"],
            "kind", entry["kind"],
            "display", entry["displayName"],
            "summary", entry["summary"],
            "bytes", str(entry["totalByteCount"]),
            "envelope", entry["envelopePath"],
            "artifacts", entry["artifactBasePath"],
        ])
        for key in sorted(entry["metadata"]):
            fields.extend(["metadata", key, entry["metadata"][key]])
    return "\n".join(f"{len(field.encode('utf-8'))}:{field}" for field in fields).encode()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--package", type=pathlib.Path, required=True)
    parser.add_argument("--output", type=pathlib.Path, required=True)
    parser.add_argument(
        "--private-key",
        type=pathlib.Path,
        default=ROOT / ".trailguard" / "development" / "package-signing-key.pem",
    )
    args = parser.parse_args()
    package = args.package.resolve()
    envelope_path = package / "envelope.json"
    if not envelope_path.is_file():
        raise FileNotFoundError(envelope_path)
    envelope = json.loads(envelope_path.read_text(encoding="utf-8"))
    manifest = envelope["manifest"]
    if manifest["kind"] != "model" or manifest["metadata"].get("model_tier") != "vision_expert":
        raise ValueError("catalog accepts only a verified Expert model package")

    private_key = serialization.load_pem_private_key(
        args.private_key.read_bytes(), password=None
    )
    trusted = json.loads(KEYRING.read_text(encoding="utf-8"))
    trusted_key = next((item for item in trusted if item["id"] == KEY_ID), None)
    if trusted_key is None:
        raise ValueError(f"development keyring is missing {KEY_ID}")
    actual_public = base64.b64encode(private_key.public_key().public_bytes(
        encoding=serialization.Encoding.Raw,
        format=serialization.PublicFormat.Raw,
    )).decode("ascii")
    if actual_public != trusted_key["publicKeyBase64"]:
        raise ValueError("private key does not match the development keyring")

    entry = {
        "packageID": manifest["packageID"],
        "version": manifest["version"],
        "kind": manifest["kind"],
        "displayName": manifest["displayName"],
        "summary": "Pinned Qwen3-VL Expert development package for retained physical testing.",
        "totalByteCount": sum(item["byteCount"] for item in manifest["artifacts"]),
        "envelopePath": f"{package.name}/envelope.json",
        "artifactBasePath": package.name,
        "metadata": {
            "memory_profile_status": manifest["metadata"]["memory_profile_status"],
            "model_tier": "vision_expert",
        },
    }
    generated_at = dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace(
        "+00:00", "Z"
    )
    catalog = {"schemaVersion": 1, "generatedAt": generated_at, "entries": [entry]}
    signed = {
        "catalog": catalog,
        "keyID": KEY_ID,
        "signature": base64.b64encode(private_key.sign(catalog_signing_payload(catalog))).decode("ascii"),
    }
    args.output.mkdir(parents=True, exist_ok=True)
    (args.output / "catalog.json").write_bytes(canonical_json(signed))
    hosted_package = args.output / package.name
    if hosted_package.is_symlink():
        if hosted_package.resolve() != package:
            raise RuntimeError(f"unexpected package symlink target: {hosted_package}")
    elif hosted_package.exists():
        raise FileExistsError(hosted_package)
    else:
        hosted_package.symlink_to(package, target_is_directory=True)
    print(args.output / "catalog.json")


if __name__ == "__main__":
    main()
