#!/usr/bin/env bash
# materialize.sh - install HorneroOS curated defaults into a HOME directory.
# Usage: scripts/materialize.sh [--dest DIR] [--dry-run]
# Defaults to $HOME. Safe to run into an empty temp HOME for testing.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${HOME}"
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dest) DEST="${2:?--dest needs a directory}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) sed -n '2,4p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "error: unknown argument: $1" >&2; exit 1 ;;
  esac
done

# XDG locations are honored only for installs into the real HOME so that
# --dest stays hermetic (a temp HOME must never leak into the real one).
if [[ $DEST == "${HOME}" ]]; then
  CONFIG_HOME="${XDG_CONFIG_HOME:-$DEST/.config}"
  DATA_HOME="${XDG_DATA_HOME:-$DEST/.local/share}"
else
  CONFIG_HOME="$DEST/.config"
  DATA_HOME="$DEST/.local/share"
fi
LIB_DIR="$DEST/.local/lib/dots"
BIN_DIR="$DEST/.local/bin"

install_dir() {
  local src="$1" dest="$2"
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "would install dir $src -> $dest"
    return
  fi
  mkdir -p "$dest"
  cp -r "$REPO_ROOT/$src/." "$dest/"
  find "$dest" -type d -exec chmod 755 {} +
  find "$dest" -type f -exec chmod 644 {} +
}

install_file() {
  local src="$1" dest="$2"
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "would install file $src -> $dest"
    return
  fi
  mkdir -p "$(dirname "$dest")"
  cp "$REPO_ROOT/$src" "$dest"
  chmod 644 "$dest"
}

# --- desktop defaults -> ~/.config -------------------------------------------
install_dir "desktop/hypr" "$CONFIG_HOME/hypr"
install_dir "desktop/kitty" "$CONFIG_HOME/kitty"
install_file "desktop/gtk/settings.ini" "$CONFIG_HOME/gtk-3.0/settings.ini"
install_file "desktop/gtk/gtkrc-2.0" "$DEST/.gtkrc-2.0"
install_dir "desktop/fontconfig" "$CONFIG_HOME/fontconfig"
install_dir "desktop/fastfetch" "$CONFIG_HOME/fastfetch"
install_dir "desktop/btop" "$CONFIG_HOME/btop"
install_dir "desktop/cava" "$CONFIG_HOME/cava"
install_dir "desktop/thunar" "$CONFIG_HOME/Thunar"
install_file "desktop/copyq/copyq.conf" "$CONFIG_HOME/copyq/copyq.conf"

# --- XDG defaults --------------------------------------------------------------
install_dir "xdg/handlr" "$CONFIG_HOME/handlr"
install_dir "xdg/git" "$CONFIG_HOME/git"

# --- implementation libs + CLI adapters ---------------------------------------
install_dir "lib/dots" "$LIB_DIR"
if [[ $DRY_RUN -eq 1 ]]; then
  echo "would install bin/dots-* -> $BIN_DIR/"
else
  mkdir -p "$BIN_DIR"
  for cli in "$REPO_ROOT"/bin/dots-*; do
    cp "$cli" "$BIN_DIR/$(basename "$cli")"
    chmod 755 "$BIN_DIR/$(basename "$cli")"
  done
fi

# --- theme packs (recipes only, no binaries) -----------------------------------
install_dir "profiles/themes" "$DATA_HOME/dots/themes"

# hypr helper scripts must stay executable after the 644 normalization above
if [[ $DRY_RUN -eq 0 ]]; then
  chmod 755 "$CONFIG_HOME"/hypr/scripts/*.sh
fi

echo "materialized HorneroOS config into $DEST"
