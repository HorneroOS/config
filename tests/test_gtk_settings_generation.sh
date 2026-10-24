#!/usr/bin/env bash
# Verify factory GTK settings are generated from the factory theme contract.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GENERATOR="$REPO_ROOT/scripts/generate-gtk-settings.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

"$GENERATOR" --check >/dev/null

# The real materializer must stage the generated contract for both GTK versions.
bash "$REPO_ROOT/scripts/materialize.sh" --dest "$TMP/materialized-home" >/dev/null
for version in 3.0 4.0; do
  cmp "$REPO_ROOT/desktop/gtk/settings.ini" \
    "$TMP/materialized-home/.config/gtk-$version/settings.ini"
done

# Build a minimal disposable fixture and deliberately stale its generated file.
python3 - "$REPO_ROOT" "$TMP/root" <<'PY'
import json
import sys
from pathlib import Path
from shutil import copyfile

source = Path(sys.argv[1])
fixture = Path(sys.argv[2])
factory = json.loads((source / "profiles/factory.json").read_text(encoding="utf-8"))
theme_id = factory["defaultTheme"]
theme_path = Path("profiles/themes") / theme_id / "theme.json"
recipe = json.loads((source / theme_path).read_text(encoding="utf-8"))
for relative in (
    Path("profiles/factory.json"),
    theme_path,
    Path("desktop/gtk/settings.ini.in"),
    Path("desktop/gtk/settings.ini"),
):
    destination = fixture / relative
    destination.parent.mkdir(parents=True, exist_ok=True)
    copyfile(source / relative, destination)
(fixture / "expected-gtk-theme-name").write_text(recipe["gtkTheme"], encoding="utf-8")
PY

"$GENERATOR" --root "$TMP/root" --check >/dev/null
python3 - "$TMP/root" <<'PY'
import sys
from pathlib import Path

root = Path(sys.argv[1])
path = root / "desktop/gtk/settings.ini"
theme_name = (root / "expected-gtk-theme-name").read_text(encoding="utf-8")
old_name = f"gtk-theme-name={theme_name}"
content = path.read_text(encoding="utf-8")
if old_name not in content:
    raise SystemExit("GTKSETTINGS-FAIL: generated fixture has no default theme setting")
path.write_text(content.replace(old_name, "gtk-theme-name=Stale-Theme", 1), encoding="utf-8")
PY
if "$GENERATOR" --root "$TMP/root" --check >/dev/null 2>&1; then
  echo "GTKSETTINGS-FAIL: stale fixture unexpectedly passed" >&2
  exit 1
fi

echo "GTKSETTINGS-TEST-PASS: clean and deliberately stale fixtures classified correctly"
