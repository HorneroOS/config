#!/usr/bin/env bash
# Factory zshrc: Signal prompt contract (ANSI palette only, status never colour
# alone, NO_COLOR/dumb plain). Skips when zsh is not installed.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RC="$REPO_ROOT/shell/zsh/zshrc"
fail() { echo "ZSHPROMPT-FAIL: $*" >&2; exit 1; }
pass() { echo "ok  $*"; }

grep -q '38;5\|%F{[0-9]\{3\}}\|%F{#' "$RC" && fail "prompt must use ANSI colour names 0-15, not 256/RGB"
pass "no 256-colour or RGB prompt colours"

if ! command -v zsh >/dev/null 2>&1; then
  echo "ZSHPROMPT-SKIP: zsh not installed" >&2
  exit 0
fi
zsh -n "$RC" || fail "zshrc does not parse"
pass "zshrc parses"

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
render() { # env... ; prints expanded prompt for the given last status
  local status="$1"; shift
  env -i HOME="$T" XDG_STATE_HOME="$T/state" PATH="$PATH" "$@" \
    zsh -fc "source '$RC' 2>/dev/null; (exit $status); print -rP -- \"\$PROMPT\"" 2>/dev/null
}
strip() { sed -e $'s/\x1b\\[[0-9;]*m//g'; }

ok_utf="$(render 0 LANG=en_US.UTF-8 TERM=xterm-256color)"
bad_utf="$(render 3 LANG=en_US.UTF-8 TERM=xterm-256color)"
bad_ascii="$(render 3 LANG=C TERM=xterm-256color)"
plain="$(render 3 LANG=en_US.UTF-8 TERM=xterm NO_COLOR=1)"

[[ "$ok_utf" == *$'\x1b['* ]] || fail "coloured prompt expected on a colour terminal"
[[ "$(strip <<<"$ok_utf")" != *"✗"* ]] || fail "success prompt must not show a failure marker"
[[ "$(strip <<<"$bad_utf")" == *"✗3"* ]] || fail "failure marker with status missing: $(strip <<<"$bad_utf")"
[[ "$(strip <<<"$bad_ascii")" == *"x3"* && "$bad_ascii" != *"✗"* ]] || fail "ASCII fallback missing"
[[ "$plain" != *$'\x1b'* ]] || fail "NO_COLOR prompt must contain no escapes"
[[ "$plain" == *"x3"* ]] || fail "NO_COLOR prompt must still show failure status"
pass "failure status carries glyph + code; ASCII + NO_COLOR fallbacks"
# fastfetch routing: bare -> hornero-fetch, with args or HORNERO_FETCH=0 -> real binary
mkdir -p "$T/bin"
printf '#!/bin/sh\necho hornero-fetch\n' >"$T/bin/hornero-fetch"; printf '#!/bin/sh\necho real-fastfetch "$@"\n' >"$T/bin/fastfetch"
chmod +x "$T/bin/hornero-fetch" "$T/bin/fastfetch"
ff() { env -i HOME="$T" XDG_STATE_HOME="$T/state" PATH="$T/bin:$PATH" "$@" zsh -fc "source '$RC' 2>/dev/null; fastfetch ${ARGS-}" 2>/dev/null; }
[[ "$(ff)" == "hornero-fetch" ]] || fail "bare fastfetch must route to hornero-fetch"
[[ "$(ARGS='--pipe' ff)" == "real-fastfetch --pipe" ]] || fail "fastfetch with arguments must run the real binary"
[[ "$(ff HORNERO_FETCH=0)" == "real-fastfetch" ]] || fail "HORNERO_FETCH=0 must bypass the card"
pass "bare fastfetch routes to hornero-fetch; arguments and HORNERO_FETCH=0 bypass it"
echo "ZSHPROMPT-PASS"
