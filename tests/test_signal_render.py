#!/usr/bin/env python3
"""Unit tests for the Hornero Signal renderers (lib/hornero/signal_render.py)."""

from __future__ import annotations

import configparser
import copy
import json
import re
import sys
import tempfile
import tomllib
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.dont_write_bytecode = True
sys.path.insert(0, str(ROOT / "lib" / "hornero"))

import signal_render as sr  # noqa: E402
import signal_theme as st  # noqa: E402

NIGHT = ROOT / "profiles/themes/hornero-signal-night/theme.json"


def night() -> dict:
    return json.loads(NIGHT.read_text(encoding="utf-8"))


class SignalRenderTests(unittest.TestCase):
    def test_terminal_formats_map_from_signal_roles(self) -> None:
        theme = night()
        p, term = theme["palette"], theme["terminal"]
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            outputs = {
                "kitty": root / "kitty/colors.conf",
                "alacritty": root / "alacritty/hornero-colors.toml",
                "ghostty": root / "ghostty/themes/Hornero Dynamic",
                "btop": root / "btop/themes/Hornero Dynamic.theme",
                "cava": root / "cava/themes/Hornero Dynamic",
            }
            written = sr.render_outputs(theme, outputs)
            self.assertEqual(set(written), {str(p_) for p_ in outputs.values()})

            kitty = outputs["kitty"].read_text(encoding="utf-8")
            self.assertIn(f"background {p['base']}", kitty)
            self.assertIn(f"foreground {p['ink']}", kitty)
            self.assertIn(f"cursor {p['signal']}", kitty)
            self.assertIn(f"selection_background {p['cueWell']}", kitty)
            self.assertEqual([f"color{i} {term[i]}" for i in range(16)],
                             [line for line in kitty.splitlines() if re.match(r"color\d+ ", line)])

            alacritty = tomllib.loads(outputs["alacritty"].read_text(encoding="utf-8"))
            self.assertEqual(alacritty["colors"]["primary"]["background"], p["base"])
            self.assertEqual(alacritty["colors"]["cursor"]["text"], p["onSignal"])
            self.assertEqual(list(alacritty["colors"]["bright"].values()), term[8:])

            ghostty = outputs["ghostty"].read_text(encoding="utf-8").splitlines()
            self.assertEqual(sum(line.startswith("palette = ") for line in ghostty), 16)
            self.assertIn(f"selection-background = {p['cueWell']}", ghostty)

            btop = dict(re.findall(r'^theme\[([^]]+)\]="([^"]*)"$',
                                   outputs["btop"].read_text(encoding="utf-8"), re.M))
            self.assertEqual(len(btop), 42)
            self.assertEqual(btop["hi_fg"], p["signal"])
            self.assertEqual(btop["selected_bg"], p["cueWell"])

            cava = configparser.ConfigParser(interpolation=None)
            cava.read(outputs["cava"], encoding="utf-8")
            self.assertEqual(cava["color"]["gradient_count"], "4")
            self.assertEqual(cava["color"]["gradient_color_3"].strip("'"), p["signal"])

    def test_qt_gtk_hypr_and_lock_use_roles_only(self) -> None:
        theme = night()
        p = theme["palette"]
        qt = sr.render_qt6ct(theme)
        for key in ("active_colors", "inactive_colors", "disabled_colors"):
            row = re.search(rf"^{key}=(.*)$", qt, re.M).group(1).split(", ")
            self.assertEqual(len(row), 22)
        active = re.search(r"^active_colors=(.*)$", qt, re.M).group(1).split(", ")
        self.assertEqual(active[sr.QT_ROLES.index("Highlight")], "#ff" + p["cue"][1:].lower())
        self.assertEqual(active[sr.QT_ROLES.index("Accent")], "#ff" + p["signal"][1:].lower())

        block = sr.gtk_palette_block(theme)
        for role in st.ROLES:
            self.assertIn(p[role], block)
        self.assertIn(f"@define-color hs_rule_strong {p['ruleStrong']};", block)
        recolor = sr.render_recolor(theme, "Hornero-Signal")
        self.assertIn(f"@define-color accent_bg_color {p['signal']};", recolor)

        hypr = sr.render_hyprland(theme)
        self.assertIn(f'active_border = "rgba({p["signal"][1:].lower()}ee)"', hypr)
        lock = sr.render_hyprlock_colors(theme)
        self.assertNotIn("{", lock)
        self.assertIn(f"$hs_ink = rgba({p['ink'][1:].lower()}ff)", lock)

    def test_live_scheme_round_trip(self) -> None:
        theme = night()
        with tempfile.TemporaryDirectory() as temporary:
            scheme = Path(temporary) / "signal/scheme.json"
            self.assertEqual(sr.main(["--theme", str(NIGHT), "--scheme-output", str(scheme)]), 0)
            doc = json.loads(scheme.read_text(encoding="utf-8"))
            self.assertEqual(doc, {"schemaVersion": 2, "id": theme["id"], "mode": "dark",
                                   "palette": theme["palette"], "terminal": theme["terminal"]})
            # The live scheme itself is valid renderer input (hyprlock refresh path).
            out = Path(temporary) / "lock.conf"
            self.assertEqual(sr.main(["--theme", str(scheme), "--hyprlock-output", str(out)]), 0)
            self.assertTrue(out.read_text(encoding="utf-8").strip())

    def test_invalid_theme_writes_no_partial_outputs(self) -> None:
        theme = night()
        broken = copy.deepcopy(theme)
        broken["palette"]["onSignal"] = broken["palette"]["signal"]
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "broken.json"
            source.write_text(json.dumps(broken), encoding="utf-8")
            kitty, alacritty = root / "kitty.conf", root / "alacritty.toml"
            rc = sr.main(["--theme", str(source), "--kitty-output", str(kitty),
                          "--alacritty-output", str(alacritty)])
            self.assertEqual(rc, 1)
            self.assertFalse(kitty.exists())
            self.assertFalse(alacritty.exists())


if __name__ == "__main__":
    unittest.main()
