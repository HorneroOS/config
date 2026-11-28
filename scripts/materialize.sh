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
  CACHE_HOME="${XDG_CACHE_HOME:-$DEST/.cache}"
else
  CONFIG_HOME="$DEST/.config"
  DATA_HOME="$DEST/.local/share"
  CACHE_HOME="$DEST/.cache"
fi
LIB_DIR="$DEST/.local/lib/hornero"
BIN_DIR="$DEST/.local/bin"

install_dir() {
  local src="$1" dest="$2"
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "would install dir $src -> $dest"
    return
  fi
  mkdir -p "$dest"
  if [[ "${3:-}" == "preserve" ]]; then
    # Seed only missing files: re-running materialize into a real HOME
    # must not overwrite user-edited copies (new files still arrive).
    cp -rn "$REPO_ROOT/$src/." "$dest/"
  else
    # Copy managed files while never overwriting existing *-user.* override files.
    local entry rel target
    while IFS= read -r -d '' entry; do
      rel="${entry#"$REPO_ROOT/$src"/}"
      target="$dest/$rel"
      if [[ "$(basename "$target")" == *-user.* && -e "$target" ]]; then
        continue
      fi
      mkdir -p "$(dirname "$target")"
      cp "$entry" "$target"
    done < <(find "$REPO_ROOT/$src" -type f -print0 | sort -z)
  fi
  find "$dest" -type d -exec chmod 755 {} +
  find "$dest" -type f -exec chmod 644 {} +
}

install_file() {
  local src="$1" dest="$2" mode="${3:-}"
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "would install file $src -> $dest"
    return
  fi
  if [[ "$mode" == "preserve" && -e "$dest" ]]; then
    return
  fi
  mkdir -p "$(dirname "$dest")"
  cp "$REPO_ROOT/$src" "$dest"
  chmod 644 "$dest"
}

# --- desktop defaults -> ~/.config -------------------------------------------
install_dir "desktop/hypr" "$CONFIG_HOME/hypr"
# preserve: user-editable compositor and terminal configs; re-running
# materialize into a real HOME seeds missing files without clobbering edits.
install_dir "desktop/niri" "$CONFIG_HOME/niri" preserve
install_file "desktop/xdg-desktop-portal/niri-portals.conf" "$CONFIG_HOME/xdg-desktop-portal/niri-portals.conf"
install_file "desktop/xdg-desktop-portal/hyprland-portals.conf" "$CONFIG_HOME/xdg-desktop-portal/hyprland-portals.conf"
install_dir "desktop/kitty" "$CONFIG_HOME/kitty" preserve
install_file "desktop/xfce4/helpers.rc" "$CONFIG_HOME/xfce4/helpers.rc"
# preserve: never overwrite a user-edited qt6ct/qt5ct.conf; horneroctl owns the
# palette keys (docs/QT_DECISION.md).
install_dir "desktop/qt6ct" "$CONFIG_HOME/qt6ct" preserve
install_dir "desktop/qt5ct" "$CONFIG_HOME/qt5ct" preserve
install_file "desktop/gtk/settings.ini" "$CONFIG_HOME/gtk-3.0/settings.ini"
install_file "desktop/gtk/settings.ini" "$CONFIG_HOME/gtk-4.0/settings.ini"
# Factory default is hornero-signal-night (see profiles/factory.json):
# pre-place its libadwaita recoloring so GTK4 apps render Signal accents with
# no apply run.
install_file "desktop/gtk-theme/Hornero-Signal/gtk-4.0/recolor.css" "$CONFIG_HOME/gtk-4.0/gtk.css"
install_file "desktop/gtk/gtkrc-2.0" "$DEST/.gtkrc-2.0"
install_dir "desktop/fontconfig" "$CONFIG_HOME/fontconfig"
install_dir "desktop/fastfetch" "$CONFIG_HOME/fastfetch"
install_dir "desktop/btop" "$CONFIG_HOME/btop"
install_dir "desktop/cava" "$CONFIG_HOME/cava"
install_dir "desktop/thunar" "$CONFIG_HOME/Thunar"
install_file "desktop/copyq/copyq.conf" "$CONFIG_HOME/copyq/copyq.conf" preserve
install_dir "desktop/alacritty" "$CONFIG_HOME/alacritty"
install_dir "desktop/ghostty" "$CONFIG_HOME/ghostty"
# Studio audio policy: Balanced (no override) is active; Low Latency and
# Advanced are opt-in templates outside pipewire.conf.d (docs/STUDIO-AUDIO.md).
install_dir "desktop/pipewire" "$CONFIG_HOME/pipewire"
# Bluetooth: WirePlumber policy is user-effective config; the BlueZ
# main.conf is a factory template staged as data only (BlueZ reads
# /etc/bluetooth/main.conf, owned by the bluez package — never write it).
install_dir "desktop/wireplumber" "$CONFIG_HOME/wireplumber" preserve
install_dir "desktop/bluetooth" "$CONFIG_HOME/hornero/bluetooth" preserve
install_dir "desktop/studio-audio" "$CONFIG_HOME/hornero/studio-audio"
install_dir "desktop/studio-presets" "$CONFIG_HOME/hornero/studio-presets"
install_dir "desktop/studio-storage" "$CONFIG_HOME/hornero/studio-storage"
# Hornero Apps trust policy (preserve user edits after initial seeding).
install_file "desktop/hornero-apps/policy.json" "$CONFIG_HOME/hornero/apps/policy.json" preserve
# Systemd user resource isolation slices (app-models.slice, app-agents.slice)
# and local LLM drop-ins (ollama, llama-server@).
install_dir "desktop/systemd/user" "$CONFIG_HOME/systemd/user"

# --- factory shell baseline (seeded once, never overwritten) -------------
if [[ $DRY_RUN -eq 1 ]]; then
  echo "would seed shell/zsh/zshrc -> $DEST/.zshrc (when absent)"
elif [[ ! -e "$DEST/.zshrc" ]]; then
  cp "$REPO_ROOT/shell/zsh/zshrc" "$DEST/.zshrc"
  chmod 644 "$DEST/.zshrc"
fi
install_file "desktop/environmentd/10-hornero-editor.conf" "$CONFIG_HOME/environment.d/10-hornero-editor.conf"
install_file "desktop/environmentd/20-hornero-session.conf" "$CONFIG_HOME/environment.d/20-hornero-session.conf"
install_file "desktop/xdg/mimeapps.list" "$CONFIG_HOME/mimeapps.list"
install_file "desktop/xdg/user-dirs.dirs" "$CONFIG_HOME/user-dirs.dirs"

# --- XDG defaults --------------------------------------------------------------
install_dir "xdg/handlr" "$CONFIG_HOME/handlr"
install_dir "xdg/git" "$CONFIG_HOME/git"

# --- implementation libs + CLI adapters ---------------------------------------
install_dir "lib/hornero" "$LIB_DIR"
if [[ $DRY_RUN -eq 1 ]]; then
  echo "would symlink bin/hornero-* -> $BIN_DIR/"
else
  mkdir -p "$BIN_DIR"
  for cli in "$REPO_ROOT"/bin/hornero-*; do
    chmod 755 "$cli"
    ln -sfn "$cli" "$BIN_DIR/$(basename "$cli")"
  done
fi

# --- theme packs (recipes only, no binaries) -> canonical hornero/* -----------
# Rows 1+8: installed theme.json recipes + wallpapers.manifest.json.
install_dir "profiles/themes" "$DATA_HOME/hornero/themes"

# --- Hornero Chromatic app templates (rendered by horneroctl) -------------------
# Manifests + *.tmpl for GTK 3/4, qt5ct/qt6ct, kitty, foot, fuzzel, neovim, zed.
install_dir "share/hornero/chromatic" "$DATA_HOME/hornero/chromatic"

# --- Hornero Apps desktop entries -> ~/.local/share/applications ----------------
install_dir "share/applications" "$DATA_HOME/applications"

# --- machine-readable shortcut manifest -> canonical hornero/* --------------
# Generated from the authoritative keybindings.lua (never hand-edited):
# the Welcome Center resolves curated shortcut ids against this file.
if [[ $DRY_RUN -eq 1 ]]; then
  echo "would generate shortcuts -> $DATA_HOME/hornero/shortcuts.json"
else
  mkdir -p "$DATA_HOME/hornero"
  python3 "$REPO_ROOT/scripts/generate-shortcuts.py" --root "$REPO_ROOT" \
    --out "$DATA_HOME/hornero/shortcuts.json"
fi

# --- brand identity (vector sources only, no binaries) -> canonical hornero/ --
# assets/brand owns .../hornero/brand exclusively: logos, wordmark, app and
# system icons, favicon, fastfetch art source and procedural wallpaper SVG.
# PNG wallpapers/icons are rendered on the target machine via
# scripts/render-brand-assets.sh and never enter the stage.
install_dir "assets/brand" "$DATA_HOME/hornero/brand"

# --- Hornero Signal wallpaper rasters (rendered, never vendored) -----------------
# The apply chain resolves wallpaperDir/defaultWallpaper rasters, so fresh
# systems must be able to apply official themes with no user photos yet.
# Best-effort: without rsvg-convert the SVGs still ship and apply fails
# later with a clear error naming the missing file.
if [[ $DRY_RUN -eq 1 ]]; then
  echo "would render flagship wallpapers -> $DATA_HOME/hornero/wallpapers"
elif command -v rsvg-convert >/dev/null 2>&1; then
  XDG_CACHE_HOME="$CACHE_HOME" bash "$REPO_ROOT/scripts/render-brand-assets.sh" --wallpapers \
    "$DATA_HOME/hornero/wallpapers" >/dev/null
else
  echo "warn: rsvg-convert missing, skipping flagship wallpaper render" >&2
fi

# --- shipped wallpaper collection -------------------------------------------
# assets/wallpapers/<wallpaperDir>/ mirrors the install tree 1:1 (theme dirs
# plus category dirs the Shell picker scans recursively), so clean
# package-only installs have every theme default available. The catalogue of
# record is profiles/themes/wallpaper-collection.json (validated by
# scripts/validate-wallpapers.py); any file not listed there fails CI.
while IFS= read -r -d '' entry; do
  rel="${entry#"$REPO_ROOT"/assets/wallpapers/}"
  target="$DATA_HOME/hornero/wallpapers/$rel"
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "would install wallpaper $entry -> $target"
  else
    mkdir -p "$(dirname "$target")"
    install -m644 "$entry" "$target"
  fi
done < <(find "$REPO_ROOT/assets/wallpapers" -type f -print0 | sort -z)

# --- Hornero GTK theme (real theme trees, standard lookup path) ----------------
# desktop/gtk-theme/Hornero-* (generated by scripts/generate-appearance.py)
# -> ~/.local/share/themes/ so GTK 3 and GTK 4 discover them without extra
# env. Dev-only sources (src/, gallery.py, README.md) are excluded: only the
# generated theme trees may flow through here (no file owned twice — the recipe
# JSONs above stay the sole owners of .../hornero/themes).
if [[ $DRY_RUN -eq 1 ]]; then
  echo "would install desktop/gtk-theme/Hornero-* -> $DATA_HOME/themes/"
else
  mkdir -p "$DATA_HOME/themes"
  for tree in "$REPO_ROOT"/desktop/gtk-theme/Hornero-*/; do
    tree="$(basename "$tree")"
    rm -rf "${DATA_HOME:?}/themes/$tree"
    mkdir -p "$DATA_HOME/themes/$tree"
    cp -r "$REPO_ROOT/desktop/gtk-theme/$tree/." "$DATA_HOME/themes/$tree/"
  done
  find "$DATA_HOME/themes" -maxdepth 1 -name 'Hornero-*' -type d \
    -exec chmod 755 {} +
  find "$DATA_HOME/themes" -path '*/Hornero-*/*' -type f \
    -exec chmod 644 {} +
fi
# --- factory default record -> canonical hornero/* -----------------------------
# profiles/factory.json declares the fresh-boot default (Hornero Signal
# Night, Cockpit layout);
# static data, no runtime fetch (see docs/FACTORY_DEFAULTS.md).
install_file "profiles/factory.json" "$DATA_HOME/hornero/factory.json"
# --- shell layout presets catalogue -> canonical hornero/* --------------------
# Layout data is synced from the pinned HorneroOS/shell source; materialize
# the canonical user-readable copy. The package also installs this catalogue
# read-only under /usr/share/hornero/shell-presets.
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
# --- the Hornero shell owns org.freedesktop.Notifications --------------------
# Stand-alone daemons (dunst, mako, swaync) claim the same bus name through
# D-Bus activation of their systemd user units; when one wins the race (a
# notify-send while the shell restarts) notifications bypass the shell for
# the rest of the session. Mask their user units (symlink to /dev/null, the
# systemd convention). A user-authored unit file is never replaced.
# Reversible: rm ~/.config/systemd/user/<daemon>.service
mask_user_unit() {
  local unit="$CONFIG_HOME/systemd/user/$1"
  if [[ -e $unit && ! -L $unit ]]; then
    echo "keeping user-authored $unit (not masked)"
    return
  fi
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "would mask user unit $1 -> /dev/null"
    return
  fi
  mkdir -p "$(dirname "$unit")"
  ln -sfn /dev/null "$unit"
}
for unit in dunst.service mako.service swaync.service; do
  mask_user_unit "$unit"
done

# Some daemons D-Bus-activate without going through systemd (Arch mako:
# fr.emersion.mako.service has Exec=/usr/bin/mako, no SystemdService), so a
# masked unit alone does not stop them. A user-level D-Bus service file with
# the same name takes precedence over the system one: shadow each with a
# no-op. A user-authored file of that name is kept.
# Reversible: rm ~/.local/share/dbus-1/services/<name>.service
shadow_dbus_service() {
  local svc="$DATA_HOME/dbus-1/services/$1"
  if [[ -e $svc ]] && ! grep -q '^# hornero: notification daemon shadow' "$svc"; then
    echo "keeping user-authored $svc (not shadowed)"
    return
  fi
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "would shadow D-Bus service $1"
    return
  fi
  mkdir -p "$(dirname "$svc")"
  printf '%s\n' '# hornero: notification daemon shadow (the shell owns org.freedesktop.Notifications)' \
    '[D-BUS Service]' 'Name=org.freedesktop.Notifications' 'Exec=/bin/false' >"$svc"
  chmod 644 "$svc"
}
for svc in org.knopwob.dunst.service fr.emersion.mako.service org.erikreider.swaync.service; do
  shadow_dbus_service "$svc"
done

echo "materialized HorneroOS config into $DEST"
