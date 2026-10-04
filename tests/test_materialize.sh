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
check ".config/niri/config.kdl"
grep -q 'spawn-at-startup "horneroctl" "shell" "start" "--yes"' "$TMP_HOME/.config/niri/config.kdl"
grep -q 'Mod+Shift+B.*layoutPicker' "$TMP_HOME/.config/niri/config.kdl"
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
check ".local/lib/hornero/gtk-theme-manager.sh"
check ".local/lib/hornero/wallpaper-resolver.sh"
check ".local/lib/hornero/easy-options/easyoptions.sh"
check ".local/bin/hornero-gtk-theme"
check ".local/bin/hornero-hyprlock-theme"
check ".local/bin/hornero-appearance"
# hornero-launcher, hornero-power-menu, hornero-clipboard are gone: launcher,
# session drawer and clipboard history are horneroctl verbs now.
check ".local/bin/hornero-night-mode"
check ".local/bin/hornero-wallpaper-set"
check ".local/bin/hornero-wallpaper-current"

# theme packs: every curated pack in profiles/themes lands in canonical
# hornero/* (rows 1+8). The expected count is derived from the repo so
# adding a theme pack never breaks this test.
expected=$(find "$REPO_ROOT/profiles/themes" -maxdepth 2 -name theme.json | wc -l)
count=$(find "$TMP_HOME/.local/share/hornero/themes" -maxdepth 2 -name theme.json | wc -l)
if [[ $count -eq $expected ]]; then
  echo "TEST-PASS: $count theme packs materialized to hornero/themes"
else
  echo "TEST-FAIL: expected $expected theme packs in hornero/themes, found $count" >&2
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
diff -r "$REPO_ROOT/profiles/shell-presets" "$TMP_HOME/.local/share/hornero/shell-presets" >/dev/null 2>&1 \
  && echo "TEST-PASS: pinned shell presets materialize byte-exactly" \
  || { echo "TEST-FAIL: materialized shell preset catalogue differs" >&2; exit 1; }
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
    && [[ -d "$herm_dest/.local/share/hornero/themes" ]]; then
    echo "TEST-PASS: hermetic dest holds canonical catalogue"
  else
    echo "TEST-FAIL: hermetic dest missing canonical catalogue" >&2
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
for f in "$TMP_HOME/.local/bin/hornero-gtk-theme" "$TMP_HOME/.local/bin/hornero-hyprlock-theme" \
         "$TMP_HOME/.local/bin/hornero-appearance" \
         "$TMP_HOME/.local/bin/hornero-night-mode" \
         "$TMP_HOME/.local/bin/hornero-wallpaper-set" "$TMP_HOME/.local/bin/hornero-wallpaper-current" \
         "$TMP_HOME/.config/hypr/scripts/gaps-interactive.sh"; do
  if [[ -x $f ]]; then
    echo "TEST-PASS: executable $f"
  else
    echo "TEST-FAIL: not executable: $f" >&2
    exit 1
  fi
done

# notification daemons that would steal org.freedesktop.Notifications
for u in dunst mako swaync; do
  link="$TMP_HOME/.config/systemd/user/$u.service"
  if [[ -L $link && $(readlink "$link") == /dev/null ]]; then
    echo "TEST-PASS: $u.service masked"
  else
    echo "TEST-FAIL: $u.service not masked" >&2
    exit 1
  fi
done
for svc in org.knopwob.dunst.service fr.emersion.mako.service org.erikreider.swaync.service; do
  f="$TMP_HOME/.local/share/dbus-1/services/$svc"
  if grep -q '^Exec=/bin/false' "$f" 2>/dev/null; then
    echo "TEST-PASS: D-Bus activation shadowed: $svc"
  else
    echo "TEST-FAIL: D-Bus activation not shadowed: $svc" >&2
    exit 1
  fi
done
# a user-authored unit is kept, and re-running stays idempotent
printf '[Service]\nExecStart=/bin/true\n' > "$TMP_HOME/.config/systemd/user/dunst.service.tmp"
rm "$TMP_HOME/.config/systemd/user/dunst.service"
mv "$TMP_HOME/.config/systemd/user/dunst.service.tmp" "$TMP_HOME/.config/systemd/user/dunst.service"
bash "$REPO_ROOT/scripts/materialize.sh" --dest "$TMP_HOME" >/dev/null
if [[ ! -L "$TMP_HOME/.config/systemd/user/dunst.service" ]]; then
  echo "TEST-PASS: user-authored dunst.service kept"
else
  echo "TEST-FAIL: user-authored dunst.service replaced" >&2
  exit 1
fi

# repo-level validation still green
"$REPO_ROOT/scripts/validate.sh"
echo "test_materialize.sh: ALL GREEN"
