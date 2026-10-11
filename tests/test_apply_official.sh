#!/usr/bin/env bash
# test_apply_official.sh - fresh-HOME apply of every official theme pack.
# Proves the final-product test: materialize, then apply each official
# theme with no user photos present, and confirm the desktop fragments
# land (wallpaper pointer, Kitty/Alacritty/Ghostty palettes, GTK css). Needs rsvg-convert
# for the flagship wallpaper render; skips honestly without it.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

pass() { echo "TEST-PASS: $1"; }
fail() { echo "TEST-FAIL: $1" >&2; exit 1; }

if ! command -v rsvg-convert >/dev/null 2>&1; then
  echo "TEST-SKIP: rsvg-convert missing, cannot render flagship wallpapers"
  exit 0
fi

OFFICIAL_IDS="$(python3 -c "import json,glob;print(' '.join(sorted(json.load(open(p))['id'] for p in glob.glob('$REPO_ROOT/profiles/themes/*/theme.json') if json.load(open(p)).get('family')=='hornero')))")"
[[ -n "$OFFICIAL_IDS" ]] || fail "no official themes found"

TMP_HOME="$(mktemp -d)"
trap 'rm -rf "$TMP_HOME"' EXIT
export HOME="$TMP_HOME"
export XDG_DATA_HOME="$TMP_HOME/.local/share"
export XDG_CONFIG_HOME="$TMP_HOME/.config"
export XDG_STATE_HOME="$TMP_HOME/.local/state"
export XDG_CACHE_HOME="$TMP_HOME/.cache"
export HORNERO_THEMES_DIR="$REPO_ROOT/profiles/themes"
# Hermetic PATH: the apply chain probes for helper CLIs (hornero-color-scheme,
# hornero-gtk-theme, hyprctl); ambient developer binaries must not leak in.
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
  [[ -s "$XDG_CACHE_HOME/hornero/smart-colors/colors-kitty.conf" ]] \
    || fail "Kitty generated palette missing for $tid"
  [[ -s "$XDG_CONFIG_HOME/alacritty/hornero-colors.toml" ]] \
    || fail "Alacritty generated palette missing for $tid"
  [[ -s "$XDG_CONFIG_HOME/ghostty/themes/Hornero Dynamic" ]] \
    || fail "Ghostty generated palette missing for $tid"
  python3 - "$XDG_CACHE_HOME/hornero/smart-colors/scheme.json" \
    "$XDG_CONFIG_HOME/alacritty/hornero-colors.toml" \
    "$XDG_CONFIG_HOME/ghostty/themes/Hornero Dynamic" <<'PY' \
    || fail "terminal palettes do not match the generated scheme for $tid"
import json, sys, tomllib
scheme = json.load(open(sys.argv[1], encoding="utf-8"))["colours"]
alacritty = tomllib.load(open(sys.argv[2], "rb"))
ghostty = open(sys.argv[3], encoding="utf-8").read()
assert alacritty["colors"]["primary"]["background"] == f'#{scheme["surface"]}'
assert alacritty["colors"]["primary"]["foreground"] == f'#{scheme["onSurface"]}'
for index in range(16):
    assert f'palette = {index}=#{scheme[f"term{index}"]}' in ghostty
PY
  grep -qx "custom_palette=true" "$XDG_CONFIG_HOME/qt6ct/qt6ct.conf" \
    || fail "qt6ct custom palette not enabled for $tid"
  grep -qx "color_scheme_path=$XDG_CONFIG_HOME/qt6ct/colors/$tid.conf" \
    "$XDG_CONFIG_HOME/qt6ct/qt6ct.conf" \
    || fail "qt6ct not pointed at the $tid palette"
  pass "applied official theme $tid (wallpaper + 3 terminal palettes + qt6ct)"
done

echo "test_apply_official.sh: ALL GREEN ($OFFICIAL_IDS)"
