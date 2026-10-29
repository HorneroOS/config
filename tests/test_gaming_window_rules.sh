#!/usr/bin/env bash
# Gaming window-rule parity: exactly one Steam rule per compositor, no
# duplicate gaming config, no per-game config sprawl (hornero#328).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
hypr_count=$(grep -c 'name = "steam-games"' "$ROOT/desktop/hypr/hyprland.lua.d/window-rules.lua")
niri_count=$(grep -c 'app-id=r#"^steam_app' "$ROOT/desktop/niri/config.kdl")
[ "$hypr_count" = "1" ] || { echo "Hyprland steam-games rules: $hypr_count (want 1)"; exit 1; }
[ "$niri_count" = "1" ] || { echo "Niri steam_app rules: $niri_count (want 1)"; exit 1; }
if grep -rn 'steam_app' "$ROOT/desktop/hypr/hyprland.lua.d/" | grep -v 'window-rules.lua' ; then
  echo "duplicate steam rule outside window-rules.lua"; exit 1
fi
echo "gaming window rules: OK"
