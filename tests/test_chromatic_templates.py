#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Shipped Chromatic templates: manifests, grammar and golden renders.

Every first-party template is rendered against the Signal Night and Day
documents and compared byte-for-byte with tests/golden/chromatic/. The same
goldens are consumed by horneroctl's V template engine (hornero#428), so the
two implementations of the grammar cannot drift. Regenerate with
CHROMATIC_UPDATE_GOLDEN=1.
"""

from __future__ import annotations

import json
import os
import re
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tests"))
sys.path.insert(0, str(ROOT / "lib" / "hornero"))

import chromatic_template as ct  # noqa: E402
import signal_theme as st  # noqa: E402

TEMPLATES = ROOT / "share" / "hornero" / "chromatic" / "templates"
GOLDEN = ROOT / "tests" / "golden" / "chromatic"
THEMES = ROOT / "profiles" / "themes"
SCHEMES = {"night": "hornero-signal-night", "day": "hornero-signal-day"}
OUTPUT_RE = re.compile(r"^(\$\{XDG_CONFIG_HOME\}|\$\{XDG_CACHE_HOME\}|\$\{XDG_DATA_HOME\}|~)/")
EXPECTED = {
    "gtk3", "gtk4", "qt6ct", "qt5ct", "kitty", "foot", "fuzzel",
    "niri", "nvim", "zed", "alacritty", "ghostty", "vscode", "firefox",
}


def scheme(key: str) -> dict:
    return st.live_scheme(st.load(THEMES / SCHEMES[key] / "theme.json"))


def manifests() -> dict[str, dict]:
    return {p.stem: json.loads(p.read_text(encoding="utf-8")) for p in sorted(TEMPLATES.glob("*.json"))}


class Manifests(unittest.TestCase):
    def test_first_party_set(self) -> None:
        self.assertEqual(set(manifests()), EXPECTED)

    def test_manifest_contract(self) -> None:
        schema = json.loads((TEMPLATES.parent / "template-manifest.schema.json").read_text(encoding="utf-8"))
        allowed = set(schema["properties"])
        for name, m in manifests().items():
            self.assertEqual(m["name"], name)
            self.assertLessEqual(set(m), allowed, name)
            self.assertEqual(m["schemaVersion"], 1)
            self.assertTrue((TEMPLATES / m["template"]).is_file(), name)
            self.assertRegex(m["output"], OUTPUT_RE)
            self.assertNotIn("..", m["output"])
            self.assertIn(m["when"], ("chromatic", "always"))
            if "requires" in m:
                self.assertRegex(m["requires"], OUTPUT_RE)
            if "adapter" in m:
                self.assertIn(m["adapter"], ("kitty", "gtk3", "gtk4", "qt6ct", "qt5ct"))

    def test_jsonschema_when_available(self) -> None:
        try:
            import jsonschema
        except ImportError:
            self.skipTest("python jsonschema not installed")
        schema = json.loads((TEMPLATES.parent / "template-manifest.schema.json").read_text(encoding="utf-8"))
        for m in manifests().values():
            jsonschema.validate(m, schema)

    def test_outputs_are_unique(self) -> None:
        outs = [m["output"] for m in manifests().values()]
        self.assertEqual(len(outs), len(set(outs)))


class Grammar(unittest.TestCase):
    S = {"id": "t", "mode": "dark",
         "palette": {"signal": "#F2A33A", "ink": "#ECE6DA", "base": "#101419"},
         "terminal": ["#000000"] * 15 + ["#ABCDEF"]}

    def r(self, text: str) -> str:
        return ct.render(text, self.S, "x.tmpl")

    def test_filters(self) -> None:
        self.assertEqual(self.r("{{signal}}|{{ signal.hex }}|{{ signal.bare }}"), "#F2A33A|#F2A33A|F2A33A")
        self.assertEqual(self.r("{{ signal.rgb }}|{{ signal.r }}|{{signal.g}}|{{ signal.b }}"), "242, 163, 58|242|163|58")
        self.assertEqual(self.r("{{ signal.rgba 0.8 }}"), "rgba(242, 163, 58, 0.80)")
        self.assertEqual(self.r("{{ term15 }} {{ term0.bare }} {{ mode }} {{ id }}"), "#ABCDEF 000000 dark t")

    def test_glow_falls_back_to_signal(self) -> None:
        self.assertEqual(self.r("{{ glow }}"), "#F2A33A")

    def test_sections(self) -> None:
        self.assertEqual(self.r("a{{#dark}}D{{/dark}}{{#light}}L{{/light}}b"), "aDb")
        light = dict(self.S, mode="light")
        self.assertEqual(ct.render("{{#dark}}D{{/dark}}{{#light}}{{ ink }}{{/light}}", light), "#ECE6DA")

    def test_rejections(self) -> None:
        cases = {
            "{{ nope }}": "1:1: unknown role",
            "ok\n  {{ signal.hsl }}": "2:3: unknown filter",
            "{{ signal.rgba }}": "bad filter arguments",
            "{{ signal.rgba 1.5 }}": "bad filter arguments",
            "{{ signal.bare 2 }}": "bad filter arguments",
            "{{ term16 }}": "unknown role",
            "{{ mode.bare }}": "unknown role",
            "{{ 1 + 1 }}": "malformed",
            "{{ signal | upper }}": "malformed",
            "{{> include }}": "malformed",
            "{{#each x}}{{/each}}": "unknown section",
            "{{#dark}}x": "unclosed section",
            "x{{/dark}}": "unmatched",
            "{{#dark}}{{#light}}": "cannot nest",
            "{{ signal": "stray",
            "a }} b": "stray",
        }
        for text, needle in cases.items():
            with self.assertRaises(ct.TemplateError, msg=text) as ctx:
                self.r(text)
            self.assertIn(needle, str(ctx.exception), text)
            self.assertTrue(str(ctx.exception).startswith("x.tmpl:"), text)


class Golden(unittest.TestCase):
    def test_every_template_renders_to_its_golden(self) -> None:
        update = os.environ.get("CHROMATIC_UPDATE_GOLDEN") == "1"
        for name, m in manifests().items():
            text = (TEMPLATES / m["template"]).read_text(encoding="utf-8")
            for key in SCHEMES:
                rendered = ct.render(text, scheme(key), m["template"])
                golden = GOLDEN / f"{name}.{key}.golden"
                if update:
                    golden.parent.mkdir(parents=True, exist_ok=True)
                    golden.write_text(rendered, encoding="utf-8")
                self.assertEqual(golden.read_text(encoding="utf-8"), rendered, f"{name}.{key}")
                self.assertNotRegex(rendered, r"\{\{|\}\}")

    def test_templates_use_only_semantic_roles(self) -> None:
        forbidden = re.compile(r"#[0-9A-Fa-f]{6}\b")
        for m in manifests().values():
            text = (TEMPLATES / m["template"]).read_text(encoding="utf-8")
            literal = [h for h in forbidden.findall(text) if h.upper() not in ("#FFFFFF", "#000000")]
            self.assertEqual(literal, [], f"{m['name']} hard-codes colours")

    def test_modes_differ_and_structured_outputs_parse(self) -> None:
        import tomllib

        zed = json.loads((GOLDEN / "zed.night.golden").read_text(encoding="utf-8"))
        self.assertEqual(zed["themes"][0]["appearance"], "dark")
        self.assertEqual(json.loads((GOLDEN / "zed.day.golden").read_text())["themes"][0]["appearance"], "light")
        vscode_night = json.loads((GOLDEN / "vscode.night.golden").read_text(encoding="utf-8"))
        vscode_day = json.loads((GOLDEN / "vscode.day.golden").read_text(encoding="utf-8"))
        self.assertEqual(vscode_night["type"], "dark")
        self.assertEqual(vscode_day["type"], "light")
        alacritty = tomllib.loads((GOLDEN / "alacritty.night.golden").read_text(encoding="utf-8"))
        self.assertIn("primary", alacritty["colors"])
        qt = (GOLDEN / "qt6ct.night.golden").read_text(encoding="utf-8")
        for line in qt.splitlines():
            if line.startswith(("active_colors=", "inactive_colors=", "disabled_colors=")):
                self.assertEqual(len(line.split("=", 1)[1].split(", ")), 22)
        self.assertIn("#ffffffff", qt)
        self.assertIn("#ff000000", (GOLDEN / "qt6ct.day.golden").read_text().split("\n")[3])


if __name__ == "__main__":
    unittest.main()
