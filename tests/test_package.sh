#!/usr/bin/env bash
# test_package.sh - real makepkg build of hornero-config plus DESTDIR-style
# install audit. No system mutation: the package is extracted with bsdtar
# into a temp root, never installed onto the host.
# Usage: tests/test_package.sh
# Skips (exit 0) when makepkg/bsdtar are unavailable (e.g. non-Arch CI).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAIL=0
pass() { echo "PKGTEST-PASS: $1"; }
fail() { echo "PKGTEST-FAIL: $1" >&2; FAIL=1; }

if ! command -v makepkg >/dev/null 2>&1 || ! command -v bsdtar >/dev/null 2>&1; then
  echo "PKGTEST-SKIP: makepkg/bsdtar not installed" >&2
  exit 0
fi

PKGDIR="$REPO_ROOT/packaging"
ROOT="$(mktemp -d)"
# Start hermetic: drop any byproducts of an earlier manual build, and remove
# everything this run creates on exit (all three are gitignored outputs).
rm -rf "$PKGDIR"/hornero-config-*.pkg.tar.zst "$PKGDIR"/src "$PKGDIR"/pkg
trap 'rm -rf "$ROOT" "$PKGDIR"/hornero-config-*.pkg.tar.zst "$PKGDIR"/src "$PKGDIR"/pkg' EXIT

# --- default (base) build -------------------------------------------------------
if (cd "$PKGDIR" && makepkg -sf --noconfirm >/tmp/hx-pkgtest-build.log 2>&1); then
  pass "makepkg build (default profile)"
else
  fail "makepkg build (default profile, see /tmp/hx-pkgtest-build.log)"
fi
PKGFILE="$(ls "$PKGDIR"/hornero-config-*.pkg.tar.zst 2>/dev/null | head -n 1 || true)"
[[ -n $PKGFILE ]] || fail "package artifact produced"
bsdtar -xf "$PKGFILE" -C "$ROOT"
pass "extract to temp root"

# --- documented layout: staged HOME must round-trip through the package --------
STAGE="$(mktemp -d)"
bash "$REPO_ROOT/scripts/materialize.sh" --dest "$STAGE" >/dev/null
for entry in "$STAGE"/.config/*; do
  base="$(basename "$entry")"
  [[ -e "$ROOT/etc/xdg/$base" ]] || fail "installed tree missing /etc/xdg/$base"
done
diff -r "$STAGE/.config" "$ROOT/etc/xdg" --exclude=gtkrc-2.0 >/dev/null 2>&1 \
  && pass "staged .config matches /etc/xdg" \
  || fail "staged .config differs from /etc/xdg"
cmp -s "$STAGE/.gtkrc-2.0" "$ROOT/etc/xdg/gtkrc-2.0" \
  && pass "gtkrc-2.0 skeleton" || fail "gtkrc-2.0 skeleton"
diff -r "$STAGE/.local/lib/dots" "$ROOT/usr/share/hornero/lib/dots" >/dev/null 2>&1 \
  && pass "lib/dots payload" || fail "lib/dots payload"
diff -r "$STAGE/.local/share/dots/themes" "$ROOT/usr/share/hornero/themes" >/dev/null 2>&1 \
  && pass "themes payload" || fail "themes payload"
for cli in "$STAGE"/.local/bin/dots-*; do
  cmp -s "$cli" "$ROOT/usr/share/hornero/bin/$(basename "$cli")" \
    || fail "bin adapter $(basename "$cli") differs"
done
pass "bin adapters"
cmp -s "$REPO_ROOT/profiles/base/profile.toml" "$ROOT/usr/share/hornero/profile.toml" \
  && cmp -s "$REPO_ROOT/profiles/base/profile.toml" "$ROOT/usr/share/hornero/profiles/base/profile.toml" \
  && pass "profile manifests" || fail "profile manifests"
[[ $(cat "$ROOT/usr/share/hornero/HORNERO_PROFILE") == "base" ]] \
  && pass "HORNERO_PROFILE=base" || fail "HORNERO_PROFILE record"
cmp -s "$REPO_ROOT/LICENSE" "$ROOT/usr/share/licenses/hornero-config/LICENSE" \
  && pass "license shipped" || fail "license shipped"
rm -rf "$STAGE"

# --- nothing outside the documented prefixes ------------------------------------
# Allowed: the prefix dirs themselves, everything below /etc/xdg and
# /usr/share, and the pacman metadata dotfiles. Anything else fails.
if find "$ROOT" -path "$ROOT/.BUILDINFO" -prune -o -path "$ROOT/.PKGINFO" -prune \
    -o -path "$ROOT/.MTREE" -prune -o -print \
    | grep -vE "^$ROOT/(etc/xdg|usr/share)(/|$)" | grep -vE "^$ROOT/(etc|usr)$" \
    | grep -vE "^$ROOT$" | grep -q .; then
  fail "files outside /etc/xdg + /usr/share"
else
  pass "install prefixes"
fi

# --- permissions: dirs 755, files 644, executables 755 --------------------------
[[ -z $(find "$ROOT/etc" "$ROOT/usr" -type d ! -perm 755) ]] \
  && pass "dir perms 755" || fail "dir perms 755"
[[ -z $(find "$ROOT/etc" "$ROOT/usr" -type f ! -perm 644 ! -perm 755) ]] \
  && pass "file perms 644/755" || fail "file perms 644/755"
[[ -x "$ROOT/usr/share/hornero/bin/dots-gtk-theme" ]] \
  && [[ -x "$ROOT/etc/xdg/hypr/scripts/gaps-interactive.sh" ]] \
  && pass "executables preserved" || fail "executables preserved"

# --- installed tree carries no identity or secrets ------------------------------
# (the /home/user gtkrc placeholder is the allowlisted upstream skeleton)
[[ -z $(grep -rn -- "^\[user\]" "$ROOT/etc/xdg/git/" || true) ]] \
  && pass "no git identity stanza" || fail "git identity stanza shipped"
LEFT="$(grep -rniE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' "$ROOT/etc" "$ROOT/usr" || true)"
[[ -z $LEFT ]] && pass "no mailbox strings" || fail "mailbox strings: $LEFT"
[[ -z $(grep -rn '/home/[a-z0-9_.-]*/' "$ROOT/etc" "$ROOT/usr" | grep -v '/home/user/' || true) ]] \
  && pass "no hardcoded home paths" || fail "hardcoded home paths"

# --- installed configs still parse ----------------------------------------------
git config --file "$ROOT/etc/xdg/git/config" --list >/dev/null 2>&1 \
  && pass "installed git config parses" || fail "installed git config parses"
python3 -c "import tomllib; tomllib.load(open('$ROOT/etc/xdg/handlr/handlr.toml','rb')); tomllib.load(open('$ROOT/usr/share/hornero/profile.toml','rb'))" \
  && pass "installed TOML parses" || fail "installed TOML parses"

# --- profile matrix ---------------------------------------------------------------
if (cd "$PKGDIR" && HORNERO_PROFILE=desktop makepkg -f >/dev/null 2>&1); then
  DESKROOT="$(mktemp -d)"
  bsdtar -xf "$PKGDIR"/hornero-config-*.pkg.tar.zst -C "$DESKROOT"
  [[ $(cat "$DESKROOT/usr/share/hornero/HORNERO_PROFILE") == "desktop" ]] \
    && pass "HORNERO_PROFILE=desktop" || fail "HORNERO_PROFILE=desktop record"
  diff -r "$ROOT/etc" "$DESKROOT/etc" >/dev/null 2>&1 \
    && pass "desktop tree identical to base" || fail "desktop tree differs from base"
  rm -rf "$DESKROOT"
else
  fail "makepkg build (desktop profile)"
fi
if (cd "$PKGDIR" && HORNERO_PROFILE=bogus makepkg -f >/dev/null 2>&1); then
  fail "bogus profile unexpectedly built"
else
  pass "bogus profile rejected"
fi

if [[ $FAIL -ne 0 ]]; then
  echo "test_package.sh: FAIL" >&2
  exit 1
fi
echo "test_package.sh: ALL GREEN"
