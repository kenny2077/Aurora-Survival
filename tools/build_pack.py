#!/usr/bin/env python3
"""Build a deterministic, signed Aurora knowledge package.

The input must already contain reviewed text, source/license metadata, and
precomputed embeddings. This tool never invents medical, survival, or vehicle
content and never computes embeddings during the release build.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import pathlib
import sqlite3
import struct
import tempfile
from typing import Any

from cryptography.hazmat.primitives import serialization


def canonical_json(value: Any) -> bytes:
    return (
        json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
        + "\n"
    ).encode("utf-8")


def sha256(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def signing_payload(manifest: dict[str, Any]) -> bytes:
    fields = [
        "schema", str(manifest["schemaVersion"]),
        "package", manifest["packageID"],
        "version", manifest["version"],
        "kind", manifest["kind"],
        "created", manifest["createdAt"],
        "minimumApp", manifest["minimumAppVersion"],
        "license", manifest["licenseIdentifier"],
        "display", manifest["displayName"],
    ]
    for artifact in sorted(manifest["artifacts"], key=lambda item: item["path"]):
        fields.extend(
            [
                "artifact", artifact["path"],
                "bytes", str(artifact["byteCount"]),
                "sha256", artifact["sha256"],
            ]
        )
    for key in sorted(manifest["metadata"]):
        fields.extend(["metadata", key, manifest["metadata"][key]])
    return "\n".join(f"{len(field.encode('utf-8'))}:{field}" for field in fields).encode()


def validate_input(pack: dict[str, Any]) -> None:
    required = {
        "schema_version", "package_id", "version", "domain", "locale",
        "effective_date", "license", "review", "records",
    }
    missing = required - pack.keys()
    if missing:
        raise ValueError(f"missing pack fields: {sorted(missing)}")
    if pack["review"]["status"] not in {"development_fixture", "approved"}:
        raise ValueError("recalled or unknown review status cannot be built")
    if not pack["records"]:
        raise ValueError("knowledge pack must include records")

    evidence_ids: set[str] = set()
    dimensions: set[int] = set()
    for record in pack["records"]:
        evidence_id = record["evidence_id"]
        if evidence_id in evidence_ids:
            raise ValueError(f"duplicate evidence id: {evidence_id}")
        evidence_ids.add(evidence_id)
        embedding = record.get("embedding")
        if not embedding or len(embedding) < 4:
            raise ValueError(f"precomputed embedding missing: {evidence_id}")
        dimensions.add(len(embedding))
        if not record["source"].get("source_id"):
            raise ValueError(f"source metadata missing: {evidence_id}")
    if len(dimensions) != 1:
        raise ValueError("all embeddings must have the same dimensions")


def build_sqlite(pack: dict[str, Any], output: pathlib.Path) -> None:
    connection = sqlite3.connect(output)
    try:
        connection.executescript(
            """
            PRAGMA page_size=4096;
            PRAGMA journal_mode=DELETE;
            PRAGMA synchronous=FULL;
            PRAGMA auto_vacuum=NONE;
            CREATE TABLE pack_metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL);
            CREATE TABLE evidence (
                evidence_id TEXT PRIMARY KEY,
                title TEXT NOT NULL,
                summary TEXT NOT NULL,
                steps_json TEXT NOT NULL,
                warnings_json TEXT NOT NULL,
                keywords_json TEXT NOT NULL,
                source_json TEXT NOT NULL,
                applicability_json TEXT NOT NULL,
                supported_answer_level TEXT NOT NULL,
                vector_offset INTEGER NOT NULL,
                vector_dimensions INTEGER NOT NULL
            );
            CREATE VIRTUAL TABLE evidence_fts USING fts5(
                evidence_id UNINDEXED,
                title,
                summary,
                steps,
                warnings,
                keywords,
                tokenize='unicode61 remove_diacritics 2'
            );
            """
        )
        metadata = {
            "package_id": pack["package_id"],
            "version": pack["version"],
            "domain": pack["domain"],
            "locale": pack["locale"],
            "effective_date": pack["effective_date"],
            "review_attestation_id": pack["review"]["attestation_id"],
        }
        connection.executemany(
            "INSERT INTO pack_metadata(key, value) VALUES (?, ?)",
            sorted(metadata.items()),
        )
        offset = 0
        for record in sorted(pack["records"], key=lambda item: item["evidence_id"]):
            dimensions = len(record["embedding"])
            values = (
                record["evidence_id"],
                record["title"],
                record["summary"],
                json.dumps(record["steps"], ensure_ascii=False, separators=(",", ":")),
                json.dumps(record["warnings"], ensure_ascii=False, separators=(",", ":")),
                json.dumps(record["keywords"], ensure_ascii=False, separators=(",", ":")),
                json.dumps(record["source"], ensure_ascii=False, sort_keys=True, separators=(",", ":")),
                json.dumps(record["applicability"], ensure_ascii=False, sort_keys=True, separators=(",", ":")),
                record["supported_answer_level"],
                offset,
                dimensions,
            )
            connection.execute(
                """
                INSERT INTO evidence VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                values,
            )
            connection.execute(
                "INSERT INTO evidence_fts VALUES (?, ?, ?, ?, ?, ?)",
                (
                    record["evidence_id"],
                    record["title"],
                    record["summary"],
                    "\n".join(record["steps"]),
                    "\n".join(record["warnings"]),
                    " ".join(record["keywords"]),
                ),
            )
            offset += dimensions * 4
        connection.commit()
        connection.execute("VACUUM")
    finally:
        connection.close()


def build_vectors(pack: dict[str, Any], output: pathlib.Path) -> None:
    with output.open("wb") as stream:
        for record in sorted(pack["records"], key=lambda item: item["evidence_id"]):
            stream.write(struct.pack(f"<{len(record['embedding'])}f", *record["embedding"]))


def build(args: argparse.Namespace) -> None:
    source_path = args.input.resolve()
    output = args.output.resolve()
    pack = json.loads(source_path.read_text(encoding="utf-8"))
    validate_input(pack)

    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="trailguard-pack-", dir=output.parent) as temp:
        staging = pathlib.Path(temp)
        content_path = staging / "content.sqlite"
        vector_path = staging / "vectors.bin"
        source_manifest_path = staging / "source-manifest.json"
        build_sqlite(pack, content_path)
        build_vectors(pack, vector_path)
        source_manifest_path.write_bytes(canonical_json(pack))

        artifacts = []
        for path in sorted((content_path, source_manifest_path, vector_path)):
            artifacts.append(
                {
                    "path": path.name,
                    "byteCount": path.stat().st_size,
                    "sha256": sha256(path),
                }
            )
        manifest = {
            "schemaVersion": 1,
            "packageID": pack["package_id"],
            "version": pack["version"],
            "kind": "knowledge",
            "createdAt": args.created_at,
            "minimumAppVersion": args.minimum_app_version,
            "licenseIdentifier": pack["license"]["identifier"],
            "displayName": args.display_name,
            "artifacts": artifacts,
            "metadata": {
                "attestation_id": pack["review"]["attestation_id"],
                "domain": pack["domain"],
                "locale": pack["locale"],
                "review_status": pack["review"]["status"],
            },
        }

        private_key = serialization.load_pem_private_key(
            args.private_key.read_bytes(),
            password=None,
        )
        signature = private_key.sign(signing_payload(manifest))
        envelope = {
            "keyID": args.key_id,
            "manifest": manifest,
            "signature": base64.b64encode(signature).decode("ascii"),
        }
        (staging / "manifest.json").write_bytes(canonical_json(manifest))
        (staging / "envelope.json").write_bytes(canonical_json(envelope))

        if output.exists():
            raise FileExistsError(f"output already exists: {output}")
        staging.rename(output)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=pathlib.Path, required=True)
    parser.add_argument("--output", type=pathlib.Path, required=True)
    parser.add_argument("--private-key", type=pathlib.Path, required=True)
    parser.add_argument("--key-id", required=True)
    parser.add_argument("--display-name", required=True)
    parser.add_argument("--created-at", required=True)
    parser.add_argument("--minimum-app-version", default="1.0.0")
    return parser.parse_args()


if __name__ == "__main__":
    build(parse_args())
