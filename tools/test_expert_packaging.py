#!/usr/bin/env python3
"""Focused tests for Expert calibration and retained packaging policy."""

from __future__ import annotations

import argparse
import unittest

from prepare_expert_model_package import validate_memory_profile_args
from run_physical_expert import rag_cases, report_failures


class ExpertPackagingTests(unittest.TestCase):
    def args(self, status: str, peaks: tuple[int | None, int | None, int | None]):
        return argparse.Namespace(
            memory_profile_status=status,
            peak_full=peaks[0],
            peak_balanced=peaks[1],
            peak_constrained=peaks[2],
        )

    def test_calibration_requires_absent_peaks(self):
        validate_memory_profile_args(self.args("calibration", (None, None, None)))
        with self.assertRaisesRegex(ValueError, "guessed"):
            validate_memory_profile_args(self.args("calibration", (1, 1, 1)))

    def test_retained_requires_every_positive_peak(self):
        validate_memory_profile_args(self.args("retained", (3, 2, 1)))
        for peaks in ((None, 2, 1), (3, 0, 1), (3, 2, -1)):
            with self.assertRaisesRegex(ValueError, "positive"):
                validate_memory_profile_args(self.args("retained", peaks))

    def test_rag_cases_are_not_counted_as_multiturn(self):
        self.assertTrue(all(case["runMode"] == "rag" for case in rag_cases(1)))

    def test_runner_fails_on_route_coverage_and_missing_cases(self):
        report = {
            "completed": True,
            "terminal_failure": None,
            "thermal_samples": [{"state": "nominal"}],
            "cases": [{"id": "a", "route_pass": False}],
        }
        failures = report_failures(report, ["a", "b"])
        self.assertIn("missing_duplicate_or_reordered_cases", failures)
        self.assertIn("route_or_coverage_failure:a", failures)

    def test_runner_fails_on_unsafe_thermal_sample(self):
        report = {
            "completed": True,
            "terminal_failure": None,
            "thermal_samples": [{"state": "serious"}],
            "cases": [],
        }
        self.assertIn("unsafe_thermal_sample", report_failures(report, []))

    def test_runner_fails_on_hidden_case_terminal_failure(self):
        report = {
            "completed": True,
            "terminal_failure": None,
            "thermal_samples": [{"state": "nominal"}],
            "cases": [{
                "id": "critical-a",
                "route_pass": True,
                "safety_pass": True,
                "terminal_failure": True,
            }],
        }
        self.assertIn(
            "case_terminal_failure:critical-a",
            report_failures(report, ["critical-a"]),
        )


if __name__ == "__main__":
    unittest.main()
