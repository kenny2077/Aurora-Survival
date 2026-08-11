#!/usr/bin/env python3
"""Build TrailGuard's deterministic, read-only wilderness knowledge database."""

from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import re
import sqlite3
import tempfile
from typing import Any


ROOT = pathlib.Path(__file__).resolve().parents[1]
DEFAULT_INPUT = ROOT / "Resources" / "Knowledge" / "survival_knowledge_source.json"
DEFAULT_LEGACY = ROOT / "Resources" / "Knowledge" / "legacy_anchor_manifest.json"
DEFAULT_OUTPUT = ROOT / "Resources" / "Knowledge" / "survival_knowledge.sqlite"
DEFAULT_FALLBACK = ROOT / "Resources" / "Knowledge" / "survival_fallback.json"
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


def create_database(
    content: dict[str, Any],
    legacy: list[dict[str, Any]],
    destination: pathlib.Path,
) -> None:
    chapters = {chapter["id"]: chapter for chapter in content["chapters"]}
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
            CREATE VIRTUAL TABLE passages_fts USING fts5(
                passage_id UNINDEXED, chapter_title, lesson_title, goal,
                aliases, answer_text, reference_text, keywords,
                tokenize='unicode61 remove_diacritics 2'
            );
            CREATE INDEX idx_lessons_chapter ON lessons(chapter_id, display_order);
            CREATE INDEX idx_passages_lesson ON passages(lesson_id, display_order);
            CREATE INDEX idx_passages_chapter ON passages(chapter_id, display_order);
            CREATE INDEX idx_aliases_normalized ON aliases(normalized_alias);
            """
        )
        metadata = {
            "schema_version": str(content["schemaVersion"]),
            "content_version": content["contentVersion"],
            "reviewed_at": content["reviewDate"],
            "language": content["language"],
            "passages_per_lesson": str(PASSAGES_PER_LESSON),
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
        for item in legacy:
            replacement = item["replacementLessonID"]
            connection.execute(
                "INSERT INTO legacy_anchors VALUES (?, ?, ?, ?, ?)",
                (
                    item["legacyChunkID"], item["status"], replacement,
                    f"{replacement}-p01", item.get("note", "Updated reviewed guidance"),
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
    content = json.loads(args.input.read_text(encoding="utf-8"))
    legacy = json.loads(args.legacy.read_text(encoding="utf-8"))["anchors"]
    validate_source(content, legacy)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="trailguard-knowledge-", dir=args.output.parent) as temp:
        staged = pathlib.Path(temp) / args.output.name
        create_database(content, legacy, staged)
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
    return parser.parse_args()


if __name__ == "__main__":
    build(parse_args())
