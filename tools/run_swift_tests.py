#!/usr/bin/env python3
"""Build Swift tests once, then run each XCTestCase with a hard time bound."""

from __future__ import annotations

import pathlib
import re
import subprocess
import sys


ROOT = pathlib.Path(__file__).resolve().parents[1]
BUILD_TIMEOUT_SECONDS = 900
CLASS_TIMEOUT_SECONDS = 120


def test_classes() -> list[str]:
    classes: set[str] = set()
    pattern = re.compile(r"final\s+class\s+([A-Za-z_][A-Za-z0-9_]*)\s*:\s*XCTestCase")
    for source in sorted((ROOT / "Tests").glob("*.swift")):
        classes.update(pattern.findall(source.read_text(encoding="utf-8")))
    if not classes:
        raise RuntimeError("No XCTestCase classes found")
    return sorted(classes)


def run(command: list[str], timeout: int, label: str) -> None:
    print(f"\n==> {label}", flush=True)
    try:
        completed = subprocess.run(
            command,
            cwd=ROOT,
            check=False,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired as error:
        raise RuntimeError(
            f"{label} exceeded the {timeout}-second limit"
        ) from error
    if completed.returncode != 0:
        raise RuntimeError(
            f"{label} failed with exit code {completed.returncode}"
        )


def main() -> None:
    classes = test_classes()
    print(f"Discovered {len(classes)} XCTestCase classes", flush=True)
    run(
        ["swift", "test", "list"],
        BUILD_TIMEOUT_SECONDS,
        "Compile and discover Swift tests",
    )
    for class_name in classes:
        run(
            [
                "swift",
                "test",
                "--skip-build",
                "--filter",
                rf"^AuroraCoreTests\.{re.escape(class_name)}/",
            ],
            CLASS_TIMEOUT_SECONDS,
            f"Run {class_name}",
        )
    print(f"\nPASS: all {len(classes)} Swift test classes", flush=True)


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, subprocess.SubprocessError) as error:
        print(f"FAIL: {error}", file=sys.stderr, flush=True)
        raise SystemExit(1)
