#!/usr/bin/env python3
"""Verify and sign the selected TrailGuard Lite model package."""

from __future__ import annotations

import argparse
import base64
import json
import pathlib
import shutil
import tempfile

from cryptography.hazmat.primitives import serialization

from build_pack import canonical_json, sha256, signing_payload


MODEL_FILENAME = "gemma-3-1b-it-Q4_K_M.gguf"
MODEL_BYTES = 806_058_240
MODEL_SHA256 = "8ccc5cd1f1b3602548715ae25a66ed73fd5dc68a210412eea643eb20eb75a135"
UPSTREAM_REPOSITORY = "ggml-org/gemma-3-1b-it-GGUF"
UPSTREAM_REVISION = "f9c28bcd85737ffc5aef028638d3341d49869c27"
MODEL_IDENTITY = f"{UPSTREAM_REPOSITORY}@{UPSTREAM_REVISION}"
GEMMA_TERMS_URL = "https://ai.google.dev/gemma/terms"
GEMMA_NOTICE = (
    "Gemma is provided under and subject to the Gemma Terms of Use found at "
    "ai.google.dev/gemma/terms\n"
).encode("utf-8")
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
    terms_path = args.terms.resolve()
    output = args.output.resolve()
    private_key_path = args.private_key.resolve()

    verify_artifact(model, MODEL_BYTES, MODEL_SHA256)
    if not terms_path.is_file():
        raise FileNotFoundError(terms_path)
    terms = terms_path.read_bytes()
    decoded_terms = terms.decode("utf-8")
    required_terms_text = (
        "Gemma Terms of Use",
        "Last modified: April 1, 2026",
        "DISTRIBUTION AND RESTRICTIONS",
    )
    if any(value not in decoded_terms for value in required_terms_text):
        raise ValueError("the supplied Gemma terms copy is incomplete or outdated")
    if output.exists():
        raise FileExistsError(f"output already exists: {output}")

    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(
        prefix="trailguard-lite-model-",
        dir=output.parent,
    ) as temporary:
        staging = pathlib.Path(temporary)
        packaged_model = staging / "weights" / MODEL_FILENAME
        packaged_terms = staging / "legal" / "GEMMA_TERMS.md"
        packaged_notice = staging / "legal" / "NOTICE"
        packaged_model.parent.mkdir(parents=True)
        packaged_terms.parent.mkdir(parents=True)
        shutil.copyfile(model, packaged_model)
        shutil.copyfile(terms_path, packaged_terms)
        packaged_notice.write_bytes(GEMMA_NOTICE)

        artifacts = [
            {
                "path": "legal/GEMMA_TERMS.md",
                "byteCount": len(terms),
                "sha256": sha256(packaged_terms),
            },
            {
                "path": "legal/NOTICE",
                "byteCount": len(GEMMA_NOTICE),
                "sha256": sha256(packaged_notice),
            },
            {
                "path": f"weights/{MODEL_FILENAME}",
                "byteCount": MODEL_BYTES,
                "sha256": MODEL_SHA256,
            },
        ]
        manifest = {
            "schemaVersion": 1,
            "packageID": "model.lite.gemma3-1b-q4km",
            "version": args.version,
            "kind": "model",
            "createdAt": args.created_at,
            "minimumAppVersion": args.minimum_app_version,
            "licenseIdentifier": "LicenseRef-Gemma-Terms-2026-04-01",
            "displayName": "TrailGuard Lite — Gemma 3 1B Q4_K_M",
            "artifacts": artifacts,
            "metadata": {
                "artifact_sha256": MODEL_SHA256,
                "chat_template": "embedded",
                "context_tokens": "2048",
                "license_review": "development_only_pending_release_review",
                "model_family": "gemma3",
                "model_identity": MODEL_IDENTITY,
                "maximum_output_tokens": "128",
                "model_path": f"weights/{MODEL_FILENAME}",
                "model_tier": "lite",
                "policy_version": "deterministic-policy-v1",
                "quantization": "Q4_K_M",
                "runtime_release": "b9637",
                "terms_url": GEMMA_TERMS_URL,
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
    parser.add_argument("--terms", type=pathlib.Path, required=True)
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
