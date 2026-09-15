#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""generate-qt-schemes.py - derive qt6ct color schemes from canonical theme tokens.

Reads profiles/themes/<id>/theme.json for the official trio
(hornero-dark, hornero-light, pampa) and writes
desktop/qt6ct/colors/<id>.conf: a qt6ct [ColorScheme] section with
active/inactive/disabled lists of 22 #AARRGGBB entries in exact
QPalette::ColorRole order (WindowText..Accent), as consumed by
Qt6CT::loadColorScheme() with QT_QPA_PLATFORMTHEME=qt6ct.

Role mapping is intentional, not positional: surfaces/text/selection
come from the theme palette/components (window body, input, card,
tooltip, primary/onPrimary), 3D bevel roles derive deterministically
from Button, and PlaceholderText follows the upstream 50%-alpha
convention. Inactive mirrors active (Qt dims nothing by itself;
invented shifts risk muddy UIs). Disabled dims text roles toward
Window and keeps surfaces/selection, mirroring upstream schemes.

A WCAG gate (Highlight vs HighlightedText >= 4.5:1) fails the run
instead of shipping invisible selected text.

Standard library only. Deterministic output: regenerate must diff
clean (drift-tested).
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
THEMES_DIR = REPO_ROOT / "profiles" / "themes"
OUT_DIR = REPO_ROOT / "desktop" / "qt6ct" / "colors"

THEMES = ("hornero-dark", "hornero-light", "pampa")

# QPalette::ColorRole order (Qt6): index == enum value, 22 roles.
ROLES = (
    "WindowText", "Button", "Light", "Midlight", "Dark", "Mid",
    "Text", "BrightText", "ButtonText", "Base", "Window", "Shadow",
    "Highlight", "HighlightedText", "Link", "LinkVisited",
    "AlternateBase", "NoRole", "ToolTipBase", "ToolTipText",
    "PlaceholderText", "Accent",
)
assert len(ROLES) == 22


def parse_hex(s: str) -> tuple[int, int, int]:
    s = s.strip().lstrip("#")
    if len(s) == 3:
        s = "".join(c * 2 for c in s)
    if len(s) != 6:
        raise ValueError(f"bad hex color: {s!r}")
    return int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16)


def fmt(rgb: tuple[int, int, int], alpha: int = 0xFF) -> str:
    r, g, b = (max(0, min(255, round(v))) for v in rgb)
    return f"#{alpha:02x}{r:02x}{g:02x}{b:02x}"


def mix(a: tuple[int, int, int], b: tuple[int, int, int], t: float):
    return tuple(x + (y - x) * t for x, y in zip(a, b))


def lighten(c: tuple[int, int, int], t: float):
    return mix(c, (255, 255, 255), t)


def darken(c: tuple[int, int, int], t: float):
    return mix(c, (0, 0, 0), t)


def luminance(rgb: tuple[int, int, int]) -> float:
    def lin(v: float) -> float:
        v /= 255.0
        return v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4

    r, g, b = (lin(v) for v in rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(a: tuple[int, int, int], b: tuple[int, int, int]) -> float:
    la, lb = luminance(a), luminance(b)
    hi, lo = (la, lb) if la >= lb else (lb, la)
    return (hi + 0.05) / (lo + 0.05)


def build_scheme(theme: dict) -> dict[str, list[str]]:
    pal = theme["palette"]
    comp = theme["components"]
    dark = theme.get("mode", "dark") == "dark"

    text = parse_hex(comp["window"]["foreground"])
    window = parse_hex(comp["window"]["background"])
    button = parse_hex(pal["surfaceVariant"])
    button_text = parse_hex(comp["window"]["foreground"])
    base = parse_hex(comp["input"]["background"])
    input_text = parse_hex(comp["input"]["foreground"])
    highlight = parse_hex(pal["primary"])
    highlighted_text = parse_hex(pal["onPrimary"])
    link = parse_hex(pal["accent"])
    link_visited = parse_hex(pal["secondary"])
    alternate = parse_hex(comp["card"]["background"])
    tip_base = parse_hex(comp["tooltip"]["background"])
    tip_text = parse_hex(comp["tooltip"]["foreground"])
    placeholder = parse_hex(pal["textMuted"])
    bright = (255, 255, 255) if dark else (0, 0, 0)

    ratio = contrast(highlight, highlighted_text)
    if ratio < 4.5:
        raise SystemExit(
            f"FAIL: {theme['id']}: Highlight/HighlightedText contrast "
            f"{ratio:.2f}:1 < 4.5:1 (invisible selected text)"
        )

    active = {
        "WindowText": text,
        "Button": button,
        "Light": lighten(button, 0.30),
        "Midlight": lighten(button, 0.15),
        "Dark": darken(button, 0.30),
        "Mid": mix(button, button_text, 0.40),
        "Text": input_text,
        "BrightText": bright,
        "ButtonText": button_text,
        "Base": base,
        "Window": window,
        "Shadow": darken(button, 0.55),
        "Highlight": highlight,
        "HighlightedText": highlighted_text,
        "Link": link,
        "LinkVisited": link_visited,
        "AlternateBase": alternate,
        "NoRole": (0, 0, 0),
        "ToolTipBase": tip_base,
        "ToolTipText": tip_text,
        "PlaceholderText": placeholder,
        "Accent": highlight,
    }

    active_list = [fmt(active[r]) for r in ROLES]
    # PlaceholderText follows the upstream 50%-alpha convention.
    active_list[ROLES.index("PlaceholderText")] = fmt(placeholder, 0x80)

    text_roles = {
        "WindowText", "Text", "BrightText", "ButtonText",
        "HighlightedText", "PlaceholderText",
    }
    disabled = {}
    for r in ROLES:
        if r in text_roles:
            disabled[r] = mix(active[r], window, 0.55)
        else:
            disabled[r] = active[r]
    disabled_list = [fmt(disabled[r]) for r in ROLES]
    disabled_list[ROLES.index("PlaceholderText")] = fmt(
        mix(placeholder, window, 0.55), 0x80)

    inactive_list = list(active_list)

    return {
        "active_colors": active_list,
        "inactive_colors": inactive_list,
        "disabled_colors": disabled_list,
    }


def render(theme_id: str, scheme: dict[str, list[str]]) -> str:
    lines = [
        "; qt6ct color scheme — GENERATED, do not hand-edit.",
        f"; Source: profiles/themes/{theme_id}/theme.json via",
        ";   scripts/generate-qt-schemes.py (regenerate must diff clean).",
        "; Roles follow QPalette::ColorRole order; see the generator",
        "; header for the token mapping.",
        "[ColorScheme]",
    ]
    for key in ("active_colors", "inactive_colors", "disabled_colors"):
        values = scheme[key]
        assert len(values) == 22, (theme_id, key, len(values))
        lines.append(f"{key}=" + ", ".join(values))
    return "\n".join(lines) + "\n"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=str(OUT_DIR),
                    help="output dir for <theme>.conf files")
    args = ap.parse_args()
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    for theme_id in THEMES:
        theme = json.loads((THEMES_DIR / theme_id / "theme.json").read_text())
        (out / f"{theme_id}.conf").write_text(
            render(theme_id, build_scheme(theme)))
        print(f"wrote {theme_id}.conf")
    return 0


if __name__ == "__main__":
    sys.exit(main())
