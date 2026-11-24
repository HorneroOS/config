#!/usr/bin/env bash
# seed-user.sh — packaged, missing-only user seeding for the
# install-on-existing-Arch path (AUR hornero-config on a machine whose
# account predates the package, so /etc/skel never reached $HOME).
#
# Contract (deliberately the safe subset of scripts/materialize.sh):
#   seed-user.sh --dest DIR [--dry-run]
# - Copies ONLY files that do not exist at the destination. Nothing a
#   user already owns is overwritten, replaced or deleted.
# - Sources are the packaged system locations (/etc/skel, /etc/xdg,
#   /usr/share/hornero), overridable for tests via HORNERO_SEED_SKEL,
#   HORNERO_SEED_XDG and HORNERO_SEED_SHARE.
# - Helpers are exposed as symlinks under .local/bin pointing at the
#   packaged /usr/share/hornero/bin copies, so package upgrades flow
#   through without re-seeding.
# - Full curated-defaults application (with overwrites) remains the
#   job of scripts/materialize.sh from a config checkout; this script
#   is the non-destructive adoption step horneroctl can always run.
set -euo pipefail

SKEL="${HORNERO_SEED_SKEL:-/etc/skel}"
XDG_SYS="${HORNERO_SEED_XDG:-/etc/xdg}"
SHARE="${HORNERO_SEED_SHARE:-/usr/share/hornero}"
DEST=""
DRY_RUN=0
seeded=0
skipped=0
conflicts=0

die() { printf 'seed-user: %s\n' "$*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dest) DEST=${2:?--dest requires a directory}; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help)
      printf 'Usage: seed-user.sh --dest DIR [--dry-run]\n'
      exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

[[ -n $DEST ]] || die "--dest is required"
case "$DEST" in
  /|/etc|/etc/*|/usr|/usr/*|/var|/var/*|/boot|/boot/*)
    die "refusing to seed into system directory: $DEST" ;;
esac
[[ ! -L $DEST ]] || die "destination is a symlink: $DEST (refusing to follow)"
[[ -d $SKEL ]] || die "skel source not found: $SKEL (is hornero-config installed?)"

log() { printf '[seed-user] %s\n' "$*"; }

seed_file() {
  local src=$1 dst=$2 mode=${3:-0644}
  [[ -e $src || -L $src ]] || return 0
  if [[ -e $dst || -L $dst ]]; then
    skipped=$((skipped + 1))
    return 0
  fi
  if [[ $DRY_RUN -eq 1 ]]; then
    log "would seed $dst"
    seeded=$((seeded + 1))
    return 0
  fi
  mkdir -p "$(dirname "$dst")"
  if [[ -L $src ]]; then
    cp -P "$src" "$dst"
  else
    cp -n "$src" "$dst"
    chmod "$mode" "$dst"
  fi
  seeded=$((seeded + 1))
}

seed_tree() {
  local src_root=$1 dst_root=$2 f rel
  [[ -d $src_root ]] || return 0
  while IFS= read -r -d '' f; do
    rel=${f#"$src_root"/}
    seed_file "$f" "$dst_root/$rel"
  done < <(find "$src_root" \( -type f -o -type l \) -print0 | sort -z)
}

seed_symlink() {
  local target=$1 link=$2
  if [[ -L $link ]]; then
    if [[ $(readlink "$link") == "$target" ]]; then
      skipped=$((skipped + 1))
    else
      conflicts=$((conflicts + 1))
      log "conflict (kept yours): $link -> $(readlink "$link")"
    fi
    return 0
  fi
  if [[ -e $link ]]; then
    conflicts=$((conflicts + 1))
    log "conflict (kept yours): $link already exists"
    return 0
  fi
  if [[ $DRY_RUN -eq 1 ]]; then
    log "would link $link -> $target"
    seeded=$((seeded + 1))
    return 0
  fi
  mkdir -p "$(dirname "$link")"
  ln -s "$target" "$link"
  seeded=$((seeded + 1))
}

# Compositor + terminal configs: whole trees, missing files only. An
# existing hand-written Hyprland config keeps every byte it owns; the
# user then opts into factory modules via horneroctl config refresh-hypr.
seed_tree "$SKEL/.config/hypr" "$DEST/.config/hypr"
seed_tree "$SKEL/.config/ghostty" "$DEST/.config/ghostty"
seed_tree "$SKEL/.config/btop" "$DEST/.config/btop"
seed_tree "$SKEL/.config/cava" "$DEST/.config/cava"
seed_tree "$SKEL/.config/environment.d" "$DEST/.config/environment.d"

# Shell baseline only when the account has none of its own.
seed_file "$SKEL/.zshrc" "$DEST/.zshrc"

# Git identity template ships as a system XDG default; seed the user
# copy only when absent so personal identity edits have a home.
seed_file "$XDG_SYS/git/config" "$DEST/.config/git/config"

# Packaged helpers become available on the user's PATH via symlinks.
if [[ -d $SHARE/bin ]]; then
  for helper in "$SHARE"/bin/hornero-*; do
    [[ -f $helper ]] || continue
    seed_symlink "$helper" "$DEST/.local/bin/$(basename "$helper")"
  done
fi

if [[ $DRY_RUN -eq 1 ]]; then
  log "dry run: would seed $seeded file(s), $skipped already present, $conflicts conflict(s) kept"
else
  log "seeded $seeded file(s), $skipped already present, $conflicts conflict(s) kept untouched"
fi
log "existing files were never overwritten; re-running is safe (idempotent)"
