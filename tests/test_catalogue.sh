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
assert doc["schemaVersion"] == 2, "schemaVersion must be 2"
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

signal = {"hornero-signal-night", "hornero-signal-day", "hornero-signal-contrast", "hornero-signal-dusk"}
assert {i for i, e in entries.items() if e["collection"] == "hornero-signal"} == signal
assert [entries[i]["collectionOrder"] for i in
        ("hornero-signal-night", "hornero-signal-day", "hornero-signal-contrast", "hornero-signal-dusk")] == [1, 2, 3, 4]
originals = {
    "patagonia", "quebrada", "ibera", "fin-del-mundo", "buenos-aires-nocturno",
    "pampa", "cuyo", "iguazu", "sierras", "jacaranda", "glaciar", "ceibo",
}
assert {i for i, e in entries.items() if e["collection"] == "hornero-originals"} == originals
assert sorted(entries[i]["collectionOrder"] for i in originals) == list(range(1, 13))
assert {entries[i]["mode"] for i in originals} == {"light", "dark"}
removed = {"hornero-dark", "hornero-light", "hornero-199x", "neon-city",
           "vapor-dreams", "soft-morning", "warm-sunset"}
assert not removed & set(entries), f"retired themes still shipped: {removed & set(entries)}"
for entry in doc["entries"]:
    assert set(entry["swatch"]) == {"base", "panel", "ink", "signal", "cue"}
    assert "schemeType" not in entry and "model" not in entry, "M3-era catalogue keys"
print(f"TEST-PASS: {len(ids)} catalogue entries cover every pack")
print(f"TEST-PASS: {len(signal)} Signal flagships + {len(originals)} Hornero Originals, retired packs absent")
print(f"TEST-PASS: wallpaper manifest covers {len(wallpaper_ids)} packs without drift")
EOF
