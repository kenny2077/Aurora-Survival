#!/usr/bin/env python3
"""Build two locally signed development knowledge packs for lifecycle checks."""

from __future__ import annotations

import argparse
import copy
import json
import pathlib
import subprocess
import sys
import tempfile

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey


ROOT = pathlib.Path(__file__).resolve().parents[1]
DEFAULT_KEY = ROOT / ".trailguard" / "development" / "package-signing-key.pem"
DEFAULT_OUTPUT = ROOT / ".trailguard" / "development" / "knowledge-lifecycle"
KEYRING = ROOT / "Resources" / "Packages" / "development_trusted_package_keys.json"
SOURCE = ROOT / "Tests" / "Fixtures" / "development_knowledge_pack.json"
KEY_ID = "development-2026-07"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--private-key", type=pathlib.Path, default=DEFAULT_KEY)
    parser.add_argument("--output-root", type=pathlib.Path, default=DEFAULT_OUTPUT)
    return parser.parse_args()


def build_pack(source: pathlib.Path, output: pathlib.Path, key: pathlib.Path) -> None:
    subprocess.run(
        [
            sys.executable,
            str(ROOT / "tools" / "build_pack.py"),
            "--input",
            str(source),
            "--output",
            str(output),
            "--private-key",
            str(key),
            "--key-id",
            KEY_ID,
            "--display-name",
            "Development Knowledge Lifecycle Fixture",
            "--created-at",
            "2026-07-28T00:00:00Z",
        ],
        check=True,
    )


def main() -> None:
    args = parse_args()
    if not args.private_key.is_file():
        raise SystemExit(
            f"Missing development private key: {args.private_key}\n"
            "Create it with: mkdir -p .trailguard/development && "
            "openssl genpkey -algorithm ED25519 "
            "-out .trailguard/development/package-signing-key.pem"
        )
    if args.output_root.exists():
        raise SystemExit(
            f"Output already exists: {args.output_root}. "
            "Choose a new --output-root or remove the old local fixture."
        )

    private_key = serialization.load_pem_private_key(
        args.private_key.read_bytes(),
        password=None,
    )
    if not isinstance(private_key, Ed25519PrivateKey):
        raise SystemExit("Development package key is not Ed25519")
    public_key = private_key.public_key().public_bytes(
        encoding=serialization.Encoding.Raw,
        format=serialization.PublicFormat.Raw,
    )
    keyring = json.loads(KEYRING.read_text(encoding="utf-8"))
    trusted = next((item for item in keyring if item["id"] == KEY_ID), None)
    if trusted is None:
        raise SystemExit(f"Development keyring is missing {KEY_ID}")
    import base64

    if base64.b64encode(public_key).decode("ascii") != trusted["publicKeyBase64"]:
        raise SystemExit("Local private key does not match the committed development public key")

    source_v1 = json.loads(SOURCE.read_text(encoding="utf-8"))
    source_v2 = copy.deepcopy(source_v1)
    source_v2["version"] = "1.1.0"

    args.output_root.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="trailguard-development-pack-") as temp:
        source_v2_path = pathlib.Path(temp) / "development_knowledge_pack_v2.json"
        source_v2_path.write_text(
            json.dumps(source_v2, ensure_ascii=False, sort_keys=True, indent=2) + "\n",
            encoding="utf-8",
        )
        build_pack(SOURCE, args.output_root / "v1", args.private_key)
        build_pack(source_v2_path, args.output_root / "v2", args.private_key)

    print(args.output_root / "v1")
    print(args.output_root / "v2")


if __name__ == "__main__":
    main()
