#!/usr/bin/env python3
"""Create the balanced, deterministic offline retrieval acceptance fixture."""

from __future__ import annotations

import json
import pathlib


ROOT = pathlib.Path(__file__).resolve().parents[1]
SOURCE = ROOT / "Resources" / "Knowledge" / "survival_knowledge_source.json"
OUTPUT = ROOT / "Tests" / "Fixtures" / "survival_retrieval_benchmark.json"

TYPOS = {
    "water": "watre", "fire": "firre", "shelter": "sheltr",
    "compass": "compas", "bleeding": "bleading", "lightning": "ligthning",
    "overheating": "overhet", "dehydration": "dehydraton",
}
CRITICAL = {"water", "fire", "navigation", "first-aid", "weather-wildlife", "car"}


def typo(value: str) -> str:
    lowered = value.lower()
    for correct, misspelled in TYPOS.items():
        if correct in lowered:
            return lowered.replace(correct, misspelled, 1)
    return lowered


def main() -> None:
    content = json.loads(SOURCE.read_text(encoding="utf-8"))
    records = []
    for chapter in content["chapters"]:
        lessons = [item for item in content["lessons"] if item["chapterID"] == chapter["id"]]
        candidates: list[tuple[str, str]] = []
        for lesson in lessons:
            candidates.extend(
                [
                    (lesson["title"], lesson["id"]),
                    (f"what do I do about {lesson['aliases'][0]}", lesson["id"]),
                    (lesson["keywords"][0], lesson["id"]),
                    (lesson["goal"], lesson["id"]),
                ]
            )
        for index, (query, lesson_id) in enumerate(candidates[:20]):
            if index % 7 == 6:
                query = typo(query)
            records.append(
                {
                    "query": query,
                    "expectedChapterID": chapter["id"],
                    "expectedLessonID": lesson_id,
                    "critical": chapter["id"] in CRITICAL,
                }
            )
    if len(records) != 200:
        raise SystemExit(f"expected 200 benchmark records, got {len(records)}")
    OUTPUT.write_text(
        json.dumps(records, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(f"wrote {len(records)} benchmark queries to {OUTPUT}")


if __name__ == "__main__":
    main()
