#!/usr/bin/env python3
"""Unit tests for Hornero's native terminal palette renderers."""

from __future__ import annotations

import configparser
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

from terminal_themes import render_scheme, render_scheme_file  # noqa: E402


def sample_colours() -> dict[str, str]:
    colours = {
        "surface": "#1D1410",
        "surfaceContainerHighest": "#3C2C21",
        "onSurface": "#F6E9DB",
        "onSurfaceVariant": "#E9D3BC",
        "outline": "#6B4E3B",
        "outlineVariant": "#6B4E3B",
        "primary": "#E07856",
        "onPrimary": "#211310",
        "onPrimaryContainer": "#F6E9DB",
        "primaryContainer": "#3C2C21",
        "secondary": "#D9A05F",
        "secondaryContainer": "#6B4E3B",
        "tertiary": "#7FA3B8",
        "tertiaryContainer": "#3C2C21",
        "error": "#F28B82",
        "errorContainer": "#3C2C21",
        "success": "#9CC184",
        "successContainer": "#3C2C21",
    }
    colours.update(
        {
            "term0": "#2B1F18",
            "term1": "#E07856",
            "term2": "#9CC184",
            "term3": "#D9A05F",
            "term4": "#7FA3B8",
            "term5": "#C08CA6",
            "term6": "#8FB3A6",
            "term7": "#E9D3BC",
            "term8": "#6B4E3B",
            "term9": "#F28B82",
            "term10": "#BFD9AE",
            "term11": "#F2B749",
            "term12": "#A9C6DA",
            "term13": "#D8A9BE",
            "term14": "#AECDC3",
            "term15": "#F6E9DB",
        }
    )
    return colours


class TerminalThemeTests(unittest.TestCase):
    def test_renders_native_configs_from_one_scheme(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            kitty = root / "kitty/colors.conf"
            alacritty = root / "alacritty/hornero-colors.toml"
            ghostty = root / "ghostty/themes/Hornero Dynamic"
            btop = root / "btop/themes/Hornero Dynamic.theme"
            cava = root / "cava/themes/Hornero Dynamic"

            written = render_scheme(
                sample_colours(),
                kitty_output=kitty,
                alacritty_output=alacritty,
                ghostty_output=ghostty,
                btop_output=btop,
                cava_output=cava,
            )

            self.assertEqual(
                set(written),
                {str(kitty), str(alacritty), str(ghostty), str(btop), str(cava)},
            )
            kitty_text = kitty.read_text(encoding="utf-8")
            self.assertIn("background #1D1410", kitty_text)
            self.assertIn("cursor_text_color #211310", kitty_text)
            self.assertEqual(sum(line.startswith("color") for line in kitty_text.splitlines()), 16)

            alacritty_data = tomllib.loads(alacritty.read_text(encoding="utf-8"))
            self.assertEqual(alacritty_data["colors"]["primary"]["background"], "#1D1410")
            self.assertEqual(alacritty_data["colors"]["cursor"]["text"], "#211310")
            self.assertEqual(len(alacritty_data["colors"]["normal"]), 8)
            self.assertEqual(len(alacritty_data["colors"]["bright"]), 8)

            ghostty_lines = ghostty.read_text(encoding="utf-8").splitlines()
            self.assertEqual(sum(line.startswith("palette = ") for line in ghostty_lines), 16)
            self.assertIn("background = #1D1410", ghostty_lines)
            self.assertIn("foreground = #F6E9DB", ghostty_lines)
            self.assertIn("cursor-text = #211310", ghostty_lines)

            btop_text = btop.read_text(encoding="utf-8")
            btop_theme = dict(
                re.findall(r'^theme\[([^]]+)\]="([^"]*)"$', btop_text, re.MULTILINE)
            )
            self.assertEqual(btop_theme["main_fg"], "#F6E9DB")
            self.assertEqual(btop_theme["title"], "#E07856")
            self.assertEqual(len(btop_theme), 42)

            cava_parser = configparser.ConfigParser(interpolation=None)
            cava_parser.read(cava, encoding="utf-8")
            self.assertEqual(cava_parser["color"]["background"].strip("'\""), "#1D1410")
            self.assertEqual(cava_parser["color"]["gradient"], "1")
            self.assertEqual(cava_parser["color"]["gradient_count"], "4")
            self.assertEqual(cava_parser["color"]["gradient_color_4"].strip("'\""), "#D9A05F")

    def test_scheme_file_requires_colours_object(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            scheme = root / "scheme.json"
            target = root / "terminal.conf"
            scheme.write_text(json.dumps({"colours": sample_colours()}), encoding="utf-8")
            render_scheme_file(scheme, kitty_output=target)
            self.assertIn("background #1D1410", target.read_text(encoding="utf-8"))

            scheme.write_text(json.dumps({"colors": {}}), encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "colours"):
                render_scheme_file(scheme, kitty_output=target)

    def test_invalid_scheme_writes_no_partial_outputs(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            kitty = root / "kitty.conf"
            alacritty = root / "alacritty.toml"
            colours = sample_colours()
            del colours["term15"]

            with self.assertRaisesRegex(ValueError, "term15"):
                render_scheme(colours, kitty_output=kitty, alacritty_output=alacritty)

            self.assertFalse(kitty.exists())
            self.assertFalse(alacritty.exists())

    def test_low_contrast_cursor_pair_writes_no_terminal_outputs(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            kitty = root / "kitty.conf"
            alacritty = root / "alacritty.toml"
            ghostty = root / "ghostty.theme"
            colours = sample_colours()
            colours["onPrimary"] = colours["primary"]

            with self.assertRaisesRegex(ValueError, "onPrimary on primary contrast"):
                render_scheme(
                    colours,
                    kitty_output=kitty,
                    alacritty_output=alacritty,
                    ghostty_output=ghostty,
                )

            self.assertFalse(kitty.exists())
            self.assertFalse(alacritty.exists())
            self.assertFalse(ghostty.exists())


if __name__ == "__main__":
    unittest.main()
