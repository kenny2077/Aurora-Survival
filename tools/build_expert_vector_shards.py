#!/usr/bin/env python3
"""Export Expert embedding units and build deterministic float16 shards."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import pathlib
import sqlite3
import struct
import subprocess
import tempfile


ROOT = pathlib.Path(__file__).resolve().parents[1]
KNOWLEDGE = ROOT / "Resources" / "Knowledge" / "survival_knowledge.sqlite"
CORPUS_V3 = ROOT / "Resources" / "Knowledge" / "expert_corpus_v3.json"
IDENTITY = "BAAI/bge-small-en-v1.5@5c38ec7c405ec4b44b94cc5a9bb96e735b38267a"
DIMENSIONS = 384
MAXIMUM_ROWS = 10_000


def canonical(value: object) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def risk_domain(chapter_id: str) -> str:
    if chapter_id == "car":
        return "vehicle"
    if chapter_id == "first-aid":
        return "first_aid"
    if chapter_id in {"navigation", "signal"}:
        return "navigation"
    return "wilderness"


def export_units() -> list[dict]:
    if not KNOWLEDGE.is_file():
        raise FileNotFoundError("build survival_knowledge.sqlite before vector export")
    units: list[dict] = []
    database = sqlite3.connect(KNOWLEDGE)
    database.row_factory = sqlite3.Row
    try:
        scenarios = database.execute("""
            SELECT scenario_id, chapter_id, title, applicability,
                   observable_cues_json, jurisdiction
            FROM expert_scenarios
            WHERE review_status IN ('primary-source-verified','humanApproved')
            ORDER BY scenario_id
        """).fetchall()
        for scenario in scenarios:
            scenario_id = scenario["scenario_id"]
            claims = database.execute("""
                SELECT claim_id, text FROM expert_claims
                WHERE scenario_id=? ORDER BY display_order
            """, (scenario_id,)).fetchall()
            cues = json.loads(scenario["observable_cues_json"])
            common = {
                "scenarioIDs": [scenario_id],
                "authority": "promoted",
                "domain": risk_domain(scenario["chapter_id"]),
                "jurisdiction": scenario["jurisdiction"],
                "expiresAt": None,
                "superseded": False,
                "unresolvedConflict": False,
                "tombstoned": False,
            }
            units.append({
                "record": {"id": scenario_id, "kind": "scenario", **common},
                "text": " ".join([
                    scenario["title"], scenario["applicability"], *cues,
                    *[item["text"] for item in claims],
                ]),
            })
            for claim in claims:
                units.append({
                    "record": {"id": claim["claim_id"], "kind": "claim", **common},
                    "text": " ".join([
                        scenario["title"], scenario["applicability"], claim["text"],
                    ]),
                })
        chunks = database.execute("""
            SELECT ch.chunk_id, ch.section_path, ch.locator, ch.text,
                   d.authority_tier, d.jurisdiction,
                   d.superseded_by_document_id, d.redistribution_class
            FROM expert_source_chunks ch
            JOIN expert_source_documents d ON d.document_id=ch.document_id
            WHERE d.redistribution_class NOT IN ('linked_metadata_only','development_only')
            ORDER BY ch.chunk_id
        """).fetchall()
        for chunk in chunks:
            scenario_ids = [row[0] for row in database.execute(
                "SELECT scenario_id FROM expert_chunk_scenarios WHERE chunk_id=? ORDER BY scenario_id",
                (chunk["chunk_id"],),
            )]
            units.append({
                "record": {
                    "id": chunk["chunk_id"],
                    "scenarioIDs": scenario_ids,
                    "kind": "source_chunk",
                    "authority": "discovery",
                    "domain": None,
                    "jurisdiction": chunk["jurisdiction"],
                    "expiresAt": None,
                    "superseded": chunk["superseded_by_document_id"] is not None,
                    "unresolvedConflict": False,
                    "tombstoned": False,
                },
                "text": " ".join([
                    chunk["section_path"], chunk["locator"],
                    chunk["text"].replace("\n", " "),
                ]),
            })
    finally:
        database.close()
    units.sort(key=lambda item: item["record"]["id"])
    identifiers = [item["record"]["id"] for item in units]
    if len(identifiers) != len(set(identifiers)):
        raise ValueError("embedding unit IDs are not unique")
    return units


def write_export(output: pathlib.Path) -> None:
    units = export_units()
    payload = b"".join(canonical(item) + b"\n" for item in units)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(payload)
    print(f"wrote {len(units)} embedding units to {output}")


def read_vectors(path: pathlib.Path) -> dict[str, list[float]]:
    result: dict[str, list[float]] = {}
    for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        item = json.loads(line)
        identifier = item.get("id")
        vector = item.get("vector")
        if not isinstance(identifier, str) or identifier in result:
            raise ValueError(f"invalid vector ID on line {line_number}")
        if not isinstance(vector, list) or len(vector) != DIMENSIONS:
            raise ValueError(f"wrong vector dimensions for {identifier}")
        values = [float(value) for value in vector]
        if not all(math.isfinite(value) for value in values):
            raise ValueError(f"non-finite vector for {identifier}")
        norm = math.sqrt(sum(value * value for value in values))
        if not math.isfinite(norm) or norm <= 0:
            raise ValueError(f"zero vector for {identifier}")
        result[identifier] = [value / norm for value in values]
    return result


def embed(
    executable: pathlib.Path,
    model: pathlib.Path,
    output: pathlib.Path,
) -> None:
    if output.exists():
        raise FileExistsError(output)
    if not executable.is_file() or not model.is_file():
        raise FileNotFoundError("llama-embedding executable or BGE GGUF is missing")
    units = export_units()
    if any("\n" in item["text"] for item in units):
        raise ValueError("embedding unit text must be one physical line")
    output.parent.mkdir(parents=True, exist_ok=True)
    embeddings: list[list[float]] = []
    with tempfile.TemporaryDirectory(prefix="trailguard-embedding-") as raw:
        prompts = pathlib.Path(raw) / "prompts.txt"
        for start in range(0, len(units), 8):
            batch = units[start:start + 8]
            prompts.write_text(
                "\n".join(item["text"] for item in batch),
                encoding="utf-8",
            )
            result = subprocess.run([
                str(executable),
                "--model", str(model),
                "--file", str(prompts),
                "--pooling", "cls",
                "--embd-normalize", "2",
                "--embd-output-format", "raw",
                "--ctx-size", "512",
                "--batch-size", "4096",
                "--ubatch-size", "512",
                "--gpu-layers", "0",
                "--no-warmup",
            ], check=True, capture_output=True, text=True)
            batch_embeddings = [
                [float(value) for value in line.split()]
                for line in result.stdout.splitlines()
                if line.strip()
            ]
            if len(batch_embeddings) != len(batch):
                raise ValueError(
                    f"embedder returned {len(batch_embeddings)} rows for "
                    f"batch of {len(batch)} at row {start}"
                )
            embeddings.extend(batch_embeddings)
    if len(embeddings) != len(units):
        raise ValueError(
            f"embedder returned {len(embeddings)} rows for {len(units)} units"
        )
    vectors = []
    for unit, vector in zip(units, embeddings, strict=True):
        if len(vector) != DIMENSIONS:
            raise ValueError(f"wrong embedding shape for {unit['record']['id']}")
        vectors.append(canonical({
            "id": unit["record"]["id"],
            "vector": vector,
        }) + b"\n")
    output.write_bytes(b"".join(vectors))
    print(f"wrote {len(vectors)} normalized BGE vectors to {output}")


def build(output: pathlib.Path, vectors_path: pathlib.Path) -> None:
    if output.exists():
        raise FileExistsError(output)
    units = export_units()
    vectors = read_vectors(vectors_path)
    expected = {item["record"]["id"] for item in units}
    if set(vectors) != expected:
        raise ValueError("vector IDs do not exactly match exported embedding units")
    output.mkdir(parents=True)
    for shard_number, start in enumerate(range(0, len(units), MAXIMUM_ROWS)):
        selected = units[start:start + MAXIMUM_ROWS]
        shard = output / f"expert-vector-shard-{shard_number:03d}"
        shard.mkdir()
        records = [item["record"] for item in selected]
        records_data = canonical(records)
        vector_data = bytearray()
        for item in selected:
            for value in vectors[item["record"]["id"]]:
                vector_data.extend(struct.pack("<e", value))
        records_path = shard / "records.json"
        vectors_path_out = shard / "vectors.f16"
        metadata_path = shard / "metadata.sqlite"
        records_path.write_bytes(records_data)
        vectors_path_out.write_bytes(vector_data)
        database = sqlite3.connect(metadata_path)
        try:
            database.executescript("""
                PRAGMA page_size=4096;
                PRAGMA journal_mode=OFF;
                PRAGMA synchronous=OFF;
                PRAGMA auto_vacuum=NONE;
                PRAGMA application_id=1414678358;
                PRAGMA user_version=3;
                CREATE TABLE records(
                    rowid INTEGER PRIMARY KEY,
                    stable_id TEXT NOT NULL UNIQUE,
                    text TEXT NOT NULL,
                    record_json BLOB NOT NULL
                );
                CREATE VIRTUAL TABLE records_fts USING fts5(
                    stable_id UNINDEXED,
                    text,
                    tokenize='unicode61 remove_diacritics 2'
                );
            """)
            for rowid, item in enumerate(selected, start=1):
                record_json = canonical(item["record"])
                database.execute(
                    "INSERT INTO records(rowid,stable_id,text,record_json) VALUES(?,?,?,?)",
                    (rowid, item["record"]["id"], item["text"], record_json),
                )
                database.execute(
                    "INSERT INTO records_fts(rowid,stable_id,text) VALUES(?,?,?)",
                    (rowid, item["record"]["id"], item["text"]),
                )
            database.commit()
            database.execute("VACUUM")
        finally:
            database.close()
        metadata_data = metadata_path.read_bytes()
        manifest = {
            "schemaVersion": 3,
            "shardID": shard.name,
            "embeddingIdentity": IDENTITY,
            "corpusIdentity": sha256(CORPUS_V3.read_bytes()),
            "dimensions": DIMENSIONS,
            "vectorCount": len(selected),
            "vectorPath": "vectors.f16",
            "vectorSHA256": sha256(vector_data),
            "recordsPath": "records.json",
            "recordsSHA256": sha256(records_data),
            "metadataPath": "metadata.sqlite",
            "metadataSHA256": sha256(metadata_data),
        }
        (shard / "expert-vector-index.json").write_bytes(canonical(manifest))
    print(f"wrote {len(units)} vectors in {(len(units) + MAXIMUM_ROWS - 1) // MAXIMUM_ROWS} shard(s)")


def main() -> None:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)
    export = subparsers.add_parser("export")
    export.add_argument("--output", type=pathlib.Path, required=True)
    embedding = subparsers.add_parser("embed")
    embedding.add_argument("--llama-embedding", type=pathlib.Path, required=True)
    embedding.add_argument("--model", type=pathlib.Path, required=True)
    embedding.add_argument("--output", type=pathlib.Path, required=True)
    package = subparsers.add_parser("build")
    package.add_argument("--vectors-jsonl", type=pathlib.Path, required=True)
    package.add_argument("--output", type=pathlib.Path, required=True)
    args = parser.parse_args()
    if args.command == "export":
        write_export(args.output.resolve())
    elif args.command == "embed":
        embed(
            args.llama_embedding.resolve(),
            args.model.resolve(),
            args.output.resolve(),
        )
    else:
        build(args.output.resolve(), args.vectors_jsonl.resolve())


if __name__ == "__main__":
    main()
