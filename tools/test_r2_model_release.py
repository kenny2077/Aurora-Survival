#!/usr/bin/env python3

import argparse
import json
import pathlib
import tempfile
import unittest
from unittest import mock
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

import publish_r2_models as release


class R2ModelReleaseTests(unittest.TestCase):
    def test_prepare_refuses_to_overwrite_release(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            (root / "beta").mkdir()
            args = argparse.Namespace(output=root, channel="beta")
            with self.assertRaises(FileExistsError):
                release.prepare(args)

    def test_catalog_requires_shared_dependency_on_each_model(self) -> None:
        catalog = {
            "schemaVersion": 1,
            "generatedAt": "2026-08-27T00:00:00Z",
            "entries": [
                {
                    "packageID": "model.lite.gemma3-1b-q4km", "version": "1",
                    "kind": "model", "displayName": "Lite", "summary": "Lite", "totalByteCount": 1,
                    "envelopePath": "packages/lite/1/envelope.json", "artifactBasePath": "packages/lite/1",
                    "metadata": {},
                },
                {
                    "packageID": "knowledge.shared-survival-rag-v3", "version": "3",
                    "kind": "knowledge", "displayName": "RAG", "summary": "RAG", "totalByteCount": 1,
                    "envelopePath": "packages/rag/3/envelope.json", "artifactBasePath": "packages/rag/3",
                    "metadata": {},
                },
            ],
        }
        private = Ed25519PrivateKey.generate()
        public = private.public_key().public_bytes(
            release.serialization.Encoding.Raw, release.serialization.PublicFormat.Raw
        )
        signed = {
            "catalog": catalog, "keyID": release.KEY_ID,
            "signature": release.base64.b64encode(private.sign(release.catalog_signing_payload(catalog))).decode(),
        }
        with mock.patch.object(release, "load_keyring", return_value=[{
            "id": release.KEY_ID,
            "publicKeyBase64": release.base64.b64encode(public).decode(),
        }]), self.assertRaisesRegex(ValueError, "dependency mismatch"):
            release.validate_catalog(signed)

    def test_production_keyring_excludes_development_keys(self) -> None:
        production_ids = {key["id"] for key in release.load_keyring(production=True)}
        self.assertNotIn(release.KEY_ID, production_ids)
        self.assertIn("aurora-package-primary-2026", production_ids)
        self.assertIn(release.KEY_ID, {key["id"] for key in release.load_keyring()})

    def test_production_catalog_rejects_development_signature(self) -> None:
        signed = {"catalog": {"entries": []}, "keyID": release.KEY_ID, "signature": ""}
        with self.assertRaisesRegex(ValueError, "untrusted catalog signing key"):
            release.validate_catalog(signed, production=True)

    def test_public_range_probe_requires_partial_content(self) -> None:
        with mock.patch.object(release.urllib.request, "urlopen") as urlopen:
            response = urlopen.return_value.__enter__.return_value
            response.status = 206
            self.assertEqual(release.public_status("https://models.invalid/file", True), 206)
            request = urlopen.call_args.args[0]
            self.assertEqual(request.headers["Range"], "bytes=0-0")


if __name__ == "__main__":
    unittest.main()
