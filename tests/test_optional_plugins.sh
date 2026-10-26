#!/usr/bin/env bash
# test_optional_plugins.sh - plugin-only config must not break a plugin-less session.
#
# Hyprland plugins (hyprpm) are optional. In the Lua-only config their
# settings live exclusively in hyprland.lua.d/plugins.lua, their binds
# dispatch through exec (a missing plugin dispatcher fails silently,
# never a config-error banner), and no other Lua module may reference
# the plugin. This is the Lua equivalent of the legacy
# `# hyprlang noerror` guard. Found by Hornero QA (smoke/no-config-errors).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LUA_DIR="$REPO_ROOT/desktop/hypr/hyprland.lua.d"
fail=0

# Plugin settings are confined to plugins.lua.
if grep -l 'scrolloverview' "$LUA_DIR"/*.lua | grep -v '/plugins.lua$' | grep -v '/keybindings.lua$' >/dev/null; then
  echo "FAIL: scrolloverview settings outside plugins.lua/keybindings.lua" >&2
  fail=1
fi
# The overview binds must go through exec_cmd so a missing plugin
# dispatcher cannot raise a config error.
if ! grep -q 'exec_cmd("hyprctl dispatch scrolloverview:overview, toggle")' "$LUA_DIR/keybindings.lua"; then
  echo "FAIL: scrolloverview overview bind is not an exec_cmd bind" >&2
  fail=1
fi
# plugins.lua must parse.
if command -v luac >/dev/null 2>&1 && ! luac -p "$LUA_DIR/plugins.lua"; then
  echo "FAIL: plugins.lua does not parse" >&2
  fail=1
fi

if [[ "$fail" -ne 0 ]]; then
  exit 1
fi
echo "ok: optional-plugin Lua config is isolated and banner-safe"
