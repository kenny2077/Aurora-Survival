#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import pathlib
import sys
import tempfile
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from prepare_species_package import EXPECTED_COUNT, EXPECTED_DIMENSIONS, validate_inputs


class SpeciesPackagingTests(unittest.TestCase):
    def test_accepts_expected_table_and_binary(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            args = self.make_args(pathlib.Path(temp))
            table = validate_inputs(args)
            self.assertEqual(table["count"], EXPECTED_COUNT)

    def test_rejects_truncated_embedding_binary(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            args = self.make_args(pathlib.Path(temp))
            args.embeddings.write_bytes(b"\0\0")
            with self.assertRaisesRegex(ValueError, "embedding binary"):
                validate_inputs(args)

    def test_rejects_wrong_dimensions(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            args = self.make_args(pathlib.Path(temp))
            table = json.loads(args.species_table.read_text())
            table["dim"] = 512
            args.species_table.write_text(json.dumps(table))
            with self.assertRaisesRegex(ValueError, "768 dimensions"):
                validate_inputs(args)

    @staticmethod
    def make_args(root: pathlib.Path) -> argparse.Namespace:
        encoder = root / "encoder.mlpackage"
        encoder.mkdir()
        species_table = root / "species_table.json"
        species_table.write_text(json.dumps({
            "dtype": "float16",
            "dim": EXPECTED_DIMENSIONS,
            "count": EXPECTED_COUNT,
            "species": [{} for _ in range(EXPECTED_COUNT)],
        }))
        embeddings = root / "species_embeddings.f16.bin"
        embeddings.write_bytes(b"\0" * (EXPECTED_COUNT * EXPECTED_DIMENSIONS * 2))
        return argparse.Namespace(
            encoder=encoder,
            species_table=species_table,
            embeddings=embeddings,
        )


if __name__ == "__main__":
    unittest.main()
