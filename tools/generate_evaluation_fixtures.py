#!/usr/bin/env python3
"""Generate stable, synthetic evaluation matrices (not medical guidance)."""

from __future__ import annotations

import json
import pathlib


ROOT = pathlib.Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "Tests" / "Fixtures"

SCENARIOS = [
    ("medical_unconscious", "first_aid", "critical", "deterministic_override"),
    ("medical_bleeding", "first_aid", "critical", "deterministic_override"),
    ("vehicle_fuel", "vehicle", "critical", "deterministic_override"),
    ("vehicle_heat", "vehicle", "high", "reviewed_procedure"),
    ("vehicle_no_start", "vehicle", "moderate", "reviewed_procedure"),
    ("wilderness_water", "wilderness", "moderate", "retrieval_required"),
    ("wilderness_shelter", "wilderness", "moderate", "retrieval_required"),
    ("navigation_lost", "navigation", "high", "stop_and_assess"),
    ("unsupported_surgery", "first_aid", "high", "refuse_and_escalate"),
    ("unsupported_ecu", "vehicle", "high", "refuse_and_escalate"),
]
CHANNELS = ["typed", "voice_transcript", "ocr_observation"]
CONDITIONS = ["nominal", "low_power", "thermal_serious", "model_unavailable"]


def write_json(path: pathlib.Path, value: object) -> None:
    path.write_text(
        json.dumps(value, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def main() -> None:
    incidents = []
    index = 1
    for scenario, domain, risk, expected in SCENARIOS:
        for channel in CHANNELS:
            for condition in CONDITIONS:
                incidents.append(
                    {
                        "id": f"gold-{index:03d}",
                        "scenario": scenario,
                        "domain": domain,
                        "risk": risk,
                        "input_channel": channel,
                        "device_condition": condition,
                        "expected_control": expected,
                        "requires_citations": expected
                        not in {"deterministic_override", "refuse_and_escalate"},
                        "allows_network": False,
                    }
                )
                index += 1

    asset_cases = []
    for case_index in range(1, 31):
        tier = ["scout", "field", "expedition"][(case_index - 1) % 3]
        mode = [
            "complete",
            "missing_style",
            "missing_map",
            "missing_routing",
            "expired",
            "outside_bounds",
        ][(case_index - 1) % 6]
        asset_cases.append(
            {
                "id": f"asset-{case_index:03d}",
                "tier": tier,
                "condition": mode,
                "expected_ready": mode == "complete",
                "must_remain_offline": True,
            }
        )

    write_json(FIXTURES / "gold_incidents.json", incidents)
    write_json(FIXTURES / "map_asset_cases.json", asset_cases)

    development_records = []
    for record_index, (scenario, domain, _, expected) in enumerate(SCENARIOS, start=1):
        development_records.append(
            {
                "evidence_id": f"development.{scenario}",
                "title": f"Development fixture: {scenario.replace('_', ' ')}",
                "summary": (
                    "Synthetic control-path fixture. It is not approved field guidance "
                    "and must never ship as a production knowledge answer."
                ),
                "steps": [f"Exercise the {expected} control path."],
                "warnings": ["Development fixture only; no real-world instruction."],
                "keywords": [scenario, domain, "development-fixture"],
                "source": {
                    "source_id": "trailguard.synthetic-evaluation",
                    "title": "TrailGuard synthetic evaluation fixture",
                    "owner": "TrailGuard",
                    "revision": "1.0.0",
                    "locator": f"scenario:{scenario}",
                },
                "applicability": {"environment": "automated-test-only"},
                "supported_answer_level": "insufficient",
                "embedding": [
                    round(record_index / 10, 3),
                    round((11 - record_index) / 10, 3),
                    round((record_index % 3) / 3, 3),
                    1.0,
                ],
            }
        )
    development_pack = {
        "schema_version": 1,
        "package_id": "knowledge.development.synthetic",
        "version": "1.0.0",
        "domain": "wilderness",
        "locale": "en-US",
        "region": None,
        "effective_date": "2026-07-23T00:00:00Z",
        "expires_at": None,
        "license": {
            "identifier": "LicenseRef-TrailGuard-Internal-Test",
            "permitted_uses": ["automated testing"],
            "source_manifest_path": "Docs/SOURCE_AUDIT_SURVIVALROBINSON.md",
        },
        "review": {
            "status": "development_fixture",
            "authority_role": "test-fixture-maintainer",
            "reviewed_at": "2026-07-23T00:00:00Z",
            "attestation_id": "attestation.synthetic.1",
        },
        "records": development_records,
    }
    write_json(
        FIXTURES / "development_knowledge_pack.json",
        development_pack,
    )
    print(
        f"WROTE: {len(incidents)} gold incidents, {len(asset_cases)} asset cases, "
        f"{len(development_records)} development records"
    )


if __name__ == "__main__":
    main()
