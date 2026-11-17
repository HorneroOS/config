#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Gate table + Chromatic scheme contract (config#140).

The gate table (profiles/themes/contrast-gates.json) is the single source of
thresholds; lib/hornero/signal_theme.py reads it. These tests pin that the
curated themes keep their standard-level behaviour, that the boosted and
maximum levels resolve as specified, and that live-scheme documents carrying
the optional chromatic / minSurfaceAlpha / clearInk blocks validate (and fail
when they should).
"""

from __future__ import annotations

import copy
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "lib" / "hornero"))

import signal_theme as st  # noqa: E402

FIXTURES = ROOT / "tests" / "fixtures" / "chromatic"
THEMES = ROOT / "profiles" / "themes"


def fixture(name: str) -> dict:
    return json.loads((FIXTURES / name).read_text(encoding="utf-8"))


class GateTable(unittest.TestCase):
    def test_levels_resolve(self) -> None:
        std = st.resolve_level("standard")
        self.assertEqual(std["text"]["min"], 4.5)
        boosted = st.resolve_level("boosted")
        self.assertEqual(boosted["textOverrides"], {"ink": 7.0, "inkMuted": 5.5})
        self.assertEqual(boosted["text"]["min"], 4.5)
        self.assertEqual(boosted["boundary"]["min"], 4.5)
        self.assertEqual(len(boosted["focus"]["on"]), 6)
        maximum = st.resolve_level("maximum")
        self.assertEqual(maximum["text"]["min"], 7.0)
        self.assertEqual(maximum["onPairs"]["min"], 7.0)
        self.assertEqual(maximum["text"]["roles"], std["text"]["roles"])
        self.assertEqual(maximum["onPairs"]["pairs"], std["onPairs"]["pairs"])

    def test_unknown_level_rejected(self) -> None:
        with self.assertRaises(ValueError):
            st.resolve_level("extreme")

    def test_module_constants_come_from_the_table(self) -> None:
        self.assertEqual(st.TEXT_MIN, 4.5)
        self.assertEqual(st.BOUNDARY_MIN, 3.0)
        self.assertEqual(st.TERM_RGY_MIN_DE, 10.0)
        self.assertEqual(len(st.ON_PAIRS), 10)

    def test_env_override(self) -> None:
        table = json.loads((THEMES / st.GATES_FILENAME).read_text(encoding="utf-8"))
        table["levels"]["standard"]["text"]["min"] = 5.0
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "gates.json"
            path.write_text(json.dumps(table), encoding="utf-8")
            code = (
                "import sys; sys.path.insert(0, %r); import signal_theme as st; "
                "print(st.TEXT_MIN)" % str(ROOT / "lib" / "hornero")
            )
            out = subprocess.run(
                [sys.executable, "-c", code], capture_output=True, text=True, check=True,
                env={"HORNERO_CONTRAST_GATES": str(path), "PATH": "/usr/bin:/bin"},
            )
            self.assertEqual(out.stdout.strip(), "5.0")

    def test_installed_layouts_find_the_table(self) -> None:
        import shutil
        layouts = (("share/hornero/lib/hornero", "share/hornero/themes"),   # package
                   (".local/lib/hornero", ".local/share/hornero/themes"))   # materialize
        for lib_rel, data_rel in layouts:
            with tempfile.TemporaryDirectory() as tmp:
                lib = Path(tmp) / lib_rel
                data = Path(tmp) / data_rel
                lib.mkdir(parents=True)
                data.mkdir(parents=True)
                shutil.copy(ROOT / "lib/hornero/signal_theme.py", lib)
                shutil.copy(THEMES / st.GATES_FILENAME, data)
                out = subprocess.run(
                    [sys.executable, "-c", "import signal_theme as st; print(st.gates_path())"],
                    cwd=lib, capture_output=True, text=True, check=True,
                    env={"PATH": "/usr/bin:/bin", "PYTHONPATH": str(lib)})
                self.assertEqual(Path(out.stdout.strip()), (data / st.GATES_FILENAME).resolve())

    def test_curated_themes_unchanged_at_standard(self) -> None:
        for path in sorted(THEMES.glob("*/theme.json")):
            doc = st.load(path)
            self.assertEqual(st.validate(doc), [], path.parent.name)
            rows = st.contrast_report(doc)
            self.assertEqual(len(rows), 4 * 6 + 10 + 3 + 1, path.parent.name)
            self.assertTrue(all(minimum in (4.5, 3.0) for _, _, minimum in rows))

    def test_curated_themes_have_no_chromatic_rows(self) -> None:
        doc = st.load(THEMES / "hornero-signal-night" / "theme.json")
        self.assertNotIn("chromatic", doc)
        self.assertEqual(st.level_for(doc), "standard")


class SchemeDocuments(unittest.TestCase):
    def test_fixtures_validate(self) -> None:
        for name in ("scheme-red-dark.json", "scheme-blue-light.json"):
            self.assertEqual(st.validate_scheme(fixture(name)), [], name)

    def test_higher_levels_demand_more(self) -> None:
        doc = fixture("scheme-red-dark.json")
        self.assertTrue(st.validate_scheme(doc, "boosted"))
        self.assertTrue(st.validate_scheme(doc, "maximum"))

    def test_resolved_level_is_honoured(self) -> None:
        doc = fixture("scheme-red-dark.json")
        doc["chromatic"]["resolved"]["contrast"] = "maximum"
        errors = st.validate_scheme(doc)
        self.assertTrue(any("7.00" in e for e in errors), errors)

    def test_curated_scheme_has_no_optional_blocks(self) -> None:
        doc = st.load(THEMES / "hornero-signal-night" / "theme.json")
        live = st.live_scheme(doc)
        self.assertEqual(set(live), {"schemaVersion", "id", "mode", "palette", "terminal"})
        self.assertEqual(st.validate_scheme(live), [])

    def test_live_scheme_keeps_live_blocks(self) -> None:
        doc = fixture("scheme-red-dark.json")
        live = st.live_scheme(doc)
        for key in ("chromatic", "minSurfaceAlpha", "clearInk"):
            self.assertEqual(live[key], doc[key])

    def test_saved_provenance_is_not_live_state(self) -> None:
        base = st.load(THEMES / "hornero-signal-night" / "theme.json")
        saved = copy.deepcopy(base)
        saved.update(id="my-amber", collection="user", chromatic={
            "engine": "1.0.0", "algorithm": 1, "createdAt": "2026-11-17T04:00:00Z",
            "request": {"source": "seed", "variant": "balanced"}, "seeds": ["#D98A3A"]})
        errors = st.validate(saved)
        # Provenance alone does not make the pack a Chromatic scheme to gate
        # beyond what the curated gates already cover; shape must be valid.
        self.assertFalse([e for e in errors if "chromatic" in e and "missing" in e], errors)
        self.assertEqual(set(st.live_scheme(saved)), {"schemaVersion", "id", "mode", "palette", "terminal"})

    def test_collection_user_accepted(self) -> None:
        doc = st.load(THEMES / "hornero-signal-night" / "theme.json")
        doc["collection"] = "user"
        self.assertEqual(st.structural_errors(doc), [])


class NegativeFixtures(unittest.TestCase):
    def mutate(self, name: str, fn) -> list[str]:
        doc = fixture("scheme-red-dark.json")
        fn(doc)
        return st.validate_scheme(doc)

    def assertRejected(self, fn, needle: str) -> None:
        errors = self.mutate("scheme-red-dark.json", fn)
        self.assertTrue(any(needle in e for e in errors), (needle, errors))

    def test_structure(self) -> None:
        self.assertRejected(lambda d: d.update(extra=1), "unknown key 'extra'")
        self.assertRejected(lambda d: d.pop("chromatic"), "requires a chromatic block")
        self.assertRejected(lambda d: d["chromatic"].update(fingerprint="sha256:zz"), "fingerprint")
        self.assertRejected(lambda d: d["chromatic"].pop("resolved"), "missing 'resolved'")
        self.assertRejected(lambda d: d["chromatic"]["resolved"].update(contrast="auto"), "resolved.contrast")
        self.assertRejected(lambda d: d["chromatic"].update(seeds=["#111111"] * 3), "seeds")
        self.assertRejected(lambda d: d["minSurfaceAlpha"].update(base=0.2), "minSurfaceAlpha.base")
        self.assertRejected(lambda d: d["minSurfaceAlpha"].update(floating=0.9), "unknown surface")
        self.assertRejected(lambda d: d["clearInk"].pop("light"), "clearInk")
        self.assertRejected(lambda d: d["clearInk"]["dark"].pop("halo"), "clearInk.dark")
        self.assertRejected(lambda d: d["clearInk"]["dark"].update(ink="#abc"), "clearInk.dark.ink")
        self.assertRejected(lambda d: d["palette"].update(accent="#000000"), "non-Signal keys")
        self.assertRejected(lambda d: d["terminal"].pop(), "exactly 16")

    def test_gates(self) -> None:
        self.assertRejected(lambda d: d["palette"].update(ink=d["palette"]["panel"]), "ink on panel")
        self.assertRejected(lambda d: d["palette"].update(focus=d["palette"]["lifted"]), "focus on")
        self.assertRejected(lambda d: d["palette"].update(alert=d["palette"]["signal"]), "deltaE-OK")
        self.assertRejected(lambda d: d["palette"].update(alert=d["palette"]["signal"]), "hue degrees")

    def test_chromatic_focus_on_every_surface(self) -> None:
        doc = fixture("scheme-red-dark.json")
        # Visible on base (standard gate) but invisible on a lighter surface.
        doc["palette"]["focus"] = doc["palette"]["lifted"]
        errors = st.validate_scheme(doc)
        self.assertTrue(any("(chromatic)" in e for e in errors), errors)

    def test_curated_without_chromatic_skips_separation(self) -> None:
        doc = st.load(THEMES / "hornero-signal-night" / "theme.json")
        self.assertFalse([r for r in st.contrast_report(doc) if "hue" in r[0]])


class Schemas(unittest.TestCase):
    def setUp(self) -> None:
        self.scheme_schema = json.loads((THEMES / "scheme.schema.json").read_text(encoding="utf-8"))
        self.tokens_schema = json.loads((THEMES / "tokens.schema.json").read_text(encoding="utf-8"))

    def test_scheme_schema_matches_module(self) -> None:
        self.assertEqual(set(self.scheme_schema["properties"]), set(st.SCHEME_KEYS))
        self.assertEqual(self.scheme_schema["required"], ["schemaVersion", "id", "mode", "palette", "terminal"])
        self.assertEqual(self.scheme_schema["properties"]["palette"]["required"], list(st.ROLES))
        self.assertEqual(set(self.scheme_schema["properties"]["minSurfaceAlpha"]["properties"]),
                         set(st.ALPHA_SURFACES))

    def test_tokens_schema_accepts_user_collection_and_chromatic(self) -> None:
        self.assertIn("user", self.tokens_schema["properties"]["collection"]["enum"])
        self.assertEqual(self.tokens_schema["properties"]["collection"]["enum"], list(st.COLLECTIONS))
        self.assertIn("chromatic", self.tokens_schema["properties"])
        self.assertEqual(self.tokens_schema["properties"]["schemaVersion"], {"const": 2})

    def test_jsonschema_validation_when_available(self) -> None:
        try:
            import jsonschema
        except ImportError:
            self.skipTest("python jsonschema not installed")
        for name in ("scheme-red-dark.json", "scheme-blue-light.json"):
            jsonschema.validate(fixture(name), self.scheme_schema)
        jsonschema.validate(st.live_scheme(st.load(THEMES / "hornero-signal-night" / "theme.json")),
                            self.scheme_schema)
        saved = st.load(THEMES / "hornero-signal-night" / "theme.json")
        saved.update(id="my-amber", collection="user", chromatic={
            "engine": "1.0.0", "algorithm": 1, "request": {"variant": "balanced"}, "seeds": ["#D98A3A"]})
        jsonschema.validate(saved, self.tokens_schema)
        bad = fixture("scheme-red-dark.json")
        bad["minSurfaceAlpha"]["base"] = 0.2
        with self.assertRaises(jsonschema.ValidationError):
            jsonschema.validate(bad, self.scheme_schema)


class Cli(unittest.TestCase):
    def run_cli(self, *args: str) -> subprocess.CompletedProcess:
        return subprocess.run([sys.executable, str(ROOT / "lib/hornero/signal_theme.py"), *args],
                              capture_output=True, text=True)

    def test_validate_scheme_flag(self) -> None:
        ok = self.run_cli("validate", "--scheme", str(FIXTURES / "scheme-red-dark.json"))
        self.assertEqual(ok.returncode, 0, ok.stderr)
        bad = self.run_cli("validate", "--scheme", "--level", "maximum", str(FIXTURES / "scheme-red-dark.json"))
        self.assertEqual(bad.returncode, 1)
        wrong = self.run_cli("validate", str(FIXTURES / "scheme-red-dark.json"))
        self.assertEqual(wrong.returncode, 1)

    def test_scheme_command_for_curated(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "scheme.json"
            done = self.run_cli("scheme", str(THEMES / "hornero-signal-night" / "theme.json"), "--output", str(out))
            self.assertEqual(done.returncode, 0, done.stderr)
            self.assertEqual(st.validate_scheme(json.loads(out.read_text())), [])


if __name__ == "__main__":
    unittest.main()
