#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Tests for scripts/validate-wallpapers.py provenance & size budget audit (config#182)."""

from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "scripts" / "validate-wallpapers.py"


def _load_module():
    spec = importlib.util.spec_from_file_location("validate_wallpapers", SCRIPT)
    assert spec and spec.loader
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


class WallpaperAuditTests(unittest.TestCase):
    def test_default_cli_output_unchanged(self) -> None:
        res = subprocess.run([sys.executable, str(SCRIPT)], capture_output=True, text=True)
        self.assertEqual(res.returncode, 0, res.stderr)
        self.assertRegex(
            res.stdout.strip(),
            r"^WALLPAPER-PASS: \d+ collection assets \(\d+ licensed\) and theme references validated$",
        )

    def test_audit_licenses_text_and_json(self) -> None:
        text_res = subprocess.run(
            [sys.executable, str(SCRIPT), "--audit-licenses"],
            capture_output=True,
            text=True,
        )
        self.assertEqual(text_res.returncode, 0, text_res.stderr)
        self.assertIn("Wallpaper License Provenance & Size Budget Audit", text_res.stdout)
        self.assertIn("Verified CC/CC0", text_res.stdout)
        self.assertIn("First-party SVG", text_res.stdout)
        self.assertIn("Largest unverified legacy assets", text_res.stdout)

        json_res = subprocess.run(
            [sys.executable, str(SCRIPT), "--audit-licenses", "--json"],
            capture_output=True,
            text=True,
        )
        self.assertEqual(json_res.returncode, 0, json_res.stderr)
        report = json.loads(json_res.stdout)
        summary = report["summary"]
        self.assertEqual(
            summary["verifiedAssets"] + summary["unverifiedAssets"],
            summary["totalCollectionAssets"],
        )
        self.assertEqual(
            summary["verifiedBytes"] + summary["unverifiedBytes"],
            summary["totalCollectionBytes"],
        )
        self.assertGreaterEqual(summary["verifiedAssets"], 3)
        self.assertGreaterEqual(summary["originalProceduralAssets"], 2)
        sizes = [row["bytes"] for row in report["unverifiedBySize"]]
        self.assertEqual(sizes, sorted(sizes, reverse=True))

    def test_budget_flags_enforce_thresholds(self) -> None:
        fail_total = subprocess.run(
            [sys.executable, str(SCRIPT), "--max-unverified-bytes", "1024"],
            capture_output=True,
            text=True,
        )
        self.assertEqual(fail_total.returncode, 1)
        self.assertIn("max-unverified-bytes", fail_total.stderr)

        fail_file = subprocess.run(
            [sys.executable, str(SCRIPT), "--max-file-bytes", "1024"],
            capture_output=True,
            text=True,
        )
        self.assertEqual(fail_file.returncode, 1)
        self.assertIn("max-file-bytes", fail_file.stderr)

    def test_approved_licenses_include_cc0(self) -> None:
        mod = _load_module()
        self.assertIn("CC0 1.0", mod.APPROVED_LICENSES)
        self.assertIn("CC BY 2.0", mod.APPROVED_LICENSES)


if __name__ == "__main__":
    unittest.main()
