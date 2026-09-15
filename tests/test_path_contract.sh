#!/usr/bin/env bash
# test_path_contract.sh - runtime path-contract conformance for bin scripts.
# Canonical hornero/* first, dots/* fallback for reads; writes go to hornero/*.
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

# --- dots-hyprlock-theme: dots-only inputs -> canonical writes ----------------
mkdir -p "$XDG_CACHE_HOME/dots/smart-colors" "$XDG_STATE_HOME/dots/wallpaper"
echo "/tmp/hx-probe-wallpaper.png" >"$XDG_STATE_HOME/dots/wallpaper/path"
touch /tmp/hx-probe-wallpaper.png
cat >"$XDG_CACHE_HOME/dots/smart-colors/scheme.json" <<'EOF'
{"mode": "dark", "colours": {"primary": "#ffb0ca", "surface": "#191114", "onSurface": "#efdfe2", "background": "#191114", "onSurfaceVariant": "#d5c2c6", "outline": "#9e8c91", "secondary": "#e6b8c2", "error": "#ff5370"}}
EOF

"$REPO_ROOT/bin/dots-hyprlock-theme" --wallpaper /tmp/hx-probe-wallpaper.png >/dev/null \
  || fail "hyprlock-theme exits 0 on dots-only inputs"
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
[[ ! -e $XDG_CACHE_HOME/dots/smart-colors/colors-hyprlock.conf ]] \
  || fail "hyprlock-theme wrote to the dots fallback"
pass "hyprlock-theme reads dots fallback, writes canonical hornero"
# dots-appearance doctor reports the canonical output (it used to read the
# never-written dots/* path and always reported 0 bytes). Only the
# hyprlock line is asserted: whole-doctor health depends on unrelated
# host state (wallpaper pointer, materialyoucolor python).
doctor_out="$("$REPO_ROOT/bin/dots-appearance" doctor 2>/dev/null || true)"
echo "$doctor_out" | grep -q "^hyprlock.conf  : [1-9][0-9]* bytes" \
  || fail "doctor misses the canonical colors-hyprlock.conf: $(echo "$doctor_out" | grep '^hyprlock.conf' || echo '(no line)')"
pass "doctor reads canonical colors-hyprlock.conf"
rm -f /tmp/hx-probe-wallpaper.png

# --- dots-night-mode: dots-only state is honoured -----------------------------
echo "enabled" >"$XDG_CACHE_HOME/dots/night_mode_state"
[[ $("$REPO_ROOT/bin/dots-night-mode" status-icon) != "󰖙" ]] \
  || fail "night-mode ignores dots fallback state"
"$REPO_ROOT/bin/dots-night-mode" status | grep -q "State file: enabled" \
  || fail "night-mode status does not report the dots fallback state"
pass "night-mode reads dots fallback state"

# --- dots-night-mode: canonical state wins ------------------------------------
echo "disabled" >"$XDG_CACHE_HOME/hornero/night_mode_state"
[[ $("$REPO_ROOT/bin/dots-night-mode" status-icon) == "󰖙" ]] \
  || fail "night-mode does not prefer canonical state"
pass "night-mode prefers canonical hornero state"

echo "test_path_contract.sh: ALL GREEN"
