#!/usr/bin/env python3
"""Prepare locally hosted, signed Aurora product packages and catalog."""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import math
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile
from typing import Any

from cryptography.hazmat.primitives import serialization


ROOT = pathlib.Path(__file__).resolve().parents[1]
DEFAULT_ROOT = ROOT / ".trailguard" / "development"
DEFAULT_KEY = DEFAULT_ROOT / "package-signing-key.pem"
DEFAULT_MAP_ASSETS = (
    DEFAULT_ROOT / "maps-assets" / "basemaps-assets-main" / "fonts"
)
KEY_ID = "development-2026-07"
CREATED_AT = "2026-07-31T00:00:00Z"


def canonical_json(value: Any) -> bytes:
    return (
        json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
        + "\n"
    ).encode("utf-8")


def signing_payload(manifest: dict[str, Any]) -> bytes:
    fields = [
        "schema", str(manifest["schemaVersion"]),
        "package", manifest["packageID"],
        "version", manifest["version"],
        "kind", manifest["kind"],
        "created", manifest["createdAt"],
        "minimumApp", manifest["minimumAppVersion"],
        "license", manifest["licenseIdentifier"],
        "display", manifest["displayName"],
    ]
    for artifact in sorted(manifest["artifacts"], key=lambda item: item["path"]):
        fields.extend(
            [
                "artifact", artifact["path"],
                "bytes", str(artifact["byteCount"]),
                "sha256", artifact["sha256"],
            ]
        )
    for key in sorted(manifest["metadata"]):
        fields.extend(["metadata", key, manifest["metadata"][key]])
    return "\n".join(
        f"{len(field.encode('utf-8'))}:{field}" for field in fields
    ).encode()


def catalog_signing_payload(catalog: dict[str, Any]) -> bytes:
    fields = ["schema", str(catalog["schemaVersion"]), "generated", catalog["generatedAt"]]
    for entry in sorted(
        catalog["entries"], key=lambda item: (item["packageID"], item["version"])
    ):
        fields.extend(
            [
                "package", entry["packageID"],
                "version", entry["version"],
                "kind", entry["kind"],
                "display", entry["displayName"],
                "summary", entry["summary"],
                "bytes", str(entry["totalByteCount"]),
                "envelope", entry["envelopePath"],
                "artifacts", entry["artifactBasePath"],
            ]
        )
        for key in sorted(entry["metadata"]):
            fields.extend(["metadata", key, entry["metadata"][key]])
    return "\n".join(
        f"{len(field.encode('utf-8'))}:{field}" for field in fields
    ).encode()


def sha256(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def deterministic_embedding(article: dict[str, Any], dimensions: int = 16) -> list[float]:
    values = [0.0] * dimensions
    text = " ".join(
        [article["title"], article["summary"]]
        + article["steps"]
        + article["warnings"]
        + article["keywords"]
    ).lower()
    for token in text.split():
        digest = hashlib.sha256(token.encode()).digest()
        values[int.from_bytes(digest[:2], "big") % dimensions] += (
            1.0 if digest[2] % 2 == 0 else -1.0
        )
    length = math.sqrt(sum(value * value for value in values)) or 1.0
    return [round(value / length, 7) for value in values]


def prepare_knowledge_packages(root: pathlib.Path, private_key: pathlib.Path) -> list[pathlib.Path]:
    articles = json.loads(
        (ROOT / "Resources" / "Knowledge" / "starter_knowledge.json").read_text(
            encoding="utf-8"
        )
    )
    names = {
        "wilderness": "Wilderness Field Manual",
        "navigation": "Offline Navigation Guide",
        "first_aid": "First Aid Quick Guide",
    }
    outputs: list[pathlib.Path] = []
    with tempfile.TemporaryDirectory(prefix="aurora-product-knowledge-") as temp:
        temp_root = pathlib.Path(temp)
        for domain, display_name in names.items():
            selected = [article for article in articles if article["domain"] == domain]
            source = {
                "schema_version": 1,
                "package_id": f"knowledge.{domain.replace('_', '-')}.starter",
                "version": "1.0.0",
                "domain": domain,
                "locale": "en-US",
                "effective_date": "2026-07-01T00:00:00Z",
                "expires_at": None,
                "license": {
                    "identifier": "LicenseRef-Aurora-Curated-Sources",
                    "permitted_uses": ["offline incident guidance"],
                    "source_manifest_path": "Resources/Knowledge/starter_knowledge.json",
                },
                "review": {
                    "status": "approved",
                    "attestation_id": "aurora.starter-review.2026-07",
                },
                "records": [],
            }
            for article in selected:
                source_info = article["source"]
                source["records"].append(
                    {
                        "evidence_id": article["id"],
                        "title": article["title"],
                        "summary": article["summary"],
                        "steps": article["steps"],
                        "warnings": article["warnings"],
                        "keywords": article["keywords"],
                        "source": {
                            "source_id": source_info["id"],
                            "title": source_info["title"],
                            "owner": source_info["organization"],
                            "revision": source_info["revision"],
                            "locator": source_info.get("url", ""),
                        },
                        "applicability": {},
                        "supported_answer_level": "supported",
                        "embedding": deterministic_embedding(article),
                    }
                )
            input_path = temp_root / f"{domain}.json"
            input_path.write_bytes(canonical_json(source))
            output = root / f"knowledge-{domain}@1.0.0"
            if not output.exists():
                subprocess.run(
                    [
                        sys.executable,
                        str(ROOT / "tools" / "build_pack.py"),
                        "--input", str(input_path),
                        "--output", str(output),
                        "--private-key", str(private_key),
                        "--key-id", KEY_ID,
                        "--display-name", display_name,
                        "--created-at", CREATED_AT,
                    ],
                    check=True,
                )
            outputs.append(output)
    return outputs


def prepare_map_package(
    root: pathlib.Path,
    private_key: Any,
    slug: str,
    display_name: str,
    sources: dict[str, pathlib.Path],
    bounds: tuple[float, float, float, float],
    region: str,
    tier: str,
    layers: list[str],
    font_assets: pathlib.Path,
    rebuild: bool,
) -> pathlib.Path:
    output = root / f"map-{slug}@1.0.0"
    if output.exists() and not rebuild:
        return output
    for source_name, source_path in sources.items():
        if not source_path.is_file():
            raise FileNotFoundError(
                f"Map source '{source_name}' is not ready: {source_path}"
            )
    with tempfile.TemporaryDirectory(prefix=f"aurora-map-{slug}-", dir=root) as temp:
        staging = pathlib.Path(temp)
        map_dir = staging / "maps"
        style_dir = staging / "style"
        fonts_dir = staging / "fonts" / "Noto Sans Regular"
        legal_dir = staging / "legal"
        map_dir.mkdir()
        style_dir.mkdir()
        fonts_dir.mkdir(parents=True)
        legal_dir.mkdir()
        packaged_sources: dict[str, pathlib.Path] = {}
        for source_name, source_path in sources.items():
            destination = map_dir / f"{slug}-{source_name}.pmtiles"
            try:
                os.link(source_path, destination)
            except OSError:
                shutil.copy2(source_path, destination)
            packaged_sources[source_name] = destination
        pmtiles_path = packaged_sources["protomaps"]
        for glyph_range in ("0-255.pbf", "256-511.pbf"):
            shutil.copy2(
                font_assets / "Noto Sans Regular" / glyph_range,
                fonts_dir / glyph_range,
            )
        shutil.copy2(font_assets / "OFL.txt", legal_dir / "OFL-Noto-Sans.txt")
        style = {
            "version": 8,
            "name": "Aurora Offline",
            "glyphs": "aurora://glyphs/{fontstack}/{range}.pbf",
            "sources": {
                "protomaps": {
                    "type": "vector",
                    "url": "aurora://pmtiles",
                    "attribution": "© OpenStreetMap contributors",
                },
                "contours": {
                    "type": "vector",
                    "url": "aurora://source/contours",
                    "attribution": "USGS 3DEP public domain",
                },
            },
            "layers": [
                {
                    "id": "background",
                    "type": "background",
                    "paint": {"background-color": "#F2F2F7"},
                },
                {
                    "id": "landcover",
                    "type": "fill",
                    "source": "protomaps",
                    "source-layer": "landcover",
                    "paint": {"fill-color": "#DCE8D4", "fill-opacity": 0.7},
                },
                {
                    "id": "landuse",
                    "type": "fill",
                    "source": "protomaps",
                    "source-layer": "landuse",
                    "paint": {"fill-color": "#E3EBDD", "fill-opacity": 0.55},
                },
                {
                    "id": "water",
                    "type": "fill",
                    "source": "protomaps",
                    "source-layer": "water",
                    "paint": {"fill-color": "#A8D5EA"},
                },
                {
                    "id": "buildings",
                    "type": "fill",
                    "source": "protomaps",
                    "source-layer": "buildings",
                    "minzoom": 12,
                    "paint": {"fill-color": "#D2CDC6", "fill-opacity": 0.8},
                },
                {
                    "id": "boundaries",
                    "type": "line",
                    "source": "protomaps",
                    "source-layer": "boundaries",
                    "paint": {
                        "line-color": "#8E8E93",
                        "line-dasharray": [2, 2],
                        "line-width": 1,
                    },
                },
                {
                    "id": "road-casing",
                    "type": "line",
                    "source": "protomaps",
                    "source-layer": "roads",
                    "minzoom": 7,
                    "layout": {"line-cap": "round", "line-join": "round"},
                    "paint": {
                        "line-color": "#C4C4C6",
                        "line-width": ["interpolate", ["linear"], ["zoom"], 7, 1.5, 14, 6],
                    },
                },
                {
                    "id": "roads",
                    "type": "line",
                    "source": "protomaps",
                    "source-layer": "roads",
                    "minzoom": 7,
                    "layout": {"line-cap": "round", "line-join": "round"},
                    "paint": {
                        "line-color": "#FFFFFF",
                        "line-width": ["interpolate", ["linear"], ["zoom"], 7, 0.8, 14, 4],
                    },
                },
                {
                    "id": "road-labels",
                    "type": "symbol",
                    "source": "protomaps",
                    "source-layer": "roads",
                    "minzoom": 10,
                    "layout": {
                        "symbol-placement": "line",
                        "text-field": ["coalesce", ["get", "name:en"], ["get", "name"]],
                        "text-font": ["Noto Sans Regular"],
                        "text-size": ["interpolate", ["linear"], ["zoom"], 10, 10, 15, 13],
                    },
                    "paint": {
                        "text-color": "#3A3A3C",
                        "text-halo-color": "#FFFFFF",
                        "text-halo-width": 1.25,
                    },
                },
                {
                    "id": "place-labels",
                    "type": "symbol",
                    "source": "protomaps",
                    "source-layer": "places",
                    "layout": {
                        "text-field": ["coalesce", ["get", "name:en"], ["get", "name"]],
                        "text-font": ["Noto Sans Regular"],
                        "text-size": ["interpolate", ["linear"], ["zoom"], 4, 11, 12, 16],
                        "text-max-width": 9,
                    },
                    "paint": {
                        "text-color": "#1C1C1E",
                        "text-halo-color": "#F2F2F7",
                        "text-halo-width": 1.5,
                    },
                },
                {
                    "id": "poi-labels",
                    "type": "symbol",
                    "source": "protomaps",
                    "source-layer": "pois",
                    "minzoom": 13,
                    "layout": {
                        "text-field": ["coalesce", ["get", "name:en"], ["get", "name"]],
                        "text-font": ["Noto Sans Regular"],
                        "text-size": 11,
                        "text-offset": [0, 0.75],
                    },
                    "paint": {
                        "text-color": "#3A3A3C",
                        "text-halo-color": "#FFFFFF",
                        "text-halo-width": 1,
                    },
                },
            ],
        }
        style_paths: dict[str, str] = {}
        for layer in layers:
            layer_style = json.loads(json.dumps(style))
            layer_style["name"] = f"Aurora {layer.title()} Offline"
            if layer in {"terrain", "topographic"}:
                layer_style["layers"].append(
                    {
                        "id": "elevation-contours",
                        "type": "line",
                        "source": "contours",
                        "source-layer": "contours",
                        "minzoom": 8,
                        "paint": {
                            "line-color": "#8A6D45",
                            "line-opacity": 0.72 if layer == "topographic" else 0.38,
                            "line-width": ["interpolate", ["linear"], ["zoom"], 8, 0.45, 14, 1.2],
                        },
                    }
                )
            if layer == "trail":
                layer_style["layers"].append(
                    {
                        "id": "trail-highlight",
                        "type": "line",
                        "source": "protomaps",
                        "source-layer": "roads",
                        "minzoom": 10,
                        "filter": ["in", ["get", "kind"], ["literal", ["path", "trail"]]],
                        "paint": {"line-color": "#B5300F", "line-width": 2.2},
                    }
                )
            style_path = style_dir / f"{layer}.json"
            style_path.write_bytes(canonical_json(layer_style))
            style_paths[layer] = f"style/{layer}.json"
        default_style_path = style_paths[layers[0]]
        west, south, east, north = bounds
        map_record = {
            "schemaVersion": 2,
            "id": f"map.{slug}",
            "name": display_name,
            "regionCode": region,
            "tier": tier,
            "version": "1.0.0",
            "generatedAt": CREATED_AT,
            "recommendedRefreshAfter": "2027-01-31T00:00:00Z",
            "bounds": {
                "southWest": {"latitude": south, "longitude": west},
                "northEast": {"latitude": north, "longitude": east},
            },
            "pmtilesPath": f"maps/{pmtiles_path.name}",
            "sourcePaths": {
                name: f"maps/{path.name}" for name, path in packaged_sources.items()
            },
            "stylePath": default_style_path,
            "stylePaths": style_paths,
            "availableLayers": layers,
            "minimumZoom": 3,
            "maximumZoom": 16,
            "sourceDate": CREATED_AT,
            "compressedByteCount": sum(path.stat().st_size for path in packaged_sources.values()),
            "unpackedByteCount": sum(path.stat().st_size for path in packaged_sources.values()),
            "minimumFreeStorageBytes": sum(path.stat().st_size for path in packaged_sources.values()) + 256_000_000,
            "glyphsDirectoryPath": "fonts",
            "routingGraphPath": None,
            "byteCount": sum(path.stat().st_size for path in packaged_sources.values()),
        }
        (staging / "map.json").write_bytes(canonical_json(map_record))
        (legal_dir / "ATTRIBUTION.txt").write_text(
            "© OpenStreetMap contributors. Protomaps Basemap Produced Work; "
            "Open Database License (ODbL) 1.0.\n",
            encoding="utf-8",
        )
        artifacts = []
        for path in sorted(staging.rglob("*")):
            if path.is_file():
                artifacts.append(
                    {
                        "path": path.relative_to(staging).as_posix(),
                        "byteCount": path.stat().st_size,
                        "sha256": sha256(path),
                    }
                )
        manifest = {
            "schemaVersion": 1,
            "packageID": f"map.{slug}",
            "version": "1.0.0",
            "kind": "map",
            "createdAt": CREATED_AT,
            "minimumAppVersion": "1.0.0",
            "licenseIdentifier": "ODbL-1.0",
            "displayName": display_name,
            "artifacts": artifacts,
            "metadata": {
                "attribution": "© OpenStreetMap contributors",
                "map_manifest_path": "map.json",
                "region": region,
                "tier": tier,
            },
        }
        envelope = {
            "keyID": KEY_ID,
            "manifest": manifest,
            "signature": base64.b64encode(
                private_key.sign(signing_payload(manifest))
            ).decode("ascii"),
        }
        (staging / "manifest.json").write_bytes(canonical_json(manifest))
        (staging / "envelope.json").write_bytes(canonical_json(envelope))
        if output.exists():
            backup = output.with_name(f"{output.name}.pre-labels")
            if backup.exists():
                raise FileExistsError(
                    f"Map backup already exists; inspect before rebuilding: {backup}"
                )
            output.rename(backup)
        staging.rename(output)
    return output


def catalog_entry(
    package: pathlib.Path,
    summary: str,
    metadata: dict[str, str] | None = None,
) -> dict[str, Any]:
    envelope = json.loads((package / "envelope.json").read_text(encoding="utf-8"))
    manifest = envelope["manifest"]
    return {
        "packageID": manifest["packageID"],
        "version": manifest["version"],
        "kind": manifest["kind"],
        "displayName": manifest["displayName"],
        "summary": summary,
        "totalByteCount": sum(item["byteCount"] for item in manifest["artifacts"]),
        "envelopePath": f"{package.name}/envelope.json",
        "artifactBasePath": package.name,
        "metadata": metadata or {},
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=pathlib.Path, default=DEFAULT_ROOT)
    parser.add_argument("--private-key", type=pathlib.Path, default=DEFAULT_KEY)
    parser.add_argument("--map-font-assets", type=pathlib.Path, default=DEFAULT_MAP_ASSETS)
    parser.add_argument("--rebuild-maps", action="store_true")
    parser.add_argument(
        "--map-regions",
        type=pathlib.Path,
        default=ROOT / "Resources" / "Packages" / "map-regions.json",
    )
    args = parser.parse_args()
    private_key = serialization.load_pem_private_key(
        args.private_key.read_bytes(), password=None
    )
    args.root.mkdir(parents=True, exist_ok=True)

    lite_source = args.root / "model-lite-gemma3-1b-q4km-dev@1.1.0"
    if not (lite_source / "envelope.json").is_file():
        raise FileNotFoundError(f"Verified Lite package is missing: {lite_source}")
    model = args.root / "model-lite-gemma3-1b-q4km-dev@1.3.0"
    if not (model / "envelope.json").is_file():
        subprocess.run(
            [
                sys.executable,
                str(ROOT / "tools" / "prepare_lite_model_package.py"),
                "--source",
                str(lite_source),
                "--output",
                str(model),
                "--private-key",
                str(args.private_key),
                "--created-at",
                CREATED_AT,
            ],
            check=True,
        )
    shared_rag = args.root / "knowledge-shared-rag-v3@3.2.0-dev"
    if not (shared_rag / "envelope.json").is_file():
        subprocess.run(
            [
                sys.executable,
                str(ROOT / "tools" / "prepare_shared_rag_package.py"),
                "--embedding",
                str(ROOT / ".trailguard" / "expert-models" / "bge-small-en-v1.5-Q8_0.gguf"),
                "--output",
                str(shared_rag),
                "--private-key",
                str(args.private_key),
                "--created-at",
                CREATED_AT,
            ],
            check=True,
        )
    knowledge = prepare_knowledge_packages(args.root, args.private_key)
    region_manifest = json.loads(args.map_regions.read_text(encoding="utf-8"))
    maps: list[pathlib.Path] = []
    for region in region_manifest["regions"]:
        maps.append(
            prepare_map_package(
                args.root,
                private_key,
                region["slug"],
                region["display_name"],
                {
                    name: args.root / path
                    for name, path in region["sources"].items()
                },
                tuple(region["bounds"]),
                region["region"],
                region["tier"],
                region["layers"],
                args.map_font_assets,
                args.rebuild_maps,
            )
        )

    entries = [
        catalog_entry(
            shared_rag,
            "Shared corpus-v3, BGE embeddings, and signed vector shards for Lite and Expert.",
            {"shared_rag_contract": "3"},
        ),
        catalog_entry(
            model,
            "Gemma 3 1B Lite release candidate for the iPhone 13 physical bake-off.",
            {
                "model_tier": "lite",
                "required_rag_package_id": "knowledge.shared-survival-rag-v3",
                "required_rag_package_version": "3.2.0-dev",
            },
        )
    ]
    summaries = {
        "wilderness": "Reviewed offline procedures for water and shelter.",
        "navigation": "Reviewed offline lost-person navigation guidance.",
        "first_aid": "Reviewed offline first-aid quick guidance.",
    }
    for package in knowledge:
        domain = package.name.split("knowledge-", 1)[1].split("@", 1)[0]
        entries.append(catalog_entry(package, summaries[domain], {"domain": domain}))
    entries.extend(
        [
            *[
                catalog_entry(
                    map_package,
                    "Statewide offline terrain, topographic, and trail context.",
                    {"region": region["region"], "size_class": "large"},
                )
                for map_package, region in zip(maps, region_manifest["regions"])
            ],
        ]
    )
    species = args.root / "species-bioclip2-north-america-504@1.0.0"
    if (species / "envelope.json").is_file():
        entries.append(
            catalog_entry(
                species,
                "Optional offline identification for 504 North American animals.",
                {"species_contract": "1", "coverage": "504 animals"},
            )
        )
    catalog = {"schemaVersion": 1, "generatedAt": CREATED_AT, "entries": entries}
    signed = {
        "catalog": catalog,
        "keyID": KEY_ID,
        "signature": base64.b64encode(
            private_key.sign(catalog_signing_payload(catalog))
        ).decode("ascii"),
    }
    (args.root / "catalog.json").write_bytes(canonical_json(signed))
    host_root = args.root / "product-host"
    host_root.mkdir(exist_ok=True)
    shutil.copy2(args.root / "catalog.json", host_root / "catalog.json")
    hosted_packages = [shared_rag, model, *knowledge, *maps]
    if (species / "envelope.json").is_file():
        hosted_packages.append(species)
    for package in hosted_packages:
        link = host_root / package.name
        if link.is_symlink():
            if link.resolve() != package.resolve():
                raise RuntimeError(f"Unexpected package link target: {link}")
        elif link.exists():
            raise RuntimeError(f"Refusing to replace non-symlink host path: {link}")
        else:
            link.symlink_to(pathlib.Path("..") / package.name, target_is_directory=True)
    print(host_root / "catalog.json")


if __name__ == "__main__":
    main()
