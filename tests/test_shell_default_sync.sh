#!/usr/bin/env bash
# test_shell_default_sync.sh - the vendored factory shell default must be a
# byte-exact copy of HorneroOS/shell at the SHA recorded in
# shell/shell.default.source (provenance gate, fails CI).
#
# Freshness against shell main is advisory here (a GitHub `::warning::`):
# a shell change must not turn every config PR red. The hard release gate
# lives in HorneroOS/hornero scripts/compose.sh, which fails a composition
# whose config pin ships a different default than its shell pin.
#
# Usage: tests/test_shell_default_sync.sh
# Env:   HORNERO_SHELL_REPO  shell repo URL (default: GitHub HorneroOS/shell)
# Needs network access to the shell repo (git fetch of one commit).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_REPO="${HORNERO_SHELL_REPO:-https://github.com/HorneroOS/shell}"
VENDORED="$REPO_ROOT/shell/shell.default.json"
SOURCE="$REPO_ROOT/shell/shell.default.source"
UPSTREAM_PATH="config/shell.default.json"

pass() { echo "SYNC-PASS: $1"; }
fail() { echo "SYNC-FAIL: $1" >&2; exit 1; }

[[ -f $SOURCE ]] || fail "missing $SOURCE"
SHA="$(sed -n 's/^shell_sha=\([0-9a-f]\{40\}\)$/\1/p' "$SOURCE")"
[[ -n $SHA ]] || fail "shell/shell.default.source has no 40-char shell_sha= line"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
git init -q "$WORK"
git -C "$WORK" remote add origin "$SHELL_REPO"

# --- provenance: vendored == shell@recorded SHA (hard) -------------------------
git -C "$WORK" fetch -q --depth 1 --filter=blob:none origin "$SHA" \
  || fail "cannot fetch $SHELL_REPO@$SHA"
git -C "$WORK" show "$SHA:$UPSTREAM_PATH" >"$WORK/pinned.json" \
  || fail "$UPSTREAM_PATH missing at shell@${SHA:0:8}"
if ! cmp -s "$VENDORED" "$WORK/pinned.json"; then
  diff -u "$WORK/pinned.json" "$VENDORED" | head -40 >&2 || true
  fail "shell/shell.default.json differs from shell@${SHA:0:8}:$UPSTREAM_PATH (copy it byte-exact or fix the recorded SHA)"
fi
pass "vendored default is byte-exact shell@${SHA:0:8}"

# --- freshness: vendored vs shell main (advisory) ------------------------------
git -C "$WORK" fetch -q --depth 1 --filter=blob:none origin main \
  || { echo "SYNC-SKIP: cannot fetch shell main" >&2; exit 0; }
if ! git -C "$WORK" show "FETCH_HEAD:$UPSTREAM_PATH" >"$WORK/main.json" 2>/dev/null; then
  echo "SYNC-SKIP: $UPSTREAM_PATH not found on shell main (advisory check only)" >&2
  exit 0
fi
MAIN_SHA="$(git -C "$WORK" rev-parse FETCH_HEAD)"
if cmp -s "$VENDORED" "$WORK/main.json"; then
  pass "vendored default matches shell main (${MAIN_SHA:0:8})"
else
  msg="shell main (${MAIN_SHA:0:8}) changed $UPSTREAM_PATH since shell@${SHA:0:8}; resync before the next composition candidate"
  echo "SYNC-STALE: $msg" >&2
  if [[ -n ${GITHUB_ACTIONS:-} ]]; then
    echo "::warning title=Factory shell default is stale::$msg"
  fi
fi
