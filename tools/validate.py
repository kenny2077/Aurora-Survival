#!/usr/bin/env python3
"""Dependency-free structural checks for environments without an Apple toolchain."""

from __future__ import annotations

import hashlib
import json
import pathlib
import re
import sqlite3
import sys


ROOT = pathlib.Path(__file__).resolve().parents[1]
KNOWLEDGE = ROOT / "Resources" / "Knowledge" / "starter_knowledge.json"
CATALOG = ROOT / "Resources" / "Models" / "catalog.json"
MAP_ASSET_CASES = ROOT / "Tests" / "Fixtures" / "map_asset_cases.json"
DEVELOPMENT_PACK = ROOT / "Tests" / "Fixtures" / "development_knowledge_pack.json"
SURVIVAL_KNOWLEDGE = ROOT / "Resources" / "Knowledge" / "survival_knowledge.sqlite"
SURVIVAL_KNOWLEDGE_HASH = ROOT / "Resources" / "Knowledge" / "survival_knowledge.sha256"
SURVIVAL_SOURCE = ROOT / "Resources" / "Knowledge" / "survival_knowledge_source.json"
SURVIVAL_FALLBACK = ROOT / "Resources" / "Knowledge" / "survival_fallback.json"
LEGACY_ANCHORS = ROOT / "Resources" / "Knowledge" / "legacy_anchor_manifest.json"
RETRIEVAL_BENCHMARK = ROOT / "Tests" / "Fixtures" / "survival_retrieval_benchmark.json"
LLAMA_RUNTIME_PACKAGE = ROOT / "Runtime" / "TrailGuardLlamaRuntime" / "Package.swift"
LLAMA_GRAMMAR_HEADER = (
    ROOT
    / "Runtime"
    / "TrailGuardLlamaRuntime"
    / "Sources"
    / "TrailGuardLlamaC"
    / "GroundedResponseGrammar.h"
)


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


def validate_survival_knowledge() -> tuple[int, int, int, int]:
    digest = hashlib.sha256(SURVIVAL_KNOWLEDGE.read_bytes()).hexdigest()
    recorded = SURVIVAL_KNOWLEDGE_HASH.read_text(encoding="utf-8").split()[0]
    if recorded != digest:
        fail("survival knowledge checksum file is stale")

    source = json.loads(SURVIVAL_SOURCE.read_text(encoding="utf-8"))
    fallback = json.loads(SURVIVAL_FALLBACK.read_text(encoding="utf-8"))
    legacy = json.loads(LEGACY_ANCHORS.read_text(encoding="utf-8")).get("anchors", [])
    benchmark = json.loads(RETRIEVAL_BENCHMARK.read_text(encoding="utf-8"))
    expected_titles = [
        "Survival Basics", "Find and Treat Water", "Start a Fire",
        "Build a Shelter", "Find Food Safely", "Navigate When Lost",
        "Signal for Rescue", "Wilderness First Aid",
        "Weather and Wildlife", "Car Breakdown",
    ]
    if [chapter.get("title") for chapter in source.get("chapters", [])] != expected_titles:
        fail("survival source must contain the ten approved chapters in order")
    if len(source.get("lessons", [])) != 70:
        fail("survival source must contain exactly 70 lessons")
    if len(fallback.get("chapters", [])) != 10 or len(fallback.get("cards", [])) != 10:
        fail("generated survival fallback must contain one card per chapter")
    if len(legacy) != 828 or len({item.get("legacyChunkID") for item in legacy}) != 828:
        fail("legacy anchor manifest must disposition all 828 old chunk IDs")
    if len(benchmark) != 200:
        fail("retrieval benchmark must contain 200 queries")
    chapter_balance: dict[str, int] = {}
    for item in benchmark:
        chapter = item.get("expectedChapterID")
        chapter_balance[chapter] = chapter_balance.get(chapter, 0) + 1
    if set(chapter_balance.values()) != {20} or len(chapter_balance) != 10:
        fail("retrieval benchmark must contain 20 queries per chapter")

    for lesson in source["lessons"]:
        if not 3 <= len(lesson.get("actions", [])) <= 6:
            fail(f"lesson needs 3–6 actions: {lesson.get('id')}")
        if not 1 <= len(lesson.get("warnings", [])) <= 3:
            fail(f"lesson needs 1–3 warnings: {lesson.get('id')}")
        if lesson.get("units") != "dual" or lesson.get("reviewStatus") != "primary-source-verified":
            fail(f"lesson review/units contract is incomplete: {lesson.get('id')}")

    connection = sqlite3.connect(f"file:{SURVIVAL_KNOWLEDGE}?mode=ro", uri=True)
    try:
        schema_version = int(connection.execute(
            "SELECT value FROM metadata WHERE key='schema_version'"
        ).fetchone()[0])
        chapter_count = connection.execute("SELECT COUNT(*) FROM chapters").fetchone()[0]
        lesson_count = connection.execute("SELECT COUNT(*) FROM lessons").fetchone()[0]
        passage_count = connection.execute("SELECT COUNT(*) FROM passages").fetchone()[0]
        indexed_count = connection.execute("SELECT COUNT(*) FROM passages_fts").fetchone()[0]
        source_count = connection.execute("SELECT COUNT(*) FROM sources").fetchone()[0]
        legacy_count = connection.execute("SELECT COUNT(*) FROM legacy_anchors").fetchone()[0]
        missing_sources = connection.execute(
            "SELECT COUNT(*) FROM passages p WHERE NOT EXISTS ("
            "SELECT 1 FROM passage_sources ps WHERE ps.passage_id=p.passage_id)"
        ).fetchone()[0]
        answer_texts = [row[0] for row in connection.execute("SELECT answer_text FROM passages")]
        prohibited = connection.execute(
            "SELECT COUNT(*) FROM passages WHERE lower(reference_text) LIKE '%repair the traction battery%' "
            "OR lower(reference_text) LIKE '%identify this mushroom%'"
        ).fetchone()[0]
    finally:
        connection.close()
    if (schema_version, chapter_count, lesson_count) != (1, 10, 70):
        fail("survival knowledge schema/chapter/lesson contract is invalid")
    if passage_count < 1_000 or passage_count != indexed_count:
        fail("survival knowledge needs at least 1,000 fully indexed passages")
    if source_count < 10 or missing_sources or legacy_count != 828:
        fail("survival knowledge source or legacy coverage is incomplete")
    if any(len(re.findall(r"[A-Za-z0-9]+", text)) > 120 for text in answer_texts):
        fail("answer-ready passages must not exceed 120 words")
    if prohibited:
        fail("survival knowledge contains prohibited plant or vehicle guidance")
    return chapter_count, lesson_count, passage_count, source_count


def validate_model_catalog() -> int:
    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    tiers = catalog.get("tiers", [])
    ids = {tier["tier"] for tier in tiers}
    if ids != {"lite", "vision_expert"}:
        fail(f"model tiers do not match contract: {sorted(ids)}")
    lite = next(tier for tier in tiers if tier["tier"] == "lite")
    lite_gates = lite.get("gates", {})
    if lite_gates.get("minimum_physical_memory_bytes") != 3_500_000_000:
        fail("lite memory gate must match the iPhone 13-class contract")
    if lite_gates.get("disable_in_low_power_mode"):
        fail("Lite must remain available when Expert degrades in Low Power Mode")
    if lite.get("maximum_context_tokens") != 2_048:
        fail("lite context must remain conservatively bounded")
    if lite.get("maximum_output_tokens") != 160:
        fail("lite output must remain conservatively bounded")
    expected_lite_candidate = {
        "candidate_model": "ggml-org/gemma-3-1b-it-GGUF",
        "candidate_revision": "f9c28bcd85737ffc5aef028638d3341d49869c27",
        "base_model": "google/gemma-3-1b-it",
        "base_revision": "dcc83ea841ab6100d6b47a070329e1ba4cf78752",
        "artifact_filename": "gemma-3-1b-it-Q4_K_M.gguf",
        "artifact_bytes": 806_058_240,
        "artifact_sha256": (
            "8ccc5cd1f1b3602548715ae25a66ed73fd5dc68a210412eea643eb20eb75a135"
        ),
        "quantization": "Q4_K_M",
        "license": "LicenseRef-Gemma-Terms-2026-04-01",
        "license_review": "development_only_pending_release_review",
        "evaluation_status": "physical_iPhone13_short_and_five_turn_pass",
    }
    mismatched_candidate = [
        key
        for key, expected in expected_lite_candidate.items()
        if lite.get(key) != expected
    ]
    if mismatched_candidate:
        fail(
            "lite candidate identity does not match the pinned Gemma bake-off "
            f"artifact: {', '.join(mismatched_candidate)}"
        )
    if lite.get("bundled") is not False:
        fail("Gemma Lite must remain unbundled before physical acceptance")
    expert = next(tier for tier in tiers if tier["tier"] == "vision_expert")
    if expert.get("display_name") != "Expert":
        fail("vision_expert must be presented as Expert")
    if not str(expert.get("validation_status", "")).startswith("locked_"):
        fail("Expert must stay validation locked")
    gates = expert.get("gates", {})
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
        if re.search(r'"http://[^"\s]+', text):
            fail(f"insecure URL in {source.relative_to(ROOT)}")
    return len(sources)


def validate_contracts() -> None:
    assistant = (ROOT / "Core" / "IncidentAssistant.swift").read_text(encoding="utf-8")
    for contract in ("limit: 2", "manualReferences", "model.generate"):
        if contract not in assistant:
            fail(f"Lite Chat orchestration is missing: {contract}")
    if "safety.evaluate" in assistant or (ROOT / "Core" / "SafetyEngine.swift").exists():
        fail("retired safety routing is still connected to Lite Chat")

    tools_view = (ROOT / "App" / "ToolsView.swift").read_text(encoding="utf-8")
    for contract in ("Offline intelligence", "tools.tier", "Validation pending"):
        if contract not in tools_view:
            fail(f"focused model center is missing: {contract}")

    required_sources = [
        "PackageVerifier.swift",
        "PackageInstaller.swift",
        "OfflineMapPack.swift",
        "LlamaRuntimeAdapter.swift",
        "ModelPreferenceStore.swift",
    ]
    for name in required_sources:
        if not (ROOT / "Core" / name).is_file():
            fail(f"production foundation missing: Core/{name}")

    production_controls = [
        "GroundedResponse.swift",
        "GroundedResponseCodec.swift",
        "IncidentNetworkPolicy.swift",
        "EmergencyCoreStore.swift",
        "ReleaseValidation.swift",
        "ResumableArtifactAssembler.swift",
        "EntitlementLedger.swift",
        "OfflineMapRuntime.swift",
    ]
    for name in production_controls:
        if not (ROOT / "Core" / name).is_file():
            fail(f"production control missing: Core/{name}")

    prompt = (ROOT / "Core" / "GroundedPromptBuilder.swift").read_text(
        encoding="utf-8"
    )
    for contract in (
        '{"a":"answer","e":[1]}',
        "REVIEWED EXCERPTS",
        "35–55 word paragraph under 360 characters",
        "exactly three sentences",
        "under 360 characters",
        "ACTIONS:",
        "WARNING:",
        "survival and incident assistant",
        "30–60 words",
        "case (.grounded, .repair)",
        "case (.incidentFallback, .repair)",
    ):
        if contract not in prompt:
            fail(f"Gemma prompt contract is missing: {contract}")

    chat_view = (ROOT / "App" / "ChatView.swift").read_text(encoding="utf-8")
    if "Fully offline · Gemma + Field Manual" in chat_view:
        fail("retired persistent offline banner remains in Chat")

    knowledge = (ROOT / "Core" / "SurvivalKnowledge.swift").read_text(encoding="utf-8")
    for contract in ("passages_fts", "ManualReference", "SQLITE_OPEN_READONLY", "legacy_anchors"):
        if contract not in knowledge:
            fail(f"survival knowledge integration is missing: {contract}")

    app_model = (ROOT / "App" / "AppModel.swift").read_text(encoding="utf-8")
    if "EmergencyCoreStore" not in app_model:
        fail("recoverable emergency core is not connected to app startup")

    downloader = (
        ROOT / "Core" / "PackageDownloadCoordinator.swift"
    ).read_text(encoding="utf-8")
    for contract in ("incidentModeDenied", "ResumableArtifactAssembler", "byteRange"):
        if contract not in downloader:
            fail(f"package delivery integration is missing: {contract}")

    incident_policy = (
        ROOT / "Core" / "IncidentNetworkPolicy.swift"
    ).read_text(encoding="utf-8")
    for denied in ("packageCatalog", "packageDownload", "purchase", "telemetry"):
        if denied not in incident_policy:
            fail(f"incident network policy is missing operation: {denied}")

    workflow = ROOT / ".github" / "workflows" / "ci.yml"
    if not workflow.is_file():
        fail("GitHub Actions CI workflow is missing")
    for app_source in ("StoreKitEntitlementBridge.swift", "ToolsView.swift", "MapPackView.swift"):
        if not (ROOT / "App" / app_source).is_file():
            fail(f"app integration missing: App/{app_source}")


def validate_llama_runtime_pin() -> str:
    manifest = LLAMA_RUNTIME_PACKAGE.read_text(encoding="utf-8")
    release = "b9637"
    commit = "aedb2a5e9ca3d4064148bbb919e0ddc0c1b70ab3"
    checksum = "46c7dad871f804d82399ddcfeb54d23b6469888801fc35124d7e33e543a9bef7"
    if f"/{release}/llama-{release}-xcframework.zip" not in manifest:
        fail("llama.cpp XCFramework release is not pinned")
    if checksum not in manifest:
        fail("llama.cpp XCFramework checksum is not pinned")

    readme = (
        ROOT / "Runtime" / "TrailGuardLlamaRuntime" / "README.md"
    ).read_text(encoding="utf-8")
    for value in (release, commit, checksum):
        if value not in readme:
            fail(f"llama.cpp runtime provenance is missing: {value}")

    bridge = (
        ROOT
        / "Runtime"
        / "TrailGuardLlamaRuntime"
        / "Sources"
        / "TrailGuardLlamaC"
        / "TrailGuardLlamaC.cpp"
    ).read_text(encoding="utf-8")
    if "llama_sampler_init_greedy" not in bridge:
        fail("llama.cpp text bridge must use deterministic greedy sampling")
    if "llama_sampler_init_grammar" not in bridge:
        fail("llama.cpp text bridge must constrain grounded JSON with a grammar")
    if not LLAMA_GRAMMAR_HEADER.is_file():
        fail("llama.cpp grounded-response grammar is missing")
    if "llama_model_chat_template" not in bridge:
        fail("llama.cpp text bridge must use the model chat template")
    if "session.context = llama_init_from_model(" not in bridge:
        fail("llama.cpp warm reuse must refresh request-local context state")
    if "llama_memory_clear(" in bridge:
        fail("llama.cpp must not reuse cleared KV state across requests")
    return release


def validate_locked_evaluations() -> int:
    test_count = 0
    for source in (ROOT / "Tests").glob("*.swift"):
        test_count += sum(
            1 for line in source.read_text(encoding="utf-8").splitlines()
            if line.strip().startswith("func test")
        )
    if test_count < 70:
        fail(f"expected at least 70 Swift tests, found {test_count}")
    return test_count


def validate_schemas_and_pack_contract() -> tuple[int, int]:
    schema_files = sorted((ROOT / "Schemas").glob("*.schema.json"))
    if len(schema_files) < 7:
        fail(f"expected at least 7 independent schemas, found {len(schema_files)}")
    for path in schema_files:
        schema = json.loads(path.read_text(encoding="utf-8"))
        if schema.get("$schema") != "https://json-schema.org/draft/2020-12/schema":
            fail(f"schema version missing in {path.relative_to(ROOT)}")
        if not schema.get("$id") or not schema.get("title"):
            fail(f"schema identity missing in {path.relative_to(ROOT)}")

    pack = json.loads(DEVELOPMENT_PACK.read_text(encoding="utf-8"))
    if pack.get("review", {}).get("status") != "development_fixture":
        fail("synthetic knowledge pack must remain development_fixture")
    records = pack.get("records", [])
    if len(records) < 10:
        fail("development pack must exercise at least 10 ingestion records")
    evidence_ids = [record.get("evidence_id") for record in records]
    if len(evidence_ids) != len(set(evidence_ids)) or any(not item for item in evidence_ids):
        fail("development pack evidence ids must be unique")
    dimensions = {len(record.get("embedding", [])) for record in records}
    if len(dimensions) != 1 or next(iter(dimensions), 0) < 4:
        fail("development pack must contain fixed-dimension precomputed embeddings")

    for tool in (
        "build_pack.py",
        "test_pack_reproducibility.py",
        "write_evaluation_report.py",
    ):
        if not (ROOT / "tools" / tool).is_file():
            fail(f"pack/evaluation tool missing: tools/{tool}")
    return len(schema_files), len(records)


def validate_evaluation_matrix() -> int:
    assets = json.loads(MAP_ASSET_CASES.read_text(encoding="utf-8"))
    if len(assets) != 30:
        fail(f"expected 30 map/asset cases, found {len(assets)}")
    asset_ids = [case.get("id") for case in assets]
    if len(asset_ids) != len(set(asset_ids)):
        fail("map/asset case ids must be unique")
    return len(assets)


def validate_repository_governance() -> int:
    adrs = sorted((ROOT / "Docs" / "ADR").glob("[0-9][0-9][0-9][0-9]-*.md"))
    if len(adrs) < 10:
        fail(f"expected at least 10 current architecture decisions, found {len(adrs)}")
    source_audit = ROOT / "Docs" / "SOURCE_AUDIT_SURVIVALROBINSON.md"
    if not source_audit.is_file():
        fail("attached architecture document source audit is missing")
    audit_text = source_audit.read_text(encoding="utf-8").replace("**", "")
    if "not accepted as a runtime knowledge source" not in audit_text:
        fail("source audit must prevent unlicensed runtime reuse")
    return len(adrs)


def main() -> None:
    article_count, source_count = validate_knowledge()
    manual_chapters, manual_lessons, passages, manual_sources = validate_survival_knowledge()
    model_count = validate_model_catalog()
    swift_count = validate_swift_sources()
    validate_contracts()
    llama_release = validate_llama_runtime_pin()
    test_count = validate_locked_evaluations()
    schema_count, development_records = validate_schemas_and_pack_contract()
    asset_count = validate_evaluation_matrix()
    adr_count = validate_repository_governance()
    print(
        "PASS: "
        f"{article_count} articles, {source_count} sources, "
        f"survival knowledge {manual_chapters} chapters/{manual_lessons} lessons/"
        f"{passages} passages/{manual_sources} primary sources, "
        f"llama.cpp {llama_release}, "
        f"{model_count} model tiers, {schema_count} schemas, "
        f"{development_records} development records, {swift_count} Swift sources, "
        f"{test_count} tests, "
        f"{asset_count} map/asset cases, {adr_count} ADRs"
    )


if __name__ == "__main__":
    try:
        main()
    except (OSError, json.JSONDecodeError, KeyError, TypeError) as exc:
        fail(str(exc))
