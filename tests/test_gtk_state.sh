#!/usr/bin/env bash
# test_gtk_state.sh - the GTK layer must never invent shell `mode`.
# dots-gtk-theme persists its own gtkColorScheme policy in
# scheme/state.json, but shell `mode` is owned by the shell pipeline
# (`dots-color-scheme sync-state`). A defaulted mode=dark went stale on the
# first write and poisoned every later light apply: `horneroctl
# appearance theme set hornero-light` then correctly refused the split
# state (mode dark vs want light). Fails (nonzero exit) on any violation.
# Usage: tests/test_gtk_state.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

pass() { echo "GTKSTATE-PASS: $1"; }
fail() { echo "GTKSTATE-FAIL: $1" >&2; exit 1; }

# Hermetic HOME (materialized layout): state lands under the temp dir only.
# XDG_* are unset so path resolution cannot escape into the developer's
# real state dirs.
unset XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME XDG_CACHE_HOME
T_HOME="$(mktemp -d)"
trap 'rm -rf "$T_HOME"' EXIT
mkdir -p "$T_HOME/.local/lib" "$T_HOME/.config"
ln -s "$REPO_ROOT/lib/dots" "$T_HOME/.local/lib/dots"

STATE="$T_HOME/.local/state/hornero/scheme/state.json"

# A color-scheme write persists the policy but must not invent shell mode.
HOME="$T_HOME" bash "$REPO_ROOT/bin/dots-gtk-theme" color-scheme prefer-dark >/dev/null 2>&1 \
  || fail "dots-gtk-theme color-scheme prefer-dark exits nonzero"
[[ -f $STATE ]] || fail "color-scheme wrote no state file ($STATE)"
grep -q '"gtkColorScheme"' "$STATE" || fail "state file lost gtkColorScheme: $(cat "$STATE")"
pass "color-scheme persists gtkColorScheme policy"
if grep -q '"mode"' "$STATE"; then
  fail "GTK layer invented shell mode: $(cat "$STATE")"
fi
pass "color-scheme writes no shell mode"

# A second write with the opposite policy keeps policy fresh, mode absent.
HOME="$T_HOME" bash "$REPO_ROOT/bin/dots-gtk-theme" color-scheme prefer-light >/dev/null 2>&1 \
  || fail "dots-gtk-theme color-scheme prefer-light exits nonzero"
grep -q '"prefer-light"' "$STATE" || fail "policy did not update: $(cat "$STATE")"
if grep -q '"mode"' "$STATE"; then
  fail "GTK layer invented shell mode on rewrite: $(cat "$STATE")"
fi
pass "policy updates across writes, mode stays absent"

echo "test_gtk_state.sh: ALL GREEN"
