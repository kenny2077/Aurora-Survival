#!/usr/bin/env python3
"""Regression contract for Aurora's public package-catalog endpoints."""

import pathlib
import re
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
DOWNLOADS_BASE = "https://downloads.auroraforgelab.com"


class DownloadDomainTests(unittest.TestCase):
    def test_active_catalogs_use_branded_download_domain(self):
        project = (ROOT / "project.yml").read_text(encoding="utf-8")
        configured = set(re.findall(r'AURORA_PACKAGE_CATALOG_URL: "([^"]+)"', project))
        self.assertEqual(configured, {
            f"{DOWNLOADS_BASE}/species/catalog.json",
            f"{DOWNLOADS_BASE}/catalog-development.json",
        })

        ui_tests = (ROOT / "UITests" / "PhysicalProductFlowTests.swift").read_text(
            encoding="utf-8"
        )
        self.assertIn(
            f'private let developmentCatalogURL = "{DOWNLOADS_BASE}/catalog-development.json"',
            ui_tests,
        )

        for path in (ROOT / "project.yml", ROOT / "UITests" / "PhysicalProductFlowTests.swift"):
            self.assertNotIn(".r2.dev", path.read_text(encoding="utf-8"), path.name)


if __name__ == "__main__":
    unittest.main()
