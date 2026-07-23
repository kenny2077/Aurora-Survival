#!/usr/bin/env python3
"""Dependency-free structural checks for environments without an Apple toolchain."""

from __future__ import annotations

import json
import pathlib
import sys


ROOT = pathlib.Path(__file__).resolve().parents[1]
KNOWLEDGE = ROOT / "Resources" / "Knowledge" / "starter_knowledge.json"
CATALOG = ROOT / "Resources" / "Models" / "catalog.json"
SAFETY_CASES = ROOT / "Tests" / "Fixtures" / "safety_cases.json"
OBD_REJECTIONS = ROOT / "Tests" / "Fixtures" / "obd_rejected_commands.json"


def fail(message: str) -> None:
    print(f"FAIL: {message}")
    raise SystemExit(1)


def validate_knowledge() -> tuple[int, int]:
    articles = json.loads(KNOWLEDGE.read_text(encoding="utf-8"))
    if not isinstance(articles, list) or not articles:
        fail("knowledge pack must contain articles")

    required = {
        "id", "domain", "title", "summary", "steps", "warnings",
        "keywords", "source", "reviewed"
    }
    allowed_domains = {"vehicle", "wilderness", "first_aid", "navigation"}
    ids: set[str] = set()
    source_ids: set[str] = set()

    for index, article in enumerate(articles):
        missing = required - article.keys()
        if missing:
            fail(f"article {index} is missing {sorted(missing)}")
        if article["id"] in ids:
            fail(f"duplicate article id: {article['id']}")
        ids.add(article["id"])
        if article["domain"] not in allowed_domains:
            fail(f"unknown domain: {article['domain']}")
        if not article["reviewed"]:
            fail(f"starter pack includes unapproved article: {article['id']}")
        if not article["steps"] or not article["warnings"]:
            fail(f"article needs steps and warnings: {article['id']}")
        source = article["source"]
        for key in ("id", "title", "organization", "revision"):
            if not source.get(key):
                fail(f"article {article['id']} has incomplete source metadata")
        source_ids.add(source["id"])

    return len(articles), len(source_ids)


def validate_model_catalog() -> int:
    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    tiers = catalog.get("tiers", [])
    ids = {tier["tier"] for tier in tiers}
    if ids != {"essential", "field", "vision_expert"}:
        fail(f"model tiers do not match contract: {sorted(ids)}")
    vision = next(tier for tier in tiers if tier["tier"] == "vision_expert")
    gates = vision.get("gates", {})
    if gates.get("minimum_physical_memory_bytes", 0) < 7_500_000_000:
        fail("vision memory gate is below approved MVP threshold")
    if not gates.get("disable_in_low_power_mode"):
        fail("vision must be disabled in Low Power Mode")
    return len(tiers)


def validate_swift_sources() -> int:
    sources = sorted((ROOT / "Core").glob("*.swift")) + sorted((ROOT / "App").glob("*.swift"))
    if len(sources) < 10:
        fail("expected app and core Swift sources")
    for source in sources:
        text = source.read_text(encoding="utf-8")
        if text.count("{") != text.count("}"):
            fail(f"unbalanced braces in {source.relative_to(ROOT)}")
        if "http://" in text:
            fail(f"insecure URL in {source.relative_to(ROOT)}")
    return len(sources)


def validate_contracts() -> None:
    safety = (ROOT / "Core" / "SafetyEngine.swift").read_text(encoding="utf-8")
    for term in ("not breathing", "severe bleeding", "fuel leak", "carbon monoxide"):
        if term not in safety:
            fail(f"critical safety rule missing: {term}")

    assistant = (ROOT / "Core" / "IncidentAssistant.swift").read_text(encoding="utf-8")
    safety_position = assistant.find("safety.evaluate")
    model_position = assistant.find("model.generate")
    if safety_position < 0 or model_position < 0 or safety_position > model_position:
        fail("model generation can occur before deterministic safety evaluation")

    settings = (ROOT / "App" / "ModelSettingsView.swift").read_text(encoding="utf-8")
    if "larger model is not a safer source" not in settings:
        fail("tier safety disclosure is missing")

    required_sources = [
        "PackageVerifier.swift",
        "PackageInstaller.swift",
        "VehicleIdentity.swift",
        "OfflineMapPack.swift",
        "OBDProtocol.swift",
        "LlamaRuntimeAdapter.swift",
    ]
    for name in required_sources:
        if not (ROOT / "Core" / name).is_file():
            fail(f"production foundation missing: Core/{name}")

    workflow = ROOT / ".github" / "workflows" / "ci.yml"
    if not workflow.is_file():
        fail("GitHub Actions CI workflow is missing")


def validate_locked_evaluations() -> tuple[int, int, int]:
    safety_cases = json.loads(SAFETY_CASES.read_text(encoding="utf-8"))
    if len(safety_cases) < 10:
        fail("locked safety suite is too small")
    ids = [case.get("id") for case in safety_cases]
    if len(ids) != len(set(ids)) or any(not item for item in ids):
        fail("locked safety case ids must be unique and non-empty")
    allowed_titles = {
        "Life-threatening emergency",
        "Severe bleeding",
        "Fire or fuel hazard",
        "Possible carbon monoxide exposure",
        "Time-critical medical symptoms",
        "Unsupported high-risk procedure",
    }
    for case in safety_cases:
        if not case.get("input") or case.get("expected_title") not in allowed_titles:
            fail(f"invalid safety fixture: {case.get('id')}")

    rejected = json.loads(OBD_REJECTIONS.read_text(encoding="utf-8"))
    if len(rejected) < 8 or "04" not in rejected:
        fail("locked OBD rejection suite is incomplete")

    test_count = 0
    for source in (ROOT / "Tests").glob("*.swift"):
        test_count += sum(
            1 for line in source.read_text(encoding="utf-8").splitlines()
            if line.strip().startswith("func test")
        )
    if test_count < 35:
        fail(f"expected at least 35 Swift tests, found {test_count}")
    return len(safety_cases), len(rejected), test_count


def main() -> None:
    article_count, source_count = validate_knowledge()
    model_count = validate_model_catalog()
    swift_count = validate_swift_sources()
    validate_contracts()
    safety_count, obd_count, test_count = validate_locked_evaluations()
    print(
        "PASS: "
        f"{article_count} articles, {source_count} sources, "
        f"{model_count} model tiers, {swift_count} Swift sources, "
        f"{test_count} tests, {safety_count} safety cases, "
        f"{obd_count} blocked OBD commands"
    )


if __name__ == "__main__":
    try:
        main()
    except (OSError, json.JSONDecodeError, KeyError, TypeError) as exc:
        fail(str(exc))
