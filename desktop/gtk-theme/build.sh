#!/usr/bin/env bash
# build.sh - copy the hand-structured sources in src/ to the shipped
# Hornero-{Dark,Light,Pampa}/gtk-{3.0,4.0}/gtk.css outputs with a generated header.
# No toolchain: plain cp, so the theme builds anywhere (CI, makepkg).
# Usage: desktop/gtk-theme/build.sh [--check]
#   --check rebuilds into a temp dir and diffs against the tree (test gate).
set -euo pipefail

THEME_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HEADER='/* GENERATED from src/ by desktop/gtk-theme/build.sh — do not hand-edit. */'

build_one() {
  local src="$1" dest="$2"
  {
    printf '%s\n' "$HEADER"
    cat "$src"
  } > "$dest"
}

build_all() {
  local out_root="${1:-$THEME_ROOT}"
  build_one "$THEME_ROOT/src/hornero-dark.css" "$out_root/Hornero-Dark/gtk-3.0/gtk.css"
  build_one "$THEME_ROOT/src/hornero-dark.css" "$out_root/Hornero-Dark/gtk-4.0/gtk.css"
  build_one "$THEME_ROOT/src/hornero-light.css" "$out_root/Hornero-Light/gtk-3.0/gtk.css"
  build_one "$THEME_ROOT/src/hornero-light.css" "$out_root/Hornero-Light/gtk-4.0/gtk.css"
  build_one "$THEME_ROOT/src/pampa.css" "$out_root/Hornero-Pampa/gtk-3.0/gtk.css"
  build_one "$THEME_ROOT/src/pampa.css" "$out_root/Hornero-Pampa/gtk-4.0/gtk.css"
}

if [[ "${1:-}" == "--check" ]]; then
  probe="$(mktemp -d)"
  trap 'rm -rf "$probe"' EXIT
  mkdir -p "$probe"/Hornero-Dark/gtk-3.0 "$probe"/Hornero-Dark/gtk-4.0 \
           "$probe"/Hornero-Light/gtk-3.0 "$probe"/Hornero-Light/gtk-4.0 \
           "$probe"/Hornero-Pampa/gtk-3.0 "$probe"/Hornero-Pampa/gtk-4.0
  build_all "$probe"
  fail=0
  for f in Hornero-Dark/gtk-3.0/gtk.css Hornero-Dark/gtk-4.0/gtk.css \
           Hornero-Light/gtk-3.0/gtk.css Hornero-Light/gtk-4.0/gtk.css \
           Hornero-Pampa/gtk-3.0/gtk.css Hornero-Pampa/gtk-4.0/gtk.css; do
    if cmp -s "$probe/$f" "$THEME_ROOT/$f"; then
      echo "GTKBUILD-PASS: $f in sync with src/"
    else
      echo "GTKBUILD-FAIL: $f differs from src/ (run desktop/gtk-theme/build.sh)" >&2
      fail=1
    fi
  done
  exit "$fail"
fi

build_all "$THEME_ROOT"
echo "built 6 gtk.css outputs from src/"
