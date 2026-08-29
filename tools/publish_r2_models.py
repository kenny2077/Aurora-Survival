#!/usr/bin/env python3
"""Prepare, validate, publish, and probe Aurora's signed v1 R2 model catalog."""

from __future__ import annotations

import argparse
import base64
import datetime as dt
import hashlib
import json
import os
import pathlib
import shutil
import subprocess
import tempfile
import urllib.error
import urllib.request

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey

from build_pack import canonical_json, signing_payload
from prepare_expert_catalog import catalog_signing_payload


ROOT = pathlib.Path(__file__).resolve().parents[1]
BUCKET = "aurora-survival-models"
KEY_ID = "development-2026-07"
PUBLIC_USER_AGENT = "AuroraReleasePublisher/1.0"
PACKAGE_SPECS = (
    (
        "lite",
        ROOT / ".trailguard/development/model-lite-gemma3-1b-q4km-dev@1.2.0",
        "1.2.0-beta.1",
    ),
    (
        "expert",
        ROOT / ".trailguard/development/model.expert.qwen3vl-2b-q4km-q8@0.4.0-dev",
        "0.4.0-beta.1",
    ),
    (
        "rag",
        ROOT / ".trailguard/development/knowledge-shared-rag-v3@3.2.0-dev",
        "3.2.0-beta.1",
    ),
)
LEGAL_FILES = {
    "lite": (
        ("legal/GEMMA_MODIFICATIONS_NOTICE.md", "Resources/Legal/GEMMA_MODIFICATIONS_NOTICE.md"),
    ),
    "expert": (
        ("legal/LICENSE.APACHE-2.0", "Resources/Legal/LICENSE_APACHE_2.0.txt"),
        ("legal/NOTICE.md", "Resources/Legal/QWEN_NOTICE.md"),
    ),
    "rag": (
        ("legal/LICENSE.MIT", "Resources/Legal/LICENSE_MIT_BGE.txt"),
        ("legal/BGE_CONVERSION_NOTICE.md", "Resources/Legal/BGE_CONVERSION_NOTICE.md"),
    ),
}


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def digest(path: pathlib.Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as handle:
        while block := handle.read(1024 * 1024):
            value.update(block)
    return value.hexdigest()


def artifact(path: pathlib.Path, root: pathlib.Path) -> dict[str, object]:
    return {
        "path": path.relative_to(root).as_posix(),
        "byteCount": path.stat().st_size,
        "sha256": digest(path),
    }


def load_keyring() -> list[dict[str, object]]:
    paths = [
        ROOT / "Resources/Packages/trusted_package_keys.json",
        ROOT / "Resources/Packages/development_trusted_package_keys.json",
    ]
    result: list[dict[str, object]] = []
    for path in paths:
        if path.is_file():
            result.extend(json.loads(path.read_text(encoding="utf-8")))
    return result


def verify_signature(envelope: dict[str, object], keyring: list[dict[str, object]]) -> None:
    key = next((item for item in keyring if item["id"] == envelope["keyID"]), None)
    if key is None:
        raise ValueError(f"untrusted signing key: {envelope['keyID']}")
    public = Ed25519PublicKey.from_public_bytes(base64.b64decode(key["publicKeyBase64"]))
    public.verify(base64.b64decode(envelope["signature"]), signing_payload(envelope["manifest"]))


def validate_package(package: pathlib.Path, *, production: bool = False) -> dict[str, object]:
    envelope = json.loads((package / "envelope.json").read_text(encoding="utf-8"))
    manifest = envelope["manifest"]
    verify_signature(envelope, load_keyring())
    seen: set[str] = set()
    for item in manifest["artifacts"]:
        relative = item["path"]
        if relative in seen or relative.startswith("/") or ".." in pathlib.PurePosixPath(relative).parts:
            raise ValueError(f"unsafe or duplicate artifact path: {relative}")
        seen.add(relative)
        path = package / relative
        if not path.is_file() or path.stat().st_size != item["byteCount"] or digest(path) != item["sha256"]:
            raise ValueError(f"artifact verification failed: {relative}")
    metadata = manifest["metadata"]
    package_id = manifest["packageID"]
    if package_id.startswith("model."):
        if metadata.get("required_rag_package_id") != "knowledge.shared-survival-rag-v3":
            raise ValueError(f"{package_id} does not declare the shared RAG dependency")
    if "gemma" in package_id:
        required = {"legal/GEMMA_TERMS.md", "legal/NOTICE", "legal/GEMMA_MODIFICATIONS_NOTICE.md"}
        if not required.issubset(seen):
            raise ValueError("Gemma package is missing terms, NOTICE, or modification record")
        terms = (package / "legal/GEMMA_TERMS.md").read_text(encoding="utf-8")
        if "April 1, 2026" not in terms or "Gemma Prohibited Use Policy" not in terms:
            raise ValueError("Gemma terms copy or prohibited-use reference is not current")
        if production and metadata.get("legal_review") != "approved":
            raise ValueError("production Gemma publication requires approved legal review metadata")
    if "qwen" in package_id and not {"legal/LICENSE.APACHE-2.0", "legal/NOTICE.md"}.issubset(seen):
        raise ValueError("Qwen package is missing Apache-2.0 license or notice")
    if package_id == "knowledge.shared-survival-rag-v3" and not {
        "legal/LICENSE.MIT", "legal/BGE_CONVERSION_NOTICE.md"
    }.issubset(seen):
        raise ValueError("shared RAG package is missing BGE MIT license or conversion notice")
    return envelope


def validate_catalog(signed: dict[str, object]) -> dict[str, object]:
    key = next((item for item in load_keyring() if item["id"] == signed["keyID"]), None)
    if key is None:
        raise ValueError(f"untrusted catalog signing key: {signed['keyID']}")
    public = Ed25519PublicKey.from_public_bytes(base64.b64decode(key["publicKeyBase64"]))
    public.verify(base64.b64decode(signed["signature"]), catalog_signing_payload(signed["catalog"]))
    entries = signed["catalog"]["entries"]
    identities = {(item["packageID"], item["version"]) for item in entries}
    if len(identities) != len(entries):
        raise ValueError("catalog contains duplicate package identities")
    rag = next((item for item in entries if item["packageID"] == "knowledge.shared-survival-rag-v3"), None)
    if rag is None:
        raise ValueError("catalog is missing shared RAG")
    for item in entries:
        if item["kind"] == "model" and (
            item["metadata"].get("required_rag_package_id") != rag["packageID"]
            or item["metadata"].get("required_rag_package_version") != rag["version"]
        ):
            raise ValueError(f"catalog dependency mismatch for {item['packageID']}")
    return signed["catalog"]


def link_or_copy(source: pathlib.Path, destination: pathlib.Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    try:
        os.link(source, destination)
    except OSError:
        shutil.copyfile(source, destination)


def prepare_package(
    tier: str,
    source: pathlib.Path,
    version: str,
    output: pathlib.Path,
    private_key: object,
    key_id: str,
    created_at: str,
) -> pathlib.Path:
    source_envelope = json.loads((source / "envelope.json").read_text(encoding="utf-8"))
    manifest = dict(source_envelope["manifest"])
    destination = output / "packages" / manifest["packageID"] / version
    if destination.exists():
        raise FileExistsError(f"refusing to overwrite immutable package: {destination}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="aurora-package-", dir=destination.parent) as temporary:
        staging = pathlib.Path(temporary)
        for item in manifest["artifacts"]:
            link_or_copy(source / item["path"], staging / item["path"])
        for relative, repository_path in LEGAL_FILES[tier]:
            link_or_copy(ROOT / repository_path, staging / relative)
        metadata = dict(manifest["metadata"])
        metadata["release_channel"] = output.name
        metadata["modification_notice"] = "included"
        if manifest["kind"] == "model":
            metadata["required_rag_package_id"] = "knowledge.shared-survival-rag-v3"
            metadata["required_rag_contract"] = "3"
        manifest.update(
            version=version,
            createdAt=created_at,
            artifacts=[artifact(path, staging) for path in sorted(staging.rglob("*")) if path.is_file()],
            metadata=metadata,
        )
        envelope = {
            "manifest": manifest,
            "keyID": key_id,
            "signature": base64.b64encode(private_key.sign(signing_payload(manifest))).decode("ascii"),
        }
        (staging / "manifest.json").write_bytes(canonical_json(manifest))
        (staging / "envelope.json").write_bytes(canonical_json(envelope))
        staging.rename(destination)
    return destination


def prepare(args: argparse.Namespace) -> pathlib.Path:
    channel_root = args.output.resolve() / args.channel
    if channel_root.exists():
        raise FileExistsError(f"refusing to overwrite release: {channel_root}")
    channel_root.mkdir(parents=True)
    private_key = serialization.load_pem_private_key(args.private_key.read_bytes(), password=None)
    created_at = utc_now()
    packages = [
        prepare_package(tier, pathlib.Path(source), version, channel_root, private_key, args.key_id, created_at)
        for tier, source, version in PACKAGE_SPECS
    ]
    envelopes = [validate_package(path, production=args.channel == "production") for path in packages]
    entries = []
    summaries = {
        "model.lite.gemma3-1b-q4km": "Private offline Gemma 3 Lite model for compact devices.",
        "model.expert.qwen3vl-2b-q4km-q8": "Offline Qwen3-VL Expert model with vision support.",
        "knowledge.shared-survival-rag-v3": "Reviewed shared survival sources and BGE retrieval index.",
    }
    for envelope in envelopes:
        manifest = envelope["manifest"]
        base = f"packages/{manifest['packageID']}/{manifest['version']}"
        metadata = {"release_channel": args.channel}
        if manifest["kind"] == "model":
            metadata.update({
                "model_tier": "lite" if "lite" in manifest["packageID"] else "vision_expert",
                "required_rag_package_id": "knowledge.shared-survival-rag-v3",
                "required_rag_package_version": next(
                    item["manifest"]["version"] for item in envelopes
                    if item["manifest"]["packageID"] == "knowledge.shared-survival-rag-v3"
                ),
            })
        entries.append({
            "packageID": manifest["packageID"], "version": manifest["version"],
            "kind": manifest["kind"], "displayName": manifest["displayName"],
            "summary": summaries[manifest["packageID"]],
            "totalByteCount": sum(item["byteCount"] for item in manifest["artifacts"]),
            "envelopePath": f"{base}/envelope.json", "artifactBasePath": base,
            "metadata": metadata,
        })
    catalog = {"schemaVersion": 1, "generatedAt": created_at, "entries": entries}
    signed = {
        "catalog": catalog, "keyID": args.key_id,
        "signature": base64.b64encode(private_key.sign(catalog_signing_payload(catalog))).decode("ascii"),
    }
    validate_catalog(signed)
    (channel_root / "catalog.json").write_bytes(canonical_json(signed))
    metadata = {
        "schemaVersion": 1, "channel": args.channel, "createdAt": created_at,
        "bucket": args.bucket, "catalogObject": f"{args.channel}/catalog.json",
        "packages": [
            {"packageID": item["packageID"], "version": item["version"],
             "totalByteCount": item["totalByteCount"], "envelopePath": item["envelopePath"]}
            for item in entries
        ],
    }
    args.metadata.parent.mkdir(parents=True, exist_ok=True)
    args.metadata.write_bytes(json.dumps(metadata, indent=2, sort_keys=True).encode() + b"\n")
    print(channel_root / "catalog.json")
    return channel_root


def public_status(url: str, range_probe: bool = False) -> int:
    headers = {"User-Agent": PUBLIC_USER_AGENT}
    if range_probe:
        headers["Range"] = "bytes=0-0"
    request = urllib.request.Request(url, headers=headers, method="GET" if range_probe else "HEAD")
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return response.status
    except urllib.error.HTTPError as error:
        return error.code


def run_rclone(
    local: pathlib.Path,
    remote: str,
    cache_control: str,
    *,
    immutable: bool,
) -> None:
    if shutil.which("rclone") is None:
        raise RuntimeError(
            "rclone is required because Wrangler cannot upload Aurora's files larger than 315 MB"
        )
    command = [
        "rclone", "copyto", str(local), remote,
        "--s3-upload-cutoff", "300M", "--s3-chunk-size", "64M",
        "--header-upload", f"Cache-Control: {cache_control}",
    ]
    if immutable:
        command.append("--immutable")
    subprocess.run(command, cwd=ROOT, check=True)


def publish(args: argparse.Namespace) -> None:
    channel_root = args.output.resolve() / args.channel
    signed = json.loads((channel_root / "catalog.json").read_text(encoding="utf-8"))
    validate_catalog(signed)
    files: list[tuple[pathlib.Path, str]] = []
    for entry in signed["catalog"]["entries"]:
        package = channel_root / entry["artifactBasePath"]
        validate_package(package, production=args.channel == "production")
        files.extend((package / name, f"{args.channel}/{entry['artifactBasePath']}/{name}") for name in ("manifest.json", "envelope.json"))
        envelope = json.loads((package / "envelope.json").read_text(encoding="utf-8"))
        files.extend((package / item["path"], f"{args.channel}/{entry['artifactBasePath']}/{item['path']}") for item in envelope["manifest"]["artifacts"])
    base = args.public_base_url.rstrip("/")
    for local, key in files:
        if public_status(f"{base}/{key}") in (200, 206):
            raise FileExistsError(f"refusing to overwrite remote immutable object: {key}")
        run_rclone(
            local,
            f"{args.rclone_remote}:{args.bucket}/{key}",
            "public,max-age=31536000,immutable",
            immutable=True,
        )
    run_rclone(
        channel_root / "catalog.json",
        f"{args.rclone_remote}:{args.bucket}/{args.channel}/catalog.json",
        "no-cache,max-age=0,must-revalidate",
        immutable=False,
    )
    verify_public(args)


def verify_public(args: argparse.Namespace) -> None:
    base = args.public_base_url.rstrip("/")
    catalog_url = f"{base}/{args.channel}/catalog.json"
    if public_status(catalog_url) != 200:
        raise RuntimeError(f"catalog is not publicly available: {catalog_url}")
    signed = json.loads(urllib.request.urlopen(
        urllib.request.Request(catalog_url, headers={"User-Agent": PUBLIC_USER_AGENT}),
        timeout=30,
    ).read())
    for entry in signed["catalog"]["entries"]:
        envelope_url = f"{base}/{args.channel}/{entry['envelopePath']}"
        envelope = json.loads(urllib.request.urlopen(
            urllib.request.Request(envelope_url, headers={"User-Agent": PUBLIC_USER_AGENT}),
            timeout=30,
        ).read())
        for item in envelope["manifest"]["artifacts"]:
            url = f"{base}/{args.channel}/{entry['artifactBasePath']}/{item['path']}"
            if public_status(url, range_probe=True) != 206:
                raise RuntimeError(f"Range probe did not return 206: {url}")
    print(catalog_url)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=("prepare", "publish", "verify-public"))
    parser.add_argument("--channel", choices=("beta", "production"), default="beta")
    parser.add_argument("--bucket", default=BUCKET)
    parser.add_argument("--rclone-remote", default="r2")
    parser.add_argument("--output", type=pathlib.Path, default=ROOT / ".trailguard/cloud-releases")
    parser.add_argument("--metadata", type=pathlib.Path, default=ROOT / "Releases/Models/beta-release.json")
    parser.add_argument("--private-key", type=pathlib.Path, default=ROOT / ".trailguard/development/package-signing-key.pem")
    parser.add_argument("--key-id", default=KEY_ID)
    parser.add_argument("--public-base-url")
    args = parser.parse_args()
    if args.action in ("publish", "verify-public") and not args.public_base_url:
        parser.error("--public-base-url is required")
    if args.channel == "production":
        raise SystemExit("production publication is blocked pending professional Gemma legal review")
    return args


if __name__ == "__main__":
    arguments = parse_args()
    {"prepare": prepare, "publish": publish, "verify-public": verify_public}[arguments.action](arguments)
