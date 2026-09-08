#!/usr/bin/env python3
"""Regression tests for public species artifact verification."""

import hashlib
import io
import unittest
from unittest.mock import patch

from publish_species_release import verify_remote


class Response(io.BytesIO):
    def __init__(self, data, status=200, headers=None):
        super().__init__(data)
        self.status = status
        self.headers = headers or {}


class SpeciesReleaseTests(unittest.TestCase):
    expected = {"byteCount": 3, "sha256": hashlib.sha256(b"abc").hexdigest()}

    def test_verified_bytes_and_exact_range_pass(self):
        with patch("publish_species_release.fetch", side_effect=[
            Response(b"abc"), Response(b"a", 206, {"Content-Range": "bytes 0-0/3"})
        ]):
            verify_remote("https://example.com/artifact", self.expected)

    def test_tampered_bytes_fail(self):
        with patch("publish_species_release.fetch", return_value=Response(b"abd")):
            with self.assertRaisesRegex(ValueError, "hash or size"):
                verify_remote("https://example.com/artifact", self.expected)

    def test_ignored_range_fails(self):
        with patch("publish_species_release.fetch", side_effect=[Response(b"abc"), Response(b"abc")]):
            with self.assertRaisesRegex(ValueError, "byte ranges"):
                verify_remote("https://example.com/artifact", self.expected)


if __name__ == "__main__":
    unittest.main()
