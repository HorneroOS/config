#!/usr/bin/env bash
# Validate shipped Kitty configs with Kitty's own parser, without the real HOME.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v kitty >/dev/null 2>&1; then
  echo "KITTY-CONFIG-SKIP: kitty is not installed" >&2
  exit 0
fi

TEMP_HOME="$(mktemp -d)"
trap 'rm -rf "$TEMP_HOME"' EXIT
mkdir -p "$TEMP_HOME/.cache/hornero/smart-colors"
# The generated color include is intentionally optional in normal use. Supply
# an empty fixture so this test can reject every other missing include.
: > "$TEMP_HOME/.cache/hornero/smart-colors/colors-kitty.conf"

export HOME="$TEMP_HOME"
export XDG_CONFIG_HOME="$TEMP_HOME/.config"
export KITTY_CONFIG_DIRECTORY="$REPO_ROOT/desktop/kitty"

kitty +runpy 'exec(open(sys.argv[1], encoding="utf-8").read(), {})' \
  "$REPO_ROOT/tests/validate_kitty_config.py" \
  "$REPO_ROOT"/desktop/kitty/*.conf
