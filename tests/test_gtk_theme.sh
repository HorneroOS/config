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
mapfile -t TREES < <(find "$THEME_ROOT" -maxdepth 1 -type d -name 'Hornero-*' -printf '%f\n' | sort)
[[ ${#TREES[@]} -ge 3 ]] || fail "expected the Hornero Signal trees, found: ${TREES[*]:-none}"
for tree in "${TREES[@]}"; do
  for f in index.theme gtk-3.0/gtk.css gtk-4.0/gtk.css gtk-4.0/recolor.css; do
    [[ -f "$THEME_ROOT/$tree/$f" ]] || fail "missing $tree/$f"
  done
  [[ ! -e "$THEME_ROOT/$tree/gtk-2.0" ]] || fail "$tree ships gtk-2.0 (no GTK2 claims)"
done
pass "${#TREES[@]} trees complete (index.theme + gtk-3.0 + gtk-4.0 + recolor, no gtk-2.0)"

# --- generated outputs stay in sync with signal.css + theme roles -------------
python3 "$REPO_ROOT/scripts/generate-appearance.py" --check >/dev/null \
  || fail "generated GTK trees drifted (run scripts/generate-appearance.py)"
pass "shipped GTK trees match src/signal.css + schema-v2 themes"

# --- deep CSS + wiring checks (stdlib python, no GTK needed) -------------------
python3 - "$REPO_ROOT" <<'PY' || exit 1
import configparser, json, re, sys
from pathlib import Path
root = Path(sys.argv[1])
sys.path.insert(0, str(root / "lib/hornero"))
import signal_theme as st
errors = []
def err(msg): errors.append(msg)

factory = json.loads((root / "profiles/factory.json").read_text())
if factory.get("gtk", {}).get("theme") != "Hornero-Signal":
    err("factory GTK style must use Hornero-Signal")
if "orchis-theme" in (root / "packaging/PKGBUILD").read_text():
    err("the Hornero GTK catalogue must not depend on Orchis")
if "Orchis" in (root / "lib/hornero/gtk-theme-manager.sh").read_text():
    err("GTK auto-detection and fallbacks must stay in the Hornero theme family")
if 'gtk-theme-name="Orchis-Light"' in (root / "desktop/gtk/gtkrc-2.0").read_text():
    err("the GTK2 skeleton must not request the unavailable Orchis theme")

themes = {p.parent.name: json.loads(p.read_text()) for p in (root / "profiles/themes").glob("*/theme.json")}
trees = sorted(p.name for p in (root / "desktop/gtk-theme").glob("Hornero-*") if p.is_dir())
owners = {t["gtkTheme"]: t for t in themes.values() if t.get("collection") in st.COLLECTIONS}
if sorted(owners) != trees:
    err(f"GTK trees {trees} != Hornero collection gtkTheme set {sorted(owners)}")
expect = {"hornero-signal-night": "Hornero-Signal", "hornero-signal-day": "Hornero-Signal-Day",
          "hornero-signal-contrast": "Hornero-Signal-Contrast"}
for tid, tree in expect.items():
    if themes[tid]["gtkTheme"] != tree:
        err(f"{tid} gtkTheme={themes[tid]['gtkTheme']!r}, want {tree!r}")
for tid, theme in themes.items():
    if theme["gtkTheme"] not in trees:
        err(f"{tid}: gtkTheme {theme['gtkTheme']!r} is not a shipped Hornero tree")

required = ["button", "entry", "headerbar", "notebook", "tab", "sidebar",
            "menu", "popover", "tooltip", "scrollbar", "scale", "progressbar",
            "switch", "check", "radio", "separator", "infobar", "toolbar",
            "frame", "treeview", "spinner", "statusbar", "suggested-action",
            "destructive-action", "levelbar"]
forbidden = ["shade(", "mix(", "alpha(", "-gtk-gradient", "@import",
             "url(", "-GtkWidget", "engine ", ":focus-visible", ":focus-within"]

for tree, theme in owners.items():
    tdir = root / "desktop/gtk-theme" / tree
    idx = configparser.ConfigParser(strict=True)
    try:
        idx.read_string((tdir / "index.theme").read_text())
        if idx.get("X-GNOME-Metatheme", "GtkTheme", fallback=None) != tree:
            err(f"{tree}/index.theme GtkTheme mismatch")
        if idx.get("X-GNOME-Metatheme", "IconTheme", fallback=None) != theme["iconTheme"]:
            err(f"{tree}/index.theme IconTheme drifts from {theme['id']} iconTheme")
    except Exception as e:
        err(f"{tree}/index.theme does not parse: {e}")
    css = {}
    for ver in ("gtk-3.0", "gtk-4.0"):
        text = (tdir / ver / "gtk.css").read_text()
        css[ver] = text
        bare = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
        if bare.count("{") != bare.count("}"):
            err(f"{tree}/{ver}/gtk.css unbalanced braces")
        if bare.count("{") < 40:
            err(f"{tree}/{ver}/gtk.css suspiciously small")
        for bad in forbidden:
            if bad in bare:
                err(f"{tree}/{ver}/gtk.css uses non-portable {bad!r}")
        for sel in required:
            if sel not in bare:
                err(f"{tree}/{ver}/gtk.css missing selector family {sel!r}")
        defined = dict(re.findall(r"@define-color\s+(\S+)\s+([^;]+);", bare))
        for name, value in defined.items():
            if not re.fullmatch(r"#[0-9A-F]{6}", value.strip()):
                err(f"{tree}/{ver}/gtk.css bad @define-color {name}")
        used = set(re.findall(r"@([a-z_]+)", bare)) - {"define"}
        for name in sorted(used - set(defined)):
            err(f"{tree}/{ver}/gtk.css references undefined colour @{name}")
        for role in st.ROLES:
            if theme["palette"][role] not in bare:
                err(f"{tree}/{ver}/gtk.css missing role {role}={theme['palette'][role]}")
        # Signal geometry: small radii only (3-5 px; 100% for radios/switch dots).
        for radius in re.findall(r"border-radius:\s*([^;]+);", bare):
            if radius.strip() not in {"0", "1px", "2px", "3px", "5px", "100%"}:
                err(f"{tree}/{ver}/gtk.css radius {radius.strip()} outside the Signal scale")
    if css["gtk-3.0"] != css["gtk-4.0"]:
        err(f"{tree}: gtk-3.0 and gtk-4.0 outputs differ (one portable source)")
    rtext = (tdir / "gtk-4.0" / "recolor.css").read_text()
    got = dict(re.findall(r"@define-color\s+([\w-]+)\s+(#[0-9A-F]{6})\s*;", rtext))
    p = theme["palette"]
    for name, role in (("accent_bg_color", "signal"), ("accent_fg_color", "onSignal"),
                       ("window_bg_color", "base"), ("window_fg_color", "ink"),
                       ("error_bg_color", "alert"), ("error_fg_color", "onAlert")):
        if got.get(name) != p[role]:
            err(f"{tree}/recolor.css {name}={got.get(name)!r}, want {role}={p[role]!r}")

gal = (root / "desktop/gtk-theme/gallery.py").read_text()
classes = re.search(r"WIDGET_CLASSES = \(\s*\"([^\"]+)\"", gal)
widgets = (root / "desktop/gtk-theme/src/signal.css").read_text()
if not classes:
    err("gallery.py WIDGET_CLASSES block missing")
else:
    for cls in classes.group(1).split():
        if cls not in widgets:
            err(f"gallery widget class {cls!r} has no selector in src/signal.css")

if errors:
    for e in errors: print(f"GTKTEST-FAIL: {e}", file=sys.stderr)
    sys.exit(1)
print("GTKTEST-PASS: css parses, selectors + roles + Signal geometry + wiring verified (GTK3+GTK4)")
PY
pass "css parse + selectors + role fidelity + theme.json wiring"

# --- real GTK 3 / GTK 4 CSS parsers (when PyGObject + GTK are installed) -------
# Display-free: GtkCssProvider parses without a display, so the run is
# isolated from any session (no DISPLAY/WAYLAND_DISPLAY, private runtime dir).
if python3 -c 'import gi' >/dev/null 2>&1; then
  RUNTIME="$(mktemp -d)"
  for ver in 4.0 3.0; do
    if python3 -c "import gi; gi.require_version('Gtk', '$ver')" >/dev/null 2>&1; then
      env -u DISPLAY -u WAYLAND_DISPLAY XDG_RUNTIME_DIR="$RUNTIME" \
        python3 "$REPO_ROOT/tests/gtk_css_parse.py" "$ver" \
        "$THEME_ROOT"/Hornero-*/gtk-"${ver%.0}".0/*.css 2>/dev/null | grep -v ' OK ' >&2 || true
      env -u DISPLAY -u WAYLAND_DISPLAY XDG_RUNTIME_DIR="$RUNTIME" \
        python3 "$REPO_ROOT/tests/gtk_css_parse.py" "$ver" \
        "$THEME_ROOT"/Hornero-*/gtk-"${ver%.0}".0/*.css >/dev/null 2>&1 \
        || fail "GTK $ver parser reports errors in the generated CSS"
      pass "GTK $ver parser accepts every generated stylesheet"
    else
      echo "GTKTEST-SKIP: GTK $ver introspection not installed (parser check not run)"
    fi
  done
  rm -rf "$RUNTIME"
else
  echo "GTKTEST-SKIP: PyGObject not installed (real-parser check not run)"
fi

# --- MIT-only: no GPL references anywhere in the theme deliverable ------------
if grep -ri "GPL\|General Public License" "$THEME_ROOT" 2>/dev/null; then
  fail "GPL reference in GTK theme deliverable (MIT-only)"
fi
pass "GTK theme deliverable MIT-only (no GPL references)"

# --- no identity, secrets, or hardcoded home paths in shipped trees -----------
if grep -rn '/home/[a-z0-9_.-]*/' "$THEME_ROOT"/Hornero-* 2>/dev/null \
    | grep -v '/home/user/' | grep -q .; then
  fail "hardcoded home path in shipped theme tree"
fi
pass "no hardcoded home paths in shipped theme trees"

# --- materialize audit: theme trees land on the standard lookup path ---------
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
bash "$REPO_ROOT/scripts/materialize.sh" --dest "$STAGE" >/dev/null
for tree in "${TREES[@]}"; do
  for f in index.theme gtk-3.0/gtk.css gtk-4.0/gtk.css gtk-4.0/recolor.css; do
    cmp -s "$THEME_ROOT/$tree/$f" "$STAGE/.local/share/themes/$tree/$f" \
      || fail "materialized themes/$tree/$f differs from source"
  done
done
pass "materialize installs byte-exact Hornero-* trees to .local/share/themes"
# Dev-only sources must not leak into the user install or the recipe dir.
for leaked in src gallery.py README.md; do
  [[ ! -e "$STAGE/.local/share/themes/$leaked" ]] \
    || fail "dev-only $leaked leaked into .local/share/themes"
done
[[ ! -e "$STAGE/.local/share/hornero/themes/Hornero-Signal" ]] \
  || fail "GTK theme tree leaked into hornero/themes recipes (double ownership)"
pass "no dev-only leaks, no double ownership with hornero/themes recipes"

# --- gallery fixture: renders where Gtk exists, skips cleanly headless -------
# timeout(1) bounds the run: a broken display must fail fast, never hang CI.
# The fixture never touches a live desktop unless explicitly requested with
# HORNERO_GALLERY_DISPLAY=1: by default it runs with no display and a private
# runtime dir, so running the suite on a workstation cannot open windows.
gallery_env=(env -u DISPLAY -u WAYLAND_DISPLAY XDG_RUNTIME_DIR="$(mktemp -d)")
if [[ "${HORNERO_GALLERY_DISPLAY:-0}" == "1" ]]; then
  gallery_env=(env)
fi
if timeout 30s "${gallery_env[@]}" python3 "$THEME_ROOT/gallery.py" --theme Hornero-Signal >/tmp/hx-gallery.log 2>&1; then
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
