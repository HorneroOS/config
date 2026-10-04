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

# --- hornero-hyprlock-theme: hornero-only inputs -> canonical writes ----------------
mkdir -p "$XDG_CACHE_HOME/hornero/smart-colors" "$XDG_STATE_HOME/hornero/wallpaper"
echo "/tmp/hx-probe-wallpaper.png" >"$XDG_STATE_HOME/hornero/wallpaper/path"
touch /tmp/hx-probe-wallpaper.png
cat >"$XDG_CACHE_HOME/hornero/smart-colors/scheme.json" <<'EOF'
{"mode": "dark", "colours": {"primary": "#ffb0ca", "surface": "#191114", "onSurface": "#efdfe2", "background": "#191114", "onSurfaceVariant": "#d5c2c6", "outline": "#9e8c91", "secondary": "#e6b8c2", "error": "#ff5370"}}
EOF

"$REPO_ROOT/bin/hornero-hyprlock-theme" --wallpaper /tmp/hx-probe-wallpaper.png >/dev/null \
  || fail "hyprlock-theme exits 0 on hornero-only inputs"
[[ -f $XDG_CACHE_HOME/hornero/smart-colors/colors-hyprlock.conf ]] \
  || fail "hyprlock-theme writes canonical hornero output"
grep -q "ffb0ca" "$XDG_CACHE_HOME/hornero/smart-colors/colors-hyprlock.conf" \
  || fail "hyprlock-theme output carries scheme colours"
# The generated override IS the effective lock-screen content, and it
# carries no date label by design: hyprlock renders $TIME12/$USER but
# neither $DATE (literal) nor cmd[] output (empty across four VM-proven
# formats), so a date label would be dead UI.
if grep -q 'text = \$DATE\|text = cmd' \
  "$XDG_CACHE_HOME/hornero/smart-colors/colors-hyprlock.conf"; then
  fail "generated hyprlock override carries a dead date label"
fi
pass "hyprlock-theme carries no dead date label"
[[ -f $XDG_CACHE_HOME/hornero/smart-colors/colors-hyprlock.conf ]] \
  || fail "hyprlock-theme did not write into the Hornero cache"
pass "hyprlock-theme writes into the Hornero cache"
# hornero-appearance doctor reports the generated output. Only the
# hyprlock line is asserted: whole-doctor health depends on unrelated
# host state (wallpaper pointer, materialyoucolor python).
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
