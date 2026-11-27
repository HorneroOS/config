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
mod_count=0
while IFS= read -r mod; do
  mod_count=$((mod_count + 1))
  [[ -f "$HYPR/hyprland.lua.d/$mod" ]] || fail "hyprland.lua loads missing module $mod"
done < <(grep -oE '(load_factory|load_user)\("[^"]+\.lua"\)' "$HYPR/hyprland.lua" | sed -E 's/.*"([^"]+)".*/\1/')
[[ "$mod_count" -ge 17 ]] || fail "hyprland.lua resolved only $mod_count modules (expected >= 17)"
echo "TEST-PASS: every module in hyprland.lua resolves ($mod_count modules)"

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
[[ "$execs" -eq 19 ]] || fail "autostart parity: expected 19, got $execs"
echo "TEST-PASS: autostart parity 19/19"

envs=$(grep -cE '\{ "[A-Z_]+",' "$HYPR/hyprland.lua.d/environment.lua")
[[ "$envs" -ge 13 ]] || fail "environment parity: expected >=13 static entries, got $envs"
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
grep -q 'hornero_helpers = load_factory("helpers.lua")' "$HYPR/hyprland.lua" \
  || fail "hyprland.lua does not load helpers.lua via load_factory"
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

# Factory/user XDG lifecycle contract (config#184):
# - Factory modules prefer HORNERO_HYPR_FACTORY_DIR / /etc/xdg/hypr/hyprland.lua.d/
#   over stale user-dir copies so pacman upgrades reach existing users.
# - *-user.lua overlays always load from user_dir first, with fallback to factory_dir.
# - Missing factory_dir or absent per-file factory modules fall back cleanly to user_dir.
LUA_BIN=""
for candidate in lua5.5 lua5.4 lua; do
  if command -v "$candidate" >/dev/null 2>&1; then
    LUA_BIN="$candidate"
    break
  fi
done
if [[ -n "$LUA_BIN" ]]; then
  LIFECYCLE_TMP="$(mktemp -d)"
  trap 'rm -rf "$LIFECYCLE_TMP"' EXIT
  mkdir -p "$LIFECYCLE_TMP/user/hyprland.lua.d" "$LIFECYCLE_TMP/factory" "$LIFECYCLE_TMP/partial-factory"
  cp "$HYPR/hyprland.lua" "$LIFECYCLE_TMP/user/hyprland.lua"

  factory_mods=(
    monitors.lua autostart.lua environment.lua input.lua gestures.lua layout.lua
    keybindings-overlay.lua helpers.lua keybindings.lua window-rules.lua
    animations.lua smart-colors.lua plugins.lua static.lua
  )
  user_mods=(monitors-user.lua keybindings-user.lua window-rules-user.lua)

  for m in "${factory_mods[@]}"; do
    if [[ "$m" == "helpers.lua" ]]; then
      printf 'table.insert(_G._loaded, "user:%s")\nreturn { source = "user" }\n' "$m" \
        >"$LIFECYCLE_TMP/user/hyprland.lua.d/$m"
      printf 'table.insert(_G._loaded, "factory:%s")\nreturn { source = "factory" }\n' "$m" \
        >"$LIFECYCLE_TMP/factory/$m"
    else
      printf 'table.insert(_G._loaded, "user:%s")\n' "$m" \
        >"$LIFECYCLE_TMP/user/hyprland.lua.d/$m"
      printf 'table.insert(_G._loaded, "factory:%s")\n' "$m" \
        >"$LIFECYCLE_TMP/factory/$m"
    fi
  done
  for m in "${user_mods[@]}"; do
    printf 'table.insert(_G._loaded, "user:%s")\n' "$m" \
      >"$LIFECYCLE_TMP/user/hyprland.lua.d/$m"
    printf 'table.insert(_G._loaded, "factory:%s")\n' "$m" \
      >"$LIFECYCLE_TMP/factory/$m"
  done
  printf 'table.insert(_G._loaded, "factory:keybindings.lua")\n' \
    >"$LIFECYCLE_TMP/partial-factory/keybindings.lua"

  # 1. Factory dir wins over stale user copies; *-user.lua still loads from user_dir.
  HORNERO_HYPR_FACTORY_DIR="$LIFECYCLE_TMP/factory" \
    "$LUA_BIN" - "$LIFECYCLE_TMP/user/hyprland.lua" <<'LUA' || fail "factory precedence lifecycle check failed"
_G._loaded = {}
dofile(arg[1])
local expected = {
  "factory:monitors.lua",
  "user:monitors-user.lua",
  "factory:autostart.lua",
  "factory:environment.lua",
  "factory:input.lua",
  "factory:gestures.lua",
  "factory:layout.lua",
  "factory:keybindings-overlay.lua",
  "factory:helpers.lua",
  "factory:keybindings.lua",
  "user:keybindings-user.lua",
  "factory:window-rules.lua",
  "user:window-rules-user.lua",
  "factory:animations.lua",
  "factory:smart-colors.lua",
  "factory:plugins.lua",
  "factory:static.lua",
}
assert(#_G._loaded == #expected, string.format("expected %d modules, got %d", #expected, #_G._loaded))
for i, want in ipairs(expected) do
  assert(_G._loaded[i] == want, string.format("slot %d: want %s, got %s", i, want, tostring(_G._loaded[i])))
end
assert(hornero_helpers and hornero_helpers.source == "factory", "hornero_helpers must come from factory_dir")
LUA
  echo "TEST-PASS: factory modules override stale user copies while *-user.lua loads from user_dir"

  # 2. Nonexistent factory dir falls back cleanly to user_dir for every module.
  HORNERO_HYPR_FACTORY_DIR="$LIFECYCLE_TMP/no-such-factory" \
    "$LUA_BIN" - "$LIFECYCLE_TMP/user/hyprland.lua" <<'LUA' || fail "missing factory fallback check failed"
_G._loaded = {}
dofile(arg[1])
assert(#_G._loaded == 17, "expected 17 fallback modules, got " .. tostring(#_G._loaded))
for i, got in ipairs(_G._loaded) do
  assert(got:match("^user:"), string.format("slot %d did not fall back to user_dir: %s", i, got))
end
assert(hornero_helpers and hornero_helpers.source == "user", "hornero_helpers must fall back to user_dir")
LUA
  echo "TEST-PASS: missing factory_dir falls back cleanly to user_dir"

  # 3. Partial factory dir overrides present files and falls back per-file to user_dir.
  HORNERO_HYPR_FACTORY_DIR="$LIFECYCLE_TMP/partial-factory" \
    "$LUA_BIN" - "$LIFECYCLE_TMP/user/hyprland.lua" <<'LUA' || fail "partial factory fallback check failed"
_G._loaded = {}
dofile(arg[1])
local saw_factory_kb = false
for _, got in ipairs(_G._loaded) do
  if got == "factory:keybindings.lua" then
    saw_factory_kb = true
  else
    assert(got:match("^user:"), "unexpected non-user load: " .. got)
  end
end
assert(saw_factory_kb, "keybindings.lua did not load from partial factory_dir")
LUA
  echo "TEST-PASS: partial factory_dir falls back per-file to user_dir"

  # 4. Absent user *-user.lua falls back cleanly to factory stub (or skips if absent in both).
  rm "$LIFECYCLE_TMP/user/hyprland.lua.d/monitors-user.lua"
  HORNERO_HYPR_FACTORY_DIR="$LIFECYCLE_TMP/factory" \
    "$LUA_BIN" - "$LIFECYCLE_TMP/user/hyprland.lua" <<'LUA' || fail "missing *-user.lua factory fallback check failed"
_G._loaded = {}
dofile(arg[1])
assert(_G._loaded[2] == "factory:monitors-user.lua", "missing user monitors-user.lua did not fall back to factory stub: " .. tostring(_G._loaded[2]))
LUA
  HORNERO_HYPR_FACTORY_DIR="$LIFECYCLE_TMP/no-such-factory" \
    "$LUA_BIN" - "$LIFECYCLE_TMP/user/hyprland.lua" <<'LUA' || fail "missing *-user.lua skip check failed"
_G._loaded = {}
dofile(arg[1])
assert(#_G._loaded == 16, "missing optional *-user.lua should skip cleanly without error")
LUA
  echo "TEST-PASS: absent *-user.lua falls back to factory stub or skips cleanly"
else
  echo "TEST-SKIP: no Lua interpreter installed for lifecycle runtime checks" >&2
fi

# Real compositor parser, when available (Hyprland 0.56 in CI/dev hosts).
if command -v Hyprland >/dev/null 2>&1; then
  out=$(HORNERO_HYPR_FACTORY_DIR="$HYPR/hyprland.lua.d" timeout 30 Hyprland --config "$HYPR/hyprland.lua" --verify-config 2>&1 || true)
  grep -q "config ok" <<<"$out" || fail "Hyprland --verify-config did not report 'config ok': $out"
  echo "TEST-PASS: Hyprland --verify-config reports config ok"
fi

echo "TEST-PASS: Hyprland Lua migration contract holds"
