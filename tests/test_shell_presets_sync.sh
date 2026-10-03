#!/usr/bin/env bash
# The installed layout catalogue is derived from the pinned HorneroOS/shell
# source. Provenance is required; freshness against shell/main is advisory and
# the release composer remains the pin-alignment gate.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_REPO="${HORNERO_SHELL_REPO:-https://github.com/HorneroOS/shell}"
SOURCE="$REPO_ROOT/shell/shell-presets.source"
CATALOGUE="$REPO_ROOT/profiles/shell-presets"

pass() { echo "SYNC-PASS: $1"; }
fail() { echo "SYNC-FAIL: $1" >&2; exit 1; }

[[ -f $SOURCE ]] || fail "missing $SOURCE"
SHA="$(sed -n 's/^shell_sha=\([0-9a-f]\{40\}\)$/\1/p' "$SOURCE")"
[[ -n $SHA ]] || fail "shell/shell-presets.source has no 40-char shell_sha= line"
[[ -d $CATALOGUE ]] || fail "missing $CATALOGUE"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
git init -q "$WORK"
git -C "$WORK" remote add origin "$SHELL_REPO"
git -C "$WORK" fetch -q --depth 1 --filter=blob:none origin "$SHA" \
  || fail "cannot fetch $SHELL_REPO@$SHA"

git -C "$WORK" ls-tree -r --name-only "$SHA" -- presets \
  | sed -n 's#^presets/##p' | grep -E '\.json$' | sort >"$WORK/upstream-files"
find "$CATALOGUE" -maxdepth 1 -type f -name '*.json' -printf '%f\n' \
  | sort >"$WORK/catalogue-files"
cmp -s "$WORK/upstream-files" "$WORK/catalogue-files" \
  || fail "packaged preset file set differs from shell@$SHA"

while IFS= read -r name; do
  git -C "$WORK" show "$SHA:presets/$name" >"$WORK/upstream.json" \
    || fail "presets/$name missing at shell@${SHA:0:8}"
  cmp -s "$CATALOGUE/$name" "$WORK/upstream.json" \
    || fail "$name differs from shell@${SHA:0:8}"
done <"$WORK/upstream-files"
pass "${SHA:0:8} layout presets are byte-exact"

if ! git -C "$WORK" fetch -q --depth 1 --filter=blob:none origin main; then
  echo "SYNC-SKIP: cannot fetch shell main (freshness advisory)" >&2
  exit 0
fi
MAIN_SHA="$(git -C "$WORK" rev-parse FETCH_HEAD)"
git -C "$WORK" ls-tree -r --name-only "$MAIN_SHA" -- presets \
  | sed -n 's#^presets/##p' | grep -E '\.json$' | sort >"$WORK/main-files"
if ! cmp -s "$WORK/catalogue-files" "$WORK/main-files"; then
  msg="shell main (${MAIN_SHA:0:8}) changed the preset file set since shell@${SHA:0:8}; refresh before the next candidate"
else
  stale=0
  while IFS= read -r name; do
    git -C "$WORK" show "$MAIN_SHA:presets/$name" >"$WORK/main.json" || { stale=1; break; }
    cmp -s "$CATALOGUE/$name" "$WORK/main.json" || { stale=1; break; }
  done <"$WORK/main-files"
  if (( stale == 0 )); then
    pass "layout presets match shell main (${MAIN_SHA:0:8})"
    exit 0
  fi
  msg="shell main (${MAIN_SHA:0:8}) changed layout presets since shell@${SHA:0:8}; refresh before the next candidate"
fi
echo "SYNC-STALE: $msg" >&2
if [[ -n ${GITHUB_ACTIONS:-} ]]; then
  echo "::warning title=Hornero layout presets are stale::$msg"
fi
