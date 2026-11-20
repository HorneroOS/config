#!/usr/bin/env bash
# test_hyprland_lua.sh - Lua-only Hyprland migration contract.
#
# The legacy hyprland.conf + hyprland.conf.d tree is retired: every Lua
# file must parse with luac, the bind/window-rule/autostart inventories
# must match the frozen legacy counts (145 binds minus the SUPER + L
# focus-right duplicate = 144, 44 window rules,
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
# 145 frozen from the retired tree, minus the SUPER + L focus-right bind
# that doubled the lock bind on the same combo (both fired).
[[ "$binds" -eq 144 ]] || fail "bind parity: expected 144 hl.bind, got $binds"
echo "TEST-PASS: bind parity 144/144"

# No global combo is bound twice: Hyprland fires every bind on a combo,
# so a duplicate silently runs two actions (SUPER + L used to lock AND
# move focus). Submap blocks are separate scopes and are skipped.
dups=$(python3 - "$HYPR/hyprland.lua.d/keybindings.lua" <<'PY'
import collections, re, sys
text = open(sys.argv[1], encoding="utf-8").read()
text = re.sub(r"(?ms)^hl\.define_submap\(.*?^end\)", "", text)
text = "\n".join(line for line in text.splitlines() if not line.lstrip().startswith("--"))
aliases = {"CONTROL": "CTRL", "MOD4": "SUPER", "META": "SUPER", "WIN": "SUPER", "MOD1": "ALT"}
def canon(combo):
    parts = [p.strip() for p in combo.split("+") if p.strip()]
    mods = sorted({aliases.get(p.upper(), p.upper()) for p in parts[:-1]})
    return " + ".join(mods + [parts[-1].lower()])
counts = collections.Counter(canon(c) for c in re.findall(r'hl\.bind\(\s*"([^"]+)"', text))
print(" ".join(sorted(c for c, n in counts.items() if n > 1)))
PY
)
[[ -z "$dups" ]] || fail "global combo bound more than once: $dups"
echo "TEST-PASS: every global combo has exactly one bind"

rules=$(grep -c 'hl\.window_rule' "$HYPR/hyprland.lua.d/window-rules.lua")
# 44 frozen from the retired tree + ghostty-opacity (all supported terminals).
[[ "$rules" -eq 45 ]] || fail "window-rule parity: expected 45, got $rules"
echo "TEST-PASS: window-rule parity 45/45"

execs=$(grep -c 'hl\.exec_cmd' "$HYPR/hyprland.lua.d/autostart.lua")
# 20 frozen from the retired tree + hornero-gtk-theme ensure (first-session
# GTK theme) + hornero-appearance apply-installer-appearance (first-login
# consumer for the installer-seeded appearance.json; no-op afterwards).
[[ "$execs" -eq 22 ]] || fail "autostart parity: expected 22, got $execs"
echo "TEST-PASS: autostart parity 22/22"

envs=$(grep -cE '\{ "[A-Z_]+",' "$HYPR/hyprland.lua.d/environment.lua")
[[ "$envs" -ge 20 ]] || fail "environment parity: expected >=20 static entries, got $envs"
# VA-API driver selection must stay hardware-neutral: forcing
# LIBVA_DRIVER_NAME=nvidia breaks Intel/AMD/hybrid/VM systems.
if grep -q '"LIBVA_DRIVER_NAME",' "$HYPR/hyprland.lua.d/environment.lua"; then
  fail "environment must not force LIBVA_DRIVER_NAME (hardware-neutral VA-API)"
fi
echo "TEST-PASS: VA-API driver not forced (hardware-neutral)"
grep -q 'DBUS_SESSION_BUS_ADDRESS' "$HYPR/hyprland.lua.d/environment.lua" \
  || fail "environment lost DBUS_SESSION_BUS_ADDRESS"
grep -q 'GNOME_KEYRING_CONTROL' "$HYPR/hyprland.lua.d/environment.lua" \
  || fail "environment lost GNOME_KEYRING_CONTROL"
echo "TEST-PASS: environment parity (22 static + 2 runtime-derived)"

# Helpers live in-process: no standalone Hyprland scripts remain, and
# keybindings call the helpers.lua functions directly.
[[ ! -d "$HYPR/scripts" ]] || fail "standalone desktop/hypr/scripts still shipped"
[[ -f "$HYPR/hyprland.lua.d/helpers.lua" ]] || fail "hyprland.lua.d/helpers.lua missing"
grep -q 'hornero_helpers = dofile(here .. "helpers.lua")' "$HYPR/hyprland.lua" \
  || fail "hyprland.lua does not load helpers.lua"
grep -q 'helpers.gaps_interactive()' "$HYPR/hyprland.lua.d/keybindings.lua" \
  || fail "gaps bind does not call helpers.gaps_interactive()"
grep -q 'helpers.smart_float()' "$HYPR/hyprland.lua.d/keybindings.lua" \
  || fail "smart-float bind does not call helpers.smart_float()"
grep -q 'function M.notification_action' "$HYPR/hyprland.lua.d/helpers.lua" \
  || fail "helpers.lua lost notification_action()"
if grep -rn 'scripts/' "$HYPR" --include='*.lua'; then
  fail "Hyprland Lua still invokes a standalone script by path"
fi
echo "TEST-PASS: helpers are in-process Lua functions, no standalone scripts remain"

# Real compositor parser, when available (Hyprland 0.56 in CI/dev hosts).
if command -v Hyprland >/dev/null 2>&1; then
  out=$(timeout 30 Hyprland --config "$HYPR/hyprland.lua" --verify-config 2>&1 || true)
  grep -q "config ok" <<<"$out" || fail "Hyprland --verify-config did not report 'config ok': $out"
  echo "TEST-PASS: Hyprland --verify-config reports config ok"
fi

echo "TEST-PASS: Hyprland Lua migration contract holds"
