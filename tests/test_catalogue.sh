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
entries = {entry["id"]: entry for entry in doc["entries"]}
for entry in doc["entries"]:
    missing = required - set(entry)
    assert not missing, f"{entry['id']}: missing keys {missing}"
    assert entry["mode"] in ("dark", "light"), f"{entry['id']}: bad mode"

manifest = json.loads((root / "profiles/themes/wallpapers.manifest.json").read_text())
wallpaper_refs = manifest["themes"]
wallpaper_ids = [item["id"] for item in wallpaper_refs]
assert len(wallpaper_ids) == len(set(wallpaper_ids)), "duplicate wallpaper theme id"
assert set(wallpaper_ids) == set(packs), "wallpaper manifest must cover every theme pack"
for item in wallpaper_refs:
    entry = entries[item["id"]]
    assert item["wallpaperDir"] == entry["wallpaperDir"], f"{item['id']}: wallpaper directory drift"
    assert item["defaultWallpaper"] == entry["defaultWallpaper"], f"{item['id']}: default wallpaper drift"

patagonia = entries["patagonia"]
fin_del_mundo = entries["fin-del-mundo"]
assert patagonia["schemeType"] == "fidelity", "Patagonia should keep the wallpaper palette close to its source"
assert fin_del_mundo["schemeType"] == "expressive", "Fin del Mundo should use its more varied palette"
originals = {
    "hornero-dark", "hornero-light", "pampa", "patagonia", "fin-del-mundo",
    "quebrada", "ibera", "buenos-aires-nocturno",
}
assert {theme_id for theme_id, entry in entries.items() if entry["collection"] == "hornero-originals"} == originals
assert sorted(entries[theme_id]["collectionOrder"] for theme_id in originals) == list(range(1, 9))
assert all(entries[theme_id]["model"] == "semantic" for theme_id in ("hornero-dark", "hornero-light", "pampa"))
assert all(entries[theme_id]["model"] == "recipe" for theme_id in originals - {"hornero-dark", "hornero-light", "pampa"})
assert {entries[theme_id]["mode"] for theme_id in ("quebrada", "ibera", "buenos-aires-nocturno")} == {"light", "dark"}
print(f"TEST-PASS: {len(ids)} catalogue entries cover every pack")
print(f"TEST-PASS: {len(originals)} Hornero Originals retain their semantic-or-recipe model")
print(f"TEST-PASS: wallpaper manifest covers {len(wallpaper_ids)} packs without drift")
EOF
