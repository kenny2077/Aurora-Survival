#!/usr/bin/env python3
"""Stage a production-key species envelope without publishing language models.

Staging never changes the discoverable catalog. Promotion is a separate action
after the release checklist and physical-device validation have passed.
"""

import argparse
import base64
import hashlib
import json
import pathlib
import urllib.error
import urllib.request

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey

from build_pack import canonical_json
from prepare_expert_catalog import catalog_signing_payload
from publish_r2_models import ROOT, run_rclone, utc_now, validate_package, verify_signature


def fetch(url):
    request = urllib.request.Request(url) if isinstance(url, str) else url
    request.add_header("User-Agent", "AuroraReleasePublisher/1.1")
    return urllib.request.urlopen(request, timeout=60)


def verify_remote(url, expected):
    digest = hashlib.sha256()
    count = 0
    with fetch(url) as response:
        while block := response.read(1024 * 1024):
            count += len(block)
            digest.update(block)
    if count != expected["byteCount"] or digest.hexdigest() != expected["sha256"]:
        raise ValueError("Public artifact hash or size mismatch")
    request = urllib.request.Request(url, headers={"Range": "bytes=0-0"})
    with fetch(request) as response:
        if response.status != 206 or response.headers.get("Content-Range") != f"bytes 0-0/{count}":
            raise ValueError("Public artifact does not honor byte ranges")
        if len(response.read(2)) != 1:
            raise ValueError("Invalid range response length")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["stage", "promote"])
    parser.add_argument("--package", required=True, type=pathlib.Path)
    parser.add_argument("--public-base-url", required=True)
    parser.add_argument("--private-key", required=True, type=pathlib.Path)
    parser.add_argument("--release-gates-passed", action="store_true")
    args = parser.parse_args()
    base = args.public_base_url.rstrip("/")
    if not base.startswith("https://"):
        parser.error("HTTPS is required")
    envelope = validate_package(args.package, production=True)
    keys = json.loads((ROOT / "Resources/Packages/trusted_package_keys.json").read_text())
    verify_signature(envelope, keys)  # Development trust is deliberately excluded.
    manifest = envelope["manifest"]
    if manifest["kind"] != "species" or manifest["version"] != "1.0.1":
        raise ValueError("This release is limited to species version 1.0.1")
    paths = {item["path"] for item in manifest["artifacts"]}
    if not {"legal/BIOCLIP2_NOTICE.md", "legal/LICENSE_MIT_BIOCLIP2.txt"}.issubset(paths):
        raise ValueError("Missing BioCLIP license or attribution")
    prefix = f"packages/{manifest['packageID']}/{manifest['version']}"
    remote = "r2:aurora-survival-models/species"
    if args.action == "stage":
        for name in ["manifest.json", "envelope.json"] + sorted(paths):
            run_rclone(args.package / name, f"{remote}/{prefix}/{name}",
                       "public,max-age=31536000,immutable", immutable=True)
        for item in manifest["artifacts"]:
            verify_remote(f"{base}/species/{prefix}/{item['path']}", item)
        print("Species artifacts staged and public hashes/ranges verified.")
    if args.action == "promote" and not args.release_gates_passed:
        parser.error("Promotion requires completed release and device gates")
    # Verify public bytes again immediately before making the package discoverable.
    if args.action == "promote":
        for item in manifest["artifacts"]:
            verify_remote(f"{base}/species/{prefix}/{item['path']}", item)
    entries = []
    previous = None
    try:
        with fetch(f"{base}/species/catalog.json") as response:
            previous = response.read()
    except urllib.error.HTTPError as error:
        if error.code != 404:
            raise
    if previous is not None:
        signed = json.loads(previous)
        key = next(item for item in keys if item["id"] == signed["keyID"])
        Ed25519PublicKey.from_public_bytes(base64.b64decode(key["publicKeyBase64"])).verify(
            base64.b64decode(signed["signature"]), catalog_signing_payload(signed["catalog"]))
        entries = signed["catalog"]["entries"]
    entries = [item for item in entries if item["packageID"] != manifest["packageID"]]
    entries.append({
        "packageID": manifest["packageID"], "version": manifest["version"], "kind": "species",
        "displayName": manifest["displayName"],
        "summary": "Offline identification of 504 North American animals.",
        "totalByteCount": sum(item["byteCount"] for item in manifest["artifacts"]),
        "envelopePath": f"{prefix}/envelope.json", "artifactBasePath": prefix,
        "metadata": {"release_channel": "species", "endpoint_tier": "r2.dev-development"},
    })
    catalog = {"schemaVersion": 1, "generatedAt": utc_now(), "entries": entries}
    private = serialization.load_pem_private_key(args.private_key.read_bytes(), password=None)
    key = next(item for item in keys if item["id"] == envelope["keyID"])
    if private.public_key().public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw) != base64.b64decode(key["publicKeyBase64"]):
        raise ValueError("Catalog signing key does not match Release trust")
    output = args.package.parent / "catalog.json"
    if previous is not None:
        backup = args.package.parent / f"catalog-{hashlib.sha256(previous).hexdigest()}.json"
        backup.write_bytes(previous)
        run_rclone(backup, f"{remote}/rollback/{backup.name}", "no-cache", immutable=True)
    output.write_bytes(canonical_json({"catalog": catalog, "keyID": envelope["keyID"],
        "signature": base64.b64encode(private.sign(catalog_signing_payload(catalog))).decode()}))
    catalog_name = "catalog.json" if args.action == "promote" else "candidate-v1.1.0.json"
    run_rclone(output, f"{remote}/{catalog_name}", "no-cache,max-age=0,must-revalidate", immutable=args.action == "stage")
    with fetch(f"{base}/species/{catalog_name}") as response:
        if response.read() != output.read_bytes():
            raise ValueError("Published catalog differs from signed local catalog")
    print(f"{base}/species/{catalog_name}")


if __name__ == "__main__":
    main()
