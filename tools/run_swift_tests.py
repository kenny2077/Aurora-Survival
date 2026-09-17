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


TEST_MODULE = "AuroraCoreTests"
CLASS_PATTERN = re.compile(r"\bclass\s+([A-Za-z_][A-Za-z0-9_]*)\s*:\s*XCTestCase\b")
APP_TARGET_ONLY_GUARD = "#if !SWIFT_PACKAGE"


def listed_classes(output: str) -> list[str]:
    """Classes SwiftPM actually compiled, so every class has at least one test."""
    prefix = f"{TEST_MODULE}."
    return sorted({
        line[len(prefix):].split("/", 1)[0]
        for line in output.splitlines()
        if line.startswith(prefix) and "/" in line
    })


def unlisted_classes(sources: dict[str, str], listed: set[str]) -> list[str]:
    """Source test classes SwiftPM would silently skip, excluding app-target-only files."""
    missing: set[str] = set()
    for text in sources.values():
        if APP_TARGET_ONLY_GUARD in text:
            continue
        missing.update(name for name in CLASS_PATTERN.findall(text) if name not in listed)
    return sorted(missing)


def run(command: list[str], timeout: int, label: str, *, capture: bool = False) -> str:
    print(f"\n==> {label}", flush=True)
    try:
        completed = subprocess.run(
            command,
            cwd=ROOT,
            check=False,
            timeout=timeout,
            capture_output=capture,
            text=capture,
        )
    except subprocess.TimeoutExpired as error:
        raise RuntimeError(
            f"{label} exceeded the {timeout}-second limit"
        ) from error
    if completed.returncode != 0:
        if capture:
            print(completed.stdout, completed.stderr, sep="\n", file=sys.stderr)
        raise RuntimeError(
            f"{label} failed with exit code {completed.returncode}"
        )
    return completed.stdout if capture else ""


def main() -> None:
    output = run(
        ["swift", "test", "list"],
        BUILD_TIMEOUT_SECONDS,
        "Compile and discover Swift tests",
        capture=True,
    )
    classes = listed_classes(output)
    if not classes:
        raise RuntimeError("No XCTestCase classes found")
    sources = {
        source.name: source.read_text(encoding="utf-8")
        for source in sorted((ROOT / "Tests").glob("**/*.swift"))
    }
    if missing := unlisted_classes(sources, set(classes)):
        raise RuntimeError(f"Test classes not run by SwiftPM: {', '.join(missing)}")
    print(f"Discovered {len(classes)} XCTestCase classes", flush=True)
    for class_name in classes:
        run(
            [
                "swift",
                "test",
                "--skip-build",
                "--filter",
                rf"^{TEST_MODULE}\.{re.escape(class_name)}/",
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
