#!/usr/bin/env python3
"""Generate the HorneroOS repository social preview cards (1280x640).

Source of truth for the images GitHub shows when a repository link is shared.
GitHub offers no API to upload a repository social preview; a maintainer sets
each PNG by hand (Settings > General > Social preview). See assets/social/README.md.

Usage: scripts/render-social-previews.py [--out DIR] [--png] [--check]
  --out DIR  output directory (default: assets/social)
  --png      also render PNGs with rsvg-convert (needs IBM Plex Mono, Plex Sans
             Condensed and Plex Sans installed; fontconfig resolves them)
  --check    do not write; fail if the committed SVGs differ from a fresh render

Design: Signal Night (RFC 0001). Roles are the flagship palette values; the
mark is assets/brand/logo-dark.svg inlined; the 45 degree La Plata diagonal is
a brand-surface detail (never inside controls), drawn in `signal`.
"""
from __future__ import annotations

import argparse
import html
import re
import shutil
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
BRAND = REPO / "assets" / "brand"

# Signal Night roles (RFC 0001 section 3.2).
GROUND, BASE, PANEL = "#0C0F13", "#13171D", "#181D24"
INK, INK_MUTED, RULE, RULE_STRONG = "#ECE6DA", "#A8ABAD", "#2C333C", "#707A85"
SIGNAL = "#F2A33A"

CARDS = [
    # (file stem, eyebrow, title, tagline lines)
    ("horneroos", "ORGANIZATION · HORNEROOS", "HorneroOS",
     ["An Arch-based workstation OS family with a", "visual language of its own: Hornero Signal."]),
    ("shell", "SHELL · QUICKSHELL", "Hornero Shell",
     ["Bars, launcher, Dashboard, notifications", "and Control Center for Wayland."]),
    ("config", "CONFIG · DEFAULTS", "Hornero Config",
     ["Themes, tokens, brand assets, wallpapers", "and factory defaults."]),
    ("hornero", "CLI · HORNERO", "horneroctl",
     ["Edition catalogue, package composition,", "release manifests and the system CLI."]),
    ("docs", "DOCS · HANDBOOK", "Hornero Docs",
     ["User, contributor and architecture", "documentation."]),
    ("qa", "QA · ACCEPTANCE", "Hornero QA",
     ["Reproducible graphical journeys,", "probes and evidence."]),
    ("website", "WEBSITE · HORNEROOS.COM", "horneroos.com",
     ["The official site, product showcase", "and documentation portal."]),
    ("plugins", "PLUGINS · PLUGINKIT", "Hornero Plugins",
     ["First-party extensions, curated catalogue,", "templates and validation."]),
    ("installer", "INSTALLER · CALAMARES", "Hornero Installer",
     ["Provisional Calamares installer and", "Archiso profile."]),
    ("greeter", "GREETER · SDDM", "Hornero Greeter",
     ["The SDDM login screen and its", "session integration."]),
]


def mark() -> str:
    """Inline body of logo-dark.svg (bird on the Signal sun disc)."""
    text = (BRAND / "logo-dark.svg").read_text()
    body = re.search(r"<svg[^>]*>(.*)</svg>", text, re.S).group(1)
    body = re.sub(r"<title>.*?</title>|<desc>.*?</desc>", "", body, flags=re.S)
    return body.strip()


def card(stem: str, eyebrow: str, title: str, lines: list[str]) -> str:
    esc = html.escape
    tag = "".join(
        f'<text x="72" y="{430 + i * 40}" font-family="IBM Plex Sans, sans-serif" '
        f'font-size="28" fill="{INK_MUTED}">{esc(line)}</text>'
        for i, line in enumerate(lines)
    )
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="1280" height="640" viewBox="0 0 1280 640" role="img" aria-label="{esc(title)} social preview">
  <title>{esc(title)} social preview</title>
  <desc>Hornero Signal Night card: bird mark, mono eyebrow, title, on-air bar and the 45 degree La Plata diagonal.</desc>
  <rect width="1280" height="640" fill="{GROUND}"/>
  <rect x="24" y="24" width="1232" height="592" fill="{BASE}" stroke="{RULE}" stroke-width="1"/>
  <clipPath id="frame"><rect x="24" y="24" width="1232" height="592"/></clipPath>
  <g clip-path="url(#frame)" fill="none">
    <path d="M640,640 L1280,0" stroke="{SIGNAL}" stroke-width="2" opacity="0.7"/>
    <path d="M700,640 L1340,0" stroke="{RULE_STRONG}" stroke-width="1" opacity="0.5"/>
    <path d="M760,640 L1400,0" stroke="{RULE}" stroke-width="1"/>
    <path d="M580,640 L1220,0" stroke="{RULE}" stroke-width="1"/>
  </g>
  <g transform="translate(872,160) scale(1.2)">
    {mark()}
  </g>
  <rect x="72" y="86" width="2" height="10" fill="{SIGNAL}"/>
  <text x="86" y="96" font-family="IBM Plex Mono, monospace" font-size="20" letter-spacing="2.4" fill="{INK_MUTED}">{esc(eyebrow)}</text>
  <text x="72" y="320" font-family="IBM Plex Sans Condensed, sans-serif" font-size="96" font-weight="600" fill="{INK}">{esc(title)}</text>
  <rect x="72" y="352" width="96" height="4" fill="{SIGNAL}"/>
  {tag}
  <text x="72" y="568" font-family="IBM Plex Mono, monospace" font-size="18" letter-spacing="2.4" fill="{RULE_STRONG}">HORNEROOS.COM</text>
</svg>
'''


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--out", type=Path, default=REPO / "assets" / "social")
    ap.add_argument("--png", action="store_true")
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    bad = 0
    for stem, eyebrow, title, lines in CARDS:
        svg = card(stem, eyebrow, title, lines)
        path = args.out / f"{stem}.svg"
        if args.check:
            if not path.is_file() or path.read_text() != svg:
                print(f"SOCIAL-FAIL: {path.name} is stale; run scripts/render-social-previews.py", file=sys.stderr)
                bad = 1
            continue
        path.write_text(svg)
        if args.png:
            if not shutil.which("rsvg-convert"):
                print("error: rsvg-convert not found", file=sys.stderr)
                return 1
            subprocess.run(["rsvg-convert", "-w", "1280", "-h", "640", str(path),
                            "-o", str(args.out / f"{stem}.png")], check=True)
    if args.check and not bad:
        print(f"SOCIAL-PASS: {len(CARDS)} social preview SVGs match their generator")
    elif not args.check:
        print(f"wrote {len(CARDS)} cards to {args.out}")
    return bad


if __name__ == "__main__":
    sys.exit(main())
