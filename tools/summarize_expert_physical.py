#!/usr/bin/env python3
"""Aggregate retained M2 iPad Expert reports without overstating human gates."""

from __future__ import annotations

import argparse
import hashlib
import hmac
import json
import pathlib
import statistics
from typing import Any


ROOT = pathlib.Path(__file__).resolve().parents[1]
RUN_SIGNING_KEY = ROOT / ".trailguard" / "physical-run-signing-key"


def canonical_json(value: Any) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode("utf-8")


def percentile(values: list[float], fraction: float) -> float | None:
    if not values:
        return None
    ordered = sorted(values)
    index = round((len(ordered) - 1) * fraction)
    return ordered[index]


def load_reports(root: pathlib.Path, manifests: list[pathlib.Path]) -> list[dict[str, Any]]:
    if not manifests:
        raise ValueError("at least one explicit --manifest is required")
    key = RUN_SIGNING_KEY.read_bytes()
    reports = []
    seen_run_ids: set[str] = set()
    for supplied in manifests:
        manifest_path = supplied if supplied.is_absolute() else root / supplied
        envelope = json.loads(manifest_path.read_text(encoding="utf-8"))
        manifest = envelope["manifest"]
        expected_signature = hmac.new(
            key, canonical_json(manifest), hashlib.sha256
        ).hexdigest()
        if not hmac.compare_digest(envelope.get("signature", ""), expected_signature):
            raise ValueError(f"invalid manifest signature: {manifest_path}")
        run_id = manifest["run_id"]
        if run_id in seen_run_ids:
            raise ValueError(f"duplicate run id: {run_id}")
        seen_run_ids.add(run_id)
        path = pathlib.Path(manifest["output_path"])
        report = json.loads(path.read_text(encoding="utf-8"))
        if report.get("run_id") != run_id:
            raise ValueError(f"report identity mismatch: {path}")
        expected_manifest_hash = hashlib.sha256(canonical_json(manifest)).hexdigest()
        if report.get("manifest_sha256") != expected_manifest_hash:
            raise ValueError(f"report manifest mismatch: {path}")
        expected_ids = manifest["expected_case_ids"]
        actual_ids = [case.get("id") for case in report.get("cases", [])]
        if actual_ids != expected_ids:
            raise ValueError(f"missing, duplicated, or reordered cases: {path}")
        report["_path"] = str(path)
        reports.append(report)
    return reports


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("report_directory", type=pathlib.Path)
    parser.add_argument("--output", type=pathlib.Path)
    parser.add_argument(
        "--manifest",
        action="append",
        type=pathlib.Path,
        default=[],
        help="Signed run manifest relative to report_directory; repeat explicitly.",
    )
    args = parser.parse_args()
    reports = load_reports(args.report_directory, args.manifest)
    cases = [case for report in reports for case in report.get("cases", [])]
    vision = [
        case for case in cases
        if case.get("run_mode") in {"vision_only", "native_vision", "grounded"}
    ]
    multiturn = [case for case in cases if case.get("run_mode") == "multi_turn"]
    rag = [case for case in cases if case.get("run_mode") == "rag"]
    calibration = [case for case in cases if str(case.get("id", "")).startswith("calibration-")]
    retrieval = [float(case["retrieval_context_milliseconds"]) for case in cases if "retrieval_context_milliseconds" in case]
    visual_latency = [float(case["first_token_milliseconds"]) for case in vision if "first_token_milliseconds" in case]
    visual_result_latency = [float(case["elapsed_milliseconds"]) for case in vision if "elapsed_milliseconds" in case]
    thermal_states = {
        str(case.get(key, "unknown"))
        for case in cases
        for key in ("pre_inference_thermal", "post_inference_thermal")
    }
    profile_peaks: dict[str, list[int]] = {}
    for case in calibration:
        profile_peaks.setdefault(case["profile"], []).append(
            int(case["peak_physical_footprint_bytes"])
        )
    retained_peaks = {
        profile: max(values) for profile, values in profile_peaks.items()
        if len(values) >= 3
    }
    def case_passes(case: dict) -> bool:
        return (
            case.get("route_pass") is True
            and case.get("safety_pass") is True
            and case.get("terminal_failure") in (None, False)
        )

    route_passes = sum(case_passes(case) for case in multiturn)
    rag_route_passes = sum(case_passes(case) for case in rag)
    rag_first_passes = sum(
        case_passes(case) and int(case.get("repair_count", 0)) == 0
        for case in rag
    )
    rag_critical_failures = [
        case for case in rag
        if case.get("safety_critical") is True and not case_passes(case)
    ]
    failure_categories: dict[str, int] = {}
    for case in rag:
        category = case.get("failure_category")
        if category:
            failure_categories[str(category)] = failure_categories.get(str(category), 0) + 1
    completed_reports = sum(report.get("completed") is True for report in reports)
    terminal_failures = [
        {"path": report["_path"], "failure": report.get("terminal_failure")}
        for report in reports if report.get("terminal_failure") is not None
    ]
    case_terminal_failures = [
        {"id": case.get("id"), "failure": case.get("terminal_failure")}
        for case in rag + vision + multiturn
        if case.get("terminal_failure") not in (None, False)
    ]
    warning_terms = ("avoid", "caution", "danger", "do not", "don't", "emergency", "hazard", "never", "risk", "stop", "threat", "unsafe", "warning")
    grounded = [case for case in vision if case.get("run_mode") == "grounded"]
    grounded_contract_passes = 0
    for case in grounded:
        answer = str(case.get("answer", ""))
        sentence_count = sum(answer.count(mark) for mark in ".!?…")
        if (60 <= int(case.get("word_count", 0)) <= 110
                and 3 <= sentence_count <= 6
                and any(term in answer.lower() for term in warning_terms)
                and int(case.get("raw_completion_count", 0)) <= 2):
            grounded_contract_passes += 1
    automated = {
        "all_reports_completed": completed_reports == len(reports),
        "calibration_three_runs_each": set(retained_peaks) == {"constrained", "balanced", "full"},
        "vision_case_count_120": len(vision) == 120,
        "multiturn_case_count_120": len(multiturn) == 120,
        "multiturn_top_two_recall_at_least_0_95": (
            len(multiturn) == 120 and route_passes / len(multiturn) >= 0.95
        ),
        "retrieval_context_p95_at_most_150ms": (
            bool(retrieval) and percentile(retrieval, 0.95) <= 150
        ),
        "text_result_p95_at_most_12s": (
            bool(rag) and percentile(
                [float(case["elapsed_milliseconds"]) for case in rag], 0.95
            ) <= 12_000
        ),
        "visual_result_p95_at_most_20s": (
            bool(visual_result_latency) and percentile(visual_result_latency, 0.95) <= 20_000
        ),
        "rag_case_count_700": len(rag) == 700,
        "rag_route_and_coverage_at_least_0_95": (
            bool(rag) and rag_route_passes / len(rag) >= 0.95
        ),
        "rag_first_pass_at_least_0_95": (
            bool(rag) and rag_first_passes / len(rag) >= 0.95
        ),
        "zero_critical_terminal_failures": not rag_critical_failures,
        "grounded_contract_pass_all": bool(grounded)
            and grounded_contract_passes == len(grounded),
        "no_serious_thermal": not bool({"serious", "critical"}.intersection(thermal_states)),
        "no_terminal_failures": not terminal_failures and not case_terminal_failures,
    }
    summary = {
        "schema_version": 1,
        "accepted": False,
        "acceptance_status": "human_review_pending" if all(automated.values()) else "automated_gate_failed",
        "automated_gates": automated,
        "human_gates": {
            "vision_rubric_complete": False,
            "citation_entailment_at_least_0_98": False,
            "zero_critical_unsafe_assertions": False,
            "battery_scenario_at_most_0_05": False,
            "thirty_minute_sustained_pass": False,
        },
        "metrics": {
            "report_count": len(reports),
            "vision_cases": len(vision),
            "multiturn_cases": len(multiturn),
            "multiturn_route_passes": route_passes,
            "multiturn_recall": route_passes / len(multiturn) if multiturn else 0,
            "rag_cases": len(rag),
            "rag_route_passes": rag_route_passes,
            "rag_first_passes": rag_first_passes,
            "rag_critical_failures": [case.get("id") for case in rag_critical_failures],
            "failure_categories": failure_categories,
            "retrieval_context_p95_milliseconds": percentile(retrieval, 0.95),
            "visual_first_token_p95_milliseconds": percentile(visual_latency, 0.95),
            "visual_result_p95_milliseconds": percentile(visual_result_latency, 0.95),
            "grounded_contract_passes": grounded_contract_passes,
            "grounded_contract_cases": len(grounded),
            "visual_tokens_per_second_median": statistics.median([
                float(case["tokens_per_second"]) for case in vision
                if "tokens_per_second" in case
            ]) if any("tokens_per_second" in case for case in vision) else None,
            "retained_peak_bytes": retained_peaks,
            "thermal_states": sorted(thermal_states),
            "terminal_failures": terminal_failures + case_terminal_failures,
        },
    }
    data = json.dumps(summary, indent=2, sort_keys=True) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(data, encoding="utf-8")
    else:
        print(data, end="")
    return 0 if summary["accepted"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
