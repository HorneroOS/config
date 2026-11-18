#!/usr/bin/env bash
# test_keybindings_overlay.sh - managed keybinding overlay contract.
#
# Runs tests/keybindings_overlay_spec.lua against the real loader
# (desktop/hypr/hyprland.lua.d/keybindings-overlay.lua) with a mock hl
# API, then checks the entrypoint loads the overlay before any bind and
# that the generated data file is never shipped.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HYPR="$REPO_ROOT/desktop/hypr"
fail() { echo "TEST-FAIL: $1" >&2; exit 1; }

LUA_BIN=""
for candidate in lua5.5 lua5.4 lua; do
  if command -v "$candidate" >/dev/null 2>&1; then
    LUA_BIN="$candidate"
    break
  fi
done
[[ -n "$LUA_BIN" ]] || fail "no Lua interpreter (lua5.4+) found"

SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT

HORNERO_KEYBINDS_OVERLAY_FILE="$SCRATCH/hornero-keybinds.lua" \
  "$LUA_BIN" "$REPO_ROOT/tests/keybindings_overlay_spec.lua" "$REPO_ROOT" "$SCRATCH"

# The overlay loads after layout.lua and before helpers/keybindings.
order=$(grep -nE 'dofile\(here \.\. "(keybindings-overlay|keybindings|keybindings-user)\.lua"\)|helpers\.lua' "$HYPR/hyprland.lua" | cut -d: -f1 | tr '\n' ' ')
read -r overlay helpers keys user <<<"$order"
[[ -n "${user:-}" && "$overlay" -lt "$helpers" && "$helpers" -lt "$keys" && "$keys" -lt "$user" ]] \
  || fail "hyprland.lua must load keybindings-overlay.lua before helpers.lua and keybindings.lua (lines: $order)"
echo "TEST-PASS: hyprland.lua loads the overlay before any bind"

# The generated data file belongs to the user's session, never the repo.
[[ ! -e "$HYPR/hornero-keybinds.lua" && ! -e "$HYPR/hyprland.lua.d/hornero-keybinds.lua" ]] \
  || fail "generated hornero-keybinds.lua must not be shipped"
echo "TEST-PASS: generated overlay data is not shipped"
