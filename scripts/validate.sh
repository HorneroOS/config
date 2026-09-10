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
  if shellcheck -S error "$REPO_ROOT"/scripts/*.sh "$REPO_ROOT"/lib/dots/*.sh \
      "$REPO_ROOT"/lib/dots/easy-options/*.sh "$REPO_ROOT"/bin/dots-* \
      "$REPO_ROOT"/desktop/hypr/scripts/*.sh "$REPO_ROOT"/tests/*.sh; then
    pass "shellcheck"
  else
    fail "shellcheck"
  fi
else
  echo "VALIDATE-SKIP: shellcheck not installed" >&2
fi

# --- structured formats via python stdlib ---------------------------------------
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
for f in (root/"xdg"/"handlr"/"handlr.toml", root/"profiles"/"base"/"profile.toml"):
    try: tomllib.loads(f.read_text())
    except Exception as e: err(f"{f}: {e}")

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

# cava config: sectionless key=value with ';'-comments
cava = root/"desktop"/"cava"/"config"
n = 0
for line in cava.read_text().splitlines():
    s = line.strip()
    if not s or s.startswith("#") or s.startswith(";") or (s.startswith("[") and s.endswith("]")): continue
    n += 1
    if "=" not in s: err(f"{cava}: line without '=': {s[:60]}")
if n == 0: err(f"{cava}: no settings parsed")

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

# --- hypr sanity: no templates, braces balance, shipped sources resolve ------------
HYPR_FAIL=0
if grep -rn "{{" "$REPO_ROOT/desktop/hypr" 2>/dev/null; then
  fail "hypr chezmoi leftovers"; HYPR_FAIL=1
fi
for f in "$REPO_ROOT"/desktop/hypr/hyprland.conf "$REPO_ROOT"/desktop/hypr/hyprland.conf.d/*.conf \
         "$REPO_ROOT"/desktop/hypr/hypridle.conf "$REPO_ROOT"/desktop/hypr/hyprlock.conf; do
  open=$(tr -cd '{' < "$f" | wc -c)
  close=$(tr -cd '}' < "$f" | wc -c)
  if [[ $open -ne $close ]]; then
    echo "VALIDATE-FAIL: unbalanced braces in $f ($open vs $close)" >&2
    HYPR_FAIL=1; FAIL=1
  fi
done
while IFS= read -r src; do
  # source = $XDG_CONFIG_HOME/hypr/<rel> must exist under desktop/hypr/
  rel="${src##*/hypr/}"
  if [[ ! -e "$REPO_ROOT/desktop/hypr/$rel" ]]; then
    echo "VALIDATE-FAIL: hypr source target missing: $src" >&2
    HYPR_FAIL=1; FAIL=1
  fi
done < <(grep -rhoE "source *= *[^ ]*hypr/[^ ]+" "$REPO_ROOT/desktop/hypr/hyprland.conf" | sed -E 's/.*hypr\///')
[[ $HYPR_FAIL -eq 0 ]] && pass "hypr sanity (no templates, balanced, sources resolve)"

# --- personal-data guard ------------------------------------------------------------
if "$REPO_ROOT/scripts/guard-personal-data.sh"; then
  pass "personal-data guard"
else
  fail "personal-data guard"
fi

if [[ $FAIL -ne 0 ]]; then
  echo "validate.sh: FAIL" >&2
  exit 1
fi
echo "validate.sh: ALL GREEN"
