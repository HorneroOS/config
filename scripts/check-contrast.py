#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""check-contrast.py - gate every shipped theme on schema v2 + WCAG.

Walks profiles/themes/*/theme.json and validates each with
lib/hornero/signal_theme.py (the same module the generators and the apply
pipeline use):

- structure: schemaVersion 2, every RFC 0001 §3.1 role present and nothing
  else in `palette`, uppercase #RRGGBB hex, 16-colour `terminal`, metadata;
- text: ink/inkMuted/signal/cue/phosphor/alert >= 4.5:1 on sunken, base,
  panel and raised; every on*-pair (and inverseSignal on inverse) >= 4.5:1;
- boundaries: ruleStrong >= 3:1 on base, panel and lifted, focus >= 3:1 on base;
- terminal: normals 1-6 >= 4.5:1 and brights 9-14 >= 3:1 on base,
  red/green/yellow separable (CIE76 dE >= 10), visible bright step.

Also requires the three flagship Signal themes. Any violation exits
nonzero so CI fails. Standard library only.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "lib" / "hornero"))

import signal_theme as st  # noqa: E402

FLAGSHIPS = ("hornero-signal-night", "hornero-signal-day", "hornero-signal-contrast")


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--themes-dir", default=str(ROOT / "profiles" / "themes"))
    parser.add_argument("--verbose", action="store_true", help="print every measured pair")
    args = parser.parse_args(argv)

    themes_dir = Path(args.themes_dir)
    errors: list[str] = []
    seen: set[str] = set()
    for path in sorted(themes_dir.glob("*/theme.json")):
        try:
            doc = st.load(path)
        except Exception as exc:  # noqa: BLE001 - report any unreadable pack
            errors.append(f"{path}: {exc}")
            continue
        theme_errors = st.validate(doc)
        if not theme_errors and doc["id"] != path.parent.name:
            theme_errors.append("id does not match its directory")
        if theme_errors:
            errors.extend(f"{path.parent.name}: {e}" for e in theme_errors)
            continue
        seen.add(doc["id"])
        worst = min(contrast for _, contrast, minimum in st.contrast_report(doc) if minimum == st.TEXT_MIN)
        print(f"CONTRAST-PASS: {doc['id']} (weakest text pair {worst:.2f}:1)")
        if args.verbose:
            for label, ratio, minimum in st.contrast_report(doc):
                print(f"  {label:28} {ratio:5.2f}:1 (min {minimum})")
    for flagship in FLAGSHIPS:
        if flagship not in seen:
            errors.append(f"required flagship theme missing or invalid: {flagship}")
    if errors:
        print("check-contrast.py: FAIL", file=sys.stderr)
        for error in errors:
            print(f"  - {error}", file=sys.stderr)
        return 1
    print(f"check-contrast.py: ALL GREEN ({len(seen)} schema-v2 themes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
