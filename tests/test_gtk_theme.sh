#!/usr/bin/env bash
# test_gtk_theme.sh - real Hornero GTK theme gates (GTK 3 + GTK 4, no GTK 2).
# Fails (nonzero exit) on any violation so CI stays red.
# Usage: tests/test_gtk_theme.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
THEME_ROOT="$REPO_ROOT/desktop/gtk-theme"

pass() { echo "GTKTEST-PASS: $1"; }
fail() { echo "GTKTEST-FAIL: $1" >&2; exit 1; }

# --- shipped trees exist, GTK 2 is neither shipped nor claimed ----------------
for variant in Dark Light; do
  for f in index.theme gtk-3.0/gtk.css gtk-4.0/gtk.css; do
    [[ -f "$THEME_ROOT/Hornero-$variant/$f" ]] \
      || fail "missing Hornero-$variant/$f"
  done
  [[ ! -e "$THEME_ROOT/Hornero-$variant/gtk-2.0" ]] \
    || fail "Hornero-$variant ships gtk-2.0 (no GTK2 claims)"
  pass "Hornero-$variant tree complete (index.theme + gtk-3.0 + gtk-4.0, no gtk-2.0)"
done

# --- generated outputs stay in sync with the hand-structured sources ----------
"$THEME_ROOT/build.sh" --check >/dev/null || fail "build.sh --check (shipped gtk.css drifted from src/)"
pass "shipped gtk.css in sync with src/"

# --- deep CSS + wiring checks (stdlib python, no GTK needed) -------------------
python3 - "$REPO_ROOT" <<'PY' || exit 1
import configparser, json, re, sys
from pathlib import Path
root = Path(sys.argv[1])
errors = []
def err(msg): errors.append(msg)

pairs = (("hornero-dark", "Hornero-Dark"), ("hornero-light", "Hornero-Light"))
# Selectors every shipped gtk.css must carry (gallery fixture covers these).
required = ["button", "entry", "headerbar", "notebook", "tab", "sidebar",
            "menu", "popover", "tooltip", "scrollbar", "scale", "progressbar",
            "switch", "check", "radio", "separator", "infobar", "toolbar",
            "frame", "treeview", "spinner", "statusbar", "suggested-action",
            "destructive-action"]
# Color functions / engine syntax the portable subset forbids.
forbidden = ["shade(", "mix(", "alpha(", "-gtk-gradient", "@import",
             "url(", "-GtkWidget", "engine "]

for tid, tname in pairs:
    theme = json.loads((root / "profiles/themes" / tid / "theme.json").read_text())
    if theme.get("gtkTheme") != tname:
        err(f"{tid}/theme.json gtkTheme={theme.get('gtkTheme')!r}, want {tname!r}")
    tdir = root / "desktop/gtk-theme" / tname
    idx = configparser.ConfigParser(strict=True)
    try:
        idx.read_string((tdir / "index.theme").read_text())
        got = idx.get("X-GNOME-Metatheme", "GtkTheme", fallback=None)
        if got != tname:
            err(f"{tname}/index.theme GtkTheme={got!r}, want {tname!r}")
        if idx.get("X-GNOME-Metatheme", "IconTheme", fallback=None) != theme.get("iconTheme"):
            err(f"{tname}/index.theme IconTheme drifts from {tid}/theme.json iconTheme")
    except Exception as e:
        err(f"{tname}/index.theme does not parse: {e}")
    css_files = {}
    for ver in ("gtk-3.0", "gtk-4.0"):
        text = (tdir / ver / "gtk.css").read_text()
        css_files[ver] = text
        # Strip comments, then braces must balance (parser-error gate).
        bare = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
        if bare.count("{") != bare.count("}"):
            err(f"{tname}/{ver}/gtk.css unbalanced braces")
        if bare.count("{") < 40:
            err(f"{tname}/{ver}/gtk.css suspiciously small ({bare.count('{')} rules)")
        for bad in forbidden:
            if bad in bare:
                err(f"{tname}/{ver}/gtk.css uses forbidden {bad!r} (portable subset only)")
        for sel in required:
            if sel not in bare:
                err(f"{tname}/{ver}/gtk.css missing selector family {sel!r}")
        for m in re.finditer(r"@define-color\s+(\S+)\s+([^;]+);", bare):
            if not re.fullmatch(r"#[0-9a-fA-F]{6}", m.group(2).strip()):
                err(f"{tname}/{ver}/gtk.css bad @define-color: {m.group(0).strip()[:60]}")
        # Token fidelity: every palette hex from theme.json appears verbatim.
        low = bare.lower()
        for key, val in theme["palette"].items():
            if val.lower() not in low:
                err(f"{tname}/{ver}/gtk.css missing palette {key}={val}")
    # GTK3 and GTK4 outputs carry the same selector set (one source per variant).
    sel3 = sorted(set(re.findall(r"(?m)^([a-z][\w:.,* >-]+?)\s*\{", css_files["gtk-3.0"])))
    sel4 = sorted(set(re.findall(r"(?m)^([a-z][\w:.,* >-]+?)\s*\{", css_files["gtk-4.0"])))
    if sel3 != sel4:
        err(f"{tname}: gtk-3.0/gtk-4.0 selector sets differ "
            f"(only-in-3.0={[s for s in sel3 if s not in sel4][:3]}, "
            f"only-in-4.0={[s for s in sel4 if s not in sel3][:3]})")

# Gallery fixture covers the styled widget set (or skips cleanly headless).
gal = (root / "desktop/gtk-theme/gallery.py").read_text()
classes = re.search(r"WIDGET_CLASSES = \(\s*\"([^\"]+)\"", gal)
if not classes:
    err("gallery.py WIDGET_CLASSES block missing")
else:
    dark = (root / "desktop/gtk-theme/Hornero-Dark/gtk-3.0/gtk.css").read_text().lower()
    for cls in classes.group(1).split():
        if cls not in dark:
            err(f"gallery widget class {cls!r} has no selector in Hornero-Dark gtk.css")

if errors:
    for e in errors: print(f"GTKTEST-FAIL: {e}", file=sys.stderr)
    sys.exit(1)
print("GTKTEST-PASS: css parses, selectors + palette + wiring verified (both variants, GTK3+GTK4)")
PY
pass "css parse + selectors + palette fidelity + theme.json wiring"

# --- MIT-only: no GPL references anywhere in the theme deliverable ------------
if grep -ri "GPL\|General Public License" "$THEME_ROOT" 2>/dev/null; then
  fail "GPL reference in GTK theme deliverable (MIT-only)"
fi
pass "GTK theme deliverable MIT-only (no GPL references)"

# --- no identity, secrets, or hardcoded home paths in shipped trees -----------
if grep -rn '/home/[a-z0-9_.-]*/' "$THEME_ROOT/Hornero-Dark" "$THEME_ROOT/Hornero-Light" 2>/dev/null \
    | grep -v '/home/user/' | grep -q .; then
  fail "hardcoded home path in shipped theme tree"
fi
pass "no hardcoded home paths in shipped theme trees"

# --- materialize audit: theme trees land on the standard lookup path ---------
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
bash "$REPO_ROOT/scripts/materialize.sh" --dest "$STAGE" >/dev/null
for variant in Dark Light; do
  for f in index.theme gtk-3.0/gtk.css gtk-4.0/gtk.css; do
    cmp -s "$THEME_ROOT/Hornero-$variant/$f" "$STAGE/.local/share/themes/Hornero-$variant/$f" \
      || fail "materialized themes/Hornero-$variant/$f differs from source"
  done
done
pass "materialize installs byte-exact Hornero-{Dark,Light} to .local/share/themes"
# Dev-only sources must not leak into the user install or the recipe dir.
for leaked in src build.sh gallery.py README.md; do
  [[ ! -e "$STAGE/.local/share/themes/$leaked" ]] \
    || fail "dev-only $leaked leaked into .local/share/themes"
done
[[ ! -e "$STAGE/.local/share/hornero/themes/Hornero-Dark" ]] \
  || fail "GTK theme tree leaked into hornero/themes recipes (double ownership)"
pass "no dev-only leaks, no double ownership with hornero/themes recipes"

# --- gallery fixture: renders where Gtk exists, skips cleanly headless -------
# timeout(1) bounds the run: a broken display must fail fast, never hang CI.
if timeout 30s python3 "$THEME_ROOT/gallery.py" --theme Hornero-Dark >/tmp/hx-gallery.log 2>&1; then
  pass "gallery fixture renders (Gtk available)"
else
  rc=$?
  if [[ $rc -eq 2 ]] && grep -q "fixture skipped, not failed" /tmp/hx-gallery.log; then
    pass "gallery fixture skips cleanly (headless host: $(tail -n 1 /tmp/hx-gallery.log))"
  elif [[ $rc -eq 124 ]]; then
    fail "gallery fixture hung (timeout) instead of skipping"
  else
    cat /tmp/hx-gallery.log >&2
    fail "gallery fixture failed (exit $rc)"
  fi
fi

echo "test_gtk_theme.sh: ALL GREEN"
