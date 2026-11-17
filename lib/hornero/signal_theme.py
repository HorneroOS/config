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
    "colorOnly", "version", "chromatic",
)
COLLECTIONS = ("hornero-signal", "hornero-originals", "user")
# Reserved live-scheme id of the generated palette (RFC 0002): no catalogue
# directory may use it and saved palettes need their own id.
CHROMATIC_ID = "hornero-chromatic"
# Optional blocks a live scheme may add (RFC 0002 §8.1).
SCHEME_KEYS: tuple[str, ...] = (
    "schemaVersion", "id", "mode", "palette", "terminal",
    "chromatic", "minSurfaceAlpha", "clearInk",
)
ALPHA_SURFACES = ("base", "panel", "raised", "lifted", "sunken")
CLEARINK_ROLES = ("ink", "inkMuted", "signal", "alert", "halo")
REQUEST_VARIANTS = ("auto", "balanced", "vibrant", "expressive", "faithful",
                    "muted", "monochrome", "high-contrast", "neon")

# --- gate table ---------------------------------------------------------------
# One data file (profiles/themes/contrast-gates.json) owns every contrast
# threshold: this module, the shell engine and horneroctl all read the same
# bytes (RFC 0001 §2 principle 3, RFC 0002 §11). Nothing below hard-codes a
# ratio.

GATES_FILENAME = "contrast-gates.json"
LEVELS = ("standard", "boosted", "maximum")
SURFACES = ("ground", "sunken", "base", "panel", "raised", "lifted")


def gates_path() -> Path:
    """Locate the gate table: env override, repo checkout, then installs.

    ``lib/hornero`` is installed as ``~/.local/lib/hornero`` (data in
    ``~/.local/share/hornero/themes``) or ``/usr/share/hornero/lib/hornero``
    (data in ``/usr/share/hornero/themes``).
    """
    override = os.environ.get("HORNERO_CONTRAST_GATES")
    if override:
        return Path(override)
    here = Path(__file__).resolve().parent
    candidates = (
        here.parent.parent / "profiles" / "themes" / GATES_FILENAME,
        here.parent.parent / "themes" / GATES_FILENAME,
        here.parent.parent / "share" / "hornero" / "themes" / GATES_FILENAME,
        Path("/usr/share/hornero/themes") / GATES_FILENAME,
    )
    for candidate in candidates:
        if candidate.is_file():
            return candidate
    raise FileNotFoundError(f"{GATES_FILENAME} not found (looked in {', '.join(map(str, candidates))})")


_GATES_CACHE: dict[str, dict] = {}


def load_gates(path: str | Path | None = None) -> dict:
    """Parse and sanity-check the gate table (cached per path)."""
    resolved = Path(path) if path else gates_path()
    key = str(resolved)
    if key not in _GATES_CACHE:
        table = json.loads(resolved.read_text(encoding="utf-8"))
        if table.get("version") != 1:
            raise ValueError(f"{resolved}: unsupported gate table version {table.get('version')!r}")
        for level in LEVELS:
            if level not in table.get("levels", {}):
                raise ValueError(f"{resolved}: gate table lacks level {level!r}")
        _GATES_CACHE[key] = table
    return _GATES_CACHE[key]


def _merge(base: dict, override: dict) -> dict:
    merged = dict(base)
    for key, value in override.items():
        if isinstance(value, dict) and isinstance(merged.get(key), dict):
            merged[key] = _merge(merged[key], value)
        else:
            merged[key] = value
    return merged


def resolve_level(level: str = "standard", table: dict | None = None) -> dict:
    """The effective rules for a level (``inherits`` chain applied)."""
    table = table or load_gates()
    levels = table["levels"]
    if level not in levels:
        raise ValueError(f"unknown gate level {level!r}")
    chain: list[str] = []
    cursor: str | None = level
    while cursor is not None:
        if cursor in chain:
            raise ValueError(f"gate level inheritance cycle at {cursor!r}")
        chain.append(cursor)
        cursor = levels[cursor].get("inherits")
    resolved: dict = {}
    for name in reversed(chain):
        resolved = _merge(resolved, {k: v for k, v in levels[name].items() if k != "inherits"})
    return resolved


def _standard_constants() -> None:
    """Module constants kept for the generators and tests (standard level)."""
    global TEXT_MIN, BOUNDARY_MIN, TEXT_ROLES, TEXT_SURFACES, BOUNDARY_SURFACES
    global ON_PAIRS, TERM_NORMAL_MIN, TERM_BRIGHT_MIN, TERM_RGY_MIN_DE, TERM_RAMP_MIN_DE
    table = load_gates()
    std = resolve_level("standard", table)
    TEXT_MIN = float(std["text"]["min"])
    BOUNDARY_MIN = float(std["boundary"]["min"])
    TEXT_ROLES = tuple(std["text"]["roles"])
    TEXT_SURFACES = tuple(std["text"]["on"])
    BOUNDARY_SURFACES = tuple(std["boundary"]["on"])
    ON_PAIRS = tuple((a, b) for a, b in std["onPairs"]["pairs"])
    term = table["terminal"]
    TERM_NORMAL_MIN = float(term["normalMin"])
    TERM_BRIGHT_MIN = float(term["brightMin"])
    TERM_RGY_MIN_DE = float(term["rgyMinDeltaE76"])
    TERM_RAMP_MIN_DE = float(term["rampMinDeltaE76"])


_standard_constants()

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


def to_oklab(hex_color: str) -> tuple[float, float, float]:
    r, g, b = (_linear(c) for c in rgb(hex_color))
    l = (0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b) ** (1.0 / 3.0)
    m = (0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b) ** (1.0 / 3.0)
    s = (0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b) ** (1.0 / 3.0)
    return (
        0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
        1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
        0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s,
    )


def delta_e_ok(a: str, b: str) -> float:
    return math.dist(to_oklab(a), to_oklab(b))


def hue_ok(hex_color: str) -> float:
    _, a, b = to_oklab(hex_color)
    return math.degrees(math.atan2(b, a)) % 360.0


def hue_distance(a: str, b: str) -> float:
    d = abs(hue_ok(a) - hue_ok(b))
    return min(d, 360.0 - d)


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

    errors.extend(palette_errors(doc.get("palette")))
    errors.extend(terminal_shape_errors(doc.get("terminal")))
    if "chromatic" in doc:
        errors.extend(chromatic_errors(doc["chromatic"], live=False))
    return errors


def palette_errors(palette: object) -> list[str]:
    errors: list[str] = []
    if not isinstance(palette, dict):
        return ["palette must be an object"]
    missing = [r for r in ROLES if r not in palette]
    extra = [k for k in palette if k not in ROLES and k not in OPTIONAL_ROLES]
    if missing:
        errors.append(f"palette missing roles: {', '.join(missing)}")
    if extra:
        errors.append(f"palette has non-Signal keys: {', '.join(extra)}")
    for role in (*ROLES, *OPTIONAL_ROLES):
        if role in palette and not _hex_ok(palette[role]):
            errors.append(f"palette.{role} must be #RRGGBB (uppercase): {palette[role]!r}")
    return errors


def terminal_shape_errors(terminal: object) -> list[str]:
    if not isinstance(terminal, list) or len(terminal) != 16:
        return ["terminal must be an array of exactly 16 colours"]
    return [
        f"terminal[{index}] must be #RRGGBB (uppercase): {value!r}"
        for index, value in enumerate(terminal)
        if not _hex_ok(value)
    ]


_SHA_RE = re.compile(r"^sha256:[0-9a-f]{64}$")


def chromatic_errors(block: object, *, live: bool) -> list[str]:
    """Shape of the ``chromatic`` provenance object (RFC 0002 §8.1/§8.2).

    Live (scheme.json): version, engine, algorithm, fingerprint, request,
    resolved are required. Saved (theme.json): engine, algorithm, request.
    """
    if not isinstance(block, dict):
        return ["chromatic must be an object"]
    errors: list[str] = []
    required = (("version", "engine", "algorithm", "fingerprint", "request", "resolved")
                if live else ("engine", "algorithm", "request"))
    for key in required:
        if key not in block:
            errors.append(f"chromatic missing {key!r}")
    allowed = {"version", "engine", "algorithm", "fingerprint", "request", "resolved",
               "seeds", "sourceKey", "createdAt"}
    for key in block:
        if key not in allowed:
            errors.append(f"chromatic has unknown key {key!r}")
    if "engine" in block and not (isinstance(block["engine"], str) and block["engine"]):
        errors.append("chromatic.engine must be a non-empty string")
    for key in ("algorithm", "version"):
        value = block.get(key)
        if key in block and (not isinstance(value, int) or isinstance(value, bool) or value < 1):
            errors.append(f"chromatic.{key} must be an integer >= 1")
    for key in ("fingerprint", "sourceKey"):
        value = block.get(key)
        if key in block and value is not None and not (isinstance(value, str) and _SHA_RE.match(value)):
            errors.append(f"chromatic.{key} must be sha256:<64 hex> or null")
    if "request" in block and not isinstance(block["request"], dict):
        errors.append("chromatic.request must be an object")
    resolved = block.get("resolved")
    if "resolved" in block:
        if not isinstance(resolved, dict):
            errors.append("chromatic.resolved must be an object")
        else:
            if resolved.get("mode") not in ("dark", "light"):
                errors.append("chromatic.resolved.mode must be 'dark' or 'light'")
            if resolved.get("variant") not in REQUEST_VARIANTS[1:]:
                errors.append("chromatic.resolved.variant must be a concrete variant")
            if resolved.get("contrast") not in LEVELS:
                errors.append(f"chromatic.resolved.contrast must be one of {LEVELS}")
    seeds = block.get("seeds")
    if "seeds" in block and (
        not isinstance(seeds, list) or len(seeds) > 2 or not all(_hex_ok(x) for x in seeds)
    ):
        errors.append("chromatic.seeds must be at most 2 #RRGGBB colours")
    if "createdAt" in block and not isinstance(block["createdAt"], str):
        errors.append("chromatic.createdAt must be a string")
    return errors


def scheme_errors(doc: object) -> list[str]:
    """Structure of the live scheme document (profiles/themes/scheme.schema.json)."""
    if not isinstance(doc, dict):
        return ["scheme document must be a JSON object"]
    errors: list[str] = []
    for key in ("schemaVersion", "id", "mode", "palette", "terminal"):
        if key not in doc:
            errors.append(f"missing required key {key!r}")
    for key in doc:
        if key not in SCHEME_KEYS:
            errors.append(f"unknown key {key!r}")
    if doc.get("schemaVersion") != SCHEMA_VERSION:
        errors.append(f"schemaVersion must be {SCHEMA_VERSION}")
    if not isinstance(doc.get("id"), str) or not ID_RE.match(doc.get("id", "")):
        errors.append("id must be lowercase kebab-case")
    if doc.get("mode") not in ("dark", "light"):
        errors.append("mode must be 'dark' or 'light'")
    errors.extend(palette_errors(doc.get("palette")))
    errors.extend(terminal_shape_errors(doc.get("terminal")))
    if "chromatic" in doc:
        errors.extend(chromatic_errors(doc["chromatic"], live=True))
    if doc.get("id") == CHROMATIC_ID and "chromatic" not in doc:
        errors.append("hornero-chromatic scheme requires a chromatic block")
    alpha = doc.get("minSurfaceAlpha")
    if "minSurfaceAlpha" in doc:
        if not isinstance(alpha, dict):
            errors.append("minSurfaceAlpha must be an object")
        else:
            for key, value in alpha.items():
                if key not in ALPHA_SURFACES:
                    errors.append(f"minSurfaceAlpha has unknown surface {key!r}")
                elif (not isinstance(value, (int, float)) or isinstance(value, bool)
                      or not 0.5 <= value <= 1.0):
                    errors.append(f"minSurfaceAlpha.{key} must be a number in 0.5..1.0")
    ink = doc.get("clearInk")
    if "clearInk" in doc:
        if not isinstance(ink, dict) or set(ink) != {"light", "dark"}:
            errors.append("clearInk must have exactly the keys 'light' and 'dark'")
        else:
            for polarity, roles in ink.items():
                if not isinstance(roles, dict) or set(roles) != set(CLEARINK_ROLES):
                    errors.append(f"clearInk.{polarity} must carry exactly {', '.join(CLEARINK_ROLES)}")
                else:
                    errors.extend(
                        f"clearInk.{polarity}.{k} must be #RRGGBB (uppercase): {v!r}"
                        for k, v in roles.items() if not _hex_ok(v)
                    )
    return errors


def level_for(doc: dict, requested: str | None = None) -> str:
    """Gate level: explicit request, else the Chromatic resolved level, else standard."""
    if requested:
        return requested
    block = doc.get("chromatic")
    if isinstance(block, dict):
        resolved = block.get("resolved")
        if isinstance(resolved, dict) and resolved.get("contrast") in LEVELS:
            return resolved["contrast"]
    return "standard"


def contrast_report(doc: dict, level: str = "standard") -> list[tuple[str, float, float]]:
    """Every gated pair as (label, ratio, minimum). Assumes valid structure."""
    rules = resolve_level(level)
    p = doc["palette"]
    rows: list[tuple[str, float, float]] = []
    text = rules["text"]
    overrides = rules.get("textOverrides", {})
    for role in text["roles"]:
        for surface in text["on"]:
            rows.append((f"{role} on {surface}", contrast(p[role], p[surface]),
                         float(overrides.get(role, text["min"]))))
    for fg, bg in rules["onPairs"]["pairs"]:
        rows.append((f"{fg} on {bg}", contrast(p[fg], p[bg]), float(rules["onPairs"]["min"])))
    boundary = rules["boundary"]
    for role in boundary["roles"]:
        for surface in boundary["on"]:
            rows.append((f"{role} on {surface}", contrast(p[role], p[surface]), float(boundary["min"])))
    focus = rules["focus"]
    for surface in focus["on"]:
        rows.append((f"focus on {surface}", contrast(p["focus"], p[surface]), float(focus["min"])))
    return rows


def chromatic_report(doc: dict, level: str = "standard") -> list[tuple[str, float, float]]:
    """Extra Chromatic rows: focus on every surface and status separation.

    Separation rows are reported as (label, measured, minimum) for both the
    OKLab distance and the OKLCH hue distance (a pair needs both).
    """
    extra = load_gates()["chromaticExtra"]
    p = doc["palette"]
    rows: list[tuple[str, float, float]] = []
    floor = float(extra["focusOnEverySurfaceMin"])
    for surface in SURFACES:
        rows.append((f"focus on {surface} (chromatic)", contrast(p["focus"], p[surface]), floor))
    sep = extra["separation"]
    for a, b in sep["pairs"]:
        rows.append((f"{a}/{b} deltaE-OK", delta_e_ok(p[a], p[b]), float(sep["minDeltaEOK"])))
        rows.append((f"{a}/{b} hue degrees", hue_distance(p[a], p[b]), float(sep["minHueDeg"])))
    return rows


def terminal_errors(doc: dict) -> list[str]:
    p, term = doc["palette"], doc["terminal"]
    bg = p["base"]
    errors: list[str] = []
    if contrast(p["ink"], bg) < TERM_NORMAL_MIN:
        errors.append(f"terminal foreground (ink) below {TERM_NORMAL_MIN}:1 on base")
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


def gate_errors(doc: dict, level: str | None = None) -> list[str]:
    """Contrast, terminal and (for Chromatic documents) separation errors."""
    name = level_for(doc, level)
    errors: list[str] = []
    rows = contrast_report(doc, name)
    if "chromatic" in doc:
        rows += chromatic_report(doc, name)
    for label, ratio, minimum in rows:
        if ratio < minimum:
            unit = "" if ("deltaE" in label or "hue" in label) else ":1"
            errors.append(f"{label} = {ratio:.2f}{unit}, below {minimum:.2f}{unit}")
    errors.extend(terminal_errors(doc))
    return errors


def validate(doc: object, level: str | None = None) -> list[str]:
    """Theme document (theme.json): structure, then gates at ``level``."""
    errors = structural_errors(doc)
    if errors:
        return errors
    assert isinstance(doc, dict)
    return gate_errors(doc, level)


def validate_scheme(doc: object, level: str | None = None) -> list[str]:
    """Live scheme document (scheme.json): structure, then gates."""
    errors = scheme_errors(doc)
    if errors:
        return errors
    assert isinstance(doc, dict)
    return gate_errors(doc, level)


# --- exports ------------------------------------------------------------------

def _live_extras(doc: dict) -> dict:
    """Optional live blocks. A saved theme's ``chromatic`` is provenance, not
    live state: only a live-shaped block (it carries a fingerprint) passes."""
    block = doc.get("chromatic")
    if not (isinstance(block, dict) and "fingerprint" in block):
        return {}
    return {key: doc[key] for key in ("chromatic", "minSurfaceAlpha", "clearInk") if key in doc}


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
        **_live_extras(doc),
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
    v.add_argument("--scheme", action="store_true",
                   help="inputs are live scheme documents (scheme.json), not theme packs")
    v.add_argument("--level", choices=LEVELS,
                   help="gate level (default: the document's resolved Chromatic level, else standard)")
    s = sub.add_parser("scheme", help="write the live scheme for one theme")
    s.add_argument("theme")
    s.add_argument("--output", help="default: $XDG_STATE_HOME/hornero/signal/scheme.json")
    args = parser.parse_args(argv)

    if args.command == "validate":
        failed = 0
        for path in args.themes:
            try:
                check = validate_scheme if args.scheme else validate
                errors = check(load(path), args.level)
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
