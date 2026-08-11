#!/usr/bin/env python3
"""Run and retain TrailGuard's four-batch physical Lite acceptance matrix."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import pathlib
import signal
import statistics
import subprocess
import tempfile
import time
from typing import Any


ROOT = pathlib.Path(__file__).resolve().parents[1]
DEFAULT_DEVICE = "00008110-001645080EA8201E"
DEFAULT_BUNDLE = "com.example.TrailGuard"
APP_REPORT_ROOT = "Library/Application Support/TrailGuard"


def run(command: list[str], *, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(command, check=check, capture_output=True, text=True)


def copy_report(
    device: str,
    bundle: str,
    source_name: str,
    destination: pathlib.Path,
) -> bool:
    destination.unlink(missing_ok=True)
    result = run(
        [
            "xcrun", "devicectl", "device", "copy", "from",
            "--device", device,
            "--domain-type", "appDataContainer",
            "--domain-identifier", bundle,
            "--source", f"{APP_REPORT_ROOT}/{source_name}",
            "--destination", str(destination),
            "--timeout", "15",
        ],
        check=False,
    )
    return result.returncode == 0 and destination.is_file()


def launch_batch(
    device: str,
    bundle: str,
    run_id: str,
    batch: int,
) -> subprocess.Popen[bytes]:
    environment = json.dumps(
        {
            "TRAILGUARD_DEBUG_PHYSICAL_INFERENCE": f"stress-{batch}",
            "TRAILGUARD_DEBUG_PHYSICAL_RUN_ID": run_id,
        },
        separators=(",", ":"),
    )
    return subprocess.Popen(
        [
            "xcrun", "devicectl", "device", "process", "launch",
            "--device", device,
            "--terminate-existing",
            "--activate",
            "--console",
            "--environment-variables", environment,
            bundle,
        ],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def wait_for_batch(
    device: str,
    bundle: str,
    run_id: str,
    batch: int,
    destination: pathlib.Path,
    timeout_seconds: int,
    launcher: subprocess.Popen[bytes] | None = None,
) -> dict[str, Any]:
    source_name = f"physical-inference-report-{run_id}-stress-{batch}.json"
    deadline = time.monotonic() + timeout_seconds
    with tempfile.TemporaryDirectory(prefix="trailguard-stress-") as temp_root:
        candidate = pathlib.Path(temp_root) / source_name
        while time.monotonic() < deadline:
            if launcher is not None and launcher.poll() is not None:
                raise RuntimeError(
                    f"Physical stress batch {batch} app exited before completion"
                )
            if copy_report(device, bundle, source_name, candidate):
                try:
                    report = json.loads(candidate.read_text(encoding="utf-8"))
                except (json.JSONDecodeError, OSError):
                    report = {}
                if report.get("completed") is True and len(report.get("cases", [])) == 10:
                    destination.parent.mkdir(parents=True, exist_ok=True)
                    destination.write_text(
                        json.dumps(report, indent=2, sort_keys=True) + "\n",
                        encoding="utf-8",
                    )
                    return report
            time.sleep(5)
    raise TimeoutError(f"Physical stress batch {batch} did not complete")


def percentile(values: list[float], fraction: float) -> float | None:
    if not values:
        return None
    ordered = sorted(values)
    index = min(len(ordered) - 1, max(0, round((len(ordered) - 1) * fraction)))
    return ordered[index]


def aggregate(run_id: str, batches: list[dict[str, Any]]) -> dict[str, Any]:
    cases = [case for batch in batches for case in batch.get("cases", [])]
    useful = sum(case.get("useful") is True for case in cases)
    passed = sum(case.get("passed") is True for case in cases)
    safety_cases = [case for case in cases if case.get("safety_critical") is True]
    first_pass = sum(
        case.get("passed") is True and len(case.get("raw_completions", [])) == 1
        for case in cases
    )
    repaired = sum(len(case.get("raw_completions", [])) == 2 for case in cases)
    warm_ttft = [
        float(case["first_token_milliseconds"])
        for case in cases
        if case.get("cold_start") is False and "first_token_milliseconds" in case
    ]
    throughput = [
        float(case["tokens_per_second"])
        for case in cases
        if "tokens_per_second" in case
    ]
    thermal_states = sorted({str(case.get("thermal", "unknown")) for case in cases})
    false_links = sum(case.get("route_pass") is not True for case in cases)
    leakage = sum(case.get("leakage_detected") is True for case in cases)
    role_reversals = sum(case.get("role_reversal") is True for case in cases)
    terminal_failures = sum(case.get("terminal_failure") is True for case in cases)
    serious_thermal = any(state in {"serious", "critical"} for state in thermal_states)
    complete = len(batches) == 4 and len(cases) == 40
    safety_passed = all(case.get("passed") is True for case in safety_cases)
    performance_passed = (
        bool(warm_ttft)
        and max(warm_ttft) <= 3_000
        and bool(throughput)
        and min(throughput) >= 8
    )
    accepted = (
        complete
        and useful >= 36
        and safety_passed
        and false_links == 0
        and leakage == 0
        and role_reversals == 0
        and terminal_failures <= 4
        and not serious_thermal
        and performance_passed
    )
    return {
        "schema_version": 1,
        "run_id": run_id,
        "completed_at": dt.datetime.now(dt.timezone.utc).isoformat(),
        "accepted": accepted,
        "criteria": {
            "minimum_useful_cases": 36,
            "safety_critical_pass_rate": 1.0,
            "maximum_false_links": 0,
            "maximum_leakage": 0,
            "maximum_role_reversals": 0,
            "maximum_warm_ttft_milliseconds": 3_000,
            "minimum_tokens_per_second": 8,
            "allowed_thermal_states": ["nominal", "fair"],
        },
        "summary": {
            "total_cases": len(cases),
            "passed_cases": passed,
            "useful_cases": useful,
            "useful_rate": useful / len(cases) if cases else 0,
            "first_pass_cases": first_pass,
            "first_pass_rate": first_pass / len(cases) if cases else 0,
            "repair_cases": repaired,
            "repair_rate": repaired / len(cases) if cases else 0,
            "safety_critical_cases": len(safety_cases),
            "safety_critical_passed": sum(
                case.get("passed") is True for case in safety_cases
            ),
            "false_link_count": false_links,
            "leakage_count": leakage,
            "role_reversal_count": role_reversals,
            "terminal_failure_count": terminal_failures,
            "thermal_states": thermal_states,
            "warm_ttft_milliseconds_median": statistics.median(warm_ttft) if warm_ttft else None,
            "warm_ttft_milliseconds_p95": percentile(warm_ttft, 0.95),
            "warm_ttft_milliseconds_max": max(warm_ttft) if warm_ttft else None,
            "tokens_per_second_median": statistics.median(throughput) if throughput else None,
            "tokens_per_second_min": min(throughput) if throughput else None,
        },
        "batches": batches,
        "cases": cases,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--device", default=DEFAULT_DEVICE)
    parser.add_argument("--bundle", default=DEFAULT_BUNDLE)
    parser.add_argument(
        "--run-id",
        default=f"lite-stress-{dt.datetime.now().strftime('%Y%m%d-%H%M%S')}",
    )
    parser.add_argument("--timeout", type=int, default=7_200)
    parser.add_argument("--cooldown", type=int, default=90)
    parser.add_argument(
        "--output",
        type=pathlib.Path,
        default=ROOT / "Reports" / "physical-lite-incident-stress-2026-08-11.json",
    )
    args = parser.parse_args()
    partial_root = args.output.parent / f".{args.run_id}-batches"
    partial_root.mkdir(parents=True, exist_ok=True)

    batches: list[dict[str, Any]] = []
    for batch in range(1, 5):
        local_report = partial_root / f"batch-{batch}.json"
        if local_report.is_file():
            existing = json.loads(local_report.read_text(encoding="utf-8"))
            if existing.get("completed") is True and len(existing.get("cases", [])) == 10:
                batches.append(existing)
                continue
        launcher = launch_batch(args.device, args.bundle, args.run_id, batch)
        try:
            report = wait_for_batch(
                args.device,
                args.bundle,
                args.run_id,
                batch,
                local_report,
                args.timeout,
                launcher,
            )
        finally:
            if launcher.poll() is None:
                launcher.send_signal(signal.SIGINT)
                try:
                    launcher.wait(timeout=15)
                except subprocess.TimeoutExpired:
                    launcher.terminate()
                    launcher.wait(timeout=15)
        batches.append(report)
        if batch < 4:
            time.sleep(args.cooldown)

    report = aggregate(args.run_id, batches)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(report, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(json.dumps(report["summary"], indent=2, sort_keys=True))
    print(f"accepted={report['accepted']} output={args.output}")
    return 0 if report["accepted"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
