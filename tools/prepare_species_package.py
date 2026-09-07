#!/usr/bin/env python3
"""Build a signed Aurora species package from a converted BioCLIP encoder."""

from __future__ import annotations

import argparse
import base64
import json
import pathlib
import shutil
import tempfile

from build_pack import canonical_json, sha256, signing_payload


EXPECTED_COUNT = 504
EXPECTED_DIMENSIONS = 768
ROOT = pathlib.Path(__file__).resolve().parents[1]
ENCODER_PATH = "models/BioCLIP2-ImageEncoder.mlpackage"
TABLE_PATH = "species/species_table.json"
EMBEDDINGS_PATH = "species/species_embeddings.f16.bin"


def validate_inputs(args: argparse.Namespace) -> dict:
    if not args.encoder.is_dir():
        raise FileNotFoundError(f"Core ML encoder package is missing: {args.encoder}")
    if not args.species_table.is_file():
        raise FileNotFoundError(f"Species table is missing: {args.species_table}")
    if not args.embeddings.is_file():
        raise FileNotFoundError(f"Embedding table is missing: {args.embeddings}")
    table = json.loads(args.species_table.read_text(encoding="utf-8"))
    if table.get("dtype") != "float16":
        raise ValueError("species table dtype must be float16")
    if table.get("count") != EXPECTED_COUNT or len(table.get("species", [])) != EXPECTED_COUNT:
        raise ValueError(f"species table must contain {EXPECTED_COUNT} rows")
    if table.get("dim") != EXPECTED_DIMENSIONS:
        raise ValueError(f"species embeddings must have {EXPECTED_DIMENSIONS} dimensions")
    expected_bytes = EXPECTED_COUNT * EXPECTED_DIMENSIONS * 2
    if args.embeddings.stat().st_size != expected_bytes:
        raise ValueError(
            f"embedding binary must be {expected_bytes} bytes, got {args.embeddings.stat().st_size}"
        )
    return table


def build(args: argparse.Namespace) -> None:
    from cryptography.hazmat.primitives import serialization

    validate_inputs(args)
    output = args.output.resolve()
    if output.exists():
        raise FileExistsError(output)
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="aurora-species-", dir=output.parent) as temp:
        staging = pathlib.Path(temp)
        encoder_destination = staging / ENCODER_PATH
        encoder_destination.parent.mkdir(parents=True)
        shutil.copytree(args.encoder, encoder_destination)
        table_destination = staging / TABLE_PATH
        table_destination.parent.mkdir(parents=True)
        shutil.copy2(args.species_table, table_destination)
        embeddings_destination = staging / EMBEDDINGS_PATH
        shutil.copy2(args.embeddings, embeddings_destination)
        notice_destination = staging / "legal" / "BIOCLIP2_NOTICE.md"
        notice_destination.parent.mkdir(parents=True)
        shutil.copy2(args.attribution, notice_destination)

        artifacts = []
        for path in sorted(staging.rglob("*")):
            if path.is_file():
                artifacts.append(
                    {
                        "path": path.relative_to(staging).as_posix(),
                        "byteCount": path.stat().st_size,
                        "sha256": sha256(path),
                    }
                )
        weight_artifacts = [
            item for item in artifacts
            if item["path"].endswith("/Data/com.apple.CoreML/weights/weight.bin")
        ]
        if len(weight_artifacts) != 1:
            raise ValueError("encoder must contain exactly one Core ML weight.bin artifact")

        manifest = {
            "schemaVersion": 1,
            "packageID": args.package_id,
            "version": args.version,
            "kind": "species",
            "createdAt": args.created_at,
            "minimumAppVersion": args.minimum_app_version,
            "licenseIdentifier": "MIT",
            "displayName": "BioCLIP-2 North American Species ID",
            "artifacts": artifacts,
            "metadata": {
                "species_contract": "1",
                "model_identity": "imageomics/bioclip-2",
                "model_revision": args.model_revision,
                "upstream_code_commit": args.upstream_code_commit,
                "encoder_path": ENCODER_PATH,
                "encoder_digest_artifact_path": weight_artifacts[0]["path"],
                "species_table_path": TABLE_PATH,
                "embeddings_path": EMBEDDINGS_PATH,
                "input_side": "224",
                "embedding_dimensions": "768",
                "species_count": "504",
                "softmax_temperature": "100",
            },
        }
        private_key = serialization.load_pem_private_key(
            args.private_key.read_bytes(), password=None
        )
        envelope = {
            "keyID": args.key_id,
            "manifest": manifest,
            "signature": base64.b64encode(
                private_key.sign(signing_payload(manifest))
            ).decode("ascii"),
        }
        (staging / "manifest.json").write_bytes(canonical_json(manifest))
        (staging / "envelope.json").write_bytes(canonical_json(envelope))
        staging.rename(output)
    print(output)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--encoder", type=pathlib.Path, required=True)
    parser.add_argument("--species-table", type=pathlib.Path, required=True)
    parser.add_argument("--embeddings", type=pathlib.Path, required=True)
    parser.add_argument("--output", type=pathlib.Path, required=True)
    parser.add_argument("--private-key", type=pathlib.Path, required=True)
    parser.add_argument("--created-at", required=True)
    parser.add_argument("--key-id", default="development-2026-07")
    parser.add_argument("--package-id", default="species.bioclip2.north-america-504")
    parser.add_argument("--version", default="1.0.0")
    parser.add_argument("--minimum-app-version", default="1.1.0")
    parser.add_argument(
        "--attribution",
        type=pathlib.Path,
        default=ROOT / "Resources" / "Legal" / "BIOCLIP2_NOTICE.md",
    )
    parser.add_argument(
        "--model-revision",
        default="2957b322090f9cb17ae72c71981c7218a28d81e0",
    )
    parser.add_argument(
        "--upstream-code-commit",
        default="be503d235dfa6009645eb06453c8580a79f5dfa1",
    )
    return parser.parse_args()


if __name__ == "__main__":
    build(parse_args())
