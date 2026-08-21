#!/usr/bin/env python3
"""Build a deterministic 100,000-row float16 exact-search device fixture."""

from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import sqlite3
import struct


IDENTITY = "BAAI/bge-small-en-v1.5@5c38ec7c405ec4b44b94cc5a9bb96e735b38267a"
DIMENSIONS = 384
ROWS_PER_SHARD = 10_000
SHARD_COUNT = 10


def canonical(value: object) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode()


def sha256(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def build(output: pathlib.Path) -> None:
    if output.exists():
        raise FileExistsError(output)
    output.mkdir(parents=True)
    half_zero = struct.pack("<e", 0.0)
    half_one = struct.pack("<e", 1.0)
    for shard_number in range(SHARD_COUNT):
        shard_id = f"expert-vector-benchmark-{shard_number:03d}"
        shard = output / shard_id
        shard.mkdir()
        vectors = shard / "vectors.f16"
        records_path = shard / "records.json"
        metadata = shard / "metadata.sqlite"
        with vectors.open("wb") as stream:
            for row in range(ROWS_PER_SHARD):
                column = (shard_number * ROWS_PER_SHARD + row) % DIMENSIONS
                stream.write(half_zero * column)
                stream.write(half_one)
                stream.write(half_zero * (DIMENSIONS - column - 1))
        records = []
        for row in range(ROWS_PER_SHARD):
            global_row = shard_number * ROWS_PER_SHARD + row
            records.append({
                "id": f"benchmark-{global_row:06d}",
                "scenarioIDs": ["benchmark-scenario"],
                "kind": "claim",
                "authority": "promoted",
                "domain": "wilderness",
                "jurisdiction": "global",
                "expiresAt": None,
                "superseded": False,
                "unresolvedConflict": False,
                "tombstoned": False,
            })
        records_path.write_bytes(canonical(records))
        connection = sqlite3.connect(metadata)
        connection.execute("PRAGMA journal_mode=OFF")
        connection.execute("CREATE TABLE records(id TEXT PRIMARY KEY, row_number INTEGER NOT NULL)")
        connection.executemany(
            "INSERT INTO records VALUES (?, ?)",
            ((item["id"], row) for row, item in enumerate(records)),
        )
        connection.commit()
        connection.close()
        manifest = {
            "schemaVersion": 1,
            "shardID": shard_id,
            "embeddingIdentity": IDENTITY,
            "dimensions": DIMENSIONS,
            "vectorCount": ROWS_PER_SHARD,
            "vectorPath": vectors.name,
            "vectorSHA256": sha256(vectors),
            "recordsPath": records_path.name,
            "recordsSHA256": sha256(records_path),
            "metadataPath": metadata.name,
            "metadataSHA256": sha256(metadata),
        }
        (shard / "expert-vector-index.json").write_bytes(canonical(manifest))
    print(f"wrote {SHARD_COUNT * ROWS_PER_SHARD} rows to {output}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=pathlib.Path, required=True)
    build(parser.parse_args().output)


if __name__ == "__main__":
    main()
