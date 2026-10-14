#!/usr/bin/env bash
# Validate the shipped Ghostty config and fallback theme with Ghostty itself.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GHOSTTY_BIN="${GHOSTTY_BIN:-ghostty}"

if ! command -v "$GHOSTTY_BIN" >/dev/null 2>&1; then
  echo "GHOSTTY-CONFIG-SKIP: $GHOSTTY_BIN is not installed" >&2
  exit 0
fi

CONFIG="$REPO_ROOT/desktop/ghostty/config.ghostty"
THEME="$REPO_ROOT/desktop/ghostty/themes/Hornero Dynamic"
if [[ ! -s "$CONFIG" || ! -s "$THEME" ]]; then
  echo "GHOSTTY-CONFIG-FAIL: shipped config or fallback theme is missing" >&2
  exit 1
fi

# Keep Ghostty from reading or writing the operator's configuration. Point its
# XDG config lookup at the shipped tree so the config resolves Hornero Dynamic.
TEMP_HOME="$(mktemp -d)"
trap 'rm -rf "$TEMP_HOME"' EXIT
export HOME="$TEMP_HOME"
export XDG_CONFIG_HOME="$REPO_ROOT/desktop"

"$GHOSTTY_BIN" +validate-config --config-file="$CONFIG"
echo "GHOSTTY-CONFIG-PASS: $CONFIG"
"$GHOSTTY_BIN" +validate-config --config-file="$THEME"
echo "GHOSTTY-CONFIG-PASS: $THEME"
