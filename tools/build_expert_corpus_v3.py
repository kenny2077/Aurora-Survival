#!/usr/bin/env python3
"""Compile manifest-discovered Markdown sources into deterministic Expert corpus v3."""

from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import re
import unicodedata
from dataclasses import dataclass
from typing import Any, Iterable


ROOT = pathlib.Path(__file__).resolve().parents[1]
DEFAULT_SOURCES = ROOT / "Resources" / "Knowledge" / "CorpusSources"
DEFAULT_OUTPUT = ROOT / "Resources" / "Knowledge" / "expert_corpus_v3.json"
DEFAULT_REPORT = ROOT / "Reports" / "survival-manual-2026" / "corpus-import-report.json"
WORD_RE = re.compile(r"[A-Za-z0-9]+(?:['’-][A-Za-z0-9]+)?")
CITATION_RE = re.compile(r"\s*cite[^]+\s*")
CHAPTER_RE = re.compile(r"^#\s+CHAPTER\s+(\d+)\s+---\s+(.+?)\s*$", re.I)
SKILL_RE = re.compile(r"^#\s+SKILL\s+(\d+)\s+---\s+(.+?)\s*$", re.I)
HEADING_RE = re.compile(r"^(#{1,6})\s+(.+?)\s*$")
SEPARATOR_RE = re.compile(r"^-{8,}$")
LIST_RE = re.compile(r"^\s*(?:[-*+]\s+|\d+[.)]\s+)(.+)$")
STOP_HEADINGS = {"CONTENTS", "PURPOSE", "METADATA SCHEMA", "EMBEDDING PIPELINE NOTES"}
CHAPTER_IDS = {
    "FIRECRAFT": "fire",
    "WATERCRAFT": "water",
    "SHELTERCRAFT": "shelter",
    "FIRST AIDCRAFT": "first-aid",
    "NAVIGATIONCRAFT": "navigation",
    "FOODCRAFT": "food",
}
GENERIC_TERMS = {
    "about", "after", "again", "also", "and", "are", "basic", "before",
    "building", "craft", "during", "for", "from", "into", "method", "of",
    "skill", "survival", "the", "this", "through", "to", "using", "with",
}
ACTION_HEADINGS = {
    "procedure", "treatment", "application", "basic steps", "basic method",
    "construction principles", "handling principles", "prevention", "location",
    "design principles", "following a bearing", "water search priority",
}
WARNING_TERMS = (
    "do not", "never", "avoid", "stop if", "stop when", "warning", "risk", "danger",
    "unsafe", "only if", "must not", "contraind", "limitation", "poison",
)
ESCALATION_TERMS = (
    "emergency services", "emergency help", "evacuat", "seek medical",
    "call for help", "rescue",
)


class CorpusError(ValueError):
    pass


@dataclass(frozen=True)
class SourceDocument:
    folder: pathlib.Path
    manifest: dict[str, Any]
    source: str


@dataclass
class Unit:
    document_id: str
    chapter_id: str
    chapter_title: str
    title: str
    section_key: str
    line_start: int
    line_end: int
    blocks: list[tuple[str, str, int]]
    priority: int

    @property
    def locator(self) -> str:
        return f"lines {self.line_start}-{self.line_end}"

    @property
    def section_path(self) -> str:
        return f"Chapter {self.chapter_title} → {self.title}"


def canonical_json(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n").encode()


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def normalize_space(value: str) -> str:
    return re.sub(r"\s+", " ", unicodedata.normalize("NFKC", value)).strip()


def slug(value: str) -> str:
    result = re.sub(r"[^a-z0-9]+", "-", normalize_space(value).lower()).strip("-")
    return result or "section"


def words(value: str) -> list[str]:
    return WORD_RE.findall(value)


def meaningful_terms(value: str) -> list[str]:
    return [word.lower() for word in words(value) if len(word) > 2 and word.lower() not in GENERIC_TERMS]


def normalized_fingerprint(value: str) -> str:
    return " ".join(word.lower() for word in words(value))


def ngrams(value: str, size: int = 5) -> set[tuple[str, ...]]:
    tokens = normalized_fingerprint(value).split()
    if len(tokens) < size:
        return {tuple(tokens)} if tokens else set()
    return {tuple(tokens[index:index + size]) for index in range(len(tokens) - size + 1)}


def jaccard(left: set[Any], right: set[Any]) -> float:
    if not left or not right:
        return 0.0
    return len(left & right) / len(left | right)


def discover_sources(root: pathlib.Path) -> list[SourceDocument]:
    documents: list[SourceDocument] = []
    for manifest_path in sorted(root.glob("*/manifest.json")):
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        required = {
            "schemaVersion", "documentID", "title", "authorityTier",
            "redistributionClass", "language", "jurisdiction", "publishedAt",
            "updatedAt", "reviewedAt", "reviewerAuditID", "canonicalPriority",
            "sourceFilename", "sourceSHA256", "promotionPolicy",
        }
        missing = sorted(required - set(manifest))
        if missing:
            raise CorpusError(f"{manifest_path}: missing {', '.join(missing)}")
        if manifest["schemaVersion"] != 3:
            raise CorpusError(f"{manifest_path}: schemaVersion must be 3")
        source_path = manifest_path.parent / manifest["sourceFilename"]
        source_bytes = source_path.read_bytes()
        actual_hash = sha256_bytes(source_bytes)
        if actual_hash != manifest["sourceSHA256"]:
            raise CorpusError(f"{source_path}: SHA-256 mismatch ({actual_hash})")
        documents.append(SourceDocument(manifest_path.parent, manifest, source_bytes.decode("utf-8")))
    if not documents:
        raise CorpusError(f"no corpus-v3 manifests found under {root}")
    ids = [item.manifest["documentID"] for item in documents]
    if len(ids) != len(set(ids)):
        raise CorpusError("document IDs must be unique")
    return documents


def clean_lines(source: str) -> tuple[list[tuple[int, str]], dict[str, int]]:
    counts = {
        "frontMatterLinesRemoved": 0,
        "emptyHTMLBlocksRemoved": 0,
        "citationMarkersRemoved": 0,
        "separatorsRemoved": 0,
        "repeatedStructuralLinesRemoved": 0,
        "tableOfContentsLinesRemoved": 0,
    }
    result: list[tuple[int, str]] = []
    in_front_matter = False
    in_html = False
    seen_chapter = False
    skipping_contents = False
    previous_structural = ""
    for line_number, raw in enumerate(source.splitlines(), 1):
        line = unicodedata.normalize("NFKC", raw.rstrip())
        if line_number == 1 and line.strip() == "---":
            in_front_matter = True
            counts["frontMatterLinesRemoved"] += 1
            continue
        if in_front_matter:
            counts["frontMatterLinesRemoved"] += 1
            if line.strip() == "---":
                in_front_matter = False
            continue
        if line.strip().startswith("```{=html}"):
            in_html = True
            counts["emptyHTMLBlocksRemoved"] += 1
            continue
        if in_html:
            counts["emptyHTMLBlocksRemoved"] += 1
            if line.strip() == "```":
                in_html = False
            continue
        if CITATION_RE.search(line):
            counts["citationMarkersRemoved"] += 1
            line = CITATION_RE.sub("", line)
        if SEPARATOR_RE.match(line.strip()):
            counts["separatorsRemoved"] += 1
            continue
        chapter_match = CHAPTER_RE.match(line)
        if chapter_match:
            seen_chapter = True
            skipping_contents = False
        if not seen_chapter:
            counts["tableOfContentsLinesRemoved"] += 1
            continue
        heading = HEADING_RE.match(line)
        if heading and heading.group(2).strip().upper() == "CONTENTS":
            skipping_contents = True
            counts["tableOfContentsLinesRemoved"] += 1
            continue
        if skipping_contents:
            counts["tableOfContentsLinesRemoved"] += 1
            continue
        structural = normalize_space(line).lower()
        if structural and structural == previous_structural and (heading or LIST_RE.match(line)):
            counts["repeatedStructuralLinesRemoved"] += 1
            continue
        if structural:
            previous_structural = structural
        result.append((line_number, line))
    return result, counts


def parse_units(document: SourceDocument) -> tuple[list[Unit], dict[str, int]]:
    lines, counts = clean_lines(document.source)
    units: list[Unit] = []
    chapter_id = ""
    chapter_title = ""
    current: Unit | None = None
    current_heading = "Overview"
    seen_in_unit: set[str] = set()
    pending_kind = ""
    pending_heading = ""
    pending_text: list[str] = []
    pending_line = 0

    def flush_text() -> None:
        nonlocal pending_kind, pending_heading, pending_text, pending_line
        if current is not None and pending_text:
            text = normalize_space(" ".join(pending_text))
            fingerprint = normalized_fingerprint(text)
            if len(words(text)) >= 4 and fingerprint in seen_in_unit:
                counts["repeatedStructuralLinesRemoved"] += 1
            elif text:
                seen_in_unit.add(fingerprint)
                current.blocks.append((pending_heading, text, pending_line))
        pending_kind = ""
        pending_heading = ""
        pending_text = []
        pending_line = 0

    def flush(end_line: int) -> None:
        nonlocal current, seen_in_unit
        flush_text()
        if current and any(text.strip() for _, text, _ in current.blocks):
            current.line_end = max(current.line_start, end_line)
            units.append(current)
        current = None
        seen_in_unit = set()

    for line_number, line in lines:
        chapter_match = CHAPTER_RE.match(line)
        if chapter_match:
            flush(line_number - 1)
            chapter_title = normalize_space(chapter_match.group(2)).upper()
            chapter_id = CHAPTER_IDS.get(chapter_title, slug(chapter_title))
            current_heading = "Core principles"
            current = Unit(
                document.manifest["documentID"], chapter_id, chapter_title.title(),
                "Core principles", f"{slug(chapter_title)}/core-principles",
                line_number, line_number, [], document.manifest["canonicalPriority"],
            )
            continue
        if not chapter_id:
            continue
        skill_match = SKILL_RE.match(line)
        if skill_match:
            flush(line_number - 1)
            title = normalize_space(skill_match.group(2)).title()
            key = f"{slug(chapter_title)}/{slug(skill_match.group(2))}"
            current = Unit(
                document.manifest["documentID"], chapter_id, chapter_title.title(),
                title, key, line_number, line_number, [],
                document.manifest["canonicalPriority"],
            )
            current_heading = "Overview"
            continue
        if current is None:
            continue
        heading = HEADING_RE.match(line)
        if heading:
            flush_text()
            heading_text = normalize_space(heading.group(2))
            if "TRAINING PROGRAM" in heading_text.upper() or heading_text.upper().startswith("END OF CHAPTER"):
                flush(line_number - 1)
                continue
            if heading_text.upper().startswith("FINAL ") and heading_text.upper().endswith(" RULE"):
                current_heading = heading_text.title()
            elif heading_text.upper() not in STOP_HEADINGS and not heading_text.upper().startswith("FIELD SURVIVAL GUIDE"):
                current_heading = heading_text.title()
            continue
        text = normalize_space(line)
        if not text:
            flush_text()
            continue
        list_match = LIST_RE.match(line)
        if list_match:
            flush_text()
            pending_kind = "list"
            pending_heading = current_heading
            pending_text = [normalize_space(list_match.group(1))]
            pending_line = line_number
        elif pending_kind == "list":
            pending_text.append(text)
        else:
            if not pending_text:
                pending_kind = "paragraph"
                pending_heading = current_heading
                pending_line = line_number
            pending_text.append(text)
    flush(lines[-1][0] if lines else 0)
    return units, counts


def split_long_text(text: str, maximum: int = 110) -> list[str]:
    if len(words(text)) <= maximum:
        return [text]
    sentences = re.split(r"(?<=[.!?])\s+", text)
    pieces: list[str] = []
    current: list[str] = []
    for sentence in sentences:
        if current and len(words(" ".join(current + [sentence]))) > maximum:
            pieces.append(" ".join(current))
            current = []
        current.append(sentence)
    if current:
        pieces.append(" ".join(current))
    return pieces


def chunk_units(units: Iterable[Unit]) -> list[dict[str, Any]]:
    chunks: list[dict[str, Any]] = []
    for unit in units:
        blocks: list[tuple[str, str, int]] = []
        for heading, text, line in unit.blocks:
            blocks.extend((heading, piece, line) for piece in split_long_text(text))
        cursor = 0
        part = 1
        while cursor < len(blocks):
            selected: list[tuple[str, str, int]] = []
            count = 0
            index = cursor
            while index < len(blocks):
                block_count = len(words(blocks[index][1]))
                if selected and count + block_count > 500:
                    break
                selected.append(blocks[index])
                count += block_count
                index += 1
                if count >= 350:
                    break
            if not selected:
                selected = [blocks[index]]
                index += 1
            text_parts: list[str] = []
            active_heading = ""
            for heading, text, _ in selected:
                if heading != active_heading:
                    text_parts.append(heading)
                    active_heading = heading
                text_parts.append(text)
            text = "\n\n".join(text_parts)
            chunk_id = f"{unit.document_id}-{unit.section_key.replace('/', '-')}-{part:02d}"
            chunks.append({
                "id": chunk_id,
                "documentID": unit.document_id,
                "chapterID": unit.chapter_id,
                "sectionKey": unit.section_key,
                "sectionPath": unit.section_path,
                "locator": f"{unit.locator}; part {part}",
                "lineStart": selected[0][2],
                "lineEnd": selected[-1][2],
                "text": text,
                "tokenEstimate": len(words(text)),
                "normalizedSHA256": sha256_bytes(normalized_fingerprint(text).encode()),
                "canonicalPriority": unit.priority,
            })
            if index >= len(blocks):
                break
            overlap_target = max(1, int(count * 0.15))
            overlap = 0
            rewind = index
            while rewind > cursor and overlap < overlap_target:
                rewind -= 1
                overlap += len(words(blocks[rewind][1]))
            cursor = max(cursor + 1, rewind)
            part += 1
    return chunks


def deduplicate(chunks: list[dict[str, Any]]) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    parent = list(range(len(chunks)))

    def find(value: int) -> int:
        while parent[value] != value:
            parent[value] = parent[parent[value]]
            value = parent[value]
        return value

    def union(left: int, right: int) -> None:
        left_root, right_root = find(left), find(right)
        if left_root != right_root:
            parent[right_root] = left_root

    exact: dict[str, int] = {}
    grams = [ngrams(chunk["text"]) for chunk in chunks]
    for index, chunk in enumerate(chunks):
        digest = chunk["normalizedSHA256"]
        if digest in exact:
            union(exact[digest], index)
        else:
            exact[digest] = index
    for left in range(len(chunks)):
        for right in range(left + 1, len(chunks)):
            if find(left) == find(right):
                continue
            if jaccard(grams[left], grams[right]) >= 0.90:
                union(left, right)
    groups: dict[int, list[int]] = {}
    for index in range(len(chunks)):
        groups.setdefault(find(index), []).append(index)
    canonical: list[dict[str, Any]] = []
    aliases: list[dict[str, Any]] = []
    for members in groups.values():
        ordered = sorted(
            members,
            key=lambda item: (-chunks[item]["canonicalPriority"], chunks[item]["documentID"], chunks[item]["id"]),
        )
        winner = dict(chunks[ordered[0]])
        canonical.append(winner)
        for member in ordered[1:]:
            candidate = chunks[member]
            aliases.append({
                "aliasChunkID": candidate["id"],
                "canonicalChunkID": winner["id"],
                "documentID": candidate["documentID"],
                "locator": candidate["locator"],
                "sectionPath": candidate["sectionPath"],
                "normalizedSHA256": candidate["normalizedSHA256"],
                "relationship": "exact" if candidate["normalizedSHA256"] == winner["normalizedSHA256"] else "near_duplicate",
            })
    return sorted(canonical, key=lambda item: item["id"]), sorted(aliases, key=lambda item: item["aliasChunkID"])


def classify_claim(text: str, heading: str) -> str:
    lowered = text.lower()
    heading_lower = heading.lower()
    if "leave in place until medical professionals" in lowered:
        return "stop_condition"
    if any(term in lowered for term in ESCALATION_TERMS):
        return "escalation"
    if (any(term in lowered for term in WARNING_TERMS)
            or heading_lower.startswith("do not")
            or "limitation" in heading_lower
            or "safety" in heading_lower):
        return "contraindication"
    if re.search(r"\b\d+(?:[.,]\d+)?(?:\s*(?:minutes?|hours?|days?|°[CF]|feet|meters?|%))?\b", text, re.I):
        return "allowed_number"
    return "action"


def concise(value: str, maximum: int = 72) -> str:
    tokens = value.split()
    if len(tokens) <= maximum:
        return value
    sentences = re.split(r"(?<=[.!?])\s+", value)
    kept: list[str] = []
    for sentence in sentences:
        if kept and len(words(" ".join(kept + [sentence]))) > maximum:
            break
        kept.append(sentence)
    return " ".join(kept) if kept else " ".join(tokens[:maximum]).rstrip(",;:") + "."


def semantic_candidates(unit: Unit) -> list[tuple[str, str, Unit]]:
    """Keep an introductory condition with its immediately associated list."""
    result: list[tuple[str, str, Unit]] = []
    index = 0
    while index < len(unit.blocks):
        heading, text, _ = unit.blocks[index]
        if text.rstrip().endswith(":"):
            pieces = [text]
            cursor = index + 1
            while cursor < len(unit.blocks) and unit.blocks[cursor][0] == heading and len(pieces) < 6:
                candidate = unit.blocks[cursor][1]
                if candidate.rstrip().endswith(":"):
                    break
                pieces.append(candidate)
                cursor += 1
            if len(pieces) > 1:
                result.append((heading, " ".join(pieces), unit))
                index = cursor
                continue
        result.append((heading, text, unit))
        index += 1
    return result


def compile_scenarios(
    documents: list[SourceDocument], units: list[Unit], chunks: list[dict[str, Any]],
) -> tuple[list[dict[str, Any]], list[dict[str, Any]], list[dict[str, Any]]]:
    manifest_by_id = {item.manifest["documentID"]: item.manifest for item in documents}
    grouped: dict[str, list[Unit]] = {}
    for unit in units:
        mapping = manifest_by_id[unit.document_id].get("scenarioMappings", {})
        scenario_id = mapping.get(unit.section_key, f"sm26-{unit.chapter_id}-{slug(unit.title)}")
        grouped.setdefault(scenario_id, []).append(unit)
    scenarios: list[dict[str, Any]] = []
    claims: list[dict[str, Any]] = []
    claim_sources: list[dict[str, Any]] = []
    chunks_by_section: dict[tuple[str, str], list[dict[str, Any]]] = {}
    for chunk in chunks:
        chunks_by_section.setdefault((chunk["documentID"], chunk["sectionKey"]), []).append(chunk)
    for scenario_id, members in sorted(grouped.items()):
        members.sort(key=lambda unit: (-unit.priority, unit.document_id, unit.line_start))
        canonical = members[0]
        source_manifest = manifest_by_id[canonical.document_id]
        candidate_texts: list[tuple[str, str, Unit]] = []
        applicability = ""
        for unit in members:
            for heading, text, _ in unit.blocks:
                if not applicability and heading.lower() == "purpose" and len(words(text)) >= 4:
                    applicability = concise(text, 45)
            candidate_texts.extend(semantic_candidates(unit))
        if not applicability:
            first = next((text for _, text, _ in candidate_texts if len(words(text)) >= 5), canonical.title)
            applicability = concise(first, 45)
        cues = list(dict.fromkeys(
            title.lower()
            for unit in members
            for title in [unit.title, *meaningful_terms(unit.title)]
        ))
        source_chunks = sorted({
            chunk["id"]
            for unit in members
            for chunk in chunks_by_section.get((unit.document_id, unit.section_key), [])
        })
        scenarios.append({
            "id": scenario_id,
            "chapterID": canonical.chapter_id,
            "title": canonical.title,
            "applicability": applicability,
            "observableCues": cues,
            "prerequisites": [],
            "riskClass": "critical" if canonical.chapter_id == "first-aid" else "high",
            "jurisdiction": source_manifest["jurisdiction"],
            "units": "dual",
            "reviewStatus": "humanApproved",
            "reviewedAt": source_manifest["reviewedAt"],
            "reviewerAuditID": source_manifest["reviewerAuditID"],
            "sourceDocumentID": canonical.document_id,
            "sourceChunkIDs": source_chunks,
            "sectionPath": canonical.section_path,
            "locator": canonical.locator,
            "canonicalPriority": canonical.priority,
        })
        chosen: list[tuple[str, str, Unit]] = [("applicability", applicability, canonical)]
        seen = {normalized_fingerprint(applicability)}
        warnings: list[tuple[str, str, Unit]] = []
        actions: list[tuple[str, str, Unit]] = []
        numerics: list[tuple[str, str, Unit]] = []
        for heading, text, unit in candidate_texts:
            if heading.lower() == "purpose":
                continue
            value = concise(text)
            fingerprint = normalized_fingerprint(value)
            if len(words(value)) < 2 or fingerprint in seen:
                continue
            seen.add(fingerprint)
            kind = classify_claim(value, heading)
            item = (kind, value, unit)
            if kind in {"contraindication", "escalation"}:
                warnings.append(item)
            elif kind == "allowed_number":
                numerics.append(item)
            else:
                actions.append(item)
        categorized = {
            unit.section_key: {
                "actions": [item for item in actions if item[2] is unit],
                "numerics": [item for item in numerics if item[2] is unit],
                "warnings": [item for item in warnings if item[2] is unit],
            }
            for unit in members
        }
        # A shared scenario must retain representative guidance from every mapped
        # skill before earlier sections consume the fixed runtime claim budget.
        for unit in members:
            buckets = categorized[unit.section_key]
            for key in ("warnings", "actions", "numerics"):
                if buckets[key]:
                    chosen.append(buckets[key].pop(0))
        for key in ("warnings", "numerics", "actions"):
            while len(chosen) < 15:
                added = False
                for unit in members:
                    bucket = categorized[unit.section_key][key]
                    if bucket:
                        chosen.append(bucket.pop(0))
                        added = True
                        if len(chosen) == 15:
                            break
                if not added:
                    break
        for order, (kind, text, unit) in enumerate(chosen[:15]):
            claim_id = f"{scenario_id}-v3-c{order + 1:02d}"
            claims.append({
                "id": claim_id,
                "scenarioID": scenario_id,
                "displayOrder": order,
                "kind": kind,
                "text": text,
                "applicability": applicability,
                "requirementClass": "context" if kind == "applicability" else kind,
                "reviewedAt": manifest_by_id[unit.document_id]["reviewedAt"],
                "promotionStatus": "humanApproved",
            })
            relevant_chunks = chunks_by_section.get((unit.document_id, unit.section_key), [])
            chunk = next((item for item in relevant_chunks if normalized_fingerprint(text) in normalized_fingerprint(item["text"])), None)
            if chunk is None and relevant_chunks:
                chunk = relevant_chunks[0]
            if chunk:
                claim_sources.append({
                    "claimID": claim_id,
                    "documentID": unit.document_id,
                    "chunkID": chunk["id"],
                    "sectionPath": chunk["sectionPath"],
                    "locator": chunk["locator"],
                })
    return scenarios, claims, claim_sources


def detect_conflicts(claims: list[dict[str, Any]], sources: list[dict[str, Any]]) -> list[dict[str, Any]]:
    document_by_claim: dict[str, set[str]] = {}
    for source in sources:
        document_by_claim.setdefault(source["claimID"], set()).add(source["documentID"])
    conflicts: list[dict[str, Any]] = []
    by_scenario: dict[str, list[dict[str, Any]]] = {}
    for claim in claims:
        by_scenario.setdefault(claim["scenarioID"], []).append(claim)
    for scenario_id, values in by_scenario.items():
        for index, left in enumerate(values):
            left_numbers = set(re.findall(r"\b\d+(?:[.,]\d+)?\b", left["text"]))
            if not left_numbers:
                continue
            for right in values[index + 1:]:
                if document_by_claim.get(left["id"], set()) == document_by_claim.get(right["id"], set()):
                    continue
                right_numbers = set(re.findall(r"\b\d+(?:[.,]\d+)?\b", right["text"]))
                if right_numbers and left_numbers != right_numbers and jaccard(set(meaningful_terms(left["text"])), set(meaningful_terms(right["text"]))) >= 0.55:
                    conflicts.append({
                        "id": f"conflict-{scenario_id}-{len(conflicts) + 1:03d}",
                        "scenarioID": scenario_id,
                        "claimIDs": [left["id"], right["id"]],
                        "reason": "incompatible numeric guidance",
                        "status": "unresolved",
                    })
    return conflicts


def build(args: argparse.Namespace) -> None:
    documents = discover_sources(args.sources)
    all_units: list[Unit] = []
    cleaning: dict[str, int] = {}
    for document in documents:
        units, counts = parse_units(document)
        all_units.extend(units)
        for key, value in counts.items():
            cleaning[key] = cleaning.get(key, 0) + value
    raw_chunks = chunk_units(all_units)
    canonical_chunks, aliases = deduplicate(raw_chunks)
    scenarios, claims, claim_sources = compile_scenarios(documents, all_units, canonical_chunks)
    conflicts = detect_conflicts(claims, claim_sources)
    unresolved = [item for item in conflicts if item["status"] == "unresolved"]
    if unresolved:
        raise CorpusError(f"{len(unresolved)} unresolved corpus conflicts")
    document_records = [{
        "id": item.manifest["documentID"],
        "title": item.manifest["title"],
        "displayOrganization": item.manifest.get("displayOrganization"),
        "url": item.manifest.get("url"),
        "authorityTier": item.manifest["authorityTier"],
        "redistributionClass": item.manifest["redistributionClass"],
        "language": item.manifest["language"],
        "jurisdiction": item.manifest["jurisdiction"],
        "publishedAt": item.manifest["publishedAt"],
        "updatedAt": item.manifest["updatedAt"],
        "reviewedAt": item.manifest["reviewedAt"],
        "reviewerAuditID": item.manifest["reviewerAuditID"],
        "canonicalPriority": item.manifest["canonicalPriority"],
        "sourceSHA256": item.manifest["sourceSHA256"],
        "provenanceClass": item.manifest["provenanceClass"],
        "provenanceDisclosureCode": item.manifest["provenanceDisclosureCode"],
    } for item in documents]
    sections = [{
        "id": f"{unit.document_id}-{unit.section_key.replace('/', '-')}",
        "documentID": unit.document_id,
        "chapterID": unit.chapter_id,
        "sectionKey": unit.section_key,
        "title": unit.title,
        "sectionPath": unit.section_path,
        "locator": unit.locator,
    } for unit in all_units]
    corpus = {
        "schemaVersion": 3,
        "corpusVersion": "survival-manual-2026.1",
        "generatedAt": "2026-08-20",
        "documents": document_records,
        "sections": sorted(sections, key=lambda item: item["id"]),
        "chunks": canonical_chunks,
        "duplicateAliases": aliases,
        "scenarios": scenarios,
        "claims": claims,
        "claimSources": claim_sources,
        "conflicts": conflicts,
        "supersessions": [],
        "buildProvenance": {
            "compiler": "tools/build_expert_corpus_v3.py",
            "compilerSchemaVersion": 3,
            "sourceManifestHashes": {
                item.manifest["documentID"]: sha256_bytes(canonical_json(item.manifest))
                for item in documents
            },
        },
    }
    report = {
        "schemaVersion": 3,
        "corpusVersion": corpus["corpusVersion"],
        "cleaning": cleaning,
        "documentCount": len(document_records),
        "sectionCount": len(sections),
        "rawChunkCount": len(raw_chunks),
        "canonicalChunkCount": len(canonical_chunks),
        "duplicateAliasCount": len(aliases),
        "scenarioCount": len(scenarios),
        "mappedExistingScenarioCount": sum(not item["id"].startswith("sm26-") for item in scenarios),
        "newScenarioCount": sum(item["id"].startswith("sm26-") for item in scenarios),
        "claimCount": len(claims),
        "numericClaimCount": sum(item["kind"] == "allowed_number" for item in claims),
        "conflictCount": len(conflicts),
        "sourceLocators": len(claim_sources),
        "vectorRecordCounts": {
            "scenario": len(scenarios),
            "claim": len(claims),
            "chunk": len(canonical_chunks),
            "total": len(scenarios) + len(claims) + len(canonical_chunks),
        },
        "corpusSHA256": sha256_bytes(canonical_json(corpus)),
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(canonical_json(corpus))
    args.report.write_bytes(canonical_json(report))


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--sources", type=pathlib.Path, default=DEFAULT_SOURCES)
    parser.add_argument("--output", type=pathlib.Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--report", type=pathlib.Path, default=DEFAULT_REPORT)
    return parser.parse_args()


if __name__ == "__main__":
    build(parse_args())
