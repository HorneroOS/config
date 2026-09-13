#!/usr/bin/env bash
# test_migrate.sh - one-shot dots/* -> hornero/* migrator semantics.
# Hermetic: everything runs under temp HOME/XDG dirs; ambient env restored.
# Covers: --dry-run previews without writing, --yes migrates the 7
# Hornero-owned rows, copy-if-canonical-absent (never overwrites),
# idempotent re-runs, non-destructive (dots/* intact), explicit NOTs
# (snapshots, shell.json, wallpaper binaries, imagecache, personal files),
# back-compat symlink same-file skip, machine-readable output shape.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MIG="$REPO_ROOT/lib/dots/migrate-to-hornero.sh"

OLD_HOME="${HOME:-}"
OLD_DATA="${XDG_DATA_HOME:-}"
OLD_STATE="${XDG_STATE_HOME:-}"
OLD_CACHE="${XDG_CACHE_HOME:-}"
restore_env() {
  if [[ -z $OLD_HOME ]]; then unset HOME; else export HOME="$OLD_HOME"; fi
  if [[ -z $OLD_DATA ]]; then unset XDG_DATA_HOME; else export XDG_DATA_HOME="$OLD_DATA"; fi
  if [[ -z $OLD_STATE ]]; then unset XDG_STATE_HOME; else export XDG_STATE_HOME="$OLD_STATE"; fi
  if [[ -z $OLD_CACHE ]]; then unset XDG_CACHE_HOME; else export XDG_CACHE_HOME="$OLD_CACHE"; fi
}

PROBE1="$(mktemp -d)"; PROBE2="$(mktemp -d)"; PROBE3="$(mktemp -d)"
cleanup() { restore_env; rm -rf "$PROBE1" "$PROBE2" "$PROBE3"; }
trap cleanup EXIT

pass() { echo "TEST-PASS: $1"; }
fail() { echo "TEST-FAIL: $1" >&2; exit 1; }

# --- 1. empty home: dry-run previews skips, writes nothing --------------------
export HOME="$PROBE1"
unset XDG_DATA_HOME XDG_STATE_HOME XDG_CACHE_HOME
OUT="$("$MIG" --dry-run)"
echo "$OUT" | grep -q '^MIGRATE-SUMMARY mode=dry-run copied=0 ' \
  || fail "empty dry-run summary: $OUT"
echo "$OUT" | grep -q 'reason=dots-absent' \
  || fail "empty dry-run reports dots-absent"
[[ -z $(find "$PROBE1" -mindepth 1 2>/dev/null || true) ]] \
  || fail "dry-run wrote into empty home"
pass "empty dry-run previews skips, writes nothing"

# --- 2. populated legacy state -------------------------------------------------
export HOME="$PROBE2" XDG_DATA_HOME="$PROBE2/.local/share" \
  XDG_STATE_HOME="$PROBE2/.local/state" XDG_CACHE_HOME="$PROBE2/.cache"
mkdir -p "$PROBE2/.local/share/dots/themes/custom-pack" \
  "$PROBE2/.local/share/dots/shell-presets" \
  "$PROBE2/.local/state/dots/scheme" "$PROBE2/.local/state/dots/wallpaper" \
  "$PROBE2/.cache/dots/smart-colors" "$PROBE2/.cache/dots/snapshots/config_123" \
  "$PROBE2/.local/share/dots/wallpapers" "$PROBE2/.cache/dots/imagecache/notifs" \
  "$PROBE2/.config/hornero"
echo '{"id":"custom-pack","name":"Custom"}' > "$PROBE2/.local/share/dots/themes/custom-pack/theme.json"
echo '{"layout":"x"}' > "$PROBE2/.local/share/dots/shell-presets/mine.json"
echo "mine" > "$PROBE2/.local/state/dots/current-shell-preset"
echo '{"mode":"dark"}' > "$PROBE2/.cache/dots/smart-colors/scheme.json"
echo '{"mode":"dark","gtkColorScheme":"follow"}' > "$PROBE2/.local/state/dots/scheme/state.json"
echo "/pics/w.png" > "$PROBE2/.local/state/dots/wallpaper/path"
echo '{"notifs":[]}' > "$PROBE2/.local/state/dots/notifs.json"
echo "recycle-me" > "$PROBE2/.cache/dots/snapshots/config_123/data"
echo '{"user":"x"}' > "$PROBE2/.config/hornero/shell.json"
echo "BIN" > "$PROBE2/.local/share/dots/wallpapers/w.png"
echo "IMG" > "$PROBE2/.cache/dots/imagecache/notifs/a.png"
echo "secret-personal" > "$PROBE2/.local/state/dots/my-diary.txt"

DRY="$("$MIG" --dry-run)"
echo "$DRY" | grep -q 'domain=theme-pack .* action=copy' || fail "dry-run previews theme-pack"
echo "$DRY" | grep -q 'domain=notifs .* action=copy' || fail "dry-run previews notifs"
echo "$DRY" | grep -q 'domain=snapshots .* reason=excluded-snapshots-regenerable' \
  || fail "dry-run excludes snapshots with reason"
[[ ! -e "$PROBE2/.local/share/hornero" && ! -e "$PROBE2/.local/state/hornero" ]] \
  || fail "dry-run wrote canonical files"
pass "dry-run previews per-row actions, writes nothing"

YES="$("$MIG" --yes)"
echo "$YES" | grep -q '^MIGRATE-SUMMARY mode=migrate copied=7 ' \
  || fail "migrate summary: $(echo "$YES" | grep SUMMARY || true)"
for f in ".local/share/hornero/themes/custom-pack/theme.json" \
         ".local/share/hornero/shell-presets/mine.json" \
         ".local/state/hornero/current-shell-preset" \
         ".cache/hornero/smart-colors/scheme.json" \
         ".local/state/hornero/scheme/state.json" \
         ".local/state/hornero/wallpaper/path" \
         ".local/state/hornero/notifs.json"; do
  [[ -f "$PROBE2/$f" ]] || fail "not migrated: $f"
done
pass "migrates the 7 Hornero-owned rows"
cmp -s "$PROBE2/.local/share/dots/themes/custom-pack/theme.json" \
       "$PROBE2/.local/share/hornero/themes/custom-pack/theme.json" \
  || fail "migrated theme bytes differ"
[[ ! -e "$PROBE2/.cache/hornero/snapshots" ]] || fail "snapshots migrated (must skip)"
[[ ! -e "$PROBE2/.local/share/hornero/wallpapers" ]] || fail "wallpapers migrated (must skip)"
[[ ! -e "$PROBE2/.cache/hornero/imagecache" ]] || fail "imagecache migrated (must skip)"
[[ -f "$PROBE2/.local/state/dots/my-diary.txt" ]] || fail "personal file touched"
[[ "$(cat "$PROBE2/.config/hornero/shell.json")" == '{"user":"x"}' ]] \
  || fail "shell.json touched (already canonical)"
pass "NOTs skipped: snapshots, shell.json, wallpapers, imagecache, personal files"

# --- 3. idempotent re-run, canonical never overwritten --------------------------
YES2="$("$MIG" --yes)"
echo "$YES2" | grep -q 'copied=0 ' || fail "rerun summary: $(echo "$YES2" | grep SUMMARY || true)"
echo "$YES2" | grep -q 'reason=canonical-exists' || fail "rerun reports canonical-exists"
echo "tampered" > "$PROBE2/.local/state/hornero/current-shell-preset"
"$MIG" --yes >/dev/null
[[ "$(cat "$PROBE2/.local/state/hornero/current-shell-preset")" == "tampered" ]] \
  || fail "canonical state overwritten (must win)"
pass "idempotent re-runs, copy-if-canonical-absent"

# --- 4. back-compat symlink: dots/themes -> ../hornero/themes -------------------
export HOME="$PROBE3" XDG_DATA_HOME="$PROBE3/d" \
  XDG_STATE_HOME="$PROBE3/s" XDG_CACHE_HOME="$PROBE3/c"
mkdir -p "$PROBE3/d/hornero/themes/p1" "$PROBE3/d/dots" "$PROBE3/s" "$PROBE3/c"
echo '{"id":"p1"}' > "$PROBE3/d/hornero/themes/p1/theme.json"
ln -s ../hornero/themes "$PROBE3/d/dots/themes"
OUT3="$("$MIG" --dry-run)"
echo "$OUT3" | grep -q 'domain=theme-pack .* reason=same-file' \
  || fail "symlink same-file skip: $OUT3"
pass "back-compat symlink skipped as same-file"

# --- 5. machine-readable shape ----------------------------------------------------
echo "$YES" | grep -vE '^MIGRATE-(ROW|SUMMARY) ' | grep -q . \
  && fail "non-machine-readable line in output"
pass "machine-readable MIGRATE-ROW/SUMMARY lines"

echo "test_migrate.sh: ALL GREEN"
