#!/usr/bin/env bash
# test_materialize.sh - materialize into a temp HOME and validate the result.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_HOME="$(mktemp -d)"
trap 'rm -rf "$TMP_HOME"' EXIT

echo "TEST-HOME: $TMP_HOME"
"$REPO_ROOT/scripts/materialize.sh" --dest "$TMP_HOME"

check() {
  if [[ -e "$TMP_HOME/$1" ]]; then
    echo "TEST-PASS: installed $1"
  else
    echo "TEST-FAIL: missing $1" >&2
    exit 1
  fi
}

check ".config/hypr/hyprland.conf"
check ".config/hypr/hyprland.conf.d/monitors.conf"
check ".config/hypr/hyprland.conf.d/keybindings.conf"
check ".config/hypr/hypridle.conf"
check ".config/hypr/hyprlock.conf"
check ".config/hypr/scripts/gaps-interactive.sh"
check ".config/kitty/kitty.conf"
check ".config/gtk-3.0/settings.ini"
check ".gtkrc-2.0"
check ".config/fontconfig/fonts.conf"
check ".config/fastfetch/config.jsonc"
check ".config/btop/btop.conf"
check ".config/cava/config"
check ".config/Thunar/uca.xml"
check ".config/copyq/copyq.conf"
check ".config/handlr/handlr.toml"
check ".config/git/config"
check ".config/git/ignore"
check ".local/lib/dots/gtk-theme-manager.sh"
check ".local/lib/dots/wallpaper-resolver.sh"
check ".local/lib/dots/easy-options/easyoptions.sh"
check ".local/bin/dots-gtk-theme"
check ".local/bin/dots-hyprlock-theme"
check ".local/bin/dots-theme-selector"
check ".local/bin/dots-appearance"

# theme packs: exactly the 12 curated packs
count=$(find "$TMP_HOME/.local/share/dots/themes" -maxdepth 2 -name theme.json | wc -l)
if [[ $count -eq 12 ]]; then
  echo "TEST-PASS: 12 theme packs materialized"
else
  echo "TEST-FAIL: expected 12 theme packs, found $count" >&2
  exit 1
fi

# installed git config parses and carries no identity
if git config --file "$TMP_HOME/.config/git/config" --list >/dev/null 2>&1; then
  echo "TEST-PASS: installed git config parses"
else
  echo "TEST-FAIL: installed git config does not parse" >&2
  exit 1
fi
if grep -rn -- "^\[user\]" "$TMP_HOME/.config/git/" 2>/dev/null; then
  echo "TEST-FAIL: identity stanza materialized" >&2
  exit 1
fi
echo "TEST-PASS: no identity in installed git config"

# executables survived with +x
for f in "$TMP_HOME/.local/bin/dots-gtk-theme" "$TMP_HOME/.local/bin/dots-hyprlock-theme" \
         "$TMP_HOME/.local/bin/dots-theme-selector" "$TMP_HOME/.local/bin/dots-appearance" \
         "$TMP_HOME/.config/hypr/scripts/gaps-interactive.sh"; do
  if [[ -x $f ]]; then
    echo "TEST-PASS: executable $f"
  else
    echo "TEST-FAIL: not executable: $f" >&2
    exit 1
  fi
done

# repo-level validation still green
"$REPO_ROOT/scripts/validate.sh"
echo "test_materialize.sh: ALL GREEN"
