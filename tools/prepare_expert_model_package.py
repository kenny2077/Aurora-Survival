#!/usr/bin/env python3
"""Verify and sign the pinned Aurora Expert model/projector package."""

from __future__ import annotations

import argparse
import base64
import json
import pathlib
import shutil
import tempfile

from build_pack import canonical_json, sha256, signing_payload


REPOSITORY = "Qwen/Qwen3-VL-2B-Instruct-GGUF"
REVISION = "52d6c8ffea26cc873ac5ad116f8631268d7eb503"
MODEL_FILENAME = "Qwen3VL-2B-Instruct-Q4_K_M.gguf"
MODEL_BYTES = 1_107_409_952
MODEL_SHA256 = "089d75c52f4b7ffc56ba998ffc50aae89fcafc755f9e7208aacca281dca6c2ae"
PROJECTOR_FILENAME = "mmproj-Qwen3VL-2B-Instruct-Q8_0.gguf"
PROJECTOR_BYTES = 445_053_216
PROJECTOR_SHA256 = "f9a68fabba69c3b81e153367b2c7521030b0fa8bb0de400c9599c8e6725f9c82"
MODEL_IDENTITY = f"{REPOSITORY}@{REVISION}"
PROJECTOR_IDENTITY = f"{MODEL_IDENTITY}:mmproj-Q8_0"
ROOT = pathlib.Path(__file__).resolve().parents[1]


def verify(path: pathlib.Path, size: int, digest: str) -> None:
    if not path.is_file():
        raise FileNotFoundError(path)
    if path.stat().st_size != size:
        raise ValueError(f"unexpected byte count for {path.name}")
    actual = sha256(path)
    if actual != digest:
        raise ValueError(f"unexpected SHA-256 for {path.name}: {actual}")


def validate_memory_profile_args(args: argparse.Namespace) -> None:
    peaks = [args.peak_full, args.peak_balanced, args.peak_constrained]
    if args.memory_profile_status == "retained":
        if any(value is None or value <= 0 for value in peaks):
            raise ValueError("all retained peak-memory measurements must be positive")
    elif any(value is not None for value in peaks):
        raise ValueError("calibration packages must not contain guessed peak-memory values")


def build(args: argparse.Namespace) -> None:
    from cryptography.hazmat.primitives import serialization

    model = args.model.resolve()
    projector = args.projector.resolve()
    output = args.output.resolve()
    verify(model, MODEL_BYTES, MODEL_SHA256)
    verify(projector, PROJECTOR_BYTES, PROJECTOR_SHA256)
    validate_memory_profile_args(args)
    if output.exists():
        raise FileExistsError(f"output already exists: {output}")

    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="aurora-expert-", dir=output.parent) as temp:
        staging = pathlib.Path(temp)
        model_out = staging / "weights" / MODEL_FILENAME
        projector_out = staging / "weights" / PROJECTOR_FILENAME
        model_out.parent.mkdir(parents=True)
        shutil.copyfile(model, model_out)
        shutil.copyfile(projector, projector_out)
        artifacts = [
            {"path": f"weights/{MODEL_FILENAME}", "byteCount": MODEL_BYTES, "sha256": MODEL_SHA256},
            {"path": f"weights/{PROJECTOR_FILENAME}", "byteCount": PROJECTOR_BYTES, "sha256": PROJECTOR_SHA256},
        ]
        metadata = {
            "chat_template": "embedded",
            "context_tokens": "8192",
            "license_review": "development_only_pending_release_review",
            "maximum_output_tokens": "256",
            "memory_profile_status": args.memory_profile_status,
            "model_family": "qwen3vl",
            "model_identity": MODEL_IDENTITY,
            "model_path": f"weights/{MODEL_FILENAME}",
            "model_tier": "vision_expert",
            "policy_version": "deterministic-policy-v1",
            "quantization": "Q4_K_M",
            "runtime_commit": "aedb2a5e9ca3d4064148bbb919e0ddc0c1b70ab3",
            "runtime_release": "b9637",
            "upstream_repository": REPOSITORY,
            "upstream_revision": REVISION,
            "vision_projector_identity": PROJECTOR_IDENTITY,
            "vision_projector_path": f"weights/{PROJECTOR_FILENAME}",
            "vision_projector_quantization": "Q8_0",
            "required_rag_package_id": "knowledge.shared-survival-rag-v3",
            "required_rag_contract": "3",
        }
        if args.memory_profile_status == "retained":
            metadata.update({
                "peak_memory_balanced_bytes": str(args.peak_balanced),
                "peak_memory_constrained_bytes": str(args.peak_constrained),
                "peak_memory_full_bytes": str(args.peak_full),
            })
        manifest = {
            "schemaVersion": 1,
            "packageID": "model.expert.qwen3vl-2b-q4km-q8",
            "version": args.version,
            "kind": "model",
            "createdAt": args.created_at,
            "minimumAppVersion": args.minimum_app_version,
            "licenseIdentifier": "Apache-2.0",
            "displayName": "Aurora Expert — Qwen3-VL 2B",
            "artifacts": artifacts,
            "metadata": metadata,
        }
        private_key = serialization.load_pem_private_key(
            args.private_key.read_bytes(), password=None
        )
        trusted = json.loads(args.trusted_keys.read_text(encoding="utf-8"))
        key = next((item for item in trusted if item["id"] == args.key_id), None)
        if key is None:
            raise ValueError(f"key ID is not trusted: {args.key_id}")
        actual_public = base64.b64encode(private_key.public_key().public_bytes(
            encoding=serialization.Encoding.Raw,
            format=serialization.PublicFormat.Raw,
        )).decode("ascii")
        if actual_public != key["publicKeyBase64"]:
            raise ValueError("private key does not match trusted key ID")
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
        pathlib.Path(temp).rename(output)
    print(f"PASS: signed development Expert package at {output}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", type=pathlib.Path, required=True)
    parser.add_argument("--projector", type=pathlib.Path, required=True)
    parser.add_argument(
        "--memory-profile-status",
        choices=("calibration", "retained"),
        default="retained",
    )
    parser.add_argument("--peak-full", type=int)
    parser.add_argument("--peak-balanced", type=int)
    parser.add_argument("--peak-constrained", type=int)
    parser.add_argument("--output", type=pathlib.Path, required=True)
    parser.add_argument("--private-key", type=pathlib.Path, required=True)
    parser.add_argument("--trusted-keys", type=pathlib.Path, default=(
        ROOT / "Resources" / "Packages" / "development_trusted_package_keys.json"
    ))
    parser.add_argument("--key-id", required=True)
    parser.add_argument("--version", default="0.5.0-dev")
    parser.add_argument("--created-at", required=True)
    parser.add_argument("--minimum-app-version", default="1.0.0")
    return parser.parse_args()


if __name__ == "__main__":
    build(parse_args())
