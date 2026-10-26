#!/usr/bin/env bash
# validate.sh - syntax-validate every shipped config format. No HOME writes.
# Usage: scripts/validate.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAIL=0
pass() { echo "VALIDATE-PASS: $1"; }
fail() { echo "VALIDATE-FAIL: $1" >&2; FAIL=1; }

# --- shell (shellcheck when available) -----------------------------------------
if command -v shellcheck >/dev/null 2>&1; then
  # Gate severity is `error`: every shipped shell file is still checked, but
  # pre-existing upstream warnings (SC1090 runtime XDG sourcing, SC2034 registry
  # vars consumed cross-file, SC2154 easyoptions-provided `arguments`) do not
  # fail the build. See docs/DECISIONS.md.
  if shellcheck -S error "$REPO_ROOT"/scripts/*.sh "$REPO_ROOT"/lib/hornero/*.sh \
      "$REPO_ROOT"/lib/hornero/easy-options/*.sh "$REPO_ROOT"/bin/hornero-* \
      "$REPO_ROOT"/tests/*.sh; then
    pass "shellcheck"
  else
    fail "shellcheck"
  fi
else
  echo "VALIDATE-SKIP: shellcheck not installed" >&2
fi

# --- Ghostty native parser (optional on non-Arch hosts) -------------------------
if command -v ghostty >/dev/null 2>&1; then
  if bash "$REPO_ROOT/scripts/validate-ghostty-config.sh"; then
    pass "Ghostty config and fallback theme"
  else
    fail "Ghostty config and fallback theme"
  fi
else
  echo "VALIDATE-SKIP: Ghostty native parser is not installed" >&2
fi

if python3 "$REPO_ROOT/scripts/validate-wallpapers.py"; then
  pass "licensed wallpaper assets and provenance"
else
  fail "licensed wallpaper assets and provenance"
fi

# --- structured formats via python stdlib ---------------------------------------
if python3 "$REPO_ROOT/scripts/validate_kitty_remote_control.py" \
    "$REPO_ROOT/desktop/kitty/kitty.conf"; then
  pass "Kitty remote control is explicitly disabled"
else
  fail "Kitty remote control is explicitly disabled"
fi

if ! python3 - "$REPO_ROOT" <<'PY'
import configparser, json, re, sys, tomllib, xml.etree.ElementTree as ET
from pathlib import Path
root = Path(sys.argv[1])
errors = []
def err(msg): errors.append(msg)

# JSON: theme packs + manifest (strict)
for f in sorted((root/"profiles"/"themes").rglob("*.json")):
    try: json.loads(f.read_text())
    except Exception as e: err(f"{f}: {e}")
# theme.json schema minimum
for f in sorted((root/"profiles"/"themes").glob("*"+"/theme.json")):
    try:
        d = json.loads(f.read_text())
        for k in ("schemaVersion","id","name","defaultWallpaper","wallpaperDir"):
            if k not in d: err(f"{f}: missing key {k}")
        if d["id"] != f.parent.name: err(f"{f}: id mismatch with directory")
    except Exception as e: err(f"{f}: {e}")

# JSONC: fastfetch (strip // and /* */ comments)
ff = root/"desktop"/"fastfetch"/"config.jsonc"
try:
    text = ff.read_text()
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    text = re.sub(r"(?m)(^|[^:])//.*$", r"\1", text)
    json.loads(text)
except Exception as e: err(f"{ff}: {e}")

# TOML: handlr + base profile
for f in (root/"xdg"/"handlr"/"handlr.toml", root/"profiles"/"base"/"profile.toml",
          root/"desktop"/"alacritty"/"alacritty.toml",
          root/"desktop"/"alacritty"/"hornero-dark.toml",
          root/"desktop"/"alacritty"/"hornero-light.toml",
          root/"desktop"/"alacritty"/"hornero-colors.toml"):
    try: tomllib.loads(f.read_text())
    except Exception as e: err(f"{f}: {e}")

# Ghostty uses a line-oriented key=value config and native palette theme files.
ghostty_config = root/"desktop"/"ghostty"/"config.ghostty"
for line_no, line in enumerate(ghostty_config.read_text().splitlines(), 1):
    stripped = line.strip()
    if stripped and not stripped.startswith("#") and "=" not in stripped:
        err(f"{ghostty_config}:{line_no}: expected key = value")
ghostty_theme = root/"desktop"/"ghostty"/"themes"/"Hornero Dynamic"
palette_entries = 0
for line_no, line in enumerate(ghostty_theme.read_text().splitlines(), 1):
    stripped = line.strip()
    if not stripped or stripped.startswith("#"): continue
    if not re.fullmatch(r"palette = (?:[0-9]|1[0-5])=#[0-9A-Fa-f]{6}", stripped) and not re.fullmatch(
        r"(?:background|foreground|cursor-color|cursor-text|selection-background|selection-foreground) = #[0-9A-Fa-f]{6}", stripped
    ):
        err(f"{ghostty_theme}:{line_no}: invalid Ghostty theme entry: {stripped}")
    if stripped.startswith("palette = "): palette_entries += 1
if palette_entries != 16: err(f"{ghostty_theme}: expected 16 palette entries, got {palette_entries}")

# INI with sections: gtk settings, thunar renamerc, copyq
for f in (root/"desktop"/"gtk"/"settings.ini",
          root/"desktop"/"thunar"/"renamerc",
          root/"desktop"/"copyq"/"copyq.conf"):
    try:
        cp = configparser.ConfigParser(strict=True)
        cp.read_string(f.read_text())
        if not cp.sections(): err(f"{f}: no sections parsed")
    except Exception as e: err(f"{f}: {e}")

# btop.conf is sectionless key=value: every non-empty non-comment line needs '='
btop = root/"desktop"/"btop"/"btop.conf"
n = 0
for line in btop.read_text().splitlines():
    s = line.strip()
    if not s or s.startswith("#"): continue
    n += 1
    if "=" not in s: err(f"{btop}: line without '=': {s[:60]}")
if n == 0: err(f"{btop}: no settings parsed")

btop_theme = root/"desktop"/"btop"/"themes"/"Hornero Dynamic.theme"
theme_keys = set()
for line in btop_theme.read_text().splitlines():
    s = line.strip()
    if not s or s.startswith("#"): continue
    m = re.fullmatch(r'theme\[([a-z_]+)\]="([^"]*)"', s)
    if not m: err(f"{btop_theme}: invalid theme setting: {s[:60]}")
    else: theme_keys.add(m.group(1))
if len(theme_keys) != 42: err(f"{btop_theme}: expected 42 unique native theme colors, found {len(theme_keys)}")

# cava config: sectionless key=value with ';'-comments
cava = root/"desktop"/"cava"/"config"
n = 0
for line in cava.read_text().splitlines():
    s = line.strip()
    if not s or s.startswith("#") or s.startswith(";") or (s.startswith("[") and s.endswith("]")): continue
    n += 1
    if "=" not in s: err(f"{cava}: line without '=': {s[:60]}")
if n == 0: err(f"{cava}: no settings parsed")

cava_theme = root/"desktop"/"cava"/"themes"/"Hornero Dynamic"
try:
    cp = configparser.ConfigParser(strict=True, interpolation=None)
    cp.read_string(cava_theme.read_text())
    if "color" not in cp: err(f"{cava_theme}: missing [color] section")
    elif cp["color"].getint("gradient_count", fallback=0) != 4:
        err(f"{cava_theme}: expected four generated gradient colors")
except Exception as e: err(f"{cava_theme}: {e}")

# XML: fontconfig + thunar custom actions
for f in (root/"desktop"/"fontconfig"/"fonts.conf", root/"desktop"/"thunar"/"uca.xml"):
    try: ET.fromstring(f.read_text())
    except Exception as e: err(f"{f}: {e}")

# thunar accels: s-expression lines
acc = root/"desktop"/"thunar"/"accels.scm"
for line in acc.read_text().splitlines():
    s = line.strip()
    if s and not (s.startswith("(") and s.endswith(")")):
        err(f"{acc}: not an s-expr: {s[:60]}")

if errors:
    print("VALIDATE-FAIL: structured formats", file=sys.stderr)
    for e in errors: print("  -", e, file=sys.stderr)
    sys.exit(1)
PY
then
  fail "structured formats"
else
  pass "structured formats (json/jsonc/toml/ini/btop/cava/xml/scm)"
fi

# --- git config parses ------------------------------------------------------------
if git config --file "$REPO_ROOT/xdg/git/config" --list >/dev/null 2>&1; then
  pass "git config syntax"
else
  fail "git config syntax"
fi

# --- hypr sanity: Lua-only config, luac parses, modules resolve -----------------
HYPR_FAIL=0
if grep -rn "{{" "$REPO_ROOT/desktop/hypr" 2>/dev/null; then
  fail "hypr chezmoi leftovers"; HYPR_FAIL=1
fi
if [[ -e "$REPO_ROOT/desktop/hypr/hyprland.conf" || -d "$REPO_ROOT/desktop/hypr/hyprland.conf.d" ]]; then
  echo "VALIDATE-FAIL: legacy hyprlang config remains under desktop/hypr (hypridle/hyprlock .conf belong to separate apps and are exempt only at the top level)" >&2
  HYPR_FAIL=1; FAIL=1
fi
for f in "$REPO_ROOT"/desktop/hypr/hyprland.lua "$REPO_ROOT"/desktop/hypr/hyprland.lua.d/*.lua \
         "$REPO_ROOT"/desktop/hypr/scripts/*.lua; do
  if command -v luac >/dev/null 2>&1; then
    if ! luac -p "$f"; then
      echo "VALIDATE-FAIL: luac -p failed: $f" >&2
      HYPR_FAIL=1; FAIL=1
    fi
  fi
  if grep -qE "hyprland\.conf|scripts/[A-Za-z-]+\.sh" "$f"; then
    echo "VALIDATE-FAIL: dangling legacy reference in $f" >&2
    HYPR_FAIL=1; FAIL=1
  fi
done
while IFS= read -r mod; do
  if [[ ! -e "$REPO_ROOT/desktop/hypr/hyprland.lua.d/$mod" ]]; then
    echo "VALIDATE-FAIL: hyprland.lua loads missing module: $mod" >&2
    HYPR_FAIL=1; FAIL=1
  fi
done < <(grep -oE 'dofile\(here \.\. "[^"]+"\)' "$REPO_ROOT/desktop/hypr/hyprland.lua" | sed -E 's/.*here \.\. "//; s/"\)//')
[[ $HYPR_FAIL -eq 0 ]] && pass "hypr sanity (Lua-only, luac -p, modules resolve, no legacy refs)"

# --- Niri config ---------------------------------------------------------------
NIRI_CONFIG="$REPO_ROOT/desktop/niri/config.kdl"
if [[ ! -s "$NIRI_CONFIG" ]]; then
  fail "Niri config missing or empty"
elif command -v niri >/dev/null 2>&1; then
  if NIRI_CONFIG="$NIRI_CONFIG" niri validate; then
    pass "Niri config parses with installed niri"
  else
    fail "Niri config parser"
  fi
else
  # Static contract only: this is not a substitute for upstream niri validate.
  grep -q '^binds {' "$NIRI_CONFIG" \
    && grep -q 'NIRI_SOCKET=' "$NIRI_CONFIG" \
    && grep -q 'horneroctl shell start --yes' "$NIRI_CONFIG" \
    && grep -q 'Mod+Shift+B.*layoutPicker' "$NIRI_CONFIG" \
    && pass "Niri config presence and Hornero binding contract (niri parser unavailable)" \
    || fail "Niri config Hornero binding contract"
fi

# --- Hornero GTK theme (parser errors + index.theme + src sync) -----------------
if ! python3 - "$REPO_ROOT" <<'PY'
import configparser, re, sys
from pathlib import Path
root = Path(sys.argv[1])
errors = []
def err(msg): errors.append(msg)
for variant in ("Hornero-Dark", "Hornero-Light", "Hornero-Pampa", "Hornero-Nocturno", "Hornero-FinDelMundo", "Hornero-Ibera", "Hornero-Iguazu", "Hornero-Patagonia", "Hornero-199X", "Hornero-Cuyo", "Hornero-Quebrada", "Hornero-Sierras"):
    tdir = root / "desktop/gtk-theme" / variant
    try:
        idx = configparser.ConfigParser(strict=True)
        idx.read_string((tdir / "index.theme").read_text())
        if idx.get("X-GNOME-Metatheme", "GtkTheme", fallback=None) != variant:
            err(f"{variant}/index.theme GtkTheme mismatch")
    except Exception as e:
        err(f"{variant}/index.theme: {e}")
    for ver in ("gtk-3.0", "gtk-4.0"):
        try:
            bare = re.sub(r"/\*.*?\*/", "", (tdir / ver / "gtk.css").read_text(), flags=re.S)
        except Exception as e:
            err(f"{variant}/{ver}/gtk.css unreadable: {e}")
            continue
        if bare.count("{") != bare.count("}"):
            err(f"{variant}/{ver}/gtk.css unbalanced braces (parser error)")
        for m in re.finditer(r"@define-color\s+\S+\s+([^;]+);", bare):
            if not re.fullmatch(r"#[0-9a-fA-F]{6}", m.group(1).strip()):
                err(f"{variant}/{ver}/gtk.css bad @define-color value")
if errors:
    print("VALIDATE-FAIL: GTK theme", file=sys.stderr)
    for e in errors: print("  -", e, file=sys.stderr)
    sys.exit(1)
PY
then
  fail "GTK theme (gtk.css parse + index.theme)"
else
  pass "GTK theme (gtk.css parse + index.theme)"
fi
if bash "$REPO_ROOT/desktop/gtk-theme/build.sh" --check >/dev/null 2>&1; then
  pass "GTK theme outputs in sync with src/"
else
  fail "GTK theme outputs drifted from src/ (run desktop/gtk-theme/build.sh)"
fi

# --- appearance contrast (WCAG AA, fails the build on violation) ------------------
if python3 "$REPO_ROOT/scripts/check-contrast.py" --themes-dir "$REPO_ROOT/profiles/themes"; then
  pass "appearance contrast (WCAG AA)"
else
  fail "appearance contrast (WCAG AA)"
fi

# --- brand SVGs: well-formed XML, vector-only, self-contained ----------------------
if python3 - "$REPO_ROOT/assets/brand" <<'PY'
import re, sys, xml.etree.ElementTree as ET
from pathlib import Path
brand = Path(sys.argv[1])
errors = []
required = ["logo.svg", "logo-symbolic.svg", "logo-mono.svg", "logo-dark.svg",
            "logo-light.svg", "wordmark.svg", "favicon.svg",
            "icons/hornero-app.svg", "icons/hornero-system.svg",
            "wallpaper/hornero-dark.svg", "wallpaper/hornero-light.svg"]
for rel in required:
    if not (brand / rel).is_file():
        errors.append(f"missing required brand asset: {rel}")
for f in sorted(brand.rglob("*.svg")):
    try:
        ET.parse(f)
    except Exception as e:
        errors.append(f"{f}: not well-formed: {e}")
    text = f.read_text()
    if "<image" in text or "data:image" in text:
        errors.append(f"{f}: embedded raster (binaries are never vendored)")
    body = re.sub(r'xmlns(?::\w+)?="[^"]*"', "", text)
    if re.search(r"https?://", body):
        errors.append(f"{f}: external reference (must be self-contained)")
if errors:
    for e in errors:
        print(f"VALIDATE-FAIL: brand {e}", file=sys.stderr)
    sys.exit(1)
print(f"VALIDATE-PASS: brand SVGs ({len(required)} required present)")
PY
then
  pass "brand SVGs (well-formed, vector-only, self-contained)"
else
  fail "brand SVGs"
fi

# --- personal-data guard ------------------------------------------------------------
if "$REPO_ROOT/scripts/guard-personal-data.sh"; then
  pass "personal-data guard"
else
  fail "personal-data guard"
fi

# --- packaged runtime deps: every shipped helper's imports are declared -----------
# generate-m3-colors.py imports materialyoucolor; without the dependency a
# package-only install cannot switch theme (found by Hornero QA, Preview 13).
if [[ -f "$REPO_ROOT/lib/hornero/generate-m3-colors.py" ]]; then
  if grep -Eq "^depends=\(.*'python-materialyoucolor'" "$REPO_ROOT/packaging/PKGBUILD"; then
    pass "PKGBUILD declares python-materialyoucolor (M3 scheme helper)"
  else
    fail "PKGBUILD depends lacks python-materialyoucolor (lib/hornero/generate-m3-colors.py)"
  fi
fi

if [[ $FAIL -ne 0 ]]; then
  echo "validate.sh: FAIL" >&2
  exit 1
fi
echo "validate.sh: ALL GREEN"
