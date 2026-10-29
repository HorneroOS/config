#!/usr/bin/env bash
# Gaming window-rule parity: exactly one Steam rule per compositor, no
# duplicate gaming config, no per-game config sprawl (hornero#328).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Count rules by match target, independent of quoting syntax, and count
# every rule inside the canonical files too (a second rule in the same
# file is still a duplicate).
hypr_count=$(grep -c 'class = ".*steam_app' "$ROOT/desktop/hypr/hyprland.lua.d/window-rules.lua")
niri_count=$(grep -Ec 'app-id=(r#)?"[^"]*steam_app' "$ROOT/desktop/niri/config.kdl")
[ "$hypr_count" = "1" ] || { echo "Hyprland steam_app rules: $hypr_count (want 1)"; exit 1; }
[ "$niri_count" = "1" ] || { echo "Niri steam_app rules: $niri_count (want 1)"; exit 1; }
if grep -rn 'steam_app' "$ROOT/desktop/hypr/hyprland.lua.d/" | grep -v 'window-rules.lua' ; then
  echo "duplicate steam rule outside window-rules.lua"; exit 1
fi
if grep -rn 'steam' "$ROOT/desktop/niri/" | grep -v 'config.kdl' ; then
  echo "duplicate steam rule outside config.kdl"; exit 1
fi
echo "gaming window rules: OK"
