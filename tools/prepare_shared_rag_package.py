#!/usr/bin/env python3
"""Build the single signed corpus-v3/BGE/vector package used by both tiers."""

from __future__ import annotations

import argparse
import base64
import json
import pathlib
import shutil
import tempfile

from build_pack import canonical_json, sha256, signing_payload


ROOT = pathlib.Path(__file__).resolve().parents[1]
EMBEDDING_IDENTITY = (
    "BAAI/bge-small-en-v1.5@5c38ec7c405ec4b44b94cc5a9bb96e735b38267a"
)
EMBEDDING_FILENAME = "bge-small-en-v1.5-Q8_0.gguf"
EMBEDDING_BYTES = 36_688_064
EMBEDDING_SHA256 = "cb33d693ed112580cd18269561b356d3348a790ef8c13b0f08c17a2373acc232"


def artifact(path: pathlib.Path, root: pathlib.Path) -> dict[str, object]:
    return {
        "path": path.relative_to(root).as_posix(),
        "byteCount": path.stat().st_size,
        "sha256": sha256(path),
    }


def build(args: argparse.Namespace) -> None:
    from cryptography.hazmat.primitives import serialization

    database = args.database.resolve()
    checksum = database.with_suffix(".sha256")
    embedding = args.embedding.resolve()
    vector_root = args.vector_root.resolve()
    if not database.is_file() or not checksum.is_file():
        raise FileNotFoundError("validated corpus-v3 database/checksum is missing")
    if not embedding.is_file() or embedding.stat().st_size != EMBEDDING_BYTES:
        raise ValueError("pinned BGE Q8_0 artifact has the wrong byte count")
    if sha256(embedding) != EMBEDDING_SHA256:
        raise ValueError("pinned BGE Q8_0 artifact has the wrong SHA-256")
    manifests = sorted(vector_root.glob("*/expert-vector-index.json"))
    if not manifests:
        raise FileNotFoundError("signed vector shard input is missing")
    identities = {
        json.loads(path.read_text(encoding="utf-8"))["corpusIdentity"]
        for path in manifests
    }
    if len(identities) != 1:
        raise ValueError("vector shards do not share one corpus identity")
    corpus_identity = identities.pop()
    output = args.output.resolve()
    if output.exists():
        raise FileExistsError(output)
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="trailguard-shared-rag-", dir=output.parent) as temp:
        staging = pathlib.Path(temp)
        knowledge_out = staging / "knowledge" / database.name
        embedding_out = staging / "weights" / EMBEDDING_FILENAME
        vectors_out = staging / "vectors"
        knowledge_out.parent.mkdir(parents=True)
        embedding_out.parent.mkdir(parents=True)
        shutil.copyfile(database, knowledge_out)
        shutil.copyfile(checksum, knowledge_out.with_suffix(".sha256"))
        shutil.copyfile(embedding, embedding_out)
        shutil.copytree(vector_root, vectors_out)
        artifact_paths = sorted(
            path for path in staging.rglob("*") if path.is_file()
        )
        artifacts = [artifact(path, staging) for path in artifact_paths]
        metadata = {
            "corpus_identity": corpus_identity,
            "embedding_context_tokens": "512",
            "embedding_dimensions": "384",
            "embedding_model_identity": EMBEDDING_IDENTITY,
            "embedding_model_path": f"weights/{EMBEDDING_FILENAME}",
            "embedding_quantization": "Q8_0",
            "knowledge_database_path": f"knowledge/{database.name}",
            "knowledge_index_schema": "3",
            "policy_version": "deterministic-policy-v1",
            "review_status": "approved",
            "shared_rag_contract": "3",
            "vector_index_schema": "3",
            "vector_root_path": "vectors",
        }
        manifest = {
            "schemaVersion": 1,
            "packageID": "knowledge.shared-survival-rag-v3",
            "version": args.version,
            "kind": "knowledge",
            "createdAt": args.created_at,
            "minimumAppVersion": args.minimum_app_version,
            "licenseIdentifier": "LicenseRef-Mixed-Reviewed-Corpus",
            "displayName": "Aurora Shared Survival RAG",
            "artifacts": artifacts,
            "metadata": metadata,
        }
        private_key = serialization.load_pem_private_key(
            args.private_key.read_bytes(), password=None
        )
        payload = signing_payload(manifest)
        signature = private_key.sign(payload)
        envelope = {
            "keyID": args.key_id,
            "manifest": manifest,
            "signature": base64.b64encode(signature).decode("ascii"),
        }
        (staging / "manifest.json").write_bytes(canonical_json(manifest))
        (staging / "envelope.json").write_bytes(canonical_json(envelope))
        pathlib.Path(temp).rename(output)
    print(output)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--database", type=pathlib.Path,
        default=ROOT / "Resources" / "Knowledge" / "survival_knowledge.sqlite",
    )
    parser.add_argument(
        "--vector-root", type=pathlib.Path,
        default=ROOT / "Resources" / "ExpertVectors",
    )
    parser.add_argument("--embedding", type=pathlib.Path, required=True)
    parser.add_argument("--output", type=pathlib.Path, required=True)
    parser.add_argument("--private-key", type=pathlib.Path, required=True)
    parser.add_argument("--key-id", default="development-2026-07")
    parser.add_argument("--version", default="3.1.0-dev")
    parser.add_argument("--created-at", required=True)
    parser.add_argument("--minimum-app-version", default="1.0.0")
    return parser.parse_args()


if __name__ == "__main__":
    build(parse_args())
