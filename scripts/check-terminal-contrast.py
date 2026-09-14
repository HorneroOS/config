#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""check-terminal-contrast.py - gate Kitty palettes on terminal readability.

Reads desktop/kitty/hornero-dark.conf and hornero-light.conf. For each
palette:

1. Readability: foreground + normal colors 1-6 and bright colors 9-14 must
   meet WCAG contrast against the background. Normals (body text weight)
   need >= 4.5:1; brights (bold/accent weight, WCAG large-text floor) need
   >= 3.0:1. The black/white axis (0, 7, 8, 15) is exempt: it carries shade
   structure, not readable hues (bright-black is dim text by convention;
   color7 on a light background is a fill, not a foreground).
2. Distinguishability: red/green/yellow must stay mutually separable for
   color-coded semantics (errors/warnings/success) at CIE76 dE >= 10,
   checked for both the normal (1/2/3) and bright (9/10/11) ramps.
3. Ramp separation: each normal/bright pair (N vs N+8) must differ at
   CIE76 dE >= 6 so the bright step reads as a distinct weight.

Any violation exits nonzero so CI fails. Standard library only.
"""
from __future__ import annotations

import argparse
import math
import re
import sys
from pathlib import Path

HEX_RE = re.compile(r"^#[0-9a-fA-F]{6}$")
KV_RE = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)\s+(.+?)\s*$")

MIN_NORMAL = 4.5
MIN_BRIGHT = 3.0
MIN_RGY_SEPARATION = 10.0
MIN_RAMP_STEP = 6.0
# Black/white axis: shade structure, exempt from the readability gate.
EXEMPT = {"color0", "color7", "color8", "color15"}


def srgb_to_linear(channel: int) -> float:
    c = channel / 255.0
    if c <= 0.03928:
        return c / 12.92
    return ((c + 0.055) / 1.055) ** 2.4


def luminance(hex_color: str) -> float:
    h = hex_color.lstrip("#")
    r, g, b = (int(h[i : i + 2], 16) for i in (0, 2, 4))
    return (
        0.2126 * srgb_to_linear(r)
        + 0.7152 * srgb_to_linear(g)
        + 0.0722 * srgb_to_linear(b)
    )


def contrast(a: str, b: str) -> float:
    lo, hi = sorted([luminance(a), luminance(b)])
    return (hi + 0.05) / (lo + 0.05)


def to_lab(hex_color: str) -> tuple[float, float, float]:
    h = hex_color.lstrip("#")
    r, g, b = (int(h[i : i + 2], 16) / 255.0 for i in (0, 2, 4))

    def f(c: float) -> float:
        return ((c + 0.055) / 1.055) ** 2.4 if c > 0.04045 else c / 12.92

    r, g, b = f(r), f(g), f(b)
    x = (r * 0.4124 + g * 0.3576 + b * 0.1805) / 0.95047
    y = r * 0.2126 + g * 0.7152 + b * 0.0722
    z = (r * 0.0193 + g * 0.1192 + b * 0.9505) / 1.08883

    def t(c: float) -> float:
        return c ** (1.0 / 3.0) if c > 0.008856 else 7.787 * c + 16.0 / 116.0

    fx, fy, fz = t(x), t(y), t(z)
    return (116.0 * fy - 16.0, 500.0 * (fx - fy), 200.0 * (fy - fz))


def delta_e(a: str, b: str) -> float:
    la, lb = to_lab(a), to_lab(b)
    return math.sqrt(sum((x - y) ** 2 for x, y in zip(la, lb)))


def parse_kitty(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        s = line.strip()
        if not s or s.startswith("#"):
            continue
        m = KV_RE.match(s)
        if not m:
            raise ValueError(f"{path}: unparseable line: {s[:60]}")
        values[m.group(1)] = m.group(2)
    return values


def check_palette(name: str, values: dict[str, str]) -> list[str]:
    errors: list[str] = []
    required = (
        ["foreground", "background"]
        + [f"color{i}" for i in range(16)]
        + [
            "cursor",
            "cursor_text_color",
            "selection_foreground",
            "selection_background",
            "url_color",
            "active_tab_foreground",
            "active_tab_background",
            "inactive_tab_foreground",
            "inactive_tab_background",
        ]
    )
    for key in required:
        if key not in values:
            errors.append(f"{name}: missing key {key}")
    for key, val in values.items():
        if key.startswith("color") or key in (
            "foreground",
            "background",
            "cursor",
            "cursor_text_color",
            "selection_foreground",
            "selection_background",
            "url_color",
            "active_tab_foreground",
            "active_tab_background",
            "inactive_tab_foreground",
            "inactive_tab_background",
        ):
            if not HEX_RE.match(val):
                errors.append(f"{name}: {key} is not #RRGGBB: {val}")
    if errors:
        return errors

    bg = values["background"]
    for key in ["foreground"] + [f"color{i}" for i in range(1, 7)]:
        r = contrast(values[key], bg)
        if r < MIN_NORMAL:
            errors.append(
                f"{name}: {key} {values[key]} contrast {r:.2f} < {MIN_NORMAL}"
            )
    for i in range(9, 15):
        key = f"color{i}"
        r = contrast(values[key], bg)
        if r < MIN_BRIGHT:
            errors.append(
                f"{name}: {key} {values[key]} contrast {r:.2f} < {MIN_BRIGHT}"
            )
    for ramp in (("color1", "color2", "color3"), ("color9", "color10", "color11")):
        for a, b in ((ramp[0], ramp[1]), (ramp[0], ramp[2]), (ramp[1], ramp[2])):
            d = delta_e(values[a], values[b])
            if d < MIN_RGY_SEPARATION:
                errors.append(
                    f"{name}: {a}/{b} too close (dE {d:.1f} < {MIN_RGY_SEPARATION})"
                )
    for n in range(8):
        a, b = f"color{n}", f"color{n + 8}"
        d = delta_e(values[a], values[b])
        if d < MIN_RAMP_STEP:
            errors.append(
                f"{name}: ramp {a}/{b} indistinct (dE {d:.1f} < {MIN_RAMP_STEP})"
            )
    return errors


def main() -> int:
    ap = argparse.ArgumentParser(description="Gate Kitty palettes on readability.")
    ap.add_argument("--kitty-dir", required=True, help="desktop/kitty directory")
    ap.add_argument(
        "--palettes",
        nargs="+",
        default=["hornero-dark", "hornero-light"],
        help="Palette basenames (without .conf)",
    )
    args = ap.parse_args()
    kitty_dir = Path(args.kitty_dir)
    errors: list[str] = []
    for palette in args.palettes:
        path = kitty_dir / f"{palette}.conf"
        if not path.is_file():
            errors.append(f"missing palette file: {path}")
            continue
        try:
            values = parse_kitty(path)
        except ValueError as e:
            errors.append(str(e))
            continue
        errors.extend(check_palette(palette, values))
    if errors:
        print("TERMINAL-CONTRAST-FAIL:", file=sys.stderr)
        for e in errors:
            print(f"  - {e}", file=sys.stderr)
        return 1
    print(f"terminal contrast OK ({', '.join(args.palettes)})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
