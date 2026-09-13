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
check ".local/bin/dots-launcher"
check ".local/bin/dots-power-menu"
check ".local/bin/dots-clipboard"
check ".local/bin/dots-night-mode"
check ".local/bin/dots-wallpaper-set"
check ".local/bin/dots-wallpaper-current"

# theme packs: exactly the 12 curated packs in canonical hornero/* (rows 1+8)
count=$(find "$TMP_HOME/.local/share/hornero/themes" -maxdepth 2 -name theme.json | wc -l)
if [[ $count -eq 12 ]]; then
  echo "TEST-PASS: 12 theme packs materialized to hornero/themes"
else
  echo "TEST-FAIL: expected 12 theme packs in hornero/themes, found $count" >&2
  exit 1
fi
if [[ -f "$TMP_HOME/.local/share/hornero/themes/wallpapers.manifest.json" ]]; then
  echo "TEST-PASS: theme manifest in hornero/themes"
else
  echo "TEST-FAIL: missing hornero/themes/wallpapers.manifest.json" >&2
  exit 1
fi
if [[ -d "$TMP_HOME/.local/share/hornero/shell-presets" ]]; then
  echo "TEST-PASS: canonical hornero/shell-presets exists"
else
  echo "TEST-FAIL: missing hornero/shell-presets" >&2
  exit 1
fi
# factory default parses, but materialize never writes a user-root shell.json
# (path-contract row 6: user file owned by the shell runtime; packaging is
# the only writer of the system default /etc/xdg/hornero/shell.json)
if python3 -c "import json; json.load(open('$REPO_ROOT/shell/shell.default.json'))" 2>/dev/null; then
  echo "TEST-PASS: shell factory default parses"
else
  echo "TEST-FAIL: shell/shell.default.json does not parse" >&2
  exit 1
fi
if [[ -e "$TMP_HOME/.config/hornero/shell.json" ]]; then
  echo "TEST-FAIL: materialize wrote user-root hornero/shell.json (must not)" >&2
  exit 1
fi
echo "TEST-PASS: no user-root hornero/shell.json materialized"
# back-compat dots/* symlinks -> hornero/* (reversible, relative for hermeticity)
for pair in "dots/themes:hornero/themes" "dots/shell-presets:hornero/shell-presets"; do
  link_name="${pair%%:*}"
  canon_name="${pair##*:}"
  link="$TMP_HOME/.local/share/$link_name"
  if [[ -L $link ]]; then
    target="$(readlink "$link")"
    if [[ $target == "../hornero/$(basename "$canon_name")" ]]; then
      echo "TEST-PASS: back-compat symlink $link_name -> $target"
    else
      echo "TEST-FAIL: $link_name points at $target, want ../hornero/$(basename "$canon_name")" >&2
      exit 1
    fi
  else
    echo "TEST-FAIL: $link_name is not a symlink" >&2
    exit 1
  fi
done
# dots fallback still resolves the 12 packs through the symlink
compat_count=$(find -L "$TMP_HOME/.local/share/dots/themes" -maxdepth 2 -name theme.json | wc -l)
if [[ $compat_count -eq 12 ]]; then
  echo "TEST-PASS: dots/themes fallback resolves 12 packs"
else
  echo "TEST-FAIL: dots fallback resolves $compat_count packs, want 12" >&2
  exit 1
fi
# --dest hermeticity: a temp dest distinct from HOME must not leak into ambient XDG
herm_xdg="$(mktemp -d)"
herm_dest="$(mktemp -d)"
if HOME="$TMP_HOME" XDG_DATA_HOME="$herm_xdg" XDG_CONFIG_HOME="$herm_xdg/config" \
    XDG_STATE_HOME="$herm_xdg/state" XDG_CACHE_HOME="$herm_xdg/cache" \
    "$REPO_ROOT/scripts/materialize.sh" --dest "$herm_dest" >/dev/null; then
  if [[ -z $(find "$herm_xdg" -mindepth 1 2>/dev/null || true) ]]; then
    echo "TEST-PASS: --dest hermetic with ambient XDG set"
  else
    echo "TEST-FAIL: --dest leaked into ambient XDG ($herm_xdg)" >&2
    find "$herm_xdg" -mindepth 1 >&2 || true
    rm -rf "$herm_xdg" "$herm_dest"
    exit 1
  fi
  if [[ -f "$herm_dest/.local/share/hornero/themes/wallpapers.manifest.json" ]] \
    && [[ -L "$herm_dest/.local/share/dots/themes" ]]; then
    echo "TEST-PASS: hermetic dest holds canonical + symlink"
  else
    echo "TEST-FAIL: hermetic dest missing canonical/symlink" >&2
    rm -rf "$herm_xdg" "$herm_dest"
    exit 1
  fi
else
  echo "TEST-FAIL: hermetic rerun failed" >&2
  rm -rf "$herm_xdg" "$herm_dest"
  exit 1
fi
rm -rf "$herm_xdg" "$herm_dest"

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
         "$TMP_HOME/.local/bin/dots-launcher" "$TMP_HOME/.local/bin/dots-power-menu" \
         "$TMP_HOME/.local/bin/dots-clipboard" "$TMP_HOME/.local/bin/dots-night-mode" \
         "$TMP_HOME/.local/bin/dots-wallpaper-set" "$TMP_HOME/.local/bin/dots-wallpaper-current" \
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
