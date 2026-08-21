#!/usr/bin/env python3
"""Run the fixed three-prompt Expert/Lite comparison on one physical iPad."""

from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import shutil
import signal
import subprocess
import tempfile
import time
from typing import Any


ROOT = pathlib.Path(__file__).resolve().parents[1]
DEFAULT_DEVICE = "00008112-001D484C2678A01E"
DEFAULT_BUNDLE = "com.example.Aurora"
DEVICE_TEMP_ROOT = "tmp"
DEVICE_REPORT_ROOT = "tmp/AuroraExpertBenchmarkReports"


CASES: list[dict[str, Any]] = [
    {
        "id": "comparison-car-no-start",
        "question": "My car will not start. The dash lights are dim and I hear one click. What should I check first?",
        "imageFilename": None,
        "runMode": "rag",
        "safetyCritical": True,
        "domain": None,
        "resetSession": True,
        "expectedLessonIDs": ["car-jump"],
        "acceptableEvidenceSets": [["car-no-start-triage"]],
        "history": [],
        "imageObservations": [],
    },
    {
        "id": "comparison-water-boil",
        "question": "How long should I boil collected stream water before drinking it?",
        "imageFilename": None,
        "runMode": "rag",
        "safetyCritical": True,
        "domain": None,
        "resetSession": True,
        "expectedLessonIDs": ["water-boil"],
        "acceptableEvidenceSets": [["water-boil-scenario"]],
        "history": [],
        "imageObservations": [],
    },
    {
        "id": "comparison-lost-trail",
        "question": "I am lost on a marked trail with two hours of daylight left. What should I do first?",
        "imageFilename": None,
        "runMode": "rag",
        "safetyCritical": True,
        "domain": None,
        "resetSession": True,
        "expectedLessonIDs": ["navigation-stop-mark"],
        "acceptableEvidenceSets": [["navigation-stop-mark-scenario"]],
        "history": [],
        "imageObservations": [],
    },
]


def run(command: list[str], *, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(command, check=check, capture_output=True, text=True)


def copy_report(
    device: str,
    bundle: str,
    source_name: str,
    destination: pathlib.Path,
) -> bool:
    destination.unlink(missing_ok=True)
    result = run([
        "xcrun", "devicectl", "device", "copy", "from",
        "--device", device,
        "--domain-type", "appDataContainer",
        "--domain-identifier", bundle,
        "--source", f"{DEVICE_REPORT_ROOT}/{source_name}",
        "--destination", str(destination),
        "--timeout", "20",
    ], check=False)
    return result.returncode == 0 and destination.is_file()


def wait_for_report(
    device: str,
    bundle: str,
    source_name: str,
    launcher: subprocess.Popen[bytes],
    timeout: int,
) -> dict[str, Any]:
    deadline = time.monotonic() + timeout
    with tempfile.TemporaryDirectory(prefix="trailguard-tier-report-") as temp:
        candidate = pathlib.Path(temp) / source_name
        while time.monotonic() < deadline:
            if launcher.poll() is not None:
                raise RuntimeError("Aurora exited before comparison completion")
            if copy_report(device, bundle, source_name, candidate):
                try:
                    report = json.loads(candidate.read_text(encoding="utf-8"))
                except (json.JSONDecodeError, OSError):
                    report = {}
                if report.get("completed") is True:
                    return report
            time.sleep(5)
    raise TimeoutError("physical tier comparison did not complete")


def write_immutable(path: pathlib.Path, value: dict[str, Any]) -> None:
    if path.exists():
        raise FileExistsError(f"immutable output already exists: {path}")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(value, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--device", default=DEFAULT_DEVICE)
    parser.add_argument("--bundle", default=DEFAULT_BUNDLE)
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--timeout", type=int, default=1_800)
    parser.add_argument("--app-bundle", type=pathlib.Path, required=True)
    parser.add_argument(
        "--output-directory",
        type=pathlib.Path,
        default=ROOT / "Reports" / "physical-tier-comparison",
    )
    args = parser.parse_args()

    run_id = "".join(
        character if character.isalnum() or character in "._-" else "-"
        for character in args.run_id
    )
    if not run_id:
        parser.error("--run-id must contain at least one safe character")
    if not args.app_bundle.is_dir():
        parser.error(f"app bundle is unavailable: {args.app_bundle}")

    combined_path = args.output_directory / f"{run_id}-combined.json"
    expert_path = args.output_directory / f"{run_id}-expert.json"
    lite_path = args.output_directory / f"{run_id}-lite.json"
    for path in [combined_path, expert_path, lite_path]:
        if path.exists():
            parser.error(f"immutable output already exists: {path}")

    fixture_data = json.dumps(
        CASES, sort_keys=True, separators=(",", ":")
    ).encode("utf-8")
    fixture_sha256 = hashlib.sha256(fixture_data).hexdigest()
    source_name = f"physical-tier-comparison-{run_id}.json"
    with tempfile.TemporaryDirectory(prefix="trailguard-tier-fixture-") as temp:
        fixture_parent = pathlib.Path(temp)
        fixture_root = fixture_parent / "AuroraExpertBenchmark"
        fixture_root.mkdir()
        (fixture_root / "cases.json").write_bytes(fixture_data)

        if copy_report(
            args.device,
            args.bundle,
            source_name,
            fixture_parent / "existing.json",
        ):
            raise FileExistsError(
                f"immutable device report already exists: {source_name}"
            )
        run([
            "xcrun", "devicectl", "device", "install", "app",
            "--device", args.device, str(args.app_bundle),
        ])
        run([
            "xcrun", "devicectl", "device", "copy", "to",
            "--device", args.device,
            "--domain-type", "appDataContainer",
            "--domain-identifier", args.bundle,
            "--source", str(fixture_parent),
            "--destination", DEVICE_TEMP_ROOT,
            "--timeout", "60",
        ])
        environment = json.dumps({
            "TRAILGUARD_DEBUG_PHYSICAL_INFERENCE": "tier-comparison",
            "TRAILGUARD_DEBUG_PHYSICAL_RUN_ID": run_id,
        }, separators=(",", ":"))
        launcher = subprocess.Popen([
            "xcrun", "devicectl", "device", "process", "launch",
            "--device", args.device,
            "--terminate-existing",
            "--activate",
            "--console",
            "--environment-variables", environment,
            args.bundle,
        ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            report = wait_for_report(
                args.device,
                args.bundle,
                source_name,
                launcher,
                args.timeout,
            )
        finally:
            if launcher.poll() is None:
                launcher.send_signal(signal.SIGINT)
                try:
                    launcher.wait(timeout=15)
                except subprocess.TimeoutExpired:
                    launcher.terminate()
                    launcher.wait(timeout=15)

    if report.get("fixture_sha256") != fixture_sha256:
        raise RuntimeError("device report fixture hash does not match")
    if report.get("terminal_failure") is not None:
        raise RuntimeError(f"device terminal failure: {report['terminal_failure']}")
    cases = report.get("cases", [])
    if len(cases) != 6:
        raise RuntimeError(f"expected six comparison cases, received {len(cases)}")
    parent_sha256 = hashlib.sha256(
        json.dumps(report, sort_keys=True, separators=(",", ":")).encode("utf-8")
    ).hexdigest()
    write_immutable(combined_path, report)
    for tier, path in [("vision_expert", expert_path), ("lite", lite_path)]:
        tier_cases = [case for case in cases if case.get("tier") == tier]
        if len(tier_cases) != 3:
            raise RuntimeError(f"expected three {tier} cases")
        write_immutable(path, {
            "schema_version": 1,
            "run_id": run_id,
            "tier": tier,
            "fixture_sha256": fixture_sha256,
            "parent_report_sha256": parent_sha256,
            "cases": tier_cases,
        })

    print(combined_path)
    print(expert_path)
    print(lite_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
