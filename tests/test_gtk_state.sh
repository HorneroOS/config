#!/usr/bin/env bash
# test_gtk_state.sh - the GTK layer must never invent shell `mode`.
# hornero-gtk-theme persists its own gtkColorScheme policy in
# scheme/state.json, but `mode` belongs to the applied theme (the live
# Hornero Signal scheme). A defaulted mode=dark went stale on the first
# write and poisoned every later light apply (e.g. hornero-signal-day). Fails (nonzero exit) on any violation.
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
ln -s "$REPO_ROOT/lib/hornero" "$T_HOME/.local/lib/hornero"

STATE="$T_HOME/.local/state/hornero/scheme/state.json"

# A color-scheme write persists the policy but must not invent shell mode.
HOME="$T_HOME" bash "$REPO_ROOT/bin/hornero-gtk-theme" color-scheme prefer-dark >/dev/null 2>&1 \
  || fail "hornero-gtk-theme color-scheme prefer-dark exits nonzero"
[[ -f $STATE ]] || fail "color-scheme wrote no state file ($STATE)"
grep -q '"gtkColorScheme"' "$STATE" || fail "state file lost gtkColorScheme: $(cat "$STATE")"
pass "color-scheme persists gtkColorScheme policy"
if grep -q '"mode"' "$STATE"; then
  fail "GTK layer invented shell mode: $(cat "$STATE")"
fi
pass "color-scheme writes no shell mode"

# A second write with the opposite policy keeps policy fresh, mode absent.
HOME="$T_HOME" bash "$REPO_ROOT/bin/hornero-gtk-theme" color-scheme prefer-light >/dev/null 2>&1 \
  || fail "hornero-gtk-theme color-scheme prefer-light exits nonzero"
grep -q '"prefer-light"' "$STATE" || fail "policy did not update: $(cat "$STATE")"
if grep -q '"mode"' "$STATE"; then
  fail "GTK layer invented shell mode on rewrite: $(cat "$STATE")"
fi
pass "policy updates across writes, mode stays absent"

# `ensure` (first session): applies once when no GTK theme was ever chosen,
# never when one was, and always leaves a marker so later choices stick.
BIN="$T_HOME/bin"; mkdir -p "$BIN"
printf '#!/bin/sh\nprintf "%%s" "${FAKE_DCONF_GTK_THEME:-}"\n' >"$BIN/dconf"; chmod +x "$BIN/dconf"
MARK="$T_HOME/.local/state/hornero/gtk-theme-initialised"
out="$(HOME="$T_HOME" PATH="$BIN:$PATH" bash "$REPO_ROOT/bin/hornero-gtk-theme" ensure 2>&1 || true)"
grep -q "Following the applied Hornero Signal theme" <<<"$out" || fail "ensure did not apply on an unset GTK theme: $out"
[[ -f $MARK ]] || fail "ensure left no first-session marker"
pass "ensure applies the Signal GTK theme once on an unset theme and records it"
out="$(HOME="$T_HOME" PATH="$BIN:$PATH" bash "$REPO_ROOT/bin/hornero-gtk-theme" ensure 2>&1 || true)"
[[ -z $out ]] || fail "ensure acted twice: $out"
pass "ensure is a no-op once initialised"
rm -f "$MARK"
out="$(HOME="$T_HOME" PATH="$BIN:$PATH" FAKE_DCONF_GTK_THEME="'Some-User-Theme'" bash "$REPO_ROOT/bin/hornero-gtk-theme" ensure 2>&1 || true)"
[[ -z $out ]] || fail "ensure overrode a chosen GTK theme: $out"
[[ -f $MARK ]] || fail "ensure left no marker when a theme was already chosen"
pass "ensure never overrides a GTK theme that was already chosen"

echo "test_gtk_state.sh: ALL GREEN"
