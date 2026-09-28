#!/usr/bin/env bash
# test_catalogue.sh - the theme catalogue contract.
#
# generate-catalogue.py must derive catalogue/registry.json from
# profiles/themes/*/theme.json deterministically: regenerating must
# produce a byte-identical file, every pack dir must appear exactly
# once, and every entry must carry the offline-cache keys a
# store-style surface needs (mode, wallpaper refs).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_HOME="$(mktemp -d)"
trap 'rm -rf "$TMP_HOME"' EXIT

OUT="$TMP_HOME/registry.json"
"$REPO_ROOT/scripts/generate-catalogue.py" --root "$REPO_ROOT" --out "$OUT" >/dev/null

diff -u "$REPO_ROOT/catalogue/registry.json" "$OUT" \
  || { echo "TEST-FAIL: catalogue/registry.json is stale; regenerate it" >&2; exit 1; }
echo "TEST-PASS: catalogue registry is fresh"

python3 - "$OUT" "$REPO_ROOT" <<'EOF'
import json
import sys
from pathlib import Path

doc = json.load(open(sys.argv[1], encoding="utf-8"))
root = Path(sys.argv[2])
assert doc["schemaVersion"] == 1, "schemaVersion must be 1"
packs = sorted(p.parent.name for p in (root / "profiles/themes").glob("*/theme.json"))
ids = [e["id"] for e in doc["entries"]]
assert ids == packs, f"registry ids {ids} != pack dirs {packs}"
assert doc["count"] == len(packs), "count must match pack dirs"
required = {"id", "name", "mode", "defaultWallpaper", "wallpaperDir"}
for entry in doc["entries"]:
    missing = required - set(entry)
    assert not missing, f"{entry['id']}: missing keys {missing}"
    assert entry["mode"] in ("dark", "light"), f"{entry['id']}: bad mode"
print(f"TEST-PASS: {len(ids)} catalogue entries cover every pack")
EOF
