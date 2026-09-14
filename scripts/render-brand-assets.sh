#!/usr/bin/env bash
# render-brand-assets.sh - validate HorneroOS brand SVGs and render PNGs.
# No repo writes except an explicit --out DIR for previews: all brand
# binaries (PNG wallpapers, icon caches) are generated on the target
# machine, never vendored. Binaries are NOT shipped in this repo.
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
if [[ -n $WALLPAPERS_DIR ]]; then
  mkdir -p "$WALLPAPERS_DIR/hornero-dark" "$WALLPAPERS_DIR/hornero-light"
  rsvg-convert -w 1920 -h 1080 "$BRAND/wallpaper/hornero-dark.svg" \
    -o "$WALLPAPERS_DIR/hornero-dark/hornero-dark-01.png"
  rsvg-convert -w 2560 -h 1440 "$BRAND"/wallpaper/hornero-dark.svg \
    -o "$WALLPAPERS_DIR/hornero-dark/hornero-dark-02-hidpi.png"
  rsvg-convert -w 1920 -h 1080 "$BRAND/wallpaper/hornero-light.svg" \
    -o "$WALLPAPERS_DIR/hornero-light/hornero-light-01.png"
  rsvg-convert -w 2560 -h 1440 "$BRAND"/wallpaper/hornero-light.svg \
    -o "$WALLPAPERS_DIR/hornero-light/hornero-light-02-hidpi.png"
  echo "BRAND-PASS: wallpaper PNGs in $WALLPAPERS_DIR"
fi
