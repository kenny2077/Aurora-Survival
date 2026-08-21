#!/usr/bin/env python3
"""Build Aurora's deterministic, read-only wilderness knowledge database."""

from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import re
import sqlite3
import tempfile
from typing import Any

from build_expert_corpus_v3 import build as compile_corpus_v3


ROOT = pathlib.Path(__file__).resolve().parents[1]
DEFAULT_INPUT = ROOT / "Resources" / "Knowledge" / "survival_knowledge_source.json"
DEFAULT_LEGACY = ROOT / "Resources" / "Knowledge" / "legacy_anchor_manifest.json"
DEFAULT_OUTPUT = ROOT / "Resources" / "Knowledge" / "survival_knowledge.sqlite"
DEFAULT_FALLBACK = ROOT / "Resources" / "Knowledge" / "survival_fallback.json"
DEFAULT_EXPERT_LANGUAGE = (
    ROOT / "Resources" / "Knowledge" / "expert_user_language.json"
)
DEFAULT_EXPERT_CORPUS = (
    ROOT / "Resources" / "Knowledge" / "expert_shadow_corpus.json"
)
DEFAULT_CORPUS_V3_SOURCES = ROOT / "Resources" / "Knowledge" / "CorpusSources"
DEFAULT_CORPUS_V3 = ROOT / "Resources" / "Knowledge" / "expert_corpus_v3.json"
DEFAULT_CORPUS_V3_REPORT = (
    ROOT / "Reports" / "survival-manual-2026" / "corpus-import-report.json"
)
EXPECTED_CHAPTERS = 10
EXPECTED_LESSONS = 70
PASSAGES_PER_LESSON = 15


class ContentError(ValueError):
    pass


def canonical_json(value: Any) -> bytes:
    return (
        json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
        + "\n"
    ).encode("utf-8")


def words(value: str) -> list[str]:
    return re.findall(r"[A-Za-z0-9]+(?:['’-][A-Za-z0-9]+)?", value)


def validate_source(content: dict[str, Any], legacy: list[dict[str, Any]]) -> None:
    if content.get("schemaVersion") != 1:
        raise ContentError("schemaVersion must be 1")
    chapters = content.get("chapters", [])
    lessons = content.get("lessons", [])
    sources = content.get("sources", [])
    if len(chapters) != EXPECTED_CHAPTERS:
        raise ContentError(f"expected {EXPECTED_CHAPTERS} chapters")
    if [chapter["number"] for chapter in chapters] != list(range(1, 11)):
        raise ContentError("chapter numbers must be 1 through 10")
    if len(lessons) != EXPECTED_LESSONS:
        raise ContentError(f"expected {EXPECTED_LESSONS} lessons")

    source_ids = {source["id"] for source in sources}
    chapter_ids = {chapter["id"] for chapter in chapters}
    lesson_ids = {lesson["id"] for lesson in lessons}
    if len(source_ids) != len(sources) or len(chapter_ids) != len(chapters):
        raise ContentError("source and chapter IDs must be unique")
    if len(lesson_ids) != len(lessons):
        raise ContentError("lesson IDs must be unique")
    expert_policy = content.get("expertPolicy", {})
    low_risk_ids = set(expert_policy.get("lowRiskLessonIDs", []))
    critical_ids = set(expert_policy.get("criticalLessonIDs", []))
    if not low_risk_ids or not critical_ids:
        raise ContentError("expert policy needs low-risk and critical lesson IDs")
    if not low_risk_ids.isdisjoint(critical_ids):
        raise ContentError("expert low-risk and critical lessons must be disjoint")
    if not low_risk_ids.union(critical_ids).issubset(lesson_ids):
        raise ContentError("expert policy references an unknown lesson")

    supplemental = content.get("expertSupplementalScenarios", [])
    supplemental_ids = [item.get("id") for item in supplemental]
    base_scenario_ids = {f"{lesson_id}-scenario" for lesson_id in lesson_ids}
    all_scenario_ids = base_scenario_ids.union(supplemental_ids)
    if len(set(supplemental_ids)) != len(supplemental_ids) or None in supplemental_ids:
        raise ContentError("supplemental Expert scenario IDs must be present and unique")
    if base_scenario_ids.intersection(supplemental_ids):
        raise ContentError("supplemental Expert scenario IDs must not replace lesson scenarios")
    for scenario in supplemental:
        scenario_id = scenario["id"]
        if scenario.get("lessonID") not in lesson_ids:
            raise ContentError(f"{scenario_id} references an unknown lesson")
        if scenario.get("chapterID") not in chapter_ids:
            raise ContentError(f"{scenario_id} references an unknown chapter")
        if scenario.get("reviewStatus") != "primary-source-verified":
            raise ContentError(f"{scenario_id} is not source reviewed")
        if not scenario.get("reviewerID"):
            raise ContentError(f"{scenario_id} needs reviewer identity")
        if scenario.get("independentApprovalStatus") not in {
            "pending-release-review", "approved",
        }:
            raise ContentError(f"{scenario_id} needs independent approval status")
        if not scenario.get("observableCues") or not scenario.get("claims"):
            raise ContentError(f"{scenario_id} needs cues and claims")
        if not set(scenario.get("relatedScenarioIDs", [])).issubset(all_scenario_ids):
            raise ContentError(f"{scenario_id} links an unknown scenario")
        for claim in scenario["claims"]:
            locators = claim.get("sourceLocators", [])
            if not locators or any(
                not item.get("locator") or item.get("sourceID") not in source_ids
                for item in locators
            ):
                raise ContentError(f"{scenario_id} claim lacks exact source locators")

    expected_counts = [6, 7, 7, 7, 6, 7, 6, 8, 8, 8]
    for chapter, expected in zip(chapters, expected_counts):
        chapter_lessons = [item for item in lessons if item["chapterID"] == chapter["id"]]
        if len(chapter_lessons) != expected:
            raise ContentError(f"{chapter['id']} needs {expected} lessons")
        if not 4 <= len(words(chapter["purpose"])) <= 8:
            raise ContentError(f"{chapter['id']} purpose must contain 4–8 words")

    forbidden = [
        "identify this mushroom", "identify this plant", "orange high-voltage cable",
        "repair the traction battery", "disable the airbag", "repair the brake line",
    ]
    for lesson in lessons:
        if lesson["chapterID"] not in chapter_ids:
            raise ContentError(f"unknown chapter: {lesson['id']}")
        if not 3 <= len(lesson["actions"]) <= 6:
            raise ContentError(f"{lesson['id']} needs 3–6 actions")
        if not 1 <= len(lesson["warnings"]) <= 3:
            raise ContentError(f"{lesson['id']} needs 1–3 warnings")
        if not lesson.get("keywords") or not lesson.get("aliases"):
            raise ContentError(f"{lesson['id']} needs keywords and aliases")
        if not set(lesson["sourceIDs"]).issubset(source_ids):
            raise ContentError(f"{lesson['id']} has an unknown source")
        combined = " ".join(
            [lesson["goal"], *lesson["actions"], *lesson["warnings"]]
        ).lower()
        if any(phrase in combined for phrase in forbidden):
            raise ContentError(f"{lesson['id']} contains prohibited guidance")

    old_ids: set[str] = set()
    for item in legacy:
        old_id = item.get("legacyChunkID")
        if not old_id or old_id in old_ids:
            raise ContentError("legacy chunk IDs must be present and unique")
        old_ids.add(old_id)
        status = item.get("status")
        if status not in {"redirected", "retired"}:
            raise ContentError(f"invalid legacy status: {old_id}")
        replacement = item.get("replacementLessonID")
        if replacement not in lesson_ids:
            raise ContentError(f"legacy replacement is invalid: {old_id}")


def validate_expert_corpus(
    corpus: dict[str, Any],
    content: dict[str, Any],
) -> None:
    if corpus.get("schemaVersion") != 1 or not corpus.get("corpusVersion"):
        raise ContentError("Expert shadow corpus version is invalid")
    documents = corpus.get("documents", [])
    chunks = corpus.get("chunks", [])
    document_ids = [item.get("id") for item in documents]
    chunk_ids = [item.get("id") for item in chunks]
    if not documents or not chunks:
        raise ContentError("Expert shadow corpus needs documents and chunks")
    if len(set(document_ids)) != len(document_ids) or None in document_ids:
        raise ContentError("Expert document IDs must be present and unique")
    if len(set(chunk_ids)) != len(chunk_ids) or None in chunk_ids:
        raise ContentError("Expert chunk IDs must be present and unique")
    allowed_authority = {"authority", "corroboration", "discovery"}
    allowed_redistribution = {
        "public_domain_full_text", "public_domain_selected_sections",
        "linked_metadata_only", "development_only",
    }
    for item in documents:
        if item.get("authorityTier") not in allowed_authority:
            raise ContentError(f"invalid Expert authority tier: {item.get('id')}")
        if item.get("redistributionClass") not in allowed_redistribution:
            raise ContentError(f"invalid redistribution class: {item.get('id')}")
        for key in (
            "title", "organization", "url", "jurisdiction", "publishedAt",
            "updatedAt", "reviewedAt", "licenseEvidence",
        ):
            if not item.get(key):
                raise ContentError(f"Expert document metadata missing {key}: {item.get('id')}")
    scenario_ids = {f"{item['id']}-scenario" for item in content["lessons"]}
    scenario_ids.update(
        item["id"] for item in content.get("expertSupplementalScenarios", [])
    )
    shipping_documents = {
        item["id"] for item in documents
        if item["redistributionClass"] not in {
            "linked_metadata_only", "development_only",
        }
    }
    for chunk in chunks:
        if chunk.get("documentID") not in shipping_documents:
            raise ContentError(
                f"unlicensed/development document cannot ship text: {chunk.get('id')}"
            )
        if not chunk.get("locator") or not chunk.get("sectionPath"):
            raise ContentError(f"Expert chunk needs a stable locator: {chunk.get('id')}")
        if len(words(chunk.get("text", ""))) < 8:
            raise ContentError(f"Expert chunk is too shallow: {chunk.get('id')}")
        if not set(chunk.get("scenarioIDs", [])).issubset(scenario_ids):
            raise ContentError(f"Expert chunk links an unknown scenario: {chunk.get('id')}")
    for edge in corpus.get("corroborationEdges", []):
        if not {edge.get("leftDocumentID"), edge.get("rightDocumentID")}.issubset(
            set(document_ids)
        ):
            raise ContentError(f"corroboration edge references unknown source: {edge.get('id')}")
    for conflict in corpus.get("conflicts", []):
        if not set(conflict.get("documentIDs", [])).issubset(set(document_ids)):
            raise ContentError(f"conflict references unknown source: {conflict.get('id')}")
    for promotion in corpus.get("claimPromotions", []):
        if promotion.get("scenarioID") not in scenario_ids:
            raise ContentError(f"claim promotion references unknown scenario: {promotion.get('id')}")
        if not set(promotion.get("sourceDocumentIDs", [])).issubset(set(document_ids)):
            raise ContentError(f"claim promotion references unknown source: {promotion.get('id')}")
        if promotion.get("status") == "human_approved":
            sources = [
                item for item in documents
                if item["id"] in promotion["sourceDocumentIDs"]
            ]
            if len({item["id"] for item in sources if item["authorityTier"] == "authority"}) < 2:
                raise ContentError(
                    f"approved critical promotion lacks two authorities: {promotion.get('id')}"
                )
            if not promotion.get("humanReviewerID"):
                raise ContentError(f"approved promotion lacks human review: {promotion.get('id')}")


def validate_corpus_v3(corpus: dict[str, Any], content: dict[str, Any]) -> None:
    if corpus.get("schemaVersion") != 3 or not corpus.get("corpusVersion"):
        raise ContentError("Expert corpus-v3 contract is invalid")
    required_groups = (
        "documents", "sections", "chunks", "duplicateAliases", "scenarios",
        "claims", "claimSources", "conflicts", "supersessions", "buildProvenance",
    )
    if any(key not in corpus for key in required_groups):
        raise ContentError("Expert corpus-v3 is incomplete")
    for key in ("documents", "sections", "chunks", "scenarios", "claims"):
        ids = [item.get("id") for item in corpus[key]]
        if None in ids or len(ids) != len(set(ids)):
            raise ContentError(f"Expert corpus-v3 {key} IDs must be present and unique")
    document_ids = {item["id"] for item in corpus["documents"]}
    chunk_ids = {item["id"] for item in corpus["chunks"]}
    scenario_ids = {item["id"] for item in corpus["scenarios"]}
    claim_ids = {item["id"] for item in corpus["claims"]}
    chapter_ids = {item["id"] for item in content["chapters"]}
    for document in corpus["documents"]:
        if document.get("redistributionClass") != "owned_full_text":
            raise ContentError(f"unsupported corpus-v3 redistribution: {document['id']}")
        if not document.get("sourceSHA256") or not document.get("reviewerAuditID"):
            raise ContentError(f"corpus-v3 provenance is incomplete: {document['id']}")
    for chunk in corpus["chunks"]:
        if chunk.get("documentID") not in document_ids:
            raise ContentError(f"corpus-v3 chunk has unknown document: {chunk['id']}")
        if not chunk.get("sectionPath") or not chunk.get("locator"):
            raise ContentError(f"corpus-v3 chunk lacks locator: {chunk['id']}")
        if not 1 <= chunk.get("tokenEstimate", 0) <= 500:
            raise ContentError(f"corpus-v3 chunk exceeds boundary: {chunk['id']}")
    for alias in corpus["duplicateAliases"]:
        if alias.get("canonicalChunkID") not in chunk_ids:
            raise ContentError("duplicate alias lacks canonical chunk")
    for scenario in corpus["scenarios"]:
        if scenario.get("chapterID") not in chapter_ids:
            raise ContentError(f"corpus-v3 scenario has unknown chapter: {scenario['id']}")
        if scenario.get("reviewStatus") != "humanApproved":
            raise ContentError(f"development scenario is not human approved: {scenario['id']}")
        if not set(scenario.get("sourceChunkIDs", [])).issubset(chunk_ids):
            raise ContentError(f"corpus-v3 scenario has unknown chunks: {scenario['id']}")
    for claim in corpus["claims"]:
        if claim.get("scenarioID") not in scenario_ids:
            raise ContentError(f"corpus-v3 claim has unknown scenario: {claim['id']}")
    located_claims = {item.get("claimID") for item in corpus["claimSources"]}
    if located_claims != claim_ids:
        raise ContentError("every corpus-v3 claim requires a source locator")
    if any(item.get("status") == "unresolved" for item in corpus["conflicts"]):
        raise ContentError("corpus-v3 has unresolved conflicts")


def lesson_passages(lesson: dict[str, Any], chapter: dict[str, Any]) -> list[dict[str, Any]]:
    answer = " ".join([lesson["goal"], lesson["actions"][0]])
    if len(words(answer)) > 120:
        raise ContentError(f"answer text exceeds 120 words: {lesson['id']}")
    seeds: list[tuple[str, str, str]] = [
        ("overview", lesson["title"], " ".join([lesson["goal"], *lesson["actions"][:2]])),
    ]
    seeds.extend(
        ("action", f"{lesson['title']}: step {index}", action)
        for index, action in enumerate(lesson["actions"], 1)
    )
    seeds.extend(
        ("warning", f"{lesson['title']}: warning {index}", warning)
        for index, warning in enumerate(lesson["warnings"], 1)
    )
    facets = list(dict.fromkeys([*lesson["aliases"], *lesson["keywords"]]))
    index = 0
    while len(seeds) < PASSAGES_PER_LESSON:
        cue = facets[index % len(facets)]
        action = lesson["actions"][index % len(lesson["actions"])]
        warning = lesson["warnings"][index % len(lesson["warnings"])]
        seeds.append(
            (
                "intent",
                f"{lesson['title']}: {cue}",
                f"Use this guidance when the problem involves {cue}. {action} Safety limit: {warning}",
            )
        )
        index += 1

    passages = []
    for order, (kind, title, reference_text) in enumerate(seeds[:PASSAGES_PER_LESSON]):
        passages.append(
            {
                "id": f"{lesson['id']}-p{order + 1:02d}",
                "lessonID": lesson["id"],
                "chapterID": chapter["id"],
                "kind": kind,
                "displayOrder": order,
                "title": title,
                "answerText": answer,
                "referenceText": reference_text,
            }
        )
    return passages


def numeric_facts(value: str) -> list[str]:
    return re.findall(r"\b\d+(?:[,.]\d+)*(?:%|°|[A-Za-z]+)?\b", value)


def expert_risk_class(content: dict[str, Any], lesson_id: str) -> str:
    policy = content["expertPolicy"]
    if lesson_id in policy["criticalLessonIDs"]:
        return "critical"
    if lesson_id in policy["lowRiskLessonIDs"]:
        return "low"
    return "high"


def apply_corpus_v3(
    connection: sqlite3.Connection,
    corpus: dict[str, Any],
    chapters: dict[str, dict[str, Any]],
) -> None:
    """Overlay canonical corpus-v3 claims without changing Manual/Lite records."""
    documents = {item["id"]: item for item in corpus["documents"]}
    claims_by_scenario: dict[str, list[dict[str, Any]]] = {}
    for claim in corpus["claims"]:
        claims_by_scenario.setdefault(claim["scenarioID"], []).append(claim)
    source_by_claim = {item["claimID"]: item for item in corpus["claimSources"]}

    for document in corpus["documents"]:
        connection.execute(
            "INSERT OR REPLACE INTO sources VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            (
                document["id"], document["title"],
                document.get("displayOrganization") or "", document.get("url") or "",
                document["publishedAt"], document["updatedAt"], document["reviewedAt"],
                document["title"], document["jurisdiction"],
                document["redistributionClass"], "humanApproved",
            ),
        )
        connection.execute(
            "INSERT INTO corpus_documents VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            (
                document["id"], document["title"], document.get("displayOrganization"),
                document.get("url"), document["authorityTier"],
                document["redistributionClass"], document["language"],
                document["jurisdiction"], document["publishedAt"],
                document["updatedAt"], document["reviewedAt"],
                document["reviewerAuditID"], document["canonicalPriority"],
                document["sourceSHA256"],
            ),
        )
        connection.execute(
            "INSERT INTO expert_source_documents VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            (
                document["id"], document["title"],
                document.get("displayOrganization") or "", document.get("url") or "",
                document["authorityTier"], document["redistributionClass"],
                document["jurisdiction"], document["publishedAt"],
                document["updatedAt"], document["reviewedAt"],
                "Owned full text; developer review recorded in private audit",
                document["sourceSHA256"], None,
            ),
        )
    for section in corpus["sections"]:
        connection.execute(
            "INSERT INTO corpus_sections VALUES (?, ?, ?, ?, ?, ?, ?)",
            (
                section["id"], section["documentID"], section["chapterID"],
                section["sectionKey"], section["title"], section["sectionPath"],
                section["locator"],
            ),
        )
    scenarios_by_chunk: dict[str, list[str]] = {}
    for scenario in corpus["scenarios"]:
        for chunk_id in scenario["sourceChunkIDs"]:
            scenarios_by_chunk.setdefault(chunk_id, []).append(scenario["id"])
    for chunk in corpus["chunks"]:
        content_hash = hashlib.sha256(chunk["text"].encode("utf-8")).hexdigest()
        connection.execute(
            "INSERT INTO corpus_chunks VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
            (
                chunk["id"], chunk["documentID"], chunk["sectionKey"],
                chunk["sectionPath"], chunk["locator"], chunk["text"],
                chunk["tokenEstimate"], chunk["normalizedSHA256"], 1,
            ),
        )
        cursor = connection.execute(
            "INSERT INTO expert_source_chunks VALUES (?, ?, ?, ?, ?, ?)",
            (
                chunk["id"], chunk["documentID"], chunk["locator"],
                chunk["sectionPath"], chunk["text"], content_hash,
            ),
        )
        connection.execute(
            "INSERT INTO expert_source_chunks_fts(rowid, text, locator, section_path) VALUES (?, ?, ?, ?)",
            (cursor.lastrowid, chunk["text"], chunk["locator"], chunk["sectionPath"]),
        )
    for alias in corpus["duplicateAliases"]:
        connection.execute(
            "INSERT INTO corpus_chunk_aliases VALUES (?, ?, ?, ?, ?, ?, ?)",
            (
                alias["aliasChunkID"], alias["canonicalChunkID"], alias["documentID"],
                alias["sectionPath"], alias["locator"], alias["normalizedSHA256"],
                alias["relationship"],
            ),
        )

    for scenario in corpus["scenarios"]:
        existing = connection.execute(
            "SELECT lesson_id FROM expert_scenarios WHERE scenario_id=?",
            (scenario["id"],),
        ).fetchone()
        is_new_scenario = existing is None
        corroborating_source_ids: list[str] = []
        if existing:
            corroborating_source_ids = [row[0] for row in connection.execute(
                """
                SELECT DISTINCT ecs.source_id FROM expert_claim_sources ecs
                JOIN expert_claims ec ON ec.claim_id=ecs.claim_id
                WHERE ec.scenario_id=? ORDER BY ecs.source_id
                """,
                (scenario["id"],),
            )]
            connection.execute(
                "DELETE FROM expert_numeric_facts WHERE claim_id IN (SELECT claim_id FROM expert_claims WHERE scenario_id=?)",
                (scenario["id"],),
            )
            connection.execute(
                "DELETE FROM expert_claim_sources WHERE claim_id IN (SELECT claim_id FROM expert_claims WHERE scenario_id=?)",
                (scenario["id"],),
            )
            connection.execute("DELETE FROM expert_claims WHERE scenario_id=?", (scenario["id"],))
        else:
            connection.execute(
                "INSERT INTO expert_scenarios VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (
                    scenario["id"], None, scenario["chapterID"], scenario["title"],
                    scenario["applicability"],
                    canonical_json(scenario["observableCues"]).decode().strip(),
                    canonical_json(scenario["prerequisites"]).decode().strip(),
                    scenario["riskClass"], scenario["jurisdiction"], scenario["units"],
                    "[]", scenario["reviewStatus"], scenario["reviewedAt"],
                ),
            )
        for source_id in corroborating_source_ids:
            connection.execute(
                "INSERT INTO corpus_scenario_corroboration VALUES (?, ?, ?, ?)",
                (scenario["id"], scenario["sourceDocumentID"], source_id, "compatible_prior_authority"),
            )
        action_texts: list[str] = []
        contraindication_texts: list[str] = []
        for claim in sorted(claims_by_scenario[scenario["id"]], key=lambda item: item["displayOrder"]):
            connection.execute(
                "INSERT INTO expert_claims VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                (
                    claim["id"], claim["scenarioID"], claim["displayOrder"], claim["kind"],
                    claim["text"], claim["applicability"], claim["requirementClass"],
                    claim["reviewedAt"],
                ),
            )
            locator = source_by_claim[claim["id"]]
            connection.execute(
                "INSERT INTO expert_claim_sources VALUES (?, ?, ?)",
                (
                    claim["id"], locator["documentID"],
                    f"{locator['sectionPath']} → {locator['locator']}",
                ),
            )
            connection.execute(
                "INSERT INTO corpus_claim_source_locators VALUES (?, ?, ?, ?, ?)",
                (
                    claim["id"], locator["documentID"], locator["chunkID"],
                    locator["sectionPath"], locator["locator"],
                ),
            )
            for token in sorted(set(numeric_facts(claim["text"]))):
                connection.execute(
                    "INSERT INTO expert_numeric_facts VALUES (?, ?)",
                    (claim["id"], token.lower()),
                )
            if claim["kind"] == "action":
                action_texts.append(claim["text"])
            elif claim["kind"] in {"contraindication", "escalation", "stop_condition"}:
                contraindication_texts.append(claim["text"])
            connection.execute(
                "INSERT INTO expert_claim_promotions VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (
                    f"promotion-{claim['id']}", scenario["id"], claim["kind"], claim["text"],
                    canonical_json([locator["documentID"]]).decode().strip(),
                    canonical_json([locator["locator"]]).decode().strip(), "[]",
                    "human_approved", scenario["reviewerAuditID"],
                    scenario["reviewerAuditID"], scenario["reviewerAuditID"],
                ),
            )
        chapter_title = chapters[scenario["chapterID"]]["title"]
        if is_new_scenario:
            connection.execute(
                "INSERT INTO expert_scenarios_fts VALUES (?, ?, ?, ?, ?, ?, ?)",
                (
                    scenario["id"], chapter_title, scenario["title"], scenario["applicability"],
                    " ".join(scenario["observableCues"]), " ".join(action_texts),
                    " ".join(contraindication_texts),
                ),
            )
        connection.execute(
            "INSERT INTO corpus_scenario_locators VALUES (?, ?, ?, ?, ?)",
            (
                scenario["id"], scenario["sourceDocumentID"],
                scenario["sourceChunkIDs"][0], scenario["sectionPath"], scenario["locator"],
            ),
        )
    for chunk_id, scenario_ids in sorted(scenarios_by_chunk.items()):
        connection.executemany(
            "INSERT INTO expert_chunk_scenarios VALUES (?, ?)",
            [(chunk_id, scenario_id) for scenario_id in sorted(scenario_ids)],
        )
    for conflict in corpus["conflicts"]:
        connection.execute(
            "INSERT INTO corpus_conflicts VALUES (?, ?, ?, ?, ?)",
            (
                conflict["id"], conflict["scenarioID"],
                canonical_json(conflict["claimIDs"]).decode().strip(),
                conflict["reason"], conflict["status"],
            ),
        )
    for supersession in corpus["supersessions"]:
        connection.execute(
            "INSERT INTO corpus_supersessions VALUES (?, ?, ?, ?)",
            (
                supersession["id"], supersession["supersededID"],
                supersession["replacementID"], supersession["reason"],
            ),
        )
    connection.execute(
        "INSERT INTO corpus_build_provenance VALUES (?, ?, ?)",
        (corpus["corpusVersion"], corpus["generatedAt"], canonical_json(corpus["buildProvenance"]).decode().strip()),
    )


def create_database(
    content: dict[str, Any],
    legacy: list[dict[str, Any]],
    expert_language: dict[str, Any],
    expert_corpus: dict[str, Any],
    corpus_v3: dict[str, Any],
    destination: pathlib.Path,
) -> None:
    chapters = {chapter["id"]: chapter for chapter in content["chapters"]}
    expected_scenarios = {f"{item['id']}-scenario" for item in content["lessons"]}
    language_records = expert_language.get("scenarios", [])
    language_by_scenario = {
        item["scenarioID"]: item.get("aliases", [])
        for item in language_records
    }
    if set(language_by_scenario) != expected_scenarios:
        raise ContentError("expert user-language aliases must cover every scenario")
    if any(not aliases for aliases in language_by_scenario.values()):
        raise ContentError("expert user-language aliases cannot be empty")
    connection = sqlite3.connect(destination)
    try:
        connection.executescript(
            """
            PRAGMA page_size=4096;
            PRAGMA journal_mode=DELETE;
            PRAGMA synchronous=FULL;
            PRAGMA auto_vacuum=NONE;
            PRAGMA foreign_keys=ON;
            CREATE TABLE metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL);
            CREATE TABLE sources (
                source_id TEXT PRIMARY KEY, title TEXT NOT NULL,
                organization TEXT NOT NULL, url TEXT NOT NULL,
                published_at TEXT NOT NULL, updated_at TEXT NOT NULL,
                reviewed_at TEXT NOT NULL, locator TEXT NOT NULL,
                jurisdiction TEXT NOT NULL, license_status TEXT NOT NULL,
                review_level TEXT NOT NULL
            );
            CREATE TABLE chapters (
                chapter_id TEXT PRIMARY KEY, chapter_no INTEGER NOT NULL UNIQUE,
                title TEXT NOT NULL, purpose TEXT NOT NULL, overview TEXT NOT NULL,
                symbol TEXT NOT NULL, theme TEXT NOT NULL
            );
            CREATE TABLE lessons (
                lesson_id TEXT PRIMARY KEY, chapter_id TEXT NOT NULL,
                display_order INTEGER NOT NULL, title TEXT NOT NULL,
                goal TEXT NOT NULL, keywords_json TEXT NOT NULL,
                aliases_json TEXT NOT NULL, jurisdiction TEXT NOT NULL,
                units TEXT NOT NULL, review_status TEXT NOT NULL,
                reviewed_at TEXT NOT NULL,
                FOREIGN KEY(chapter_id) REFERENCES chapters(chapter_id)
            );
            CREATE TABLE lesson_actions (
                lesson_id TEXT NOT NULL, display_order INTEGER NOT NULL,
                text TEXT NOT NULL, PRIMARY KEY(lesson_id, display_order),
                FOREIGN KEY(lesson_id) REFERENCES lessons(lesson_id)
            );
            CREATE TABLE lesson_warnings (
                lesson_id TEXT NOT NULL, display_order INTEGER NOT NULL,
                text TEXT NOT NULL, PRIMARY KEY(lesson_id, display_order),
                FOREIGN KEY(lesson_id) REFERENCES lessons(lesson_id)
            );
            CREATE TABLE passages (
                passage_id TEXT PRIMARY KEY, lesson_id TEXT NOT NULL,
                chapter_id TEXT NOT NULL, kind TEXT NOT NULL,
                display_order INTEGER NOT NULL, title TEXT NOT NULL,
                answer_text TEXT NOT NULL, reference_text TEXT NOT NULL,
                keywords_json TEXT NOT NULL, intent_tags_json TEXT NOT NULL,
                hazard_tags_json TEXT NOT NULL, biome_tags_json TEXT NOT NULL,
                jurisdiction TEXT NOT NULL, units TEXT NOT NULL,
                review_status TEXT NOT NULL, reviewed_at TEXT NOT NULL,
                FOREIGN KEY(lesson_id) REFERENCES lessons(lesson_id),
                FOREIGN KEY(chapter_id) REFERENCES chapters(chapter_id)
            );
            CREATE TABLE passage_sources (
                passage_id TEXT NOT NULL, source_id TEXT NOT NULL,
                PRIMARY KEY(passage_id, source_id),
                FOREIGN KEY(passage_id) REFERENCES passages(passage_id),
                FOREIGN KEY(source_id) REFERENCES sources(source_id)
            );
            CREATE TABLE aliases (
                alias TEXT NOT NULL, lesson_id TEXT NOT NULL,
                normalized_alias TEXT NOT NULL,
                PRIMARY KEY(alias, lesson_id),
                FOREIGN KEY(lesson_id) REFERENCES lessons(lesson_id)
            );
            CREATE TABLE legacy_anchors (
                legacy_chunk_id TEXT PRIMARY KEY, status TEXT NOT NULL,
                replacement_lesson_id TEXT NOT NULL,
                replacement_passage_id TEXT NOT NULL, note TEXT NOT NULL,
                FOREIGN KEY(replacement_lesson_id) REFERENCES lessons(lesson_id),
                FOREIGN KEY(replacement_passage_id) REFERENCES passages(passage_id)
            );
            CREATE TABLE expert_scenarios (
                scenario_id TEXT PRIMARY KEY, lesson_id TEXT,
                chapter_id TEXT NOT NULL, title TEXT NOT NULL,
                applicability TEXT NOT NULL, observable_cues_json TEXT NOT NULL,
                prerequisites_json TEXT NOT NULL, risk_class TEXT NOT NULL,
                jurisdiction TEXT NOT NULL, units TEXT NOT NULL,
                related_scenario_ids_json TEXT NOT NULL,
                review_status TEXT NOT NULL, reviewed_at TEXT NOT NULL,
                FOREIGN KEY(lesson_id) REFERENCES lessons(lesson_id),
                FOREIGN KEY(chapter_id) REFERENCES chapters(chapter_id)
            );
            CREATE TABLE expert_claims (
                claim_id TEXT PRIMARY KEY, scenario_id TEXT NOT NULL,
                display_order INTEGER NOT NULL, kind TEXT NOT NULL,
                text TEXT NOT NULL, applicability TEXT NOT NULL,
                requirement_class TEXT NOT NULL, reviewed_at TEXT NOT NULL,
                FOREIGN KEY(scenario_id) REFERENCES expert_scenarios(scenario_id)
            );
            CREATE TABLE expert_claim_sources (
                claim_id TEXT NOT NULL, source_id TEXT NOT NULL,
                locator TEXT NOT NULL,
                PRIMARY KEY(claim_id, source_id),
                FOREIGN KEY(claim_id) REFERENCES expert_claims(claim_id),
                FOREIGN KEY(source_id) REFERENCES sources(source_id)
            );
            CREATE TABLE expert_numeric_facts (
                claim_id TEXT NOT NULL, token TEXT NOT NULL,
                PRIMARY KEY(claim_id, token),
                FOREIGN KEY(claim_id) REFERENCES expert_claims(claim_id)
            );
            CREATE TABLE expert_source_documents (
                document_id TEXT PRIMARY KEY, title TEXT NOT NULL,
                organization TEXT NOT NULL, url TEXT NOT NULL,
                authority_tier TEXT NOT NULL, redistribution_class TEXT NOT NULL,
                jurisdiction TEXT NOT NULL, published_at TEXT NOT NULL,
                updated_at TEXT NOT NULL, reviewed_at TEXT NOT NULL,
                license_evidence TEXT NOT NULL, content_hash TEXT NOT NULL,
                superseded_by_document_id TEXT,
                FOREIGN KEY(superseded_by_document_id)
                    REFERENCES expert_source_documents(document_id)
            );
            CREATE TABLE expert_source_chunks (
                chunk_id TEXT PRIMARY KEY, document_id TEXT NOT NULL,
                locator TEXT NOT NULL, section_path TEXT NOT NULL,
                text TEXT NOT NULL, content_hash TEXT NOT NULL,
                FOREIGN KEY(document_id)
                    REFERENCES expert_source_documents(document_id)
            );
            CREATE TABLE expert_chunk_scenarios (
                chunk_id TEXT NOT NULL, scenario_id TEXT NOT NULL,
                PRIMARY KEY(chunk_id, scenario_id),
                FOREIGN KEY(chunk_id) REFERENCES expert_source_chunks(chunk_id),
                FOREIGN KEY(scenario_id) REFERENCES expert_scenarios(scenario_id)
            );
            CREATE TABLE expert_corroboration_edges (
                edge_id TEXT PRIMARY KEY, left_document_id TEXT NOT NULL,
                right_document_id TEXT NOT NULL, topic TEXT NOT NULL,
                locator TEXT NOT NULL,
                FOREIGN KEY(left_document_id)
                    REFERENCES expert_source_documents(document_id),
                FOREIGN KEY(right_document_id)
                    REFERENCES expert_source_documents(document_id)
            );
            CREATE TABLE expert_conflicts (
                conflict_id TEXT PRIMARY KEY, document_ids_json TEXT NOT NULL,
                topic TEXT NOT NULL, resolution TEXT NOT NULL,
                jurisdiction TEXT NOT NULL
            );
            CREATE TABLE expert_claim_promotions (
                promotion_id TEXT PRIMARY KEY, scenario_id TEXT NOT NULL,
                kind TEXT NOT NULL, text TEXT NOT NULL,
                source_document_ids_json TEXT NOT NULL,
                source_locators_json TEXT NOT NULL,
                benchmark_gap_ids_json TEXT NOT NULL, status TEXT NOT NULL,
                extractor_review_id TEXT NOT NULL,
                critic_review_id TEXT NOT NULL, human_reviewer_id TEXT,
                FOREIGN KEY(scenario_id) REFERENCES expert_scenarios(scenario_id)
            );
            CREATE TABLE corpus_documents (
                document_id TEXT PRIMARY KEY, title TEXT NOT NULL,
                display_organization TEXT, url TEXT, authority_tier TEXT NOT NULL,
                redistribution_class TEXT NOT NULL, language TEXT NOT NULL,
                jurisdiction TEXT NOT NULL, published_at TEXT NOT NULL,
                updated_at TEXT NOT NULL, reviewed_at TEXT NOT NULL,
                reviewer_audit_id TEXT NOT NULL, canonical_priority INTEGER NOT NULL,
                source_sha256 TEXT NOT NULL
            );
            CREATE TABLE corpus_sections (
                section_id TEXT PRIMARY KEY, document_id TEXT NOT NULL,
                chapter_id TEXT NOT NULL, section_key TEXT NOT NULL,
                title TEXT NOT NULL, section_path TEXT NOT NULL,
                locator TEXT NOT NULL,
                FOREIGN KEY(document_id) REFERENCES corpus_documents(document_id)
            );
            CREATE TABLE corpus_chunks (
                chunk_id TEXT PRIMARY KEY, document_id TEXT NOT NULL,
                section_key TEXT NOT NULL, section_path TEXT NOT NULL,
                locator TEXT NOT NULL, text TEXT NOT NULL,
                token_estimate INTEGER NOT NULL, normalized_sha256 TEXT NOT NULL,
                is_canonical INTEGER NOT NULL,
                FOREIGN KEY(document_id) REFERENCES corpus_documents(document_id)
            );
            CREATE TABLE corpus_chunk_aliases (
                alias_chunk_id TEXT PRIMARY KEY, canonical_chunk_id TEXT NOT NULL,
                document_id TEXT NOT NULL, section_path TEXT NOT NULL,
                locator TEXT NOT NULL, normalized_sha256 TEXT NOT NULL,
                relationship TEXT NOT NULL,
                FOREIGN KEY(canonical_chunk_id) REFERENCES corpus_chunks(chunk_id)
            );
            CREATE TABLE corpus_scenario_locators (
                scenario_id TEXT PRIMARY KEY, document_id TEXT NOT NULL,
                chunk_id TEXT NOT NULL, section_path TEXT NOT NULL,
                locator TEXT NOT NULL,
                FOREIGN KEY(scenario_id) REFERENCES expert_scenarios(scenario_id),
                FOREIGN KEY(document_id) REFERENCES corpus_documents(document_id),
                FOREIGN KEY(chunk_id) REFERENCES corpus_chunks(chunk_id)
            );
            CREATE TABLE corpus_claim_source_locators (
                claim_id TEXT PRIMARY KEY, document_id TEXT NOT NULL,
                chunk_id TEXT NOT NULL, section_path TEXT NOT NULL,
                locator TEXT NOT NULL,
                FOREIGN KEY(claim_id) REFERENCES expert_claims(claim_id),
                FOREIGN KEY(document_id) REFERENCES corpus_documents(document_id),
                FOREIGN KEY(chunk_id) REFERENCES corpus_chunks(chunk_id)
            );
            CREATE TABLE corpus_scenario_corroboration (
                scenario_id TEXT NOT NULL, canonical_document_id TEXT NOT NULL,
                corroborating_source_id TEXT NOT NULL, relationship TEXT NOT NULL,
                PRIMARY KEY(scenario_id, corroborating_source_id),
                FOREIGN KEY(scenario_id) REFERENCES expert_scenarios(scenario_id)
            );
            CREATE TABLE corpus_conflicts (
                conflict_id TEXT PRIMARY KEY, scenario_id TEXT NOT NULL,
                claim_ids_json TEXT NOT NULL, reason TEXT NOT NULL,
                status TEXT NOT NULL
            );
            CREATE TABLE corpus_supersessions (
                supersession_id TEXT PRIMARY KEY, superseded_id TEXT NOT NULL,
                replacement_id TEXT NOT NULL, reason TEXT NOT NULL
            );
            CREATE TABLE corpus_build_provenance (
                corpus_version TEXT PRIMARY KEY, generated_at TEXT NOT NULL,
                provenance_json TEXT NOT NULL
            );
            CREATE VIRTUAL TABLE passages_fts USING fts5(
                passage_id UNINDEXED, chapter_title, lesson_title, goal,
                aliases, answer_text, reference_text, keywords,
                tokenize='unicode61 remove_diacritics 2'
            );
            CREATE VIRTUAL TABLE expert_scenarios_fts USING fts5(
                scenario_id UNINDEXED, chapter_title, title, applicability,
                observable_cues, actions, contraindications,
                tokenize='unicode61 remove_diacritics 2'
            );
            CREATE VIRTUAL TABLE expert_source_chunks_fts USING fts5(
                text, locator, section_path,
                content='expert_source_chunks', content_rowid='rowid',
                tokenize='unicode61 remove_diacritics 2'
            );
            CREATE INDEX idx_lessons_chapter ON lessons(chapter_id, display_order);
            CREATE INDEX idx_passages_lesson ON passages(lesson_id, display_order);
            CREATE INDEX idx_passages_chapter ON passages(chapter_id, display_order);
            CREATE INDEX idx_aliases_normalized ON aliases(normalized_alias);
            CREATE INDEX idx_expert_scenarios_lesson
                ON expert_scenarios(lesson_id);
            CREATE INDEX idx_expert_claims_scenario
                ON expert_claims(scenario_id, display_order);
            CREATE INDEX idx_expert_chunks_document
                ON expert_source_chunks(document_id);
            CREATE INDEX idx_expert_chunk_scenarios_scenario
                ON expert_chunk_scenarios(scenario_id, chunk_id);
            """
        )
        metadata = {
            "schema_version": "3",
            "content_version": content["contentVersion"],
            "reviewed_at": content["reviewDate"],
            "language": content["language"],
            "passages_per_lesson": str(PASSAGES_PER_LESSON),
            "expert_corpus_version": expert_corpus["corpusVersion"],
            "expert_contract_version": "3",
            "knowledge_contract_version": "3",
            "vector_contract_version": "3",
            "package_contract_version": "3",
            "corpus_v3_version": corpus_v3["corpusVersion"],
        }
        connection.executemany(
            "INSERT INTO metadata(key, value) VALUES (?, ?)", sorted(metadata.items())
        )
        for source in sorted(content["sources"], key=lambda item: item["id"]):
            connection.execute(
                "INSERT INTO sources VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (
                    source["id"], source["title"], source["organization"], source["url"],
                    source["publishedAt"], source["updatedAt"], source["reviewedAt"],
                    source["locator"], source["jurisdiction"], source["licenseStatus"],
                    source["reviewLevel"],
                ),
            )
        for chapter in content["chapters"]:
            connection.execute(
                "INSERT INTO chapters VALUES (?, ?, ?, ?, ?, ?, ?)",
                (
                    chapter["id"], chapter["number"], chapter["title"],
                    chapter["purpose"], chapter["overview"], chapter["symbol"],
                    chapter["theme"],
                ),
            )
        chapter_order: dict[str, int] = {chapter["id"]: 0 for chapter in content["chapters"]}
        for lesson in content["lessons"]:
            order = chapter_order[lesson["chapterID"]]
            chapter_order[lesson["chapterID"]] += 1
            connection.execute(
                "INSERT INTO lessons VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (
                    lesson["id"], lesson["chapterID"], order, lesson["title"],
                    lesson["goal"], canonical_json(lesson["keywords"]).decode().strip(),
                    canonical_json(lesson["aliases"]).decode().strip(),
                    lesson.get("jurisdiction", "global"), lesson.get("units", "dual"),
                    lesson["reviewStatus"], lesson["reviewedAt"],
                ),
            )
            connection.executemany(
                "INSERT INTO lesson_actions VALUES (?, ?, ?)",
                [(lesson["id"], index, text) for index, text in enumerate(lesson["actions"])],
            )
            connection.executemany(
                "INSERT INTO lesson_warnings VALUES (?, ?, ?)",
                [(lesson["id"], index, text) for index, text in enumerate(lesson["warnings"])],
            )
            for alias in sorted(set([*lesson["aliases"], *lesson["keywords"]])):
                connection.execute(
                    "INSERT INTO aliases VALUES (?, ?, ?)",
                    (alias, lesson["id"], " ".join(words(alias.lower()))),
                )
            chapter = chapters[lesson["chapterID"]]
            for passage in lesson_passages(lesson, chapter):
                connection.execute(
                    "INSERT INTO passages VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                    (
                        passage["id"], passage["lessonID"], passage["chapterID"],
                        passage["kind"], passage["displayOrder"], passage["title"],
                        passage["answerText"], passage["referenceText"],
                        canonical_json(lesson["keywords"]).decode().strip(),
                        canonical_json(lesson["aliases"]).decode().strip(),
                        canonical_json(lesson.get("hazardTags", [])).decode().strip(),
                        canonical_json(lesson.get("biomeTags", ["all"])).decode().strip(),
                        lesson.get("jurisdiction", "global"), lesson.get("units", "dual"),
                        lesson["reviewStatus"], lesson["reviewedAt"],
                    ),
                )
                for source_id in lesson["sourceIDs"]:
                    connection.execute(
                        "INSERT INTO passage_sources VALUES (?, ?)",
                        (passage["id"], source_id),
                    )
                aliases = " ".join([*lesson["aliases"], *lesson["keywords"]])
                connection.execute(
                    "INSERT INTO passages_fts VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                    (
                        passage["id"], chapter["title"], lesson["title"], lesson["goal"],
                        aliases, passage["answerText"], passage["referenceText"],
                        " ".join(lesson["keywords"]),
                    ),
                )
            scenario_id = f"{lesson['id']}-scenario"
            observable_cues = list(dict.fromkeys([
                *lesson["aliases"], *lesson["keywords"],
                *lesson.get("hazardTags", []),
                *language_by_scenario[scenario_id],
            ]))
            related_ids = [
                f"{item}-scenario"
                for item in lesson.get("relatedLessonIDs", [])
            ]
            connection.execute(
                "INSERT INTO expert_scenarios VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (
                    scenario_id, lesson["id"], lesson["chapterID"],
                    lesson["title"], lesson["goal"],
                    canonical_json(observable_cues).decode().strip(),
                    canonical_json(lesson.get("prerequisites", [])).decode().strip(),
                    expert_risk_class(content, lesson["id"]),
                    lesson.get("jurisdiction", "global"),
                    lesson.get("units", "dual"),
                    canonical_json(related_ids).decode().strip(),
                    lesson["reviewStatus"], lesson["reviewedAt"],
                ),
            )
            default_claim_specs = [{
                "kind": "applicability", "text": lesson["goal"],
                "applicability": lesson["goal"], "requirementClass": "context",
            }]
            default_claim_specs += [{
                "kind": "action", "text": value, "applicability": lesson["goal"],
                "requirementClass": "immediate_action",
            } for value in lesson["actions"]]
            default_claim_specs += [
                (
                    "escalation"
                    if any(term in value.lower() for term in [
                        "emergency", "call emergency", "seek", "evacuat",
                    ])
                    else "contraindication",
                    value,
                )
                for value in lesson["warnings"]
            ]
            default_claim_specs[-len(lesson["warnings"]):] = [{
                "kind": kind, "text": value, "applicability": lesson["goal"],
                "requirementClass": kind,
            } for kind, value in default_claim_specs[-len(lesson["warnings"]):]]
            claim_specs = lesson.get("expertClaims", default_claim_specs)
            action_texts: list[str] = []
            contraindication_texts: list[str] = []
            source_by_id = {item["id"]: item for item in content["sources"]}
            for claim_order, claim_spec in enumerate(claim_specs):
                kind = claim_spec["kind"]
                claim_text = claim_spec["text"]
                applicability = claim_spec.get("applicability", lesson["goal"])
                requirement_class = claim_spec.get("requirementClass", kind)
                claim_id = f"{scenario_id}-c{claim_order + 1:02d}"
                connection.execute(
                    "INSERT INTO expert_claims VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                    (
                        claim_id, scenario_id, claim_order, kind,
                        claim_text, applicability, requirement_class,
                        lesson["reviewedAt"],
                    ),
                )
                for source_id in lesson["sourceIDs"]:
                    connection.execute(
                        "INSERT INTO expert_claim_sources VALUES (?, ?, ?)",
                        (claim_id, source_id, source_by_id[source_id]["locator"]),
                    )
                for token in sorted(set(numeric_facts(claim_text))):
                    connection.execute(
                        "INSERT INTO expert_numeric_facts VALUES (?, ?)",
                        (claim_id, token.lower()),
                    )
                if kind == "action":
                    action_texts.append(claim_text)
                elif kind in {"contraindication", "escalation"}:
                    contraindication_texts.append(claim_text)
            connection.execute(
                "INSERT INTO expert_scenarios_fts VALUES (?, ?, ?, ?, ?, ?, ?)",
                (
                    scenario_id, chapter["title"], lesson["title"],
                    lesson["goal"], " ".join(observable_cues),
                    " ".join(action_texts), " ".join(contraindication_texts),
                ),
            )
        for scenario in content.get("expertSupplementalScenarios", []):
            chapter = chapters[scenario["chapterID"]]
            connection.execute(
                "INSERT INTO expert_scenarios VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (
                    scenario["id"], scenario["lessonID"], scenario["chapterID"],
                    scenario["title"], scenario["applicability"],
                    canonical_json(scenario["observableCues"]).decode().strip(),
                    canonical_json(scenario.get("prerequisites", [])).decode().strip(),
                    scenario["riskClass"], scenario.get("jurisdiction", "global"),
                    scenario.get("units", "dual"),
                    canonical_json(scenario.get("relatedScenarioIDs", [])).decode().strip(),
                    scenario["reviewStatus"], scenario["reviewedAt"],
                ),
            )
            action_texts: list[str] = []
            contraindication_texts: list[str] = []
            for claim_order, claim in enumerate(scenario["claims"]):
                claim_id = f"{scenario['id']}-c{claim_order + 1:02d}"
                connection.execute(
                    "INSERT INTO expert_claims VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                    (
                        claim_id, scenario["id"], claim_order, claim["kind"],
                        claim["text"], claim.get("applicability", scenario["applicability"]),
                        claim.get("requirementClass", claim["kind"]), scenario["reviewedAt"],
                    ),
                )
                for source in claim["sourceLocators"]:
                    connection.execute(
                        "INSERT INTO expert_claim_sources VALUES (?, ?, ?)",
                        (claim_id, source["sourceID"], source["locator"]),
                    )
                for token in sorted(set(numeric_facts(claim["text"]))):
                    connection.execute(
                        "INSERT INTO expert_numeric_facts VALUES (?, ?)",
                        (claim_id, token.lower()),
                    )
                if claim["kind"] == "action":
                    action_texts.append(claim["text"])
                elif claim["kind"] in {"contraindication", "escalation"}:
                    contraindication_texts.append(claim["text"])
            connection.execute(
                "INSERT INTO expert_scenarios_fts VALUES (?, ?, ?, ?, ?, ?, ?)",
                (
                    scenario["id"], chapter["title"], scenario["title"],
                    scenario["applicability"], " ".join(scenario["observableCues"]),
                    " ".join(action_texts), " ".join(contraindication_texts),
                ),
            )
        apply_corpus_v3(connection, corpus_v3, chapters)
        for item in legacy:
            replacement = item["replacementLessonID"]
            connection.execute(
                "INSERT INTO legacy_anchors VALUES (?, ?, ?, ?, ?)",
                (
                    item["legacyChunkID"], item["status"], replacement,
                    f"{replacement}-p01", item.get("note", "Updated reviewed guidance"),
                ),
            )
        document_hashes: dict[str, str] = {}
        for document in expert_corpus["documents"]:
            related_chunks = [
                chunk for chunk in expert_corpus["chunks"]
                if chunk["documentID"] == document["id"]
            ]
            document_hashes[document["id"]] = hashlib.sha256(
                canonical_json(related_chunks)
            ).hexdigest()
            connection.execute(
                "INSERT INTO expert_source_documents VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (
                    document["id"], document["title"], document["organization"],
                    document["url"], document["authorityTier"],
                    document["redistributionClass"], document["jurisdiction"],
                    document["publishedAt"], document["updatedAt"],
                    document["reviewedAt"], document["licenseEvidence"],
                    document_hashes[document["id"]],
                    document.get("supersededByDocumentID"),
                ),
            )
        for chunk in expert_corpus["chunks"]:
            chunk_hash = hashlib.sha256(chunk["text"].encode("utf-8")).hexdigest()
            cursor = connection.execute(
                "INSERT INTO expert_source_chunks VALUES (?, ?, ?, ?, ?, ?)",
                (
                    chunk["id"], chunk["documentID"], chunk["locator"],
                    chunk["sectionPath"], chunk["text"], chunk_hash,
                ),
            )
            rowid = cursor.lastrowid
            connection.execute(
                "INSERT INTO expert_source_chunks_fts(rowid, text, locator, section_path) VALUES (?, ?, ?, ?)",
                (rowid, chunk["text"], chunk["locator"], chunk["sectionPath"]),
            )
            connection.executemany(
                "INSERT INTO expert_chunk_scenarios VALUES (?, ?)",
                [(chunk["id"], scenario_id) for scenario_id in chunk["scenarioIDs"]],
            )
        for edge in expert_corpus.get("corroborationEdges", []):
            connection.execute(
                "INSERT INTO expert_corroboration_edges VALUES (?, ?, ?, ?, ?)",
                (edge["id"], edge["leftDocumentID"], edge["rightDocumentID"], edge["topic"], edge["locator"]),
            )
        for conflict in expert_corpus.get("conflicts", []):
            connection.execute(
                "INSERT INTO expert_conflicts VALUES (?, ?, ?, ?, ?)",
                (
                    conflict["id"], canonical_json(conflict["documentIDs"]).decode().strip(),
                    conflict["topic"], conflict["resolution"], conflict["jurisdiction"],
                ),
            )
        for promotion in expert_corpus.get("claimPromotions", []):
            connection.execute(
                "INSERT INTO expert_claim_promotions VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (
                    promotion["id"], promotion["scenarioID"], promotion["kind"], promotion["text"],
                    canonical_json(promotion["sourceDocumentIDs"]).decode().strip(),
                    canonical_json(promotion["sourceLocators"]).decode().strip(),
                    canonical_json(promotion["benchmarkGapIDs"]).decode().strip(),
                    promotion["status"], promotion["extractorReviewID"],
                    promotion["criticReviewID"], promotion.get("humanReviewerID"),
                ),
            )
        connection.commit()
        connection.execute("VACUUM")
    finally:
        connection.close()


def write_fallback(content: dict[str, Any], destination: pathlib.Path) -> None:
    lessons_by_chapter: dict[str, list[dict[str, Any]]] = {}
    for lesson in content["lessons"]:
        lessons_by_chapter.setdefault(lesson["chapterID"], []).append(lesson)
    cards = []
    for chapter in content["chapters"]:
        lesson = lessons_by_chapter[chapter["id"]][0]
        cards.append(
            {
                "chapterID": chapter["id"], "chapterNumber": chapter["number"],
                "chapterTitle": chapter["title"], "lessonID": lesson["id"],
                "title": lesson["title"], "goal": lesson["goal"],
                "actions": lesson["actions"], "warnings": lesson["warnings"],
                "reviewedAt": lesson["reviewedAt"],
            }
        )
    destination.write_bytes(
        canonical_json(
            {
                "schemaVersion": 1,
                "reviewDate": content["reviewDate"],
                "chapters": content["chapters"],
                "cards": cards,
            }
        )
    )


def build(args: argparse.Namespace) -> None:
    compile_corpus_v3(
        argparse.Namespace(
            sources=args.corpus_v3_sources,
            output=args.corpus_v3,
            report=args.corpus_v3_report,
        )
    )
    content = json.loads(args.input.read_text(encoding="utf-8"))
    legacy = json.loads(args.legacy.read_text(encoding="utf-8"))["anchors"]
    expert_language = json.loads(
        args.expert_language.read_text(encoding="utf-8")
    )
    expert_corpus = json.loads(args.expert_corpus.read_text(encoding="utf-8"))
    corpus_v3 = json.loads(args.corpus_v3.read_text(encoding="utf-8"))
    validate_source(content, legacy)
    validate_expert_corpus(expert_corpus, content)
    validate_corpus_v3(corpus_v3, content)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="trailguard-knowledge-", dir=args.output.parent) as temp:
        staged = pathlib.Path(temp) / args.output.name
        create_database(content, legacy, expert_language, expert_corpus, corpus_v3, staged)
        staged.replace(args.output)
    write_fallback(content, args.fallback)
    digest = hashlib.sha256(args.output.read_bytes()).hexdigest()
    args.output.with_suffix(".sha256").write_text(
        f"{digest}  {args.output.name}\n", encoding="utf-8"
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=pathlib.Path, default=DEFAULT_INPUT)
    parser.add_argument("--legacy", type=pathlib.Path, default=DEFAULT_LEGACY)
    parser.add_argument("--output", type=pathlib.Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--fallback", type=pathlib.Path, default=DEFAULT_FALLBACK)
    parser.add_argument(
        "--expert-language",
        type=pathlib.Path,
        default=DEFAULT_EXPERT_LANGUAGE,
    )
    parser.add_argument(
        "--expert-corpus", type=pathlib.Path, default=DEFAULT_EXPERT_CORPUS
    )
    parser.add_argument(
        "--corpus-v3-sources", type=pathlib.Path, default=DEFAULT_CORPUS_V3_SOURCES
    )
    parser.add_argument("--corpus-v3", type=pathlib.Path, default=DEFAULT_CORPUS_V3)
    parser.add_argument(
        "--corpus-v3-report", type=pathlib.Path, default=DEFAULT_CORPUS_V3_REPORT
    )
    return parser.parse_args()


if __name__ == "__main__":
    build(parse_args())
