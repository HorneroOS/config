#!/usr/bin/env bash
# build.sh - copy the hand-structured sources in src/ to the shipped
# Hornero-*/gtk-{3.0,4.0}/gtk.css outputs with a generated header.
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
  build_one "$THEME_ROOT/src/buenos-aires-nocturno.css" "$out_root/Hornero-Nocturno/gtk-3.0/gtk.css"
  build_one "$THEME_ROOT/src/buenos-aires-nocturno.css" "$out_root/Hornero-Nocturno/gtk-4.0/gtk.css"
  build_one "$THEME_ROOT/src/fin-del-mundo.css" "$out_root/Hornero-FinDelMundo/gtk-3.0/gtk.css"
  build_one "$THEME_ROOT/src/fin-del-mundo.css" "$out_root/Hornero-FinDelMundo/gtk-4.0/gtk.css"
  build_one "$THEME_ROOT/src/ibera.css" "$out_root/Hornero-Ibera/gtk-3.0/gtk.css"
  build_one "$THEME_ROOT/src/ibera.css" "$out_root/Hornero-Ibera/gtk-4.0/gtk.css"
  build_one "$THEME_ROOT/src/iguazu.css" "$out_root/Hornero-Iguazu/gtk-3.0/gtk.css"
  build_one "$THEME_ROOT/src/iguazu.css" "$out_root/Hornero-Iguazu/gtk-4.0/gtk.css"
  build_one "$THEME_ROOT/src/patagonia.css" "$out_root/Hornero-Patagonia/gtk-3.0/gtk.css"
  build_one "$THEME_ROOT/src/patagonia.css" "$out_root/Hornero-Patagonia/gtk-4.0/gtk.css"
  build_one "$THEME_ROOT/src/hornero-199x.css" "$out_root/Hornero-199X/gtk-3.0/gtk.css"
  build_one "$THEME_ROOT/src/hornero-199x.css" "$out_root/Hornero-199X/gtk-4.0/gtk.css"
  build_one "$THEME_ROOT/src/cuyo.css" "$out_root/Hornero-Cuyo/gtk-3.0/gtk.css"
  build_one "$THEME_ROOT/src/cuyo.css" "$out_root/Hornero-Cuyo/gtk-4.0/gtk.css"
  build_one "$THEME_ROOT/src/quebrada.css" "$out_root/Hornero-Quebrada/gtk-3.0/gtk.css"
  build_one "$THEME_ROOT/src/quebrada.css" "$out_root/Hornero-Quebrada/gtk-4.0/gtk.css"
  build_one "$THEME_ROOT/src/sierras.css" "$out_root/Hornero-Sierras/gtk-3.0/gtk.css"
  build_one "$THEME_ROOT/src/sierras.css" "$out_root/Hornero-Sierras/gtk-4.0/gtk.css"
}

if [[ "${1:-}" == "--check" ]]; then
  probe="$(mktemp -d)"
  trap 'rm -rf "$probe"' EXIT
  mkdir -p "$probe"/Hornero-Dark/gtk-3.0 \
           "$probe"/Hornero-Dark/gtk-4.0 \
           "$probe"/Hornero-Light/gtk-3.0 \
           "$probe"/Hornero-Light/gtk-4.0 \
           "$probe"/Hornero-Pampa/gtk-3.0 \
           "$probe"/Hornero-Pampa/gtk-4.0 \
           "$probe"/Hornero-Nocturno/gtk-3.0 \
           "$probe"/Hornero-Nocturno/gtk-4.0 \
           "$probe"/Hornero-FinDelMundo/gtk-3.0 \
           "$probe"/Hornero-FinDelMundo/gtk-4.0 \
           "$probe"/Hornero-Ibera/gtk-3.0 \
           "$probe"/Hornero-Ibera/gtk-4.0 \
           "$probe"/Hornero-Iguazu/gtk-3.0 \
           "$probe"/Hornero-Iguazu/gtk-4.0 \
           "$probe"/Hornero-Patagonia/gtk-3.0 \
           "$probe"/Hornero-Patagonia/gtk-4.0 \
           "$probe"/Hornero-199X/gtk-3.0 \
           "$probe"/Hornero-199X/gtk-4.0 \
           "$probe"/Hornero-Cuyo/gtk-3.0 \
           "$probe"/Hornero-Cuyo/gtk-4.0 \
           "$probe"/Hornero-Quebrada/gtk-3.0 \
           "$probe"/Hornero-Quebrada/gtk-4.0 \
           "$probe"/Hornero-Sierras/gtk-3.0 \
           "$probe"/Hornero-Sierras/gtk-4.0
  build_all "$probe"
  fail=0
  for f in Hornero-Dark/gtk-3.0/gtk.css \
           Hornero-Dark/gtk-4.0/gtk.css \
           Hornero-Light/gtk-3.0/gtk.css \
           Hornero-Light/gtk-4.0/gtk.css \
           Hornero-Pampa/gtk-3.0/gtk.css \
           Hornero-Pampa/gtk-4.0/gtk.css \
           Hornero-Nocturno/gtk-3.0/gtk.css \
           Hornero-Nocturno/gtk-4.0/gtk.css \
           Hornero-FinDelMundo/gtk-3.0/gtk.css \
           Hornero-FinDelMundo/gtk-4.0/gtk.css \
           Hornero-Ibera/gtk-3.0/gtk.css \
           Hornero-Ibera/gtk-4.0/gtk.css \
           Hornero-Iguazu/gtk-3.0/gtk.css \
           Hornero-Iguazu/gtk-4.0/gtk.css \
           Hornero-Patagonia/gtk-3.0/gtk.css \
           Hornero-Patagonia/gtk-4.0/gtk.css \
           Hornero-199X/gtk-3.0/gtk.css \
           Hornero-199X/gtk-4.0/gtk.css \
           Hornero-Cuyo/gtk-3.0/gtk.css \
           Hornero-Cuyo/gtk-4.0/gtk.css \
           Hornero-Quebrada/gtk-3.0/gtk.css \
           Hornero-Quebrada/gtk-4.0/gtk.css \
           Hornero-Sierras/gtk-3.0/gtk.css \
           Hornero-Sierras/gtk-4.0/gtk.css; do
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
echo "built 24 gtk.css outputs from src/"
