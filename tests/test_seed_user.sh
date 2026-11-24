#!/usr/bin/env bash
# Packaged user seeding (seed-user.sh): missing-only, idempotent, and
# never overwrites a file the user already owns.
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
script="$repo_root/scripts/seed-user.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

skel="$work/skel"
xdg="$work/xdg"
share="$work/share"
dest="$work/home"

mkdir -p "$skel/.config/hypr/hyprland.lua.d" "$skel/.config/environment.d" \
  "$xdg/git" "$share/bin" "$dest/.config/hypr" "$dest/.local/bin"

printf 'factory entrypoint\n' >"$skel/.config/hypr/hyprland.lua"
printf 'factory module\n' >"$skel/.config/hypr/hyprland.lua.d/autostart.lua"
printf 'PATH line\n' >"$skel/.config/environment.d/50-hornero-path.conf"
printf 'factory zshrc\n' >"$skel/.zshrc"
printf '[user]\n\tname =\n' >"$xdg/git/config"
printf '#!/bin/sh\nexit 0\n' >"$share/bin/hornero-fake-helper"
chmod 755 "$share/bin/hornero-fake-helper"

# Pre-existing user files that must survive byte-for-byte.
printf 'MY OWN HYPRLAND\n' >"$dest/.config/hypr/hyprland.lua"
printf 'my own helper\n' >"$dest/.local/bin/hornero-fake-helper"

export HORNERO_SEED_SKEL="$skel" HORNERO_SEED_XDG="$xdg" HORNERO_SEED_SHARE="$share"

# Dry run writes nothing.
bash "$script" --dest "$dest" --dry-run >/dev/null
[[ ! -e $dest/.config/environment.d/50-hornero-path.conf ]] || {
  echo "FAIL: dry run wrote files" >&2; exit 1; }

bash "$script" --dest "$dest"

grep -qx 'MY OWN HYPRLAND' "$dest/.config/hypr/hyprland.lua" || {
  echo "FAIL: user hyprland.lua was overwritten" >&2; exit 1; }
grep -qx 'factory module' "$dest/.config/hypr/hyprland.lua.d/autostart.lua" || {
  echo "FAIL: missing hypr module not seeded" >&2; exit 1; }
grep -qx 'PATH line' "$dest/.config/environment.d/50-hornero-path.conf" || {
  echo "FAIL: environment.d not seeded" >&2; exit 1; }
grep -qx 'factory zshrc' "$dest/.zshrc" || { echo "FAIL: .zshrc not seeded" >&2; exit 1; }
[[ -f $dest/.config/git/config ]] || { echo "FAIL: git config not seeded" >&2; exit 1; }
grep -qx 'my own helper' "$dest/.local/bin/hornero-fake-helper" || {
  echo "FAIL: existing helper replaced by symlink" >&2; exit 1; }
[[ ! -L $dest/.local/bin/hornero-fake-helper ]] || {
  echo "FAIL: existing helper became a symlink" >&2; exit 1; }

# Second run is a no-op (idempotent) and still preserves user files.
bash "$script" --dest "$dest" | grep -q 'seeded 0 file' || {
  echo "FAIL: second run was not a no-op" >&2; exit 1; }
grep -qx 'MY OWN HYPRLAND' "$dest/.config/hypr/hyprland.lua" || {
  echo "FAIL: second run modified user file" >&2; exit 1; }

# System destinations and symlinked destinations are refused.
if bash "$script" --dest /etc 2>/dev/null; then
  echo "FAIL: system destination accepted" >&2; exit 1
fi
ln -s "$dest" "$work/home-link"
if bash "$script" --dest "$work/home-link" 2>/dev/null; then
  echo "FAIL: symlinked destination accepted" >&2; exit 1
fi

# Helper symlink is created when the slot is free.
rm "$dest/.local/bin/hornero-fake-helper"
bash "$script" --dest "$dest" >/dev/null
[[ $(readlink "$dest/.local/bin/hornero-fake-helper") == "$share/bin/hornero-fake-helper" ]] || {
  echo "FAIL: helper symlink missing/wrong" >&2; exit 1; }

echo "PASS: packaged user seeding is missing-only, idempotent and guarded"
