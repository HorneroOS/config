#!/usr/bin/env bash
# test_hyprland_lua.sh - Lua-only Hyprland migration contract.
#
# The legacy hyprland.conf + hyprland.conf.d tree is retired: every Lua
# file must parse with luac, the bind/window-rule/autostart inventories
# must match the frozen legacy counts (145 binds, 44 window rules,
# 20 autostart commands, 24 environment values), and no shipped Lua
# file may reference a removed .conf or .sh path.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HYPR="$REPO_ROOT/desktop/hypr"
fail() { echo "TEST-FAIL: $1" >&2; exit 1; }

# No legacy hyprlang entrypoint or module tree remains.
[[ ! -e "$HYPR/hyprland.conf" ]] || fail "legacy hyprland.conf still shipped"
[[ ! -d "$HYPR/hyprland.conf.d" ]] || fail "legacy hyprland.conf.d still shipped"
[[ -f "$HYPR/hyprland.lua" ]] || fail "hyprland.lua missing"

# Every Lua file parses.
if command -v luac >/dev/null 2>&1; then
  while IFS= read -r f; do
    luac -p "$f" || fail "luac -p failed: $f"
  done < <(find "$HYPR" -name '*.lua' -type f | sort)
  echo "TEST-PASS: luac -p parses every Hyprland Lua file"
else
  echo "TEST-SKIP: luac not installed" >&2
fi

# No dangling references to removed files.
if grep -rnE 'hyprland\.conf|hyprland\.conf\.d|scripts/[A-Za-z-]+\.sh' "$HYPR" --include='*.lua'; then
  fail "dangling legacy reference in Hyprland Lua tree"
fi
echo "TEST-PASS: no dangling .conf/.sh references in Hyprland Lua tree"

# Every module named by the entrypoint exists.
while IFS= read -r mod; do
  [[ -f "$HYPR/hyprland.lua.d/$mod" ]] || fail "hyprland.lua loads missing module $mod"
done < <(grep -oE 'dofile\(here \.\. "[^"]+"\)' "$HYPR/hyprland.lua" | sed -E 's/.*here \.\. "//; s/"\)//')
echo "TEST-PASS: every dofile module in hyprland.lua resolves"

# Parity inventories (frozen from the retired hyprlang tree).
binds=$(grep -c 'hl\.bind' "$HYPR/hyprland.lua.d/keybindings.lua")
[[ "$binds" -eq 145 ]] || fail "bind parity: expected 145 hl.bind, got $binds"
echo "TEST-PASS: bind parity 145/145"

rules=$(grep -c 'hl\.window_rule' "$HYPR/hyprland.lua.d/window-rules.lua")
[[ "$rules" -eq 44 ]] || fail "window-rule parity: expected 44, got $rules"
echo "TEST-PASS: window-rule parity 44/44"

execs=$(grep -c 'hl\.exec_cmd' "$HYPR/hyprland.lua.d/autostart.lua")
[[ "$execs" -eq 20 ]] || fail "autostart parity: expected 20, got $execs"
echo "TEST-PASS: autostart parity 20/20"

envs=$(grep -cE '\{ "[A-Z_]+",' "$HYPR/hyprland.lua.d/environment.lua")
[[ "$envs" -ge 22 ]] || fail "environment parity: expected >=22 static entries, got $envs"
grep -q 'DBUS_SESSION_BUS_ADDRESS' "$HYPR/hyprland.lua.d/environment.lua" \
  || fail "environment lost DBUS_SESSION_BUS_ADDRESS"
grep -q 'GNOME_KEYRING_CONTROL' "$HYPR/hyprland.lua.d/environment.lua" \
  || fail "environment lost GNOME_KEYRING_CONTROL"
echo "TEST-PASS: environment parity (22 static + 2 runtime-derived)"

# Helper scripts are Lua, executable, and parse.
for s in gaps-interactive smart-float notification-handler; do
  [[ -x "$HYPR/scripts/$s.lua" ]] || fail "scripts/$s.lua missing or not executable"
  [[ ! -e "$HYPR/scripts/$s.sh" ]] || fail "legacy scripts/$s.sh still shipped"
done
echo "TEST-PASS: hypr helper scripts are executable Lua, no shell helpers remain"

# Real compositor parser, when available (Hyprland 0.56 in CI/dev hosts).
if command -v Hyprland >/dev/null 2>&1; then
  out=$(timeout 30 Hyprland --config "$HYPR/hyprland.lua" --verify-config 2>&1 || true)
  grep -q "config ok" <<<"$out" || fail "Hyprland --verify-config did not report 'config ok': $out"
  echo "TEST-PASS: Hyprland --verify-config reports config ok"
fi

echo "TEST-PASS: Hyprland Lua migration contract holds"
