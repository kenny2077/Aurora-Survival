#!/usr/bin/env python3
"""Create a compressed BioCLIP Core ML encoder challenger and its provenance report."""

from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import shutil
import tempfile
import time

import coremltools as ct
import numpy as np
from coremltools.optimize import coreml as cto


def file_sha256(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def package_fingerprint(root: pathlib.Path) -> tuple[str, int, list[dict[str, object]]]:
    digest = hashlib.sha256()
    total = 0
    files: list[dict[str, object]] = []
    for path in sorted(item for item in root.rglob("*") if item.is_file()):
        relative = path.relative_to(root).as_posix()
        file_digest = file_sha256(path)
        size = path.stat().st_size
        digest.update(relative.encode("utf-8"))
        digest.update(b"\0")
        digest.update(file_digest.encode("ascii"))
        total += size
        files.append({"path": relative, "sha256": file_digest, "byte_count": size})
    return digest.hexdigest(), total, files


def optimize(model: ct.models.MLModel, mode: str) -> ct.models.MLModel:
    if mode == "int8-linear":
        config = cto.OptimizationConfig(
            global_config=cto.OpLinearQuantizerConfig(
                mode="linear_symmetric",
                dtype=np.int8,
                granularity="per_channel",
                weight_threshold=2_048,
            )
        )
        return cto.linear_quantize_weights(model, config=config)
    if mode == "palettized6-kmeans":
        config = cto.OptimizationConfig(
            global_config=cto.OpPalettizerConfig(
                mode="kmeans",
                nbits=6,
                granularity="per_tensor",
                num_kmeans_workers=1,
                weight_threshold=2_048,
            )
        )
        return cto.palettize_weights(model, config=config)
    raise ValueError(f"unsupported mode: {mode}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=pathlib.Path, required=True)
    parser.add_argument("--output", type=pathlib.Path, required=True)
    parser.add_argument("--mode", choices=("int8-linear", "palettized6-kmeans"), required=True)
    parser.add_argument("--report", type=pathlib.Path, required=True)
    args = parser.parse_args()

    if not args.input.is_dir():
        raise FileNotFoundError(args.input)
    if args.output.exists():
        raise FileExistsError(args.output)

    source_digest, source_size, _ = package_fingerprint(args.input)
    started = time.monotonic()
    model = ct.models.MLModel(str(args.input), skip_model_load=True)
    compressed = optimize(model, args.mode)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="aurora-species-opt-", dir=args.output.parent) as temp:
        staged = pathlib.Path(temp) / args.output.name
        compressed.save(str(staged))
        shutil.move(staged, args.output)
    output_digest, output_size, files = package_fingerprint(args.output)

    report = {
        "schema_version": 1,
        "mode": args.mode,
        "source": str(args.input.resolve()),
        "source_sha256": source_digest,
        "source_byte_count": source_size,
        "output": str(args.output.resolve()),
        "output_sha256": output_digest,
        "output_byte_count": output_size,
        "size_reduction_fraction": 1 - output_size / source_size,
        "generation_seconds": time.monotonic() - started,
        "coremltools_version": ct.__version__,
        "files": files,
    }
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps({key: report[key] for key in (
        "mode", "output_byte_count", "size_reduction_fraction", "generation_seconds"
    )}, indent=2))


if __name__ == "__main__":
    main()
