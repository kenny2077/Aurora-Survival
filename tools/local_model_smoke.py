#!/usr/bin/env python3
"""Smoke-test Aurora's installed local Ollama development models.

This harness is deliberately outside the iOS runtime. It verifies that a local
workstation can provide structured-output and embedding experiments without
creating a network dependency in Aurora Incident Mode.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import pathlib
import time
import urllib.error
import urllib.request
from typing import Any


ROOT = pathlib.Path(__file__).resolve().parents[1]
DEFAULT_MODELS = ("qwen3:4b", "gemma3:4b")
DEFAULT_EMBEDDING_MODEL = "qwen3-embedding:0.6b"

RESPONSE_SCHEMA: dict[str, Any] = {
    "type": "object",
    "additionalProperties": False,
    "required": [
        "answer_confidence",
        "immediate_action",
        "evidence_ids",
        "do_not_do",
    ],
    "properties": {
        "answer_confidence": {
            "type": "string",
            "enum": ["insufficient", "limited", "supported"],
        },
        "immediate_action": {"type": "string"},
        "evidence_ids": {
            "type": "array",
            "items": {"type": "string"},
        },
        "do_not_do": {
            "type": "array",
            "items": {"type": "string"},
        },
    },
}


def request_json(
    base_url: str,
    path: str,
    payload: dict[str, Any] | None = None,
    timeout: float = 180,
) -> dict[str, Any]:
    data = None if payload is None else json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(
        f"{base_url.rstrip('/')}{path}",
        data=data,
        headers={"Content-Type": "application/json"},
        method="GET" if data is None else "POST",
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return json.load(response)


def installed_models(base_url: str) -> set[str]:
    response = request_json(base_url, "/api/tags", timeout=10)
    return {
        item["name"]
        for item in response.get("models", [])
        if isinstance(item, dict) and isinstance(item.get("name"), str)
    }


def evidence_fixture() -> tuple[str, set[str]]:
    articles = json.loads(
        (ROOT / "Resources" / "Knowledge" / "starter_knowledge.json").read_text(
            encoding="utf-8"
        )
    )
    selected = [
        article
        for article in articles
        if article.get("domain") == "wilderness"
    ][:2]
    if not selected:
        raise RuntimeError("No wilderness fixture evidence is available")
    blocks = []
    ids: set[str] = set()
    for article in selected:
        evidence_id = article["id"]
        ids.add(evidence_id)
        blocks.append(
            "\n".join(
                [
                    f"Evidence ID: {evidence_id}",
                    f"Title: {article['title']}",
                    f"Summary: {article['summary']}",
                    "Steps: " + " | ".join(article.get("steps", [])),
                    "Warnings: " + " | ".join(article.get("warnings", [])),
                ]
            )
        )
    return "\n\n".join(blocks), ids


def generation_smoke(
    base_url: str,
    model: str,
    evidence: str,
    allowed_evidence_ids: set[str],
) -> dict[str, Any]:
    schema = json.loads(json.dumps(RESPONSE_SCHEMA))
    schema["properties"]["evidence_ids"]["items"]["enum"] = sorted(
        allowed_evidence_ids
    )
    system = (
        "You are a Aurora development evaluator. Use only the supplied "
        "evidence. Never invent an evidence ID, medical instruction, repair "
        "procedure, or exact value. If evidence is insufficient, say so in "
        "the schema. Return only JSON matching the supplied schema."
    )
    prompt = (
        "Question: How should I make backcountry water safer to drink?\n\n"
        "Reviewed development evidence:\n"
        f"{evidence}\n\nSchema:\n{json.dumps(schema, sort_keys=True)}"
    )
    started = time.perf_counter()
    response = request_json(
        base_url,
        "/api/generate",
        {
            "model": model,
            "system": system,
            "prompt": prompt,
            "format": schema,
            "stream": False,
            "think": False,
            "keep_alive": "2m",
            "options": {
                "temperature": 0,
                "num_predict": 256,
            },
        },
    )
    elapsed = time.perf_counter() - started
    parsed = json.loads(response.get("response", ""))
    returned_ids = parsed.get("evidence_ids")
    if not isinstance(returned_ids, list):
        raise RuntimeError(f"{model} did not return evidence_ids")
    unknown = sorted(set(returned_ids) - allowed_evidence_ids)
    if unknown:
        raise RuntimeError(f"{model} invented evidence IDs: {unknown}")
    if parsed.get("answer_confidence") == "supported" and not returned_ids:
        raise RuntimeError(f"{model} claimed support without evidence")

    eval_count = int(response.get("eval_count") or 0)
    eval_duration = int(response.get("eval_duration") or 0)
    tokens_per_second = (
        eval_count / (eval_duration / 1_000_000_000)
        if eval_count and eval_duration
        else None
    )
    return {
        "model": model,
        "status": "pass",
        "wall_seconds": round(elapsed, 3),
        "load_seconds": round(
            int(response.get("load_duration") or 0) / 1_000_000_000,
            3,
        ),
        "prompt_tokens": response.get("prompt_eval_count"),
        "output_tokens": eval_count,
        "tokens_per_second": (
            None if tokens_per_second is None else round(tokens_per_second, 3)
        ),
        "evidence_ids": returned_ids,
        "answer_confidence": parsed.get("answer_confidence"),
    }


def embedding_smoke(base_url: str, model: str) -> dict[str, Any]:
    started = time.perf_counter()
    response = request_json(
        base_url,
        "/api/embed",
        {
            "model": model,
            "input": [
                "lost outdoors emergency signaling",
                "make yourself visible and call for rescue",
            ],
            "truncate": False,
        },
    )
    elapsed = time.perf_counter() - started
    embeddings = response.get("embeddings")
    if not isinstance(embeddings, list) or len(embeddings) != 2:
        raise RuntimeError("Embedding endpoint did not return two vectors")
    dimensions = {len(vector) for vector in embeddings if isinstance(vector, list)}
    if len(dimensions) != 1 or next(iter(dimensions), 0) < 4:
        raise RuntimeError("Embedding dimensions are missing or inconsistent")
    return {
        "model": model,
        "status": "pass",
        "wall_seconds": round(elapsed, 3),
        "dimensions": next(iter(dimensions)),
        "prompt_tokens": response.get("prompt_eval_count"),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", default="http://127.0.0.1:11434")
    parser.add_argument("--models", nargs="+", default=list(DEFAULT_MODELS))
    parser.add_argument("--embedding-model", default=DEFAULT_EMBEDDING_MODEL)
    parser.add_argument("--output", type=pathlib.Path)
    args = parser.parse_args()

    try:
        available = installed_models(args.base_url)
    except (OSError, urllib.error.URLError) as error:
        print(f"FAIL: Ollama is not reachable at {args.base_url}: {error}")
        return 2

    required = set(args.models) | {args.embedding_model}
    missing = sorted(required - available)
    if missing:
        print(f"FAIL: required local models are missing: {', '.join(missing)}")
        return 2

    evidence, evidence_ids = evidence_fixture()
    results: list[dict[str, Any]] = []
    for model in args.models:
        print(f"Testing structured output: {model}", flush=True)
        results.append(
            generation_smoke(
                args.base_url,
                model,
                evidence,
                evidence_ids,
            )
        )
    print(f"Testing embeddings: {args.embedding_model}", flush=True)
    embedding_result = embedding_smoke(args.base_url, args.embedding_model)

    report = {
        "schema_version": 1,
        "created_at": dt.datetime.now(dt.timezone.utc)
        .replace(microsecond=0)
        .isoformat()
        .replace("+00:00", "Z"),
        "purpose": "workstation-only model transport and schema smoke test",
        "incident_mode_runtime": False,
        "generation": results,
        "embedding": embedding_result,
    }
    if args.output:
        output = args.output.resolve()
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(
            json.dumps(report, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        print(f"Wrote {output}")
    print(json.dumps(report, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
