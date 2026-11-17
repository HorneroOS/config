#!/usr/bin/env bash
# render-boot-assets.sh - assemble the Hornero Signal boot themes.
# Renders the vector sources in desktop/boot/art with rsvg-convert (no fonts
# needed: text is already outlined) and stages complete theme directories.
# Usage: scripts/render-boot-assets.sh --out DIR
#   DIR/grub/hornero-signal/       GRUB theme (theme.txt, PNGs, pf2 fonts)
#   DIR/plymouth/hornero-signal/   Plymouth script theme
#   DIR/iso/splash.png             800x600 syslinux splash for the live ISO
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$REPO_ROOT/desktop/boot"
OUT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --out) OUT="${2:?--out needs a directory}"; shift 2 ;;
    -h|--help) sed -n '2,9p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "error: unknown argument: $1" >&2; exit 1 ;;
  esac
done
[[ -n $OUT ]] || { echo "error: --out DIR is required" >&2; exit 1; }
command -v rsvg-convert >/dev/null 2>&1 || { echo "error: missing tool: rsvg-convert" >&2; exit 1; }

png() { # png <svg> <dest> [scale]
  rsvg-convert --zoom "${3:-1}" "$SRC/art/$1.svg" -o "$2"
}

# --- GRUB ----------------------------------------------------------------------
G="$OUT/grub/hornero-signal"
mkdir -p "$G"
install -m644 "$SRC/grub/theme.txt" "$G/theme.txt"
install -m644 "$SRC"/grub/fonts/*.pf2 "$G/"
png grub-background "$G/background.png"
rsvg-convert --width 56 --height 56 "$SRC/art/mark.svg" -o "$G/mark.png"
png eyebrow-menu "$G/eyebrow.png"
for part in c n s e w nw ne sw se; do png "select_$part" "$G/select_$part.png"; done

# --- Plymouth ------------------------------------------------------------------
P="$OUT/plymouth/hornero-signal"
mkdir -p "$P"
install -m644 "$SRC/plymouth/hornero-signal.plymouth" "$P/hornero-signal.plymouth"
install -m644 "$SRC/plymouth/hornero-signal.script" "$P/hornero-signal.script"
# Rendered at 2x so the script can scale down on 1080p and up to 4K.
rsvg-convert --width 320 --height 320 "$SRC/art/mark.svg" -o "$P/mark.png"
png eyebrow-boot "$P/eyebrow.png" 2
png eyebrow-passphrase "$P/passphrase.png" 2
png segment-on "$P/segment-on.png" 2
png segment-off "$P/segment-off.png" 2
png bullet "$P/bullet.png" 2

# --- Live ISO (syslinux) -------------------------------------------------------
mkdir -p "$OUT/iso"
png iso-splash "$OUT/iso/splash.png"
echo "boot assets written to $OUT"
