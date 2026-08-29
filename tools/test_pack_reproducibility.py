#!/usr/bin/env python3
"""Verify byte-for-byte deterministic knowledge pack builds."""

from __future__ import annotations

import filecmp
import pathlib
import subprocess
import sys
import tempfile

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey


ROOT = pathlib.Path(__file__).resolve().parents[1]


def build(output: pathlib.Path, key_path: pathlib.Path) -> None:
    subprocess.run(
        [
            sys.executable,
            str(ROOT / "tools" / "build_pack.py"),
            "--input",
            str(ROOT / "Tests" / "Fixtures" / "development_knowledge_pack.json"),
            "--output",
            str(output),
            "--private-key",
            str(key_path),
            "--key-id",
            "reproducibility-test",
            "--display-name",
            "Development Knowledge Fixture",
            "--created-at",
            "2026-07-23T00:00:00Z",
        ],
        check=True,
    )


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="aurora-repro-") as temp:
        root = pathlib.Path(temp)
        key = Ed25519PrivateKey.generate()
        key_path = root / "private.pem"
        key_path.write_bytes(
            key.private_bytes(
                encoding=serialization.Encoding.PEM,
                format=serialization.PrivateFormat.PKCS8,
                encryption_algorithm=serialization.NoEncryption(),
            )
        )
        first = root / "first"
        second = root / "second"
        build(first, key_path)
        build(second, key_path)

        comparison = filecmp.dircmp(first, second)
        if comparison.left_only or comparison.right_only or comparison.diff_files:
            raise SystemExit(
                "FAIL: pack builds differ: "
                f"left={comparison.left_only}, right={comparison.right_only}, "
                f"changed={comparison.diff_files}"
            )
        for path in first.iterdir():
            if not filecmp.cmp(path, second / path.name, shallow=False):
                raise SystemExit(f"FAIL: artifact differs: {path.name}")
        print(f"PASS: reproducible pack with {len(list(first.iterdir()))} files")


if __name__ == "__main__":
    main()
