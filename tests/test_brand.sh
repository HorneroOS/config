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
    wallpaper/hornero-dark.svg wallpaper/hornero-light.svg; do
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
[[ -f "$STAGE/.local/share/hornero/brand/wallpaper/hornero-dark.svg" ]] \
  && pass "staged wallpaper source" || fail "wallpaper source not staged"
[[ -f "$STAGE/.config/fastfetch/hornero.txt" ]] \
  && pass "staged fastfetch mark" || fail "fastfetch mark not staged"

# --- 4. flagship recipes point at rendered PNG names ------------------------------
# Official themes (family==hornero) are discovered so new packs join automatically.
OFFICIAL_IDS="$(python3 -c "import json,glob;print(' '.join(sorted(json.load(open(p))['id'] for p in glob.glob('$REPO_ROOT/profiles/themes/*/theme.json') if json.load(open(p)).get('family')=='hornero')))")"
for tid in $OFFICIAL_IDS; do
  wall="$(python3 -c "import json;print(json.load(open('$REPO_ROOT/profiles/themes/$tid/theme.json'))['defaultWallpaper'])")"
  case "$wall" in
    "$tid-01.png") pass "$tid defaultWallpaper=$wall" ;;
    *) fail "$tid defaultWallpaper=$wall (want $tid-01.png)" ;;
  esac
done
python3 -c "import json;print(json.load(open('$REPO_ROOT/profiles/themes/hornero-light/theme.json'))['iconTheme'])" \
  | grep -qx "Papirus" \
  && pass "light iconTheme=Papirus" || fail "light iconTheme is not Papirus"

# --- 5. wallpaper render produces the referenced PNGs ------------------------------
WALLS="$(mktemp -d)"
bash "$REPO_ROOT/scripts/render-brand-assets.sh" --wallpapers "$WALLS" >/dev/null
for tid in $OFFICIAL_IDS; do
  wall="$(python3 -c "import json;print(json.load(open('$REPO_ROOT/profiles/themes/$tid/theme.json'))['defaultWallpaper'])")"
  wdir="$(python3 -c "import json;print(json.load(open('$REPO_ROOT/profiles/themes/$tid/theme.json'))['wallpaperDir'])")"
  [[ -f "$WALLS/$wdir/$wall" ]] \
    && pass "rendered $wdir/$wall" || fail "render missing: $wdir/$wall"
done
rm -rf "$WALLS"

# --- 6. missing-wallpaper empty state still fails clean ----------------------------
if bash "$REPO_ROOT/bin/dots-wallpaper-set" "$STAGE/.config/does-not-exist.png" 2>/dev/null; then
  fail "dots-wallpaper-set accepted a missing file"
else
  pass "missing wallpaper still errors cleanly"
fi

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
