#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""check-contrast.py - fail when any theme text-on-surface pair misses WCAG AA.

Walks profiles/themes/*/theme.json. Every theme carrying the versioned
semantic token model (palette + components) has each component
{background, foreground} pair measured against WCAG 2.x relative-luminance
contrast; WCAG AA for normal text requires >= 4.5:1, which is the gate for
every pair (large-text 3:1 is subsumed). Legacy recipe-only packs without
palette/components are reported and skipped. Any violation exits nonzero
so CI fails. Standard library only (no third-party code).
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

MIN_RATIO = 4.5
HEX_RE = re.compile(r"^#[0-9a-fA-F]{6}$")

# Core text pairs every token theme must keep AA-clean, as
# (label, background-key, foreground-key) into palette.
CORE_PAIRS = (
    ("body", "background", "text"),
    ("surface", "surface", "text"),
    ("surface-variant", "surfaceVariant", "onSurfaceVariant"),
    ("primary", "primary", "onPrimary"),
    ("secondary", "secondary", "onSecondary"),
    ("accent", "accent", "onAccent"),
)


def srgb_to_linear(channel: int) -> float:
    c = channel / 255.0
    if c <= 0.03928:
        return c / 12.92
    return ((c + 0.055) / 1.055) ** 2.4


def luminance(hex_color: str) -> float:
    hex_color = hex_color.lstrip("#")
    r, g, b = (int(hex_color[i : i + 2], 16) for i in (0, 2, 4))
    return (
        0.2126 * srgb_to_linear(r)
        + 0.7152 * srgb_to_linear(g)
        + 0.0722 * srgb_to_linear(b)
    )


def contrast_ratio(bg: str, fg: str) -> float:
    lighter = max(luminance(bg), luminance(fg))
    darker = min(luminance(bg), luminance(fg))
    return (lighter + 0.05) / (darker + 0.05)


def check_theme(path: Path, min_ratio: float) -> list[str]:
    errors: list[str] = []
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        return [f"{path}: invalid JSON: {exc}"]

    theme_id = data.get("id", path.parent.name)
    palette = data.get("palette")
    components = data.get("components")
    if palette is None or components is None:
        print(f"CONTRAST-SKIP: {theme_id} (recipe-only pack, no token model)")
        return []

    def check_pair(label: str, bg: str, fg: str) -> None:
        for value, role in ((bg, "background"), (fg, "foreground")):
            if not isinstance(value, str) or not HEX_RE.match(value):
                errors.append(
                    f"{theme_id}:{label}: {role} is not #RRGGBB: {value!r}"
                )
                return
        ratio = contrast_ratio(bg, fg)
        status = "PASS" if ratio >= min_ratio else "FAIL"
        print(
            f"CONTRAST-{status}: {theme_id}:{label} "
            f"{fg} on {bg} = {ratio:.2f}:1 (min {min_ratio:.1f}:1)"
        )
        if ratio < min_ratio:
            errors.append(
                f"{theme_id}:{label}: {ratio:.2f}:1 below WCAG AA {min_ratio:.1f}:1"
            )

    for label, bg_key, fg_key in CORE_PAIRS:
        if bg_key not in palette or fg_key not in palette:
            errors.append(f"{theme_id}: palette missing {bg_key}/{fg_key}")
            continue
        check_pair(f"palette/{label}", palette[bg_key], palette[fg_key])

    if not isinstance(components, dict) or not components:
        errors.append(f"{theme_id}: components must be a non-empty object")
        return errors
    for name, pair in sorted(components.items()):
        if not isinstance(pair, dict):
            errors.append(f"{theme_id}:components/{name}: not an object")
            continue
        if "background" not in pair or "foreground" not in pair:
            errors.append(
                f"{theme_id}:components/{name}: missing background/foreground"
            )
            continue
        check_pair(f"components/{name}", pair["background"], pair["foreground"])

    # Every palette hex value must be well-formed, even decorative ones.
    for key, value in sorted(palette.items()):
        if not isinstance(value, str) or not HEX_RE.match(value):
            errors.append(f"{theme_id}:palette/{key}: not #RRGGBB: {value!r}")

    return errors


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(
        description="Fail when any theme text pair misses WCAG AA."
    )
    parser.add_argument(
        "--themes-dir",
        default=str(
            Path(__file__).resolve().parent.parent
            / "profiles"
            / "themes"
        ),
        help="Directory containing per-theme subdirectories.",
    )
    parser.add_argument(
        "--min-ratio",
        type=float,
        default=MIN_RATIO,
        help="Minimum contrast ratio (WCAG AA normal text = 4.5).",
    )
    parser.add_argument(
        "--require-token-themes",
        default="hornero-dark,hornero-light",
        help="Comma-separated theme ids that must carry the token model.",
    )
    args = parser.parse_args(argv)

    themes_dir = Path(args.themes_dir)
    errors: list[str] = []
    token_ids: set[str] = set()

    for theme_file in sorted(themes_dir.glob("*/theme.json")):
        try:
            data = json.loads(theme_file.read_text(encoding="utf-8"))
        except Exception as exc:
            errors.append(f"{theme_file}: invalid JSON: {exc}")
            continue
        if data.get("palette") is not None and data.get("components") is not None:
            token_ids.add(theme_file.parent.name)
        errors.extend(check_theme(theme_file, args.min_ratio))

    for required in (
        name.strip()
        for name in args.require_token_themes.split(",")
        if name.strip()
    ):
        if required not in token_ids:
            errors.append(
                f"required flagship token theme missing or model-less: {required}"
            )

    if errors:
        print("check-contrast.py: FAIL", file=sys.stderr)
        for error in errors:
            print(f"  - {error}", file=sys.stderr)
        return 1
    print("check-contrast.py: ALL GREEN (WCAG AA >= 4.5:1)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
