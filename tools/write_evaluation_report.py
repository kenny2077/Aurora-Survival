#!/usr/bin/env python3
"""Create a provenance-complete Aurora evaluation report."""

from __future__ import annotations

import argparse
import json
import pathlib


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=pathlib.Path, required=True)
    parser.add_argument("--created-at", required=True)
    parser.add_argument("--app-commit", required=True)
    parser.add_argument("--prompt-version", required=True)
    parser.add_argument("--policy-version", required=True)
    parser.add_argument("--device", required=True)
    parser.add_argument("--os", required=True)
    parser.add_argument("--suite", required=True)
    parser.add_argument("--passed", type=int, required=True)
    parser.add_argument("--failed", type=int, required=True)
    parser.add_argument("--skipped", type=int, required=True)
    parser.add_argument("--model-json", default="null")
    parser.add_argument("--packs-json", default="[]")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    if min(args.passed, args.failed, args.skipped) < 0:
        raise SystemExit("result counts cannot be negative")
    report = {
        "schema_version": 1,
        "created_at": args.created_at,
        "app_commit": args.app_commit,
        "prompt_version": args.prompt_version,
        "policy_version": args.policy_version,
        "model": json.loads(args.model_json),
        "packs": json.loads(args.packs_json),
        "device": args.device,
        "os": args.os,
        "suite": args.suite,
        "results": {
            "passed": args.passed,
            "failed": args.failed,
            "skipped": args.skipped,
        },
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(report, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(f"WROTE: {args.output}")


if __name__ == "__main__":
    main()
