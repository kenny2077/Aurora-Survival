#!/usr/bin/env python3
"""Verify and sign the selected Aurora Lite model package."""

from __future__ import annotations

import argparse
import base64
import json
import pathlib
import shutil
import tempfile

from cryptography.hazmat.primitives import serialization

from build_pack import canonical_json, sha256, signing_payload


MODEL_FILENAME = "Phi-3.5-mini-instruct-Q4_K_M.gguf"
MODEL_BYTES = 2_393_232_672
MODEL_SHA256 = "e4165e3a71af97f1b4820da61079826d8752a2088e313af0c7d346796c38eff5"
LICENSE_BYTES = 1_084
LICENSE_SHA256 = "fa8235e5b48faca34e3ca98cf4f694ef08bd216d28b58071a1f85b1d50cb814d"
UPSTREAM_REPOSITORY = "bartowski/Phi-3.5-mini-instruct-GGUF"
UPSTREAM_REVISION = "6d70da17e749a471ccb62ade694486011a75cda3"
ROOT = pathlib.Path(__file__).resolve().parents[1]


def verify_artifact(
    path: pathlib.Path,
    expected_bytes: int,
    expected_sha256: str,
) -> None:
    if not path.is_file():
        raise FileNotFoundError(path)
    if path.stat().st_size != expected_bytes:
        raise ValueError(
            f"unexpected byte count for {path.name}: {path.stat().st_size}"
        )
    actual_sha256 = sha256(path)
    if actual_sha256 != expected_sha256:
        raise ValueError(f"unexpected SHA-256 for {path.name}: {actual_sha256}")


def build(args: argparse.Namespace) -> None:
    model = args.model.resolve()
    license_path = args.license.resolve()
    output = args.output.resolve()
    private_key_path = args.private_key.resolve()

    verify_artifact(model, MODEL_BYTES, MODEL_SHA256)
    verify_artifact(license_path, LICENSE_BYTES, LICENSE_SHA256)
    if output.exists():
        raise FileExistsError(f"output already exists: {output}")

    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(
        prefix="trailguard-lite-model-",
        dir=output.parent,
    ) as temporary:
        staging = pathlib.Path(temporary)
        packaged_model = staging / "weights" / MODEL_FILENAME
        packaged_license = staging / "legal" / "LICENSE.MIT"
        packaged_model.parent.mkdir(parents=True)
        packaged_license.parent.mkdir(parents=True)
        shutil.copyfile(model, packaged_model)
        shutil.copyfile(license_path, packaged_license)

        artifacts = [
            {
                "path": "legal/LICENSE.MIT",
                "byteCount": LICENSE_BYTES,
                "sha256": LICENSE_SHA256,
            },
            {
                "path": f"weights/{MODEL_FILENAME}",
                "byteCount": MODEL_BYTES,
                "sha256": MODEL_SHA256,
            },
        ]
        manifest = {
            "schemaVersion": 1,
            "packageID": "model.lite.phi35-mini-q4km",
            "version": args.version,
            "kind": "model",
            "createdAt": args.created_at,
            "minimumAppVersion": args.minimum_app_version,
            "licenseIdentifier": "MIT",
            "displayName": "Aurora Lite — Phi-3.5 Mini Q4_K_M",
            "artifacts": artifacts,
            "metadata": {
                "artifact_sha256": MODEL_SHA256,
                "chat_template": "phi3_chatml",
                "context_tokens": "2048",
                "maximum_output_tokens": "256",
                "model_path": f"weights/{MODEL_FILENAME}",
                "model_tier": "lite",
                "policy_version": "deterministic-policy-v1",
                "quantization": "Q4_K_M",
                "upstream_repository": UPSTREAM_REPOSITORY,
                "upstream_revision": UPSTREAM_REVISION,
            },
        }

        private_key = serialization.load_pem_private_key(
            private_key_path.read_bytes(),
            password=None,
        )
        trusted_keys = json.loads(args.trusted_keys.read_text(encoding="utf-8"))
        trusted_key = next(
            (item for item in trusted_keys if item["id"] == args.key_id),
            None,
        )
        if trusted_key is None:
            raise ValueError(f"key ID is not trusted: {args.key_id}")
        public_key_base64 = base64.b64encode(
            private_key.public_key().public_bytes(
                encoding=serialization.Encoding.Raw,
                format=serialization.PublicFormat.Raw,
            )
        ).decode("ascii")
        if public_key_base64 != trusted_key["publicKeyBase64"]:
            raise ValueError("private key does not match the trusted key ID")
        payload = signing_payload(manifest)
        signature = private_key.sign(payload)
        private_key.public_key().verify(signature, payload)
        envelope = {
            "keyID": args.key_id,
            "manifest": manifest,
            "signature": base64.b64encode(signature).decode("ascii"),
        }
        (staging / "manifest.json").write_bytes(canonical_json(manifest))
        (staging / "envelope.json").write_bytes(canonical_json(envelope))
        pathlib.Path(temporary).rename(output)

    print(f"PASS: signed Lite model package at {output}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", type=pathlib.Path, required=True)
    parser.add_argument("--license", type=pathlib.Path, required=True)
    parser.add_argument("--output", type=pathlib.Path, required=True)
    parser.add_argument("--private-key", type=pathlib.Path, required=True)
    parser.add_argument(
        "--trusted-keys",
        type=pathlib.Path,
        default=(
            ROOT
            / "Resources"
            / "Packages"
            / "development_trusted_package_keys.json"
        ),
    )
    parser.add_argument("--key-id", required=True)
    parser.add_argument("--version", default="1.0.0")
    parser.add_argument("--created-at", required=True)
    parser.add_argument("--minimum-app-version", default="1.0.0")
    return parser.parse_args()


if __name__ == "__main__":
    build(parse_args())
