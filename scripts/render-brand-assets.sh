#!/usr/bin/env bash
# render-brand-assets.sh - validate HorneroOS brand SVGs and render PNGs.
# No repo writes except an explicit --out DIR for previews: procedural
# brand binaries (SVG renders, icon caches) are generated on the target
# machine, never vendored. Exception: the photographic flagship
# wallpapers (assets/brand/wallpaper/hornero-{dark,light}.png) ARE
# vendored sources (~2 MB each) and are copied verbatim as the
# hornero-dark/light defaults; the SVGs remain vector masters.
# Usage: scripts/render-brand-assets.sh [--out DIR] [--wallpapers DIR]
#   --out DIR        write recognizability PNGs (default: mktemp, kept on stdout)
#   --wallpapers DIR render hornero-dark/light PNGs at 1920x1080 + 2560x1440
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BRAND="$REPO_ROOT/assets/brand"
OUT=""
WALLPAPERS_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out) OUT="${2:?--out needs a directory}"; shift 2 ;;
    --wallpapers) WALLPAPERS_DIR="${2:?--wallpapers needs a directory}"; shift 2 ;;
    -h|--help) sed -n '2,7p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "error: unknown argument: $1" >&2; exit 1 ;;
  esac
done

need() { command -v "$1" >/dev/null 2>&1 || { echo "error: missing tool: $1" >&2; exit 1; }; }
need rsvg-convert; need python3

# --- 1. well-formed XML, no embedded rasters ------------------------------------
python3 - "$BRAND" <<'PY'
import re, sys, xml.etree.ElementTree as ET
from pathlib import Path
brand = Path(sys.argv[1])
errors = []
svgs = sorted(brand.rglob("*.svg"))
if not svgs:
    errors.append("no SVGs found")
for f in svgs:
    try:
        ET.parse(f)
    except Exception as e:
        errors.append(f"{f}: not well-formed: {e}")
    text = f.read_text()
    if "<image" in text or "data:image" in text:
        errors.append(f"{f}: embedded raster (no rasters allowed)")
    # xmlns namespace declarations are not external references.
    body = re.sub(r'xmlns(?::\w+)?="[^"]*"', "", text)
    if re.search(r"https?://", body):
        errors.append(f"{f}: external reference (must be self-contained)")
if errors:
    for e in errors:
        print(f"BRAND-FAIL: {e}")
    sys.exit(1)
print(f"BRAND-PASS: {len(svgs)} SVGs well-formed, vector-only, self-contained")
PY

# --- 2. recognizability PNGs ------------------------------------------------------
if [[ -z $OUT ]]; then OUT="$(mktemp -d)"; fi
mkdir -p "$OUT"
for svg in "$BRAND"/logo.svg "$BRAND"/logo-symbolic.svg "$BRAND"/logo-mono.svg \
           "$BRAND"/logo-dark.svg "$BRAND"/logo-light.svg "$BRAND"/favicon.svg; do
  base="$(basename "$svg" .svg)"
  for s in 16 24 32 48 64 128 256 512; do
    rsvg-convert -w "$s" -h "$s" "$svg" -o "$OUT/$base-$s.png"
  done
done
rsvg-convert -w 512 "$BRAND"/wordmark.svg -o "$OUT/wordmark-512.png"
echo "BRAND-PASS: recognizability PNGs in $OUT"

# --- 3. wallpaper PNGs (procedural SVG -> local raster, never vendored) ------------
# Official themes (family==hornero) are discovered from the recipe tree so
# adding a theme pack never requires touching this script.
if [[ -n $WALLPAPERS_DIR ]]; then
  python3 - "$REPO_ROOT/profiles/themes" "$BRAND/wallpaper" "$WALLPAPERS_DIR" <<'PY'
import json, shutil, subprocess, sys
from pathlib import Path
themes_dir, svg_dir, out_dir = (Path(a) for a in sys.argv[1:4])
rendered = []
for recipe in sorted(themes_dir.glob("*/theme.json")):
    doc = json.loads(recipe.read_text(encoding="utf-8"))
    if doc.get("family") != "hornero":
        continue
    target_dir = out_dir / doc["wallpaperDir"]
    target_dir.mkdir(parents=True, exist_ok=True)
    default = target_dir / doc["defaultWallpaper"]
    hidpi = target_dir / f"{doc['id']}-02-hidpi.png"
    # Photographic flagship override: vendored PNG wins over the SVG
    # render for hornero-dark/light (1586x992 source; upscaling on
    # larger panels is accepted until a 2560px master lands).
    photo = svg_dir / f"{doc['id']}.png"
    if photo.is_file():
        shutil.copyfile(photo, default)
        shutil.copyfile(photo, hidpi)
        rendered.append(str(default.relative_to(out_dir)) + " (photo)")
        continue
    svg = svg_dir / f"{doc['id']}.svg"
    if not svg.is_file():
        print(f"BRAND-SKIP: no flagship SVG for {doc['id']}", file=sys.stderr)
        continue
    subprocess.run(["rsvg-convert", "-w", "1920", "-h", "1080", str(svg),
                    "-o", str(default)], check=True)
    subprocess.run(["rsvg-convert", "-w", "2560", "-h", "1440", str(svg),
                    "-o", str(hidpi)], check=True)
    rendered.append(str(default.relative_to(out_dir)))
print(f"BRAND-PASS: wallpaper PNGs in {out_dir}: {', '.join(rendered)}")
PY
fi
