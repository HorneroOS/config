#!/usr/bin/env bash
# test_desktop_integration.sh - P2 desktop integration: Hyprland semantic
# colors, Kitty flagship palettes, Qt decision artifacts, and Hornero Dark
# factory defaults. Materializes into a temp HOME; no system mutation.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_HOME="$(mktemp -d)"
trap 'rm -rf "$TMP_HOME"' EXIT

"$REPO_ROOT/scripts/materialize.sh" --dest "$TMP_HOME" >/dev/null

pass() { echo "TEST-PASS: $1"; }
fail() { echo "TEST-FAIL: $1" >&2; exit 1; }

# --- (1) Hyprland semantic integration ---------------------------------------
# Factory borders/gradient come from the flagship dark tokens (terracotta
# primary E07856, amber accent F2B749, clay border 6B4E3B), not neon.
grep -qi "e07856" "$TMP_HOME/.config/hypr/hyprland.conf" \
  || fail "hyprland.conf missing flagship terracotta active border"
grep -qi "f2b749" "$TMP_HOME/.config/hypr/hyprland.conf" \
  || fail "hyprland.conf missing flagship amber gradient stop"
grep -qi "6b4e3b" "$TMP_HOME/.config/hypr/hyprland.conf" \
  || fail "hyprland.conf missing clay inactive border"
grep -qi "0f0b08" "$TMP_HOME/.config/hypr/hyprland.conf" \
  || fail "hyprland.conf shadow not tinted with flagship scrim"
# No neon-rainbow leftovers (catppuccin mauve/blue placeholders).
if grep -qi "cba6f7\|89b4fa\|45475a" "$TMP_HOME/.config/hypr/hyprland.conf" \
    "$TMP_HOME/.config/hypr/hyprland.conf.d/colors.conf"; then
  fail "catppuccin placeholder borders still shipped"
fi
pass "hyprland factory borders/shadow are flagship dark, no neon leftovers"
# Group + groupbar colors present in the sourced colors.conf.
for token in e07856 6b4e3b f2b749 3c2c21 2b1f18; do
  grep -qi "$token" "$TMP_HOME/.config/hypr/hyprland.conf.d/colors.conf" \
    || fail "colors.conf missing flagship token $token"
done
pass "hyprland colors.conf carries active/inactive/group/groupbar set"
# Light fragment ships with the same structure for the documented opt-in.
[[ -f "$TMP_HOME/.config/hypr/hyprland.conf.d/hornero-light.conf" ]] \
  || fail "hornero-light.conf not materialized"
grep -qi "b24827" "$TMP_HOME/.config/hypr/hyprland.conf.d/hornero-light.conf" \
  || fail "hornero-light.conf missing flagship light primary"
pass "hyprland light fragment materialized with flagship light tokens"

# --- (2) Kitty palettes --------------------------------------------------------
[[ -f "$TMP_HOME/.config/kitty/hornero-dark.conf" ]] \
  || fail "kitty hornero-dark.conf not materialized"
[[ -f "$TMP_HOME/.config/kitty/hornero-light.conf" ]] \
  || fail "kitty hornero-light.conf not materialized"
grep -q "include hornero-dark.conf" "$TMP_HOME/.config/kitty/kitty.conf" \
  || fail "kitty.conf does not include the Hornero Dark factory palette"
if grep -q "202734\|CBCCC6" "$TMP_HOME/.config/kitty/kitty.conf"; then
  fail "kitty.conf still carries the pre-flagship fallback palette"
fi
pass "kitty factory default includes hornero-dark, old fallback gone"
# Terminal readability gate (normals AA, brights large-text floor, R/G/Y
# distinguishable, ramps stepped) over both shipped palettes.
python3 "$REPO_ROOT/scripts/check-terminal-contrast.py" \
  --kitty-dir "$REPO_ROOT/desktop/kitty" \
  || fail "terminal contrast gate"
pass "kitty palettes pass readability + distinguishability gate"

# --- (3) Qt decision -----------------------------------------------------------
[[ -f "$TMP_HOME/.config/qt6ct/qt6ct.conf" ]] \
  || fail "qt6ct.conf not materialized"
grep -q "^style=Fusion" "$TMP_HOME/.config/qt6ct/qt6ct.conf" \
  || fail "qt6ct.conf does not pin Fusion style"
grep -q "Papirus-Dark" "$TMP_HOME/.config/qt6ct/qt6ct.conf" \
  || fail "qt6ct.conf missing factory icon theme"
grep -q "QT_QPA_PLATFORMTHEME,qt6ct" \
  "$TMP_HOME/.config/hypr/hyprland.conf.d/environment.conf" \
  || fail "hypr environment no longer pins qt6ct platformtheme"
[[ -f "$REPO_ROOT/docs/QT_DECISION.md" ]] \
  || fail "docs/QT_DECISION.md missing"
# No Kvantum config ships (deferred by evidence: no Plasma session).
if find "$TMP_HOME" -iname "*kvantum*" | grep -q .; then
  fail "kvantum artifacts materialized despite deferral"
fi
pass "qt6ct factory default + platformtheme pin, kvantum deferred"

# --- (4) Factory defaults: fresh boot = Hornero Dark ---------------------------
[[ -f "$TMP_HOME/.local/share/hornero/factory.json" ]] \
  || fail "factory.json not materialized"
python3 - "$REPO_ROOT/profiles/factory.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["defaultTheme"] == "hornero-dark", "defaultTheme is not hornero-dark"
assert "hornero-dark" in d["availableThemes"] and "hornero-light" in d["availableThemes"]
assert d["fonts"]["material"] == "Material Symbols Rounded"
assert "extra/ttf-material-symbols-variable" in d["fonts"]["packages"]
assert d["icons"]["theme"] == "Papirus-Dark"
PY
pass "factory.json declares Hornero Dark + fonts/icons with dep names"
# Factory record agrees with the flagship recipes it points at.
python3 - "$REPO_ROOT/profiles/factory.json" "$REPO_ROOT/profiles/themes" <<'PY'
import json, sys
factory = json.load(open(sys.argv[1]))
base = sys.argv[2]
for mode in factory["availableThemes"]:
    theme = json.load(open(f"{base}/{mode}/theme.json"))
    assert theme["id"] == mode, f"recipe id mismatch: {mode}"
assert factory["defaultTheme"] == "hornero-dark"
assert factory["wallpaper"]["defaultWallpaper"] == json.load(
    open(f"{base}/hornero-dark/theme.json"))["defaultWallpaper"]
PY
pass "factory record matches flagship theme recipes"
# No runtime dependency on ulises-jeremias/dotfiles in anything new or
# materialized: that repo is a read-only extraction source (provenance
# mentions in DECISIONS/docs stay allowlisted per AGENTS.md).
# NOTE: this test file itself is excluded from the search below because it
# necessarily spells out the forbidden patterns to assert their absence.
if grep -rn "git clone.*dotfiles\|curl.*dotfiles\|wget.*dotfiles\|github.com/ulises-jeremias/dotfiles.*clone\|raw.githubusercontent.*dotfiles" \
    "$REPO_ROOT/desktop/kitty" "$REPO_ROOT/desktop/hypr" "$REPO_ROOT/desktop/qt6ct" \
    "$REPO_ROOT/profiles/factory.json" "$REPO_ROOT/scripts/check-terminal-contrast.py" \
    2>/dev/null | grep -v "test_desktop_integration" ; then
  fail "new desktop-integration files reference a dotfiles runtime fetch"
fi
pass "no dotfiles runtime dependency in desktop-integration files"

# Theme switch re-themes kitty + libadwaita atomically (Preview 2 QA: light
# shell with a dark terminal, or Adwaita-blue GTK4 under dark, is a
# half-applied desktop). Exercises the installed lib against the TMP stage.
export XDG_CONFIG_HOME="$TMP_HOME/.config" XDG_DATA_HOME="$TMP_HOME/.local/share"
export HOME="$TMP_HOME" REPO_ROOT="$REPO_ROOT"
bash -c '
    source "$REPO_ROOT/lib/dots/apply-appearance.sh"
    _dots_aa_sync_kitty hornero-light
    grep -qx "include hornero-light.conf" "$XDG_CONFIG_HOME/kitty/kitty.conf" || exit 11
    _dots_aa_sync_recolor hornero-light
    cmp -s "$XDG_DATA_HOME/themes/Hornero-Light/gtk-4.0/recolor.css" \
           "$XDG_CONFIG_HOME/gtk-4.0/gtk.css" || exit 12
    _dots_aa_sync_kitty hornero-dark
    grep -qx "include hornero-dark.conf" "$XDG_CONFIG_HOME/kitty/kitty.conf" || exit 13
    _dots_aa_sync_recolor hornero-dark
    cmp -s "$XDG_DATA_HOME/themes/Hornero-Dark/gtk-4.0/recolor.css" \
           "$XDG_CONFIG_HOME/gtk-4.0/gtk.css" || exit 14
  ' || fail "theme switch does not re-theme kitty + recolor atomically ($?)"
pass "theme switch re-themes kitty + libadwaita recolor"

echo "test_desktop_integration.sh: ALL GREEN"
