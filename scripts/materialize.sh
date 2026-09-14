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

# Back-compat symlink dots/* -> hornero/* (reversible: rm the symlink).
# Idempotent: existing correct symlink is kept; stale file/dir is replaced.
# Target is relative (../hornero/<name>) so --dest stays hermetic.
compat_link() {
  local target="$1" link="$2"
  local name
  name="$(basename "$target")"
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "would link $link -> ../hornero/$name"
    return
  fi
  if [[ -L $link ]]; then
    local cur
    cur="$(readlink "$link" || true)"
    if [[ $cur == "$target" || $cur == "../hornero/$name" ]]; then
      return
    fi
    rm -f "$link"
  elif [[ -e $link ]]; then
    rm -rf "$link"
  fi
  mkdir -p "$(dirname "$link")" "$(dirname "$target")"
  ln -sfn "../hornero/$name" "$link"
}

# --- desktop defaults -> ~/.config -------------------------------------------
install_dir "desktop/hypr" "$CONFIG_HOME/hypr"
install_dir "desktop/kitty" "$CONFIG_HOME/kitty"
install_dir "desktop/qt6ct" "$CONFIG_HOME/qt6ct"
install_file "desktop/gtk/settings.ini" "$CONFIG_HOME/gtk-3.0/settings.ini"
install_file "desktop/gtk/settings.ini" "$CONFIG_HOME/gtk-4.0/settings.ini"
# Factory default is hornero-dark (see profiles/factory.json): pre-place its
# libadwaita recoloring so GTK4 apps render flagship accents with no apply run.
install_file "desktop/gtk-theme/Hornero-Dark/gtk-4.0/recolor.css" "$CONFIG_HOME/gtk-4.0/gtk.css"
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

# --- theme packs (recipes only, no binaries) -> canonical hornero/* -----------
# Rows 1+8: installed theme.json recipes + wallpapers.manifest.json.
install_dir "profiles/themes" "$DATA_HOME/hornero/themes"

# --- brand identity (vector sources only, no binaries) -> canonical hornero/ --
# assets/brand owns .../hornero/brand exclusively: logos, wordmark, app and
# system icons, favicon, fastfetch art source and procedural wallpaper SVG.
# PNG wallpapers/icons are rendered on the target machine via
# scripts/render-brand-assets.sh and never enter the stage.
install_dir "assets/brand" "$DATA_HOME/hornero/brand"

# --- Hornero GTK theme (real theme trees, standard lookup path) ----------------
# desktop/gtk-theme/Hornero-{Dark,Light} -> ~/.local/share/themes/ so GTK 3
# and GTK 4 discover them without extra env. Dev-only sources (src/,
# build.sh, gallery.py, README.md) are excluded: only the two theme trees
# plus nothing else may flow through here (no file owned twice — the recipe
# JSONs above stay the sole owners of .../hornero/themes).
if [[ $DRY_RUN -eq 1 ]]; then
  echo "would install desktop/gtk-theme/Hornero-{Dark,Light} -> $DATA_HOME/themes/"
else
  mkdir -p "$DATA_HOME/themes"
  for variant in Dark Light; do
    rm -rf "$DATA_HOME/themes/Hornero-$variant"
    mkdir -p "$DATA_HOME/themes/Hornero-$variant"
    cp -r "$REPO_ROOT/desktop/gtk-theme/Hornero-$variant/." \
      "$DATA_HOME/themes/Hornero-$variant/"
  done
  find "$DATA_HOME/themes/Hornero-Dark" "$DATA_HOME/themes/Hornero-Light" \
    -type d -exec chmod 755 {} +
  find "$DATA_HOME/themes/Hornero-Dark" "$DATA_HOME/themes/Hornero-Light" \
    -type f -exec chmod 644 {} +
fi
# --- factory default record -> canonical hornero/* -----------------------------
# profiles/factory.json declares the fresh-boot default (Hornero Dark);
# static data, no runtime fetch (see docs/FACTORY_DEFAULTS.md).
install_file "profiles/factory.json" "$DATA_HOME/hornero/factory.json"
# --- shell layout presets catalogue -> canonical hornero/* --------------------
# Row 2: no curated source in this repo yet (owner HorneroOS/shell per
# docs/DECISIONS.md); ensure the canonical dir exists for future packs.
if [[ -d "$REPO_ROOT/profiles/shell-presets" ]]; then
  install_dir "profiles/shell-presets" "$DATA_HOME/hornero/shell-presets"
else
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "would ensure dir $DATA_HOME/hornero/shell-presets"
  else
    mkdir -p "$DATA_HOME/hornero/shell-presets"
    chmod 755 "$DATA_HOME/hornero/shell-presets"
  fi
fi
# --- back-compat dots/* symlinks -> hornero/* (symlink strategy) -------------
compat_link "$DATA_HOME/hornero/themes" "$DATA_HOME/dots/themes"
compat_link "$DATA_HOME/hornero/shell-presets" "$DATA_HOME/dots/shell-presets"

# hypr helper scripts must stay executable after the 644 normalization above
if [[ $DRY_RUN -eq 0 ]]; then
  chmod 755 "$CONFIG_HOME"/hypr/scripts/*.sh
fi

echo "materialized HorneroOS config into $DEST"
