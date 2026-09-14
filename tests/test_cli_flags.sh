#!/usr/bin/env bash
# test_cli_flags.sh - easyoptions CLIs must parse flags without `which`.
# Minimal systems (Arch cloud images, containers) do not ship /usr/bin/which.
# The vendored option parser resolved its own path through `which`, so with
# `which` absent it registered zero options and rejected every flag (even
# `-q`), which silently broke `dots_apply_theme`'s GTK step (`|| true`) and
# left split theme states. Fails (nonzero exit) on any violation.
# Usage: tests/test_cli_flags.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

pass() { echo "CLIFLAGS-PASS: $1"; }
fail() { echo "CLIFLAGS-FAIL: $1" >&2; exit 1; }

# Hermetic HOME: the bins source lib/ from ~/.local/lib/dots (materialized
# layout), so point a temp HOME at the repo lib. Nothing is written outside
# the temp dir.
T_HOME="$(mktemp -d)"
trap 'rm -rf "$T_HOME"' EXIT
mkdir -p "$T_HOME/.local/lib" "$T_HOME/.config"
ln -s "$REPO_ROOT/lib/dots" "$T_HOME/.local/lib/dots"

# Simulate a system without `which` at the exact call site: an exported
# failing function shadows the binary for every child bash, producing the
# same empty substitution the parser saw in minimal guests.
which() { echo "which: command not found" >&2; return 127; }
export -f which

# The authentic P2 failure: `dots-gtk-theme -q <verb>` exited 1 with
# "Error: unrecognized option -q." `current` is read-only (empty config
# reads as empty theme); only the exit status and the absence of the
# parser error are asserted.
out="$(HOME="$T_HOME" bash "$REPO_ROOT/bin/dots-gtk-theme" -q current 2>&1)" \
  || fail "dots-gtk-theme -q current exits nonzero without which: $out"
[[ $out != *"unrecognized option"* ]] \
  || fail "dots-gtk-theme rejects -q without which: $out"
pass "dots-gtk-theme parses -q without which"

# Long flag on another shared-parser consumer stays working too.
out="$(HOME="$T_HOME" bash "$REPO_ROOT/bin/dots-clipboard" --help 2>&1)" \
  || fail "dots-clipboard --help exits nonzero without which: $out"
pass "dots-clipboard parses --help without which"

# Sanity: unshadowed runs keep working (no regression on normal systems).
unset -f which
HOME="$T_HOME" bash "$REPO_ROOT/bin/dots-gtk-theme" -q current >/dev/null 2>&1 \
  || fail "dots-gtk-theme -q current exits nonzero with which present"
pass "dots-gtk-theme parses -q with which present"

echo "test_cli_flags.sh: ALL GREEN"
