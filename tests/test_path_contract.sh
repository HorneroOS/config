#!/usr/bin/env bash
# test_path_contract.sh - runtime XDG path conformance for Hornero utilities.
# Hermetic: everything runs under temp XDG dirs and temp HOME.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROBE="$(mktemp -d)"
trap 'rm -rf "$PROBE"' EXIT

export XDG_CACHE_HOME="$PROBE/cache"
export XDG_STATE_HOME="$PROBE/state"
export XDG_DATA_HOME="$PROBE/data"
export HOME="$PROBE/home"
mkdir -p "$XDG_CACHE_HOME" "$XDG_STATE_HOME" "$XDG_DATA_HOME" "$HOME"

pass() { echo "TEST-PASS: $1"; }
fail() { echo "TEST-FAIL: $1" >&2; exit 1; }

# --- hornero-hyprlock-theme: live Signal scheme -> canonical cache write --------
mkdir -p "$HOME/.local/lib" "$XDG_STATE_HOME/hornero/wallpaper"
ln -s "$REPO_ROOT/lib/hornero" "$HOME/.local/lib/hornero"
echo "/tmp/hx-probe-wallpaper.png" >"$XDG_STATE_HOME/hornero/wallpaper/path"
touch /tmp/hx-probe-wallpaper.png
python3 "$REPO_ROOT/lib/hornero/signal_theme.py" scheme \
  "$REPO_ROOT/profiles/themes/hornero-signal-night/theme.json" >/dev/null \
  || fail "signal_theme.py scheme writes the live scheme"
[[ -f $XDG_STATE_HOME/hornero/signal/scheme.json ]] \
  || fail "live scheme is not at \$XDG_STATE_HOME/hornero/signal/scheme.json"
pass "live Signal scheme lands at the contract path"

"$REPO_ROOT/bin/hornero-hyprlock-theme" >/dev/null \
  || fail "hyprlock-theme exits 0 on the live Signal scheme"
OUT="$XDG_CACHE_HOME/hornero/smart-colors/colors-hyprlock.conf"
[[ -f $OUT ]] || fail "hyprlock-theme writes canonical hornero output"
grep -q '^\$hs_signal = rgba(f2ac52ff)$' "$OUT" \
  || fail "hyprlock-theme output carries the scheme's signal role"
# The sourced override holds variables only; widgets (and the deliberate
# absence of a dead $DATE/cmd[] label) live in desktop/hypr/hyprlock.conf.
if grep -q '{' "$OUT"; then
  fail "hyprlock override declares widgets (must be variables only)"
fi
if grep -q 'text = \$DATE\|text = cmd' "$REPO_ROOT/desktop/hypr/hyprlock.conf"; then
  fail "hyprlock.conf carries a dead date label"
fi
pass "hyprlock-theme writes variables only into the Hornero cache"
# hornero-appearance doctor reports the generated output. Only the
# hyprlock line is asserted: whole-doctor health depends on host state.
doctor_out="$("$REPO_ROOT/bin/hornero-appearance" doctor 2>/dev/null || true)"
echo "$doctor_out" | grep -q "^hyprlock.conf  : [1-9][0-9]* bytes" \
  || fail "doctor misses the canonical colors-hyprlock.conf: $(echo "$doctor_out" | grep '^hyprlock.conf' || echo '(no line)')"
pass "doctor reads canonical colors-hyprlock.conf"
rm -f /tmp/hx-probe-wallpaper.png

# --- hornero-night-mode: hornero-only state is honoured -----------------------------
echo "enabled" >"$XDG_CACHE_HOME/hornero/night_mode_state"
[[ $("$REPO_ROOT/bin/hornero-night-mode" status-icon) != "󰖙" ]] \
  || fail "night-mode ignores its canonical XDG state"
"$REPO_ROOT/bin/hornero-night-mode" status | grep -q "State file: enabled" \
  || fail "night-mode status does not report its canonical state"
pass "night-mode reads canonical XDG state"

# --- hornero-night-mode: canonical state wins ------------------------------------
echo "disabled" >"$XDG_CACHE_HOME/hornero/night_mode_state"
[[ $("$REPO_ROOT/bin/hornero-night-mode" status-icon) == "󰖙" ]] \
  || fail "night-mode does not prefer canonical state"
pass "night-mode follows canonical XDG state"

echo "test_path_contract.sh: ALL GREEN"
