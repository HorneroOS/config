#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Hornero Signal theme model (schema v2): load, validate, export.

One module owns the theme contract (RFC 0001 §3.1) so the repository
generators, the CI gates and the runtime apply pipeline can never
disagree about role names or contrast rules. Standard library only.

    python3 signal_theme.py validate <theme.json>...
    python3 signal_theme.py scheme <theme.json> [--output PATH]

`scheme` writes the live scheme document the shell watches
(``$XDG_STATE_HOME/hornero/signal/scheme.json``) atomically.
"""

from __future__ import annotations

import json
import math
import os
import re
import sys
import tempfile
from pathlib import Path

SCHEMA_VERSION = 2

# RFC 0001 §3.1 colour roles, in contract order. A theme palette carries
# these keys plus the optional ones below: no Material leftovers, no gaps.
ROLES: tuple[str, ...] = (
    "ground", "sunken", "base", "panel", "raised", "lifted",
    "ink", "inkMuted", "inkFaint",
    "rule", "ruleStrong",
    "signal", "onSignal", "signalWell", "onSignalWell",
    "cue", "onCue", "cueWell", "onCueWell",
    "phosphor", "onPhosphor", "phosphorWell", "onPhosphorWell",
    "alert", "onAlert", "alertWell", "onAlertWell",
    "inverse", "onInverse", "inverseSignal",
    "scrim", "shadow", "focus",
)
# Optional roles (RFC 0001 amendment 2). Consumers resolve an absent role to
# its fallback: `glow` (live-signal emphasis, e.g. the registration tick
# halo) defaults to `signal`.
OPTIONAL_ROLES: dict[str, str] = {"glow": "signal"}

REQUIRED_KEYS: tuple[str, ...] = (
    "schemaVersion", "id", "name", "mode", "palette", "terminal",
    "gtkTheme", "iconTheme", "defaultWallpaper", "wallpaperDir",
)
OPTIONAL_KEYS: tuple[str, ...] = (
    "$schema", "description", "tags", "collection", "collectionOrder",
    "colorOnly", "version",
)
COLLECTIONS = ("hornero-signal", "hornero-originals")

# WCAG 2.x gates (RFC 0001 §2 principle 3).
TEXT_MIN = 4.5
BOUNDARY_MIN = 3.0
TEXT_ROLES = ("ink", "inkMuted", "signal", "cue", "phosphor", "alert")
TEXT_SURFACES = ("sunken", "base", "panel", "raised")
BOUNDARY_SURFACES = ("base", "panel", "lifted")
ON_PAIRS: tuple[tuple[str, str], ...] = (
    ("onSignal", "signal"), ("onSignalWell", "signalWell"),
    ("onCue", "cue"), ("onCueWell", "cueWell"),
    ("onPhosphor", "phosphor"), ("onPhosphorWell", "phosphorWell"),
    ("onAlert", "alert"), ("onAlertWell", "alertWell"),
    ("onInverse", "inverse"), ("inverseSignal", "inverse"),
)

# Terminal palette gate (normals AA, brights large-text floor, separable
# red/green/yellow, visible normal->bright step). The black/white axis
# (0, 7, 8, 15) carries shade structure, not readable hues.
TERM_NORMAL_MIN = 4.5
TERM_BRIGHT_MIN = 3.0
TERM_RGY_MIN_DE = 10.0
TERM_RAMP_MIN_DE = 6.0

HEX_RE = re.compile(r"^#[0-9A-F]{6}$")
ID_RE = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
SEMVER_RE = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+$")


# --- colour maths -------------------------------------------------------------

def rgb(hex_color: str) -> tuple[int, int, int]:
    h = hex_color.lstrip("#")
    return int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)


def _linear(channel: int) -> float:
    c = channel / 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def luminance(hex_color: str) -> float:
    r, g, b = rgb(hex_color)
    return 0.2126 * _linear(r) + 0.7152 * _linear(g) + 0.0722 * _linear(b)


def contrast(a: str, b: str) -> float:
    lo, hi = sorted((luminance(a), luminance(b)))
    return (hi + 0.05) / (lo + 0.05)


def to_lab(hex_color: str) -> tuple[float, float, float]:
    r, g, b = (_linear(c) for c in rgb(hex_color))
    x = (r * 0.4124 + g * 0.3576 + b * 0.1805) / 0.95047
    y = r * 0.2126 + g * 0.7152 + b * 0.0722
    z = (r * 0.0193 + g * 0.1192 + b * 0.9505) / 1.08883

    def f(t: float) -> float:
        return t ** (1.0 / 3.0) if t > 0.008856 else 7.787 * t + 16.0 / 116.0

    fx, fy, fz = f(x), f(y), f(z)
    return 116.0 * fy - 16.0, 500.0 * (fx - fy), 200.0 * (fy - fz)


def delta_e(a: str, b: str) -> float:
    return math.dist(to_lab(a), to_lab(b))


def mix(a: str, b: str, amount: float) -> str:
    """Blend ``b`` into ``a`` by ``amount`` (0 = a, 1 = b) in sRGB."""
    ra, rb = rgb(a), rgb(b)
    return "#" + "".join(
        f"{round(x + (y - x) * amount):02X}" for x, y in zip(ra, rb)
    )


# --- loading and validation ---------------------------------------------------

def load(path: str | Path) -> dict:
    return json.loads(Path(path).read_text(encoding="utf-8"))


def _hex_ok(value: object) -> bool:
    return isinstance(value, str) and bool(HEX_RE.match(value))


def structural_errors(doc: object) -> list[str]:
    """Schema-v2 shape checks (mirrors profiles/themes/tokens.schema.json)."""
    if not isinstance(doc, dict):
        return ["theme document must be a JSON object"]
    errors: list[str] = []
    for key in REQUIRED_KEYS:
        if key not in doc:
            errors.append(f"missing required key {key!r}")
    allowed = set(REQUIRED_KEYS) | set(OPTIONAL_KEYS)
    for key in doc:
        if key not in allowed:
            errors.append(f"unknown key {key!r} (schema v2 forbids it)")
    if doc.get("schemaVersion") != SCHEMA_VERSION:
        errors.append(f"schemaVersion must be {SCHEMA_VERSION}")
    if not isinstance(doc.get("id"), str) or not ID_RE.match(doc.get("id", "")):
        errors.append("id must be lowercase kebab-case")
    for key in ("name", "gtkTheme", "iconTheme", "defaultWallpaper", "wallpaperDir"):
        if key in doc and (not isinstance(doc[key], str) or not doc[key].strip()):
            errors.append(f"{key} must be a non-empty string")
    if doc.get("mode") not in ("dark", "light"):
        errors.append("mode must be 'dark' or 'light'")
    if "description" in doc and not isinstance(doc["description"], str):
        errors.append("description must be a string")
    if "tags" in doc and (
        not isinstance(doc["tags"], list)
        or not all(isinstance(t, str) and t for t in doc["tags"])
    ):
        errors.append("tags must be a list of non-empty strings")
    if "collection" in doc and doc["collection"] not in COLLECTIONS:
        errors.append(f"collection must be one of {COLLECTIONS}")
    if "collectionOrder" in doc and (
        not isinstance(doc["collectionOrder"], int)
        or isinstance(doc["collectionOrder"], bool)
        or doc["collectionOrder"] < 1
    ):
        errors.append("collectionOrder must be an integer >= 1")
    if "colorOnly" in doc and not isinstance(doc["colorOnly"], bool):
        errors.append("colorOnly must be a boolean")
    if "version" in doc and (
        not isinstance(doc["version"], str) or not SEMVER_RE.match(doc["version"])
    ):
        errors.append("version must be MAJOR.MINOR.PATCH")

    palette = doc.get("palette")
    if not isinstance(palette, dict):
        errors.append("palette must be an object")
    else:
        missing = [r for r in ROLES if r not in palette]
        extra = [k for k in palette if k not in ROLES and k not in OPTIONAL_ROLES]
        if missing:
            errors.append(f"palette missing roles: {', '.join(missing)}")
        if extra:
            errors.append(f"palette has non-Signal keys: {', '.join(extra)}")
        for role in (*ROLES, *OPTIONAL_ROLES):
            if role in palette and not _hex_ok(palette[role]):
                errors.append(f"palette.{role} must be #RRGGBB (uppercase): {palette[role]!r}")

    terminal = doc.get("terminal")
    if not isinstance(terminal, list) or len(terminal) != 16:
        errors.append("terminal must be an array of exactly 16 colours")
    else:
        for index, value in enumerate(terminal):
            if not _hex_ok(value):
                errors.append(f"terminal[{index}] must be #RRGGBB (uppercase): {value!r}")
    return errors


def contrast_report(doc: dict) -> list[tuple[str, float, float]]:
    """Every gated pair as (label, ratio, minimum). Assumes valid structure."""
    p = doc["palette"]
    rows: list[tuple[str, float, float]] = []
    for role in TEXT_ROLES:
        for surface in TEXT_SURFACES:
            rows.append((f"{role} on {surface}", contrast(p[role], p[surface]), TEXT_MIN))
    for fg, bg in ON_PAIRS:
        rows.append((f"{fg} on {bg}", contrast(p[fg], p[bg]), TEXT_MIN))
    for surface in BOUNDARY_SURFACES:
        rows.append((f"ruleStrong on {surface}", contrast(p["ruleStrong"], p[surface]), BOUNDARY_MIN))
    rows.append(("focus on base", contrast(p["focus"], p["base"]), BOUNDARY_MIN))
    return rows


def terminal_errors(doc: dict) -> list[str]:
    p, term = doc["palette"], doc["terminal"]
    bg = p["base"]
    errors: list[str] = []
    if contrast(p["ink"], bg) < TERM_NORMAL_MIN:
        errors.append("terminal foreground (ink) below 4.5:1 on base")
    for index in range(1, 7):
        ratio = contrast(term[index], bg)
        if ratio < TERM_NORMAL_MIN:
            errors.append(f"terminal[{index}] {ratio:.2f}:1 on base, below {TERM_NORMAL_MIN}:1")
    for index in range(9, 15):
        ratio = contrast(term[index], bg)
        if ratio < TERM_BRIGHT_MIN:
            errors.append(f"terminal[{index}] {ratio:.2f}:1 on base, below {TERM_BRIGHT_MIN}:1")
    for start in (1, 9):
        r, g, y = term[start], term[start + 1], term[start + 2]
        for a, b, label in ((r, g, "red/green"), (r, y, "red/yellow"), (g, y, "green/yellow")):
            if delta_e(a, b) < TERM_RGY_MIN_DE:
                errors.append(f"terminal {label} (from {start}) dE {delta_e(a, b):.1f} < {TERM_RGY_MIN_DE}")
    for index in range(1, 7):
        if delta_e(term[index], term[index + 8]) < TERM_RAMP_MIN_DE:
            errors.append(
                f"terminal[{index}] vs [{index + 8}] dE {delta_e(term[index], term[index + 8]):.1f}"
                f" < {TERM_RAMP_MIN_DE} (bright step invisible)"
            )
    return errors


def validate(doc: object) -> list[str]:
    errors = structural_errors(doc)
    if errors:
        return errors
    assert isinstance(doc, dict)
    for label, ratio, minimum in contrast_report(doc):
        if ratio < minimum:
            errors.append(f"{label} = {ratio:.2f}:1, below {minimum:.1f}:1")
    errors.extend(terminal_errors(doc))
    return errors


# --- exports ------------------------------------------------------------------

def live_scheme(doc: dict) -> dict:
    """The shell-facing live scheme document (mission #28 contract)."""
    return {
        "schemaVersion": SCHEMA_VERSION,
        "id": doc["id"],
        "mode": doc["mode"],
        "palette": {
            role: doc["palette"][role]
            for role in (*ROLES, *OPTIONAL_ROLES)
            if role in doc["palette"]
        },
        "terminal": list(doc["terminal"]),
    }


def atomic_write(path: str | Path, contents: str) -> None:
    destination = Path(path).expanduser()
    destination.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=f".{destination.name}.", dir=destination.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as output:
            output.write(contents)
            output.flush()
            os.fsync(output.fileno())
        os.chmod(temporary, 0o644)
        os.replace(temporary, destination)
    except BaseException:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass
        raise


def default_scheme_path() -> Path:
    state = os.environ.get("XDG_STATE_HOME") or str(Path.home() / ".local" / "state")
    return Path(state) / "hornero" / "signal" / "scheme.json"


def main(argv: list[str]) -> int:
    import argparse

    parser = argparse.ArgumentParser(description="Hornero Signal theme model (schema v2)")
    sub = parser.add_subparsers(dest="command", required=True)
    v = sub.add_parser("validate", help="validate theme.json files (structure + WCAG)")
    v.add_argument("themes", nargs="+")
    s = sub.add_parser("scheme", help="write the live scheme for one theme")
    s.add_argument("theme")
    s.add_argument("--output", help="default: $XDG_STATE_HOME/hornero/signal/scheme.json")
    args = parser.parse_args(argv)

    if args.command == "validate":
        failed = 0
        for path in args.themes:
            try:
                errors = validate(load(path))
            except (OSError, json.JSONDecodeError) as exc:
                errors = [str(exc)]
            for error in errors:
                print(f"SIGNAL-FAIL: {path}: {error}", file=sys.stderr)
            failed += bool(errors)
        return 1 if failed else 0

    doc = load(args.theme)
    errors = validate(doc)
    if errors:
        for error in errors:
            print(f"SIGNAL-FAIL: {args.theme}: {error}", file=sys.stderr)
        return 1
    out = Path(args.output) if args.output else default_scheme_path()
    atomic_write(out, json.dumps(live_scheme(doc), indent=2) + "\n")
    print(f"wrote {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
