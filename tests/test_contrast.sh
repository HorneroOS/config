#!/usr/bin/env bash
# test_contrast.sh - flagship token themes pass WCAG AA + stay MIT-only.
# Fails (nonzero exit) on any contrast violation so CI stays red.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Flagship packs exist with the versioned semantic token model.
for theme in hornero-dark hornero-light; do
  if [[ -f "$REPO_ROOT/profiles/themes/$theme/theme.json" ]]; then
    echo "TEST-PASS: flagship pack $theme present"
  else
    echo "TEST-FAIL: flagship pack $theme missing" >&2
    exit 1
  fi
  if python3 -c "import json; d=json.load(open('$REPO_ROOT/profiles/themes/$theme/theme.json')); assert d['family']=='hornero' and d['tokensVersion'] and d['palette'] and d['components'], 'token model incomplete'"; then
    echo "TEST-PASS: $theme carries versioned token model"
  else
    echo "TEST-FAIL: $theme token model incomplete" >&2
    exit 1
  fi
done

# Mode selectors are first-class (not an inverted duplicate): dark and light
# disagree on darkMode/gtkPreferDark and ship distinct ramps.
if python3 - "$REPO_ROOT/profiles/themes" <<'PY'
import json, sys
base = sys.argv[1]
dark = json.load(open(f"{base}/hornero-dark/theme.json"))
light = json.load(open(f"{base}/hornero-light/theme.json"))
assert dark["mode"] == "dark" and light["mode"] == "light"
assert dark["darkMode"] is True and light["darkMode"] is False
assert dark["gtkPreferDark"] is True and light["gtkPreferDark"] is False
assert dark["palette"]["background"] != light["palette"]["background"]
assert dark["palette"]["primary"] != light["palette"]["primary"]
PY
then
  echo "TEST-PASS: dark and light are first-class distinct ramps"
else
  echo "TEST-FAIL: flagship modes not first-class distinct" >&2
  exit 1
fi

# WCAG AA gate: every text-on-surface pair >= 4.5:1.
"$REPO_ROOT/scripts/check-contrast.py" --themes-dir "$REPO_ROOT/profiles/themes"
echo "TEST-PASS: WCAG AA contrast gate green"

# MIT-only: no GPL-licensed code in the shipped appearance artifacts
# (this test file itself names the forbidden strings, so it is not scanned).
if grep -ri "GPL\|General Public License" "$REPO_ROOT/profiles/themes/hornero-dark" \
    "$REPO_ROOT/profiles/themes/hornero-light" "$REPO_ROOT/profiles/themes/tokens.schema.json" \
    "$REPO_ROOT/scripts/check-contrast.py" 2>/dev/null; then
  echo "TEST-FAIL: GPL reference in appearance deliverable (MIT-only)" >&2
  exit 1
fi
echo "TEST-PASS: appearance deliverable MIT-only (no GPL references)"

# Wallpapers stay refs-only: manifest mentions the flagship dirs, no binaries vendored.
for theme in hornero-dark hornero-light; do
  if python3 -c "import json; m=json.load(open('$REPO_ROOT/profiles/themes/wallpapers.manifest.json')); assert any(t['wallpaperDir']=='$theme' for t in m['themes']), 'missing manifest ref'"; then
    echo "TEST-PASS: wallpapers manifest refs $theme (no binaries)"
  else
    echo "TEST-FAIL: wallpapers manifest missing $theme ref" >&2
    exit 1
  fi
  if find "$REPO_ROOT/profiles/themes/$theme" -iname '*.jpg' -o -iname '*.png' -o -iname '*.webp' | grep -q .; then
    echo "TEST-FAIL: binary wallpaper vendored under $theme" >&2
    exit 1
  fi
done

echo "test_contrast.sh: ALL GREEN"
