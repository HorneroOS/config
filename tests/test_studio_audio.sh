#!/usr/bin/env bash
# test_studio_audio.sh - Studio audio policy: safe default, opt-in templates,
# reversibility, and no machine-specific data.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BALANCED="$REPO_ROOT/desktop/pipewire/pipewire.conf.d/10-hornero-studio-balanced.conf"
LOW_LATENCY="$REPO_ROOT/desktop/studio-audio/low-latency.conf"
ADVANCED="$REPO_ROOT/desktop/studio-audio/advanced.conf"

fail() {
  echo "TEST-FAIL: $1" >&2
  exit 1
}

for file in "$BALANCED" "$LOW_LATENCY" "$ADVANCED"; do
  [[ -f "$file" ]] || fail "missing policy file: $file"
done

# Balanced is the safe default: it must not force any clock values.
if grep -Eq 'default\.clock\.(rate|quantum|min-quantum|max-quantum)[[:space:]]*=' "$BALANCED"; then
  fail "Balanced policy must not override clock rate or quantum"
fi
echo "TEST-PASS: Balanced forces no clock override"

# Low Latency is the only template carrying proposal quantum values.
grep -q 'default.clock.quantum = 128' "$LOW_LATENCY" || fail "Low Latency template must propose quantum 128"
if grep -Eq '^[[:space:]]*default\.clock\.(rate|quantum)' "$ADVANCED"; then
  fail "Advanced template must not ship fixed clock values"
fi
echo "TEST-PASS: Low Latency proposes values; Advanced ships none"

# Templates are opt-in data, never active PipeWire drop-ins in the profile.
grep -q 'modules.pipewire' "$REPO_ROOT/profiles/base/profile.toml" || fail "pipewire module not registered"
grep -q 'desktop/studio-audio' "$REPO_ROOT/profiles/base/profile.toml" || fail "studio-audio templates not registered"
if grep -q 'pipewire.conf.d.*low-latency\|low-latency.*pipewire.conf.d' "$REPO_ROOT/profiles/base/profile.toml"; then
  fail "Low Latency template must not install into pipewire.conf.d"
fi
echo "TEST-PASS: templates are opt-in and outside pipewire.conf.d"

# Portable: no device names, personal paths, or the legacy session manager.
if grep -rEqi 'alsa_input|alsa_output|bluez_output|/home/[a-z]+|pipewire-media-session' \
    "$REPO_ROOT/desktop/pipewire" "$REPO_ROOT/desktop/studio-audio"; then
  fail "Studio audio policy must not contain device names, personal paths, or pipewire-media-session"
fi
echo "TEST-PASS: policy is portable and WirePlumber-based"

# Restoration is documented and exact: remove the installed file.
grep -q 'remove the copy to restore' "$LOW_LATENCY" || fail "Low Latency must document exact restoration"
grep -q 'docs/STUDIO-AUDIO.md' "$BALANCED" || fail "Balanced must point at the Studio audio doc"
echo "TEST-PASS: restoration path is documented"

echo "ALL STUDIO AUDIO TESTS PASSED"
