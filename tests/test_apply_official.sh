#!/usr/bin/env bash
# test_apply_official.sh - fresh-HOME apply of every Hornero collection theme.
# Proves the final-product test: materialize, then apply each Hornero Signal
# and Hornero Original theme with no user photos present, and confirm the
# desktop fragments land (live Signal scheme, wallpaper pointer, application
# palettes, Hyprland/hyprlock caches, kitty/qt6ct/libadwaita switches), all
# carrying the theme's own schema-v2 roles. Needs rsvg-convert for the Signal
# wallpaper render; skips honestly without it.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

pass() { echo "TEST-PASS: $1"; }
fail() { echo "TEST-FAIL: $1" >&2; exit 1; }

if ! command -v rsvg-convert >/dev/null 2>&1; then
  echo "TEST-SKIP: rsvg-convert missing, cannot render flagship wallpapers"
  exit 0
fi

OFFICIAL_IDS="$(python3 -c "import json,glob;print(' '.join(sorted(json.load(open(p))['id'] for p in glob.glob('$REPO_ROOT/profiles/themes/*/theme.json') if json.load(open(p)).get('collection','').startswith('hornero-'))))")"
[[ -n "$OFFICIAL_IDS" ]] || fail "no official themes found"

TMP_HOME="$(mktemp -d)"
trap 'rm -rf "$TMP_HOME"' EXIT
export HOME="$TMP_HOME"
export XDG_DATA_HOME="$TMP_HOME/.local/share"
export XDG_CONFIG_HOME="$TMP_HOME/.config"
export XDG_STATE_HOME="$TMP_HOME/.local/state"
export XDG_CACHE_HOME="$TMP_HOME/.cache"
export HORNERO_THEMES_DIR="$REPO_ROOT/profiles/themes"
# Hermetic PATH: the apply chain probes for helper CLIs (hornero-gtk-theme,
# hyprctl, notify-send); ambient developer binaries must not leak in.
export PATH="$TMP_HOME/.local/bin:/usr/local/bin:/usr/bin:/bin"

bash "$REPO_ROOT/scripts/materialize.sh" --dest "$TMP_HOME" >/dev/null \
  || fail "materialize failed"

# shellcheck source=/dev/null
source "$REPO_ROOT/lib/hornero/apply-appearance.sh"

for tid in $OFFICIAL_IDS; do
  hornero_apply_theme "$tid" >/dev/null 2>&1 \
    || fail "apply failed for official theme $tid"
  [[ -f "$XDG_STATE_HOME/hornero/wallpaper/path" ]] \
    || fail "no wallpaper pointer after applying $tid"
  grep -qx "include $tid.conf" "$XDG_CONFIG_HOME/kitty/kitty.conf" \
    || fail "kitty not re-themed for $tid"
  for out in "$XDG_STATE_HOME/hornero/signal/scheme.json" \
      "$XDG_CONFIG_HOME/alacritty/hornero-colors.toml" \
      "$XDG_CONFIG_HOME/ghostty/themes/Hornero Dynamic" \
      "$XDG_CONFIG_HOME/btop/themes/Hornero Dynamic.theme" \
      "$XDG_CONFIG_HOME/cava/themes/Hornero Dynamic" \
      "$XDG_CACHE_HOME/hornero/smart-colors/colors-hyprland.lua" \
      "$XDG_CACHE_HOME/hornero/smart-colors/colors-hyprlock.conf"; do
    [[ -s $out ]] || fail "apply of $tid did not write $out"
  done
  python3 - "$HORNERO_THEMES_DIR/$tid/theme.json" \
    "$XDG_STATE_HOME/hornero/signal/scheme.json" \
    "$XDG_CONFIG_HOME/alacritty/hornero-colors.toml" \
    "$XDG_CONFIG_HOME/ghostty/themes/Hornero Dynamic" \
    "$XDG_CONFIG_HOME/btop/themes/Hornero Dynamic.theme" \
    "$XDG_CONFIG_HOME/cava/themes/Hornero Dynamic" \
    "$XDG_CACHE_HOME/hornero/smart-colors/colors-hyprland.lua" \
    "$XDG_CACHE_HOME/hornero/smart-colors/colors-hyprlock.conf" \
    "$XDG_CONFIG_HOME/gtk-4.0/gtk.css" <<'PY' \
    || fail "applied files do not carry the $tid roles"
import configparser
import json
import re
import sys
import tomllib
from pathlib import Path

theme = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
p, term = theme["palette"], theme["terminal"]
scheme = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
assert scheme == {"schemaVersion": 2, "id": theme["id"], "mode": theme["mode"],
                  "palette": p, "terminal": term}, "live scheme drifts from the theme"
with Path(sys.argv[3]).open("rb") as source:
    alacritty = tomllib.load(source)
assert alacritty["colors"]["primary"]["background"] == p["base"]
assert alacritty["colors"]["primary"]["foreground"] == p["ink"]
ghostty = Path(sys.argv[4]).read_text(encoding="utf-8")
for index in range(16):
    assert f"palette = {index}={term[index]}" in ghostty
btop = dict(re.findall(r'^theme\[([^]]+)\]="([^"]*)"$', Path(sys.argv[5]).read_text(), re.M))
assert btop["main_fg"] == p["ink"] and btop["hi_fg"] == p["signal"]
cava = configparser.ConfigParser(interpolation=None)
cava.read(sys.argv[6], encoding="utf-8")
assert cava["color"]["background"].strip("'") == p["base"]
hypr = Path(sys.argv[7]).read_text(encoding="utf-8").lower()
assert p["signal"].lstrip("#").lower() in hypr and p["rule"].lstrip("#").lower() in hypr
lock = Path(sys.argv[8]).read_text(encoding="utf-8").lower()
assert f"$hs_ground = rgba({p['ground'].lstrip('#').lower()}ff)" in lock
assert "{" not in lock, "hyprlock cache must hold variables only"
recolor = Path(sys.argv[9]).read_text(encoding="utf-8")
assert f"@define-color accent_bg_color {p['signal']};" in recolor
assert f"@define-color window_bg_color {p['base']};" in recolor
PY
  grep -qx "custom_palette=true" "$XDG_CONFIG_HOME/qt6ct/qt6ct.conf" \
    || fail "qt6ct custom palette not enabled for $tid"
  grep -qx "color_scheme_path=$XDG_CONFIG_HOME/qt6ct/colors/$tid.conf" \
    "$XDG_CONFIG_HOME/qt6ct/qt6ct.conf" \
    || fail "qt6ct not pointed at the $tid palette"
  pass "applied $tid (live scheme, wallpaper, 4 app palettes, hypr + hyprlock caches, kitty, qt6ct, libadwaita)"
done

echo "test_apply_official.sh: ALL GREEN ($OFFICIAL_IDS)"
