#!/usr/bin/env python3
"""generate-boot-art.py - emit the text-bearing boot SVGs with glyphs as paths.

The boot theme renders on build machines that may not have IBM Plex installed
(AUR chroots, CI), and Plymouth cannot rely on fonts inside the initramfs.
So the few text assets (mono eyebrows) are converted to vector outlines once,
here, and the resulting SVGs are committed under desktop/boot/art/. Needs
fontTools and IBM Plex Mono; it is a development-time tool, not a build step.

Usage: scripts/generate-boot-art.py [--font-dir DIR]
Colours come from the hornero-signal-night theme roles (RFC 0001), never
hardcoded here.
"""
import argparse
import re
import json
import sys
from pathlib import Path

from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / "desktop" / "boot" / "art"

# name -> (text, px size, tracking in em, role colour, with registration tick)
EYEBROWS = {
    "eyebrow-boot": ("HORNEROOS", 15, 0.32, "inkMuted", True),
    "eyebrow-passphrase": ("PASSPHRASE", 15, 0.32, "inkMuted", True),
    "eyebrow-menu": ("HORNEROOS · BOOT", 15, 0.30, "inkMuted", True),
    "eyebrow-installer": ("HORNEROOS · INSTALLER", 15, 0.30, "inkMuted", True),
    "eyebrow-installer-hint": ("SELECT · ENTER TO START", 13, 0.26, "inkFaintText", False),
}


def load_palette():
    theme = json.loads((ROOT / "profiles/themes/hornero-signal-night/theme.json").read_text())
    pal = dict(theme["palette"])
    pal["inkFaintText"] = pal["inkMuted"]
    return pal


def text_svg(font, text, size, tracking, color, tick):
    upm = font["head"].unitsPerEm
    scale = size / upm
    gs = font.getGlyphSet()
    cmap = font.getBestCmap()
    pad = 2
    asc = round(size * 0.78)
    x = pad + (12 if tick else 0)
    paths = []
    for ch in text:
        name = cmap[ord(ch)]
        pen = SVGPathPen(gs, ntos=lambda v: f"{v:.2f}".rstrip("0").rstrip("."))
        tp = TransformPen(pen, (scale, 0, 0, -scale, x, pad + asc))
        gs[name].draw(tp)
        d = pen.getCommands()
        if d:
            paths.append(d)
        x += gs[name].width * scale + tracking * size
    width = round(x - tracking * size + pad)
    height = round(asc + size * 0.25 + 2 * pad)
    tick_el = ""
    if tick:
        # RFC 0001 registration tick: 2 x 10 px signal bar.
        ty = pad + asc - 10
        tick_el = f'<rect x="{pad}" y="{ty}" width="2" height="10" fill="{PAL["signal"]}"/>'
    body = f'<path fill="{color}" d="{" ".join(paths)}"/>'
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" '
        f'viewBox="0 0 {width} {height}">\n'
        f"  <title>{text}</title>\n"
        f"  {tick_el}\n  {body}\n</svg>\n"
    )


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--font-dir", default=str(Path.home() / ".local/share/fonts/hornero-signal-test"))
    args = ap.parse_args()
    font_path = Path(args.font_dir) / "IBMPlexMono-Medium.ttf"
    if not font_path.is_file():
        sys.exit(f"missing {font_path}")
    font = TTFont(font_path)
    ART.mkdir(parents=True, exist_ok=True)
    for name, (text, size, tracking, role, tick) in EYEBROWS.items():
        svg = text_svg(font, text, size, tracking, PAL[role], tick)
        (ART / f"{name}.svg").write_text(svg)
        print("wrote", ART / f"{name}.svg")
    compose_iso_splash()


def _inner(name, dx, dy):
    svg = (ART / f"{name}.svg").read_text()
    body = svg.split("\n", 2)[2].rsplit("</svg>", 1)[0].replace("  <title>", "<title>", 1)
    body = "\n".join(ln for ln in body.splitlines() if not ln.strip().startswith("<title>"))
    return f'<g transform="translate({dx} {dy})">\n{body}\n</g>'


def compose_iso_splash():
    """Bake the outlined eyebrows into the 800x600 syslinux splash."""
    path = ART / "iso-splash.svg"
    text = path.read_text()
    marker = "<!--EYEBROWS-->"
    text = re.sub(r"<!--EYEBROWS-->.*?(?=\n  <g transform=\"translate\(48 40\))|<!--EYEBROWS-->", marker, text, count=1, flags=re.S)
    block = _inner("eyebrow-installer", 120, 62) + "\n  " + _inner("eyebrow-installer-hint", 46, 556)
    path.write_text(text.replace(marker, marker + "\n  " + block))
    print("composed", path)


PAL = load_palette()

if __name__ == "__main__":
    main()
