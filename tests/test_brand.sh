#!/usr/bin/env bash
# test_brand.sh - brand identity contract: required assets exist, install
# mapping stages them, wallpaper PNG names match the flagship recipes, the
# missing-wallpaper empty state still fails clean, and the fastfetch mark
# renders. No system mutation (temp HOME only).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAIL=0
pass() { echo "BRANDTEST-PASS: $1"; }
fail() { echo "BRANDTEST-FAIL: $1" >&2; FAIL=1; }

# --- 1. required sources present --------------------------------------------------
for rel in logo.svg logo-symbolic.svg logo-mono.svg logo-dark.svg logo-light.svg \
    wordmark.svg favicon.svg icons/hornero-app.svg icons/hornero-system.svg \
    wallpaper/hornero-signal-night.svg wallpaper/hornero-signal-day.svg; do
  [[ -f "$REPO_ROOT/assets/brand/$rel" ]] \
    && pass "source $rel" || fail "source missing: $rel"
done
[[ -f "$REPO_ROOT/desktop/fastfetch/hornero.txt" ]] \
  && pass "fastfetch mark" || fail "fastfetch mark missing"

# --- 2. vector-only (shared with validate.sh, enforced again here) ----------------
if grep -rl "<image\|data:image" "$REPO_ROOT/assets/brand" 2>/dev/null | grep -q .; then
  fail "embedded raster found under assets/brand"
else
  pass "no embedded rasters"
fi

# --- 3. materialize stages brand + fastfetch mark ----------------------------------
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
bash "$REPO_ROOT/scripts/materialize.sh" --dest "$STAGE" >/dev/null
[[ -f "$STAGE/.local/share/hornero/brand/logo.svg" ]] \
  && pass "staged hornero/brand/logo.svg" || fail "brand not staged"
[[ -f "$STAGE/.local/share/hornero/brand/wallpaper/hornero-signal-night.svg" ]] \
  && pass "staged wallpaper source" || fail "wallpaper source not staged"
[[ -f "$STAGE/.config/fastfetch/hornero.txt" ]] \
  && pass "staged fastfetch mark" || fail "fastfetch mark not staged"

# --- 4. Signal recipes point at rendered PNG names ---------------------------------
# Hornero Signal themes are discovered so new flagships join automatically.
OFFICIAL_IDS="$(python3 -c "import json,glob;print(' '.join(sorted(json.load(open(p))['id'] for p in glob.glob('$REPO_ROOT/profiles/themes/*/theme.json') if json.load(open(p)).get('collection')=='hornero-signal')))")"
[[ -n $OFFICIAL_IDS ]] || fail "no hornero-signal themes found"
for tid in $OFFICIAL_IDS; do
  wall="$(python3 -c "import json;print(json.load(open('$REPO_ROOT/profiles/themes/$tid/theme.json'))['defaultWallpaper'])")"
  wdir="$(python3 -c "import json;print(json.load(open('$REPO_ROOT/profiles/themes/$tid/theme.json'))['wallpaperDir'])")"
  [[ "$wall" == "$wdir-01.png" && -f "$REPO_ROOT/assets/brand/wallpaper/$wdir.svg" ]] \
    && pass "$tid defaultWallpaper=$wdir/$wall (procedural Signal source)" \
    || fail "$tid defaultWallpaper=$wall has no assets/brand/wallpaper/$wdir.svg source"
done
python3 -c "import json;print(json.load(open('$REPO_ROOT/profiles/themes/hornero-signal-day/theme.json'))['iconTheme'])" \
  | grep -qx "Papirus" \
  && pass "day iconTheme=Papirus" || fail "day iconTheme is not Papirus"

# --- 5. wallpaper render produces the referenced PNGs ------------------------------
WALLS="$(mktemp -d)"
bash "$REPO_ROOT/scripts/render-brand-assets.sh" --wallpapers "$WALLS" >/dev/null
for tid in $OFFICIAL_IDS; do
  wall="$(python3 -c "import json;print(json.load(open('$REPO_ROOT/profiles/themes/$tid/theme.json'))['defaultWallpaper'])")"
  wdir="$(python3 -c "import json;print(json.load(open('$REPO_ROOT/profiles/themes/$tid/theme.json'))['wallpaperDir'])")"
  if [[ "$wall" == *.jpg ]]; then
    # Photo-led flagships ship the photograph, not a render.
    [[ -f "$REPO_ROOT/assets/wallpapers/$wdir/$wall" ]] \
      && pass "photo default $wall" || fail "photo default missing: $wall"
    continue
  fi
  [[ -f "$WALLS/$wdir/$wall" ]] \
    && pass "rendered $wdir/$wall" || fail "render missing: $wdir/$wall"
done
rm -rf "$WALLS"

# --- 6. missing-wallpaper empty state still fails clean ----------------------------
if bash "$REPO_ROOT/bin/hornero-wallpaper-set" "$STAGE/.config/does-not-exist.png" 2>/dev/null; then
  fail "hornero-wallpaper-set accepted a missing file"
else
  pass "missing wallpaper still errors cleanly"
fi

# --- 6b. Signal-only colours, outlined wordmark, social previews ------------------
# Pre-Signal clay/terracotta hexes must not return to the brand sources.
if grep -rliE '#(E07856|B24827|F2B749|2B1A11|7C4A2C|FFFDF7|F6E9DB|E89A55)' "$REPO_ROOT/assets/brand" "$REPO_ROOT/assets/social" 2>/dev/null | grep -q .; then
  fail "pre-Signal clay/terracotta colour found in brand or social sources"
else
  pass "brand sources carry Signal colours only"
fi
# The wordmark is outlined so it renders without IBM Plex installed.
if grep -q "<text" "$REPO_ROOT/assets/brand/wordmark.svg"; then
  fail "wordmark.svg has live <text> (must be outlined paths)"
else
  pass "wordmark.svg is outlined (font-independent)"
fi
# Social previews: committed SVGs match the generator; every SVG has its PNG.
python3 "$REPO_ROOT/scripts/render-social-previews.py" --check \
  && pass "social preview SVGs match generator" || fail "social preview SVGs stale"
for svg in "$REPO_ROOT"/assets/social/*.svg; do
  png="${svg%.svg}.png"
  if [[ -f $png ]] && [[ "$(python3 -c "import struct,sys;d=open(sys.argv[1],'rb').read(24);print(*struct.unpack('>II',d[16:24]))" "$png")" == "1280 640" ]]; then
    pass "$(basename "$png") is 1280x640"
  else
    fail "$(basename "$png") missing or not 1280x640"
  fi
done

# --- 7. fastfetch mark renders ------------------------------------------------------
if command -v fastfetch >/dev/null 2>&1; then
  if fastfetch --logo-type file --logo "$REPO_ROOT/desktop/fastfetch/hornero.txt" \
      --structure Title 2>/dev/null | grep -q "H O R N E R O"; then
    pass "fastfetch mark renders"
  else
    fail "fastfetch mark did not render"
  fi
else
  echo "BRANDTEST-SKIP: fastfetch not installed" >&2
fi

[[ $FAIL -eq 0 ]] && echo "test_brand.sh: ALL GREEN"
exit "$FAIL"
