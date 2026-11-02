#!/usr/bin/env bash
# test_factory_defaults.sh - curated factory defaults from the dotfiles
# audit: editor contract, session env, fonts, XDG defaults, Hyprland
# monitors extension point. Materializes into a temp HOME.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_HOME="$(mktemp -d)"
trap 'rm -rf "$TMP_HOME"' EXIT

"$REPO_ROOT/scripts/materialize.sh" --dest "$TMP_HOME" >/dev/null

pass() { echo "TEST-PASS: $1"; }
fail() { echo "TEST-FAIL: $1" >&2; exit 1; }

CFG="$TMP_HOME/.config"

# Editor contract: SUDO_EDITOR follows the nano factory editor; git too.
grep -qx "SUDO_EDITOR=nano" "$CFG/environment.d/10-hornero-editor.conf" \
  || fail "SUDO_EDITOR missing from editor environment"
git config --file "$TMP_HOME/.config/git/config" core.editor | grep -qx "nano" \
  || fail "git core.editor is not nano"
pass "editor contract (SUDO_EDITOR + git core.editor = nano)"

# Session baseline for non-Hyprland sessions.
grep -qx "TERMINAL=kitty" "$CFG/environment.d/20-hornero-session.conf" \
  || fail "session baseline missing TERMINAL"
grep -q 'PATH=${HOME}/.local/bin' "$CFG/environment.d/20-hornero-session.conf" \
  || fail "session baseline missing ~/.local/bin PATH entry"
if grep -q "BROWSER=" "$CFG/environment.d/20-hornero-session.conf"; then
  fail "session baseline sets BROWSER before a factory browser exists"
fi
pass "session environment baseline (no premature BROWSER)"

# Fonts: kitty uses the factory mono family; fontconfig aliases parse.
grep -q "^font_family CaskaydiaCove NF" "$CFG/kitty/kitty.conf" \
  || fail "kitty font_family is not the factory mono family"
if grep -q "Hack Nerd Font" "$CFG/kitty/kitty.conf"; then
  fail "kitty still references Hack Nerd Font"
fi
python3 -c 'import sys, xml.etree.ElementTree as ET; ET.parse(sys.argv[1])' \
  "$CFG/fontconfig/fonts.conf" || fail "fontconfig fonts.conf does not parse"
grep -q "Noto Sans CJK" "$CFG/fontconfig/fonts.conf" \
  || fail "fontconfig missing CJK fallback"
grep -q "Noto Color Emoji" "$CFG/fontconfig/fonts.conf" \
  || fail "fontconfig missing emoji fallback"
pass "fonts (kitty family + fontconfig CJK/emoji fallbacks)"

# XDG defaults: Thunar for directories, standard user dirs, no browser.
grep -qx "inode/directory=thunar.desktop" "$CFG/mimeapps.list" \
  || fail "mimeapps.list missing Thunar directory default"
if grep -qi "http" "$CFG/mimeapps.list"; then
  fail "mimeapps.list sets a web handler before a factory browser exists"
fi
grep -qx 'XDG_DOCUMENTS_DIR="$HOME/Documents"' "$CFG/user-dirs.dirs" \
  || fail "user-dirs.dirs missing Documents entry"
pass "xdg defaults (mimeapps + user-dirs, browser deferred)"

# Hyprland: user monitor overrides load after the generic fallback.
grep -q 'dofile(here .. "monitors-user.lua")' "$CFG/hypr/hyprland.lua" \
  || fail "hyprland.lua does not load monitors-user.lua"
[[ -f "$CFG/hypr/hyprland.lua.d/monitors-user.lua" ]] \
  || fail "monitors-user.lua not materialized"
pass "hyprland monitors-user.lua extension point"

# No personal data in the new factory files.
if grep -rn "/home/[a-z]" "$CFG/environment.d" "$CFG/mimeapps.list" \
    "$CFG/user-dirs.dirs" "$CFG/hypr/hyprland.lua.d/monitors-user.lua"; then
  fail "factory defaults contain a personal /home path"
fi
pass "no personal paths in factory defaults"
