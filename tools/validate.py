#!/usr/bin/env python3
"""Dependency-free structural checks for environments without an Apple toolchain."""

from __future__ import annotations

import hashlib
import json
import pathlib
import sys


ROOT = pathlib.Path(__file__).resolve().parents[1]
KNOWLEDGE = ROOT / "Resources" / "Knowledge" / "starter_knowledge.json"
CATALOG = ROOT / "Resources" / "Models" / "catalog.json"
SAFETY_CASES = ROOT / "Tests" / "Fixtures" / "safety_cases.json"
OBD_REJECTIONS = ROOT / "Tests" / "Fixtures" / "obd_rejected_commands.json"
GOLD_INCIDENTS = ROOT / "Tests" / "Fixtures" / "gold_incidents.json"
MAP_ASSET_CASES = ROOT / "Tests" / "Fixtures" / "map_asset_cases.json"
DEVELOPMENT_PACK = ROOT / "Tests" / "Fixtures" / "development_knowledge_pack.json"
EMERGENCY_CORE = ROOT / "Resources" / "Knowledge" / "emergency_core.json"
LLAMA_RUNTIME_PACKAGE = ROOT / "Runtime" / "AuroraLlamaRuntime" / "Package.swift"
LLAMA_GRAMMAR_HEADER = (
    ROOT
    / "Runtime"
    / "AuroraLlamaRuntime"
    / "Sources"
    / "AuroraLlamaC"
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


def validate_emergency_core(expected_articles: int) -> str:
    core = json.loads(EMERGENCY_CORE.read_text(encoding="utf-8"))
    if core.get("schemaVersion") != 1:
        fail("emergency core schema version is invalid")
    if core.get("policyVersion") != "deterministic-policy-v1":
        fail("emergency core policy version is not pinned")
    articles = core.get("articles", [])
    if len(articles) != expected_articles:
        fail("emergency core does not match the starter fixture")
    if any(article.get("reviewed") is not True for article in articles):
        fail("emergency core contains an unreviewed article")
    return core.get("version", "")


def validate_model_catalog() -> int:
    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    tiers = catalog.get("tiers", [])
    ids = {tier["tier"] for tier in tiers}
    if ids != {"essential", "lite", "field", "vision_expert"}:
        fail(f"model tiers do not match contract: {sorted(ids)}")
    lite = next(tier for tier in tiers if tier["tier"] == "lite")
    lite_gates = lite.get("gates", {})
    if lite_gates.get("minimum_physical_memory_bytes") != 3_500_000_000:
        fail("lite memory gate must match the iPhone 13-class contract")
    if not lite_gates.get("disable_in_low_power_mode"):
        fail("lite must be disabled in Low Power Mode")
    if lite.get("maximum_context_tokens") != 2_048:
        fail("lite context must remain conservatively bounded")
    if lite.get("maximum_output_tokens") != 256:
        fail("lite output must remain conservatively bounded")
    expected_lite_candidate = {
        "candidate_model": "bartowski/Phi-3.5-mini-instruct-GGUF",
        "candidate_revision": "6d70da17e749a471ccb62ade694486011a75cda3",
        "base_model": "microsoft/Phi-3.5-mini-instruct",
        "base_revision": "2fe192450127e6a83f7441aef6e3ca586c338b77",
        "artifact_filename": "Phi-3.5-mini-instruct-Q4_K_M.gguf",
        "artifact_bytes": 2_393_232_672,
        "artifact_sha256": (
            "e4165e3a71af97f1b4820da61079826d8752a2088e313af0c7d346796c38eff5"
        ),
        "quantization": "Q4_K_M",
        "license": "MIT",
        "workstation_evaluation": (
            "Reports/native-llama-lite-phi-3.5-mini-q4_k_m.json"
        ),
    }
    mismatched_candidate = [
        key
        for key, expected in expected_lite_candidate.items()
        if lite.get(key) != expected
    ]
    if mismatched_candidate:
        fail(
            "lite candidate identity does not match the approved workstation "
            f"artifact: {', '.join(mismatched_candidate)}"
        )
    if lite.get("bundled") is not False:
        fail("evaluated lite candidate must remain unbundled before Mac acceptance")
    evaluation_path = ROOT / lite["workstation_evaluation"]
    if not evaluation_path.is_file():
        fail("approved lite workstation evaluation is missing")
    evaluation = json.loads(evaluation_path.read_text(encoding="utf-8"))
    summary = evaluation.get("summary", {})
    if summary.get("passed_cases") != 12 or not summary.get(
        "eligible_for_mac_handoff"
    ):
        fail("approved lite workstation evaluation is not fully green")
    evaluated_model = evaluation.get("model", {})
    for report_key, catalog_key in (
        ("repo", "candidate_model"),
        ("revision", "candidate_revision"),
        ("filename", "artifact_filename"),
        ("sha256", "artifact_sha256"),
        ("size_bytes", "artifact_bytes"),
        ("quantization", "quantization"),
        ("license", "license"),
    ):
        if evaluated_model.get(report_key) != lite.get(catalog_key):
            fail(f"lite catalog and workstation report differ: {catalog_key}")
    evaluated_runtime = evaluation.get("runtime", {})
    if (
        evaluated_runtime.get("release") != "b9637"
        or evaluated_runtime.get("context_tokens") != 2_048
        or evaluated_runtime.get("maximum_output_tokens") != 256
    ):
        fail("lite workstation evaluation used the wrong runtime configuration")
    evaluator_path = ROOT / "tools" / "native_llama_lite_eval.py"
    evaluator_sha256 = hashlib.sha256(evaluator_path.read_bytes()).hexdigest()
    if (
        evaluation.get("evaluation_contract", {}).get("evaluator_sha256")
        != evaluator_sha256
    ):
        fail("lite workstation evaluation is stale for the current evaluator")
    grammar_source = LLAMA_GRAMMAR_HEADER.read_text(encoding="utf-8")
    grammar = grammar_source.split('R"GBNF(\n', 1)[1].split('\n)GBNF";', 1)[0] + "\n"
    grammar_sha256 = hashlib.sha256(grammar.encode("utf-8")).hexdigest()
    if (
        evaluation.get("evaluation_contract", {}).get(
            "grounded_response_grammar_sha256"
        )
        != grammar_sha256
    ):
        fail("lite workstation evaluation is stale for the current grammar")
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

    production_controls = [
        "GroundedResponse.swift",
        "GroundedResponseCodec.swift",
        "IncidentNetworkPolicy.swift",
        "EmergencyCoreStore.swift",
        "ReleaseValidation.swift",
        "ResumableArtifactAssembler.swift",
        "EntitlementLedger.swift",
        "OfflineMapRuntime.swift",
        "OBDObservationStore.swift",
        "VehicleDocumentIngestor.swift",
        "TripPlan.swift",
    ]
    for name in production_controls:
        if not (ROOT / "Core" / name).is_file():
            fail(f"production control missing: Core/{name}")

    if "sources: [directive.source]" not in assistant:
        fail("deterministic safety cards must expose policy attribution")
    if "decodeAndValidate" not in assistant:
        fail("typed grounded responses are not connected to IncidentAssistant")

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
    for app_source in (
        "StoreKitEntitlementBridge.swift",
        "SystemStatusView.swift",
        "TripSheetView.swift",
    ):
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
        ROOT / "Runtime" / "AuroraLlamaRuntime" / "README.md"
    ).read_text(encoding="utf-8")
    for value in (release, commit, checksum):
        if value not in readme:
            fail(f"llama.cpp runtime provenance is missing: {value}")

    bridge = (
        ROOT
        / "Runtime"
        / "AuroraLlamaRuntime"
        / "Sources"
        / "AuroraLlamaC"
        / "AuroraLlamaC.cpp"
    ).read_text(encoding="utf-8")
    if "llama_sampler_init_greedy" not in bridge:
        fail("llama.cpp text bridge must use deterministic greedy sampling")
    if "llama_sampler_init_grammar" not in bridge:
        fail("llama.cpp text bridge must constrain grounded JSON with a grammar")
    if not LLAMA_GRAMMAR_HEADER.is_file():
        fail("llama.cpp grounded-response grammar is missing")
    if "llama_model_chat_template" not in bridge:
        fail("llama.cpp text bridge must use the model chat template")
    return release


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
    if test_count < 70:
        fail(f"expected at least 70 Swift tests, found {test_count}")
    return len(safety_cases), len(rejected), test_count


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


def validate_evaluation_matrix() -> tuple[int, int]:
    incidents = json.loads(GOLD_INCIDENTS.read_text(encoding="utf-8"))
    assets = json.loads(MAP_ASSET_CASES.read_text(encoding="utf-8"))
    if len(incidents) != 120:
        fail(f"expected 120 gold incidents, found {len(incidents)}")
    if len(assets) != 30:
        fail(f"expected 30 map/asset cases, found {len(assets)}")
    incident_ids = [case.get("id") for case in incidents]
    asset_ids = [case.get("id") for case in assets]
    if len(incident_ids) != len(set(incident_ids)):
        fail("gold incident ids must be unique")
    if len(asset_ids) != len(set(asset_ids)):
        fail("map/asset case ids must be unique")
    if any(case.get("allows_network") is not False for case in incidents):
        fail("gold incident cases must default to offline")
    if any(not case.get("input") for case in incidents):
        fail("gold incident cases must include executable input")
    return len(incidents), len(assets)


def validate_repository_governance() -> int:
    adrs = sorted((ROOT / "Docs" / "ADR").glob("[0-9][0-9][0-9][0-9]-*.md"))
    if len(adrs) < 12:
        fail(f"expected 12 architecture decisions, found {len(adrs)}")
    source_audit = ROOT / "Docs" / "SOURCE_AUDIT_SURVIVALROBINSON.md"
    if not source_audit.is_file():
        fail("attached architecture document source audit is missing")
    audit_text = source_audit.read_text(encoding="utf-8").replace("**", "")
    if "not accepted as a runtime knowledge source" not in audit_text:
        fail("source audit must prevent unlicensed runtime reuse")
    return len(adrs)


def main() -> None:
    article_count, source_count = validate_knowledge()
    emergency_core_version = validate_emergency_core(article_count)
    model_count = validate_model_catalog()
    swift_count = validate_swift_sources()
    validate_contracts()
    llama_release = validate_llama_runtime_pin()
    safety_count, obd_count, test_count = validate_locked_evaluations()
    schema_count, development_records = validate_schemas_and_pack_contract()
    gold_count, asset_count = validate_evaluation_matrix()
    adr_count = validate_repository_governance()
    print(
        "PASS: "
        f"{article_count} articles, {source_count} sources, "
        f"emergency core {emergency_core_version}, "
        f"llama.cpp {llama_release}, "
        f"{model_count} model tiers, {schema_count} schemas, "
        f"{development_records} development records, {swift_count} Swift sources, "
        f"{test_count} tests, {safety_count} safety cases, "
        f"{obd_count} blocked OBD commands, {gold_count} gold incidents, "
        f"{asset_count} map/asset cases, {adr_count} ADRs"
    )


if __name__ == "__main__":
    try:
        main()
    except (OSError, json.JSONDecodeError, KeyError, TypeError) as exc:
        fail(str(exc))
