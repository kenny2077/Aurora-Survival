#!/usr/bin/env python3
"""Create Aurora's signed, commit-pinned built-in model catalog."""

from __future__ import annotations

import base64
import json
import pathlib
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
PRIVATE_ROOT = ROOT / ".trailguard" / "release"
CATALOG_PATH = ROOT / "Resources" / "Packages" / "builtin_model_catalog_v2.json"
KEYRING_PATH = ROOT / "Resources" / "Packages" / "trusted_package_keys.json"


def key(path: pathlib.Path) -> pathlib.Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    if not path.exists():
        subprocess.run(
            ["openssl", "genpkey", "-algorithm", "ED25519", "-out", str(path)],
            check=True,
        )
        path.chmod(0o600)
    return path


def public_raw(path: pathlib.Path) -> bytes:
    der = subprocess.run(
        ["openssl", "pkey", "-in", str(path), "-pubout", "-outform", "DER"],
        check=True, capture_output=True,
    ).stdout
    if len(der) < 32:
        raise ValueError("invalid Ed25519 public key")
    return der[-32:]


def sign(path: pathlib.Path, payload: bytes) -> bytes:
    with tempfile.TemporaryDirectory(prefix="aurora-release-sign-") as temp:
        payload_path = pathlib.Path(temp) / "payload"
        signature_path = pathlib.Path(temp) / "signature"
        payload_path.write_bytes(payload)
        subprocess.run([
            "openssl", "pkeyutl", "-sign", "-rawin", "-inkey", str(path),
            "-in", str(payload_path), "-out", str(signature_path),
        ], check=True)
        return signature_path.read_bytes()


def signing_payload(catalog: dict) -> bytes:
    values = ["schema", str(catalog["schemaVersion"]), "generated", catalog["generatedAt"]]
    for entry in sorted(catalog["entries"], key=lambda item: f"{item['packageID']}@{item['version']}"):
        values += [
            "package", entry["packageID"], "version", entry["version"],
            "display", entry["displayName"], "summary", entry["summary"],
            "tier", entry["tier"], "modality", entry["modality"],
            "license", entry["licenseIdentifier"],
            "runtime", entry["minimumRuntimeCommit"],
            "locked", str(entry["expertLocked"]).lower(),
            "envelopeKey", entry["envelope"]["keyID"],
            "envelopeSignature", entry["envelope"]["signature"],
        ]
        for artifact in sorted(entry["artifacts"], key=lambda item: item["filename"]):
            values += [
                "repository", artifact["repository"],
                "revision", artifact["revision"],
                "filename", artifact["filename"],
                "bytes", str(artifact["byteCount"]),
                "sha256", artifact["sha256"],
            ]
    return "\n".join(f"{len(value.encode('utf-8'))}:{value}" for value in values).encode()


def manifest_payload(manifest: dict) -> bytes:
    values = [
        "schema", str(manifest["schemaVersion"]),
        "package", manifest["packageID"], "version", manifest["version"],
        "kind", manifest["kind"], "created", manifest["createdAt"],
        "minimumApp", manifest["minimumAppVersion"],
        "license", manifest["licenseIdentifier"], "display", manifest["displayName"],
    ]
    for artifact in sorted(manifest["artifacts"], key=lambda item: item["path"]):
        values += [
            "artifact", artifact["path"], "bytes", str(artifact["byteCount"]),
            "sha256", artifact["sha256"],
        ]
    for name in sorted(manifest["metadata"]):
        values += ["metadata", name, manifest["metadata"][name]]
    return "\n".join(f"{len(value.encode('utf-8'))}:{value}" for value in values).encode()


def main() -> None:
    primary = key(PRIVATE_ROOT / "aurora-package-primary.key")
    recovery = key(PRIVATE_ROOT / "aurora-package-recovery.key")
    catalog = {
        "schemaVersion": 2,
        "generatedAt": "2026-08-13T00:00:00Z",
        "entries": [
            {
                "packageID": "model-lite-gemma3-1b-q4km",
                "version": "f9c28bcd85737ffc5aef028638d3341d49869c27",
                "displayName": "Aurora Lite",
                "summary": "Fast offline text guidance for iPhone and iPad.",
                "tier": "lite",
                "modality": "text",
                "licenseIdentifier": "LicenseRef-Gemma-Terms-2026-04-01",
                "minimumRuntimeCommit": "aedb2a5e9ca3d4064148bbb919e0ddc0c1b70ab3",
                "expertLocked": False,
                "artifacts": [{
                    "repository": "ggml-org/gemma-3-1b-it-GGUF",
                    "revision": "f9c28bcd85737ffc5aef028638d3341d49869c27",
                    "filename": "gemma-3-1b-it-Q4_K_M.gguf",
                    "byteCount": 806058240,
                    "sha256": "8ccc5cd1f1b3602548715ae25a66ed73fd5dc68a210412eea643eb20eb75a135",
                }],
            },
            {
                "packageID": "model-expert-qwen3vl-2b-q4km",
                "version": "52d6c8ffea26cc873ac5ad116f8631268d7eb503",
                "displayName": "Aurora Expert",
                "summary": "Higher-depth offline text and vision guidance for validated devices.",
                "tier": "vision_expert",
                "modality": "text+vision",
                "licenseIdentifier": "Apache-2.0",
                "minimumRuntimeCommit": "aedb2a5e9ca3d4064148bbb919e0ddc0c1b70ab3",
                "expertLocked": True,
                "artifacts": [
                    {
                        "repository": "Qwen/Qwen3-VL-2B-Instruct-GGUF",
                        "revision": "52d6c8ffea26cc873ac5ad116f8631268d7eb503",
                        "filename": "Qwen3VL-2B-Instruct-Q4_K_M.gguf",
                        "byteCount": 1107409952,
                        "sha256": "089d75c52f4b7ffc56ba998ffc50aae89fcafc755f9e7208aacca281dca6c2ae",
                    },
                    {
                        "repository": "Qwen/Qwen3-VL-2B-Instruct-GGUF",
                        "revision": "52d6c8ffea26cc873ac5ad116f8631268d7eb503",
                        "filename": "mmproj-Qwen3VL-2B-Instruct-Q8_0.gguf",
                        "byteCount": 445053216,
                        "sha256": "f9a68fabba69c3b81e153367b2c7521030b0fa8bb0de400c9599c8e6725f9c82",
                    },
                ],
            },
        ],
    }
    for entry in catalog["entries"]:
        manifest = {
            "schemaVersion": 1,
            "packageID": entry["packageID"],
            "version": entry["version"],
            "kind": "model",
            "createdAt": catalog["generatedAt"],
            "minimumAppVersion": "1.0.0",
            "licenseIdentifier": entry["licenseIdentifier"],
            "displayName": entry["displayName"],
            "artifacts": [{
                "path": artifact["filename"],
                "byteCount": artifact["byteCount"],
                "sha256": artifact["sha256"],
            } for artifact in entry["artifacts"]],
            "metadata": {
                "model_tier": entry["tier"],
                "runtime_commit": entry["minimumRuntimeCommit"],
                "modality": entry["modality"],
            },
        }
        entry["envelope"] = {
            "manifest": manifest,
            "keyID": "aurora-package-primary-2026",
            "signature": base64.b64encode(sign(primary, manifest_payload(manifest))).decode(),
        }
    signature = sign(primary, signing_payload(catalog))
    envelope = {
        "catalog": catalog,
        "keyID": "aurora-package-primary-2026",
        "signature": base64.b64encode(signature).decode(),
    }
    CATALOG_PATH.write_text(json.dumps(envelope, indent=2, sort_keys=True) + "\n")
    keys = [
        ("aurora-package-primary-2026", primary),
        ("aurora-package-recovery-2026", recovery),
    ]
    keyring = [{
        "id": identifier,
        "publicKeyBase64": base64.b64encode(public_raw(value)).decode(),
        "validFrom": "2026-08-13T00:00:00Z",
        "validUntil": "2031-08-13T00:00:00Z",
    } for identifier, value in keys]
    KEYRING_PATH.write_text(json.dumps(keyring, indent=2, sort_keys=True) + "\n")


if __name__ == "__main__":
    main()
