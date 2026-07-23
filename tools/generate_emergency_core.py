#!/usr/bin/env python3
"""Wrap the reviewed starter fixture in the recoverable emergency-core format."""

from __future__ import annotations

import json
import pathlib


ROOT = pathlib.Path(__file__).resolve().parents[1]
SOURCE = ROOT / "Resources" / "Knowledge" / "starter_knowledge.json"
OUTPUT = ROOT / "Resources" / "Knowledge" / "emergency_core.json"


def main() -> None:
    articles = json.loads(SOURCE.read_text(encoding="utf-8"))
    if not articles or any(article.get("reviewed") is not True for article in articles):
        raise SystemExit("emergency core requires non-empty reviewed articles")
    core = {
        "schemaVersion": 1,
        "version": "1.0.0-development",
        "policyVersion": "deterministic-policy-v1",
        "articles": articles,
    }
    OUTPUT.write_text(
        json.dumps(core, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(f"WROTE: {OUTPUT.relative_to(ROOT)} with {len(articles)} articles")


if __name__ == "__main__":
    main()
