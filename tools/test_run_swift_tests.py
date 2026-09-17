#!/usr/bin/env python3

import unittest

import run_swift_tests as runner


class SwiftTestRunnerTests(unittest.TestCase):
    def test_listed_classes_come_from_swiftpm_output(self) -> None:
        output = "\n".join([
            "Building for debugging...",
            "AuroraCoreTests.BetaTests/testOne",
            "AuroraCoreTests.AlphaTests/testOne",
            "AuroraCoreTests.AlphaTests/testTwo",
            "OtherTests.IgnoredTests/testOne",
        ])
        self.assertEqual(runner.listed_classes(output), ["AlphaTests", "BetaTests"])

    def test_unlisted_source_class_fails_unless_app_target_only(self) -> None:
        sources = {
            "Listed.swift": "final class ListedTests: XCTestCase {}",
            "AppOnly.swift": "#if !SWIFT_PACKAGE\nfinal class AppOnlyTests: XCTestCase {}\n#endif",
            "Dropped.swift": "class DroppedTests: XCTestCase {}",
        }
        self.assertEqual(runner.unlisted_classes(sources, {"ListedTests"}), ["DroppedTests"])


if __name__ == "__main__":
    unittest.main()
