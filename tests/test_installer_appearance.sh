#!/usr/bin/env bash
# test_installer_appearance.sh - first-login consumer for the
# installer-seeded ~/.config/hornero/appearance.json (schemaVersion 1:
# theme + shellPreset, seeded by HorneroOS/installer
# configure-user-defaults.py). Hermetic: temp HOME, stubbed theme apply
# (the lib hornero_apply_theme) and stubbed horneroctl record every call,
# so the real desktop is never touched. Fails (nonzero) on any violation.
# Usage: tests/test_installer_appearance.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$REPO_ROOT/bin/hornero-appearance"

pass() { echo "INSTALLER-APPEARANCE-PASS: $1"; }
fail() { echo "INSTALLER-APPEARANCE-FAIL: $1" >&2; exit 1; }

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/.config/hornero" "$T/.local/lib/hornero" "$T/bin" \
	"$T/themes/hornero-signal-night" "$T/themes/hornero-signal-day" \
	"$T/presets" "$T/state"
echo '{}' >"$T/themes/hornero-signal-night/theme.json"
echo '{}' >"$T/themes/hornero-signal-day/theme.json"
echo '{}' >"$T/presets/cockpit.json"
echo '{}' >"$T/presets/studio.json"

# Stub the shell-side theme apply that bin/hornero-appearance sources.
cat >"$T/.local/lib/hornero/apply-appearance.sh" <<'EOF'
hornero_apply_theme() { printf '%s\n' "$1" >>"$HORNERO_TEST_THEME_LOG"; }
EOF
# Stub horneroctl (the shell preset applier).
cat >"$T/bin/horneroctl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$HORNERO_TEST_CTL_LOG"
EOF
chmod +x "$T/bin/horneroctl"

export HORNERO_TEST_THEME_LOG="$T/theme.log"
export HORNERO_TEST_CTL_LOG="$T/ctl.log"

MARKER="$T/state/hornero/appearance/installer-applied.json"
SCHEME="$T/state/hornero/signal/scheme.json"
POINTER="$T/state/hornero/current-shell-preset"
SEED="$T/.config/hornero/appearance.json"

run_consumer() {
	env \
		HOME="$T" \
		XDG_CONFIG_HOME="$T/.config" \
		XDG_DATA_HOME="$T/.local/share" \
		XDG_STATE_HOME="$T/state" \
		XDG_CACHE_HOME="$T/.cache" \
		HORNERO_THEMES_DIR="$T/themes" \
		HORNERO_SHELL_PRESETS_DIR="$T/presets" \
		HORNERO_SYSTEM_SHELL_PRESETS_DIR="$T/no-system-presets" \
		PATH="$T/bin:$PATH" \
		bash "$BIN" "$@"
}

reset_state() {
	rm -rf "$T/state" "$HORNERO_TEST_THEME_LOG" "$HORNERO_TEST_CTL_LOG"
	rm -f "$SEED"
	mkdir -p "$T/state"
}

seed() { printf '%s\n' "$1" >"$SEED"; }

# 1. No seeded file: no-op success, nothing recorded (dashed alias too).
reset_state
run_consumer --apply-installer-appearance \
	|| fail "no-seed run must exit 0"
[[ ! -e $MARKER ]] || fail "no-seed run wrote a marker"
pass "no seeded appearance.json is a no-op"

# 2. Seeded night/cockpit (the values the installer can send today):
# theme + preset applied once, marker written, second run is a no-op.
reset_state
seed '{"schemaVersion": 1, "theme": "hornero-signal-night", "shellPreset": "cockpit"}'
run_consumer apply-installer-appearance \
	|| fail "seeded run must exit 0"
grep -qx 'hornero-signal-night' "$HORNERO_TEST_THEME_LOG" \
	|| fail "seeded theme was not applied"
grep -qx 'shell preset apply cockpit --yes' "$HORNERO_TEST_CTL_LOG" \
	|| fail "seeded preset was not applied via horneroctl"
[[ -f $MARKER ]] || fail "seeded run wrote no marker"
python3 -c '
import json, sys
m = json.load(open(sys.argv[1]))
assert m["theme"] == "hornero-signal-night" and m["shellPreset"] == "cockpit"
assert m["themeApplied"] is True and m["presetApplied"] is True
assert len(m["seedSha256"]) == 64
' "$MARKER" || fail "marker content is wrong"
run_consumer apply-installer-appearance \
	|| fail "second run must exit 0"
[[ $(wc -l <"$HORNERO_TEST_THEME_LOG") -eq 1 ]] \
	|| fail "second run re-applied the theme"
[[ $(wc -l <"$HORNERO_TEST_CTL_LOG") -eq 1 ]] \
	|| fail "second run re-applied the preset"
pass "seeded theme+preset apply exactly once (idempotent)"

# 3. A live scheme naming another theme is a later user choice: the
# seeded theme must not overwrite it, but consumption is still recorded.
reset_state
seed '{"schemaVersion": 1, "theme": "hornero-signal-night", "shellPreset": "cockpit"}'
mkdir -p "$(dirname "$SCHEME")"
printf '{"id": "hornero-signal-day"}\n' >"$SCHEME"
run_consumer apply-installer-appearance \
	|| fail "user-theme run must exit 0"
[[ ! -s $HORNERO_TEST_THEME_LOG ]] \
	|| fail "consumer overwrote a live user theme"
python3 -c '
import json, sys
m = json.load(open(sys.argv[1]))
assert m["themeApplied"] is False and m["presetApplied"] is True
' "$MARKER" || fail "user-theme marker must record themeApplied=false"
pass "live user theme is never overwritten"

# 4. A preset pointer naming another preset is likewise left alone.
reset_state
seed '{"schemaVersion": 1, "theme": "hornero-signal-night", "shellPreset": "cockpit"}'
mkdir -p "$(dirname "$POINTER")"
printf 'studio\n' >"$POINTER"
run_consumer apply-installer-appearance \
	|| fail "user-preset run must exit 0"
[[ ! -s $HORNERO_TEST_CTL_LOG ]] \
	|| fail "consumer overwrote a live user preset"
grep -qx 'hornero-signal-night' "$HORNERO_TEST_THEME_LOG" \
	|| fail "theme should still apply when only the preset is user-owned"
pass "active user preset is never overwritten"

# 5. Unknown values fail closed: no marker, nothing applied.
reset_state
seed '{"schemaVersion": 1, "theme": "no-such-theme", "shellPreset": "cockpit"}'
if run_consumer apply-installer-appearance 2>/dev/null; then
	fail "unknown theme must exit nonzero"
fi
[[ ! -e $MARKER && ! -s $HORNERO_TEST_THEME_LOG ]] \
	|| fail "unknown theme left state behind"
reset_state
seed '{"schemaVersion": 1, "theme": "hornero-signal-night", "shellPreset": "nope"}'
if run_consumer apply-installer-appearance 2>/dev/null; then
	fail "unknown preset must exit nonzero"
fi
[[ ! -e $MARKER && ! -s $HORNERO_TEST_THEME_LOG && ! -s $HORNERO_TEST_CTL_LOG ]] \
	|| fail "unknown preset must be rejected before anything applies"
pass "unknown theme/preset fail closed before applying"

# 6. Malformed or foreign-schema seeds fail closed.
reset_state
seed '{not json'
if run_consumer apply-installer-appearance 2>/dev/null; then
	fail "malformed seed must exit nonzero"
fi
seed '{"schemaVersion": 99, "theme": "hornero-signal-night"}'
if run_consumer apply-installer-appearance 2>/dev/null; then
	fail "foreign schemaVersion must exit nonzero"
fi
[[ ! -e $MARKER ]] || fail "bad seeds wrote a marker"
pass "malformed/foreign seeds fail closed"

# 7. Without horneroctl a seeded preset cannot be honoured: fail closed.
reset_state
seed '{"schemaVersion": 1, "theme": "hornero-signal-night", "shellPreset": "cockpit"}'
if HORNEROCTL_BIN="$T/bin/absent-horneroctl" run_consumer apply-installer-appearance 2>/dev/null; then
	fail "missing horneroctl must exit nonzero"
fi
[[ ! -e $MARKER ]] || fail "missing horneroctl wrote a marker"
pass "missing preset applier fails closed"

# 8. First-login wiring: Hyprland autostart invokes the consumer before
# the shell starts, so the seeded scheme is on disk when the shell reads it.
grep -q 'hornero-appearance apply-installer-appearance' \
	"$REPO_ROOT/desktop/hypr/hyprland.lua.d/autostart.lua" \
	|| fail "autostart.lua does not invoke the consumer"
pass "autostart invokes the consumer at first login"

echo "INSTALLER-APPEARANCE-PASS: all cases"
