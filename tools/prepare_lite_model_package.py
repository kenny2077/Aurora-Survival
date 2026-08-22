#!/usr/bin/env python3
"""Re-sign the pinned Gemma artifact with the shared-RAG dependency contract."""

from __future__ import annotations

import argparse
import base64
import json
import pathlib
import shutil
import tempfile

from build_pack import canonical_json, signing_payload


def build(args: argparse.Namespace) -> None:
    from cryptography.hazmat.primitives import serialization

    source = args.source.resolve()
    output = args.output.resolve()
    envelope = json.loads((source / "envelope.json").read_text(encoding="utf-8"))
    source_manifest = envelope["manifest"]
    if source_manifest["packageID"] != "model.lite.gemma3-1b-q4km":
        raise ValueError("unexpected Lite source package")
    if output.exists():
        raise FileExistsError(output)
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="trailguard-lite-", dir=output.parent) as temp:
        staging = pathlib.Path(temp)
        for artifact in source_manifest["artifacts"]:
            source_file = source / artifact["path"]
            destination = staging / artifact["path"]
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source_file, destination)
        metadata = dict(source_manifest["metadata"])
        metadata.update({
            "required_rag_package_id": "knowledge.shared-survival-rag-v3",
            "required_rag_contract": "3",
        })
        manifest = dict(source_manifest)
        manifest.update({
            "version": args.version,
            "createdAt": args.created_at,
            "minimumAppVersion": args.minimum_app_version,
            "metadata": metadata,
        })
        private_key = serialization.load_pem_private_key(
            args.private_key.read_bytes(), password=None
        )
        payload = signing_payload(manifest)
        signed = {
            "keyID": args.key_id,
            "manifest": manifest,
            "signature": base64.b64encode(private_key.sign(payload)).decode("ascii"),
        }
        (staging / "manifest.json").write_bytes(canonical_json(manifest))
        (staging / "envelope.json").write_bytes(canonical_json(signed))
        pathlib.Path(temp).rename(output)
    print(output)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=pathlib.Path, required=True)
    parser.add_argument("--output", type=pathlib.Path, required=True)
    parser.add_argument("--private-key", type=pathlib.Path, required=True)
    parser.add_argument("--key-id", default="development-2026-07")
    parser.add_argument("--version", default="1.2.0")
    parser.add_argument("--created-at", required=True)
    parser.add_argument("--minimum-app-version", default="1.0.0")
    return parser.parse_args()


if __name__ == "__main__":
    build(parse_args())
