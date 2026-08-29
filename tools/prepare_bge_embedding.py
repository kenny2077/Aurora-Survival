#!/usr/bin/env python3
"""Build the pinned BGE-small Expert query embedder with pinned llama.cpp."""

from __future__ import annotations

import argparse
import hashlib
import pathlib
import subprocess
import sys
import tempfile


REPOSITORY = "BAAI/bge-small-en-v1.5"
REVISION = "5c38ec7c405ec4b44b94cc5a9bb96e735b38267a"
FILES = {
    "config.json": (743, "094f8e891b932f2000c92cfc663bac4c62069f5d8af5b5278c4306aef3084750"),
    "model.safetensors": (133_466_304, "3c9f31665447c8911517620762200d2245a2518d6e7208acc78cd9db317e21ad"),
    "tokenizer.json": (711_396, "d241a60d5e8f04cc1b2b3e9ef7a4921b27bf526d9f6050ab90f9267a1f9e5c66"),
    "tokenizer_config.json": (366, "9261e7d79b44c8195c1cada2b453e55b00aeb81e907a6664974b4d7776172ab3"),
    "vocab.txt": (231_508, "07eced375cec144d27c900241f3e339478dec958f92fddbc551f295c992038a3"),
}


def digest(path: pathlib.Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1_048_576), b""):
            value.update(block)
    return value.hexdigest()


def verify_source(root: pathlib.Path) -> None:
    for name, (size, expected) in FILES.items():
        path = root / name
        if not path.is_file() or path.stat().st_size != size:
            raise ValueError(f"pinned source file is missing or has wrong size: {name}")
        if digest(path) != expected:
            raise ValueError(f"pinned source file has wrong SHA-256: {name}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=pathlib.Path, required=True)
    parser.add_argument("--llama-cpp", type=pathlib.Path, required=True)
    parser.add_argument("--output", type=pathlib.Path, required=True)
    parser.add_argument(
        "--python",
        type=pathlib.Path,
        default=pathlib.Path(sys.executable),
        help="Python interpreter containing the pinned llama.cpp conversion dependencies.",
    )
    args = parser.parse_args()
    source = args.source.resolve()
    llama = args.llama_cpp.resolve()
    output = args.output.resolve()
    verify_source(source)
    converter = llama / "convert_hf_to_gguf.py"
    quantizer = llama / "build" / "bin" / "llama-quantize"
    if not converter.is_file() or not quantizer.is_file():
        raise FileNotFoundError(
            "pinned llama.cpp converter/quantizer missing; build commit "
            "aedb2a5e9ca3d4064148bbb919e0ddc0c1b70ab3 first"
        )
    if output.exists():
        raise FileExistsError(output)
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="aurora-bge-", dir=output.parent) as raw:
        f16 = pathlib.Path(raw) / "bge-small-en-v1.5-f16.gguf"
        subprocess.run([
            str(args.python.absolute()), str(converter), str(source),
            "--outfile", str(f16), "--outtype", "f16",
        ], check=True)
        subprocess.run([str(quantizer), str(f16), str(output), "Q8_0"], check=True)
    print(f"identity={REPOSITORY}@{REVISION}")
    print(f"bytes={output.stat().st_size}")
    print(f"sha256={digest(output)}")


if __name__ == "__main__":
    main()
