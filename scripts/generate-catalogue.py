#!/usr/bin/env python3
"""Generate the theme catalogue from profiles/themes/*/theme.json.

Reads every curated theme pack and emits `catalogue/registry.json`:

    {"schemaVersion": 1, "source": "<relpath>", "entries": [
      {"id": "neon-city", "name": "Neon City", "mode": "dark", ...}, ...]}

The registry is the offline cache contract: store-style surfaces render
from this file without touching the packs, and wallpapers stay
fetch-on-demand per profiles/themes/wallpapers.manifest.json (binary
packs are NOT vendored). Deterministic output (sorted entries, trailing
newline) so tests can regenerate + diff.

Usage: python3 scripts/generate-catalogue.py [--root DIR] [--out PATH]
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path


def entry(pack: dict) -> dict:
    return {
        "id": pack["id"],
        "name": pack.get("name", pack["id"]),
        "description": pack.get("description", ""),
        "tags": pack.get("tags", []),
        "mode": "dark" if pack.get("darkMode", True) else "light",
        "family": pack.get("family", ""),
        "version": pack.get("version", pack.get("tokensVersion", "")),
        "schemeType": pack.get("schemeType", ""),
        "defaultWallpaper": pack.get("defaultWallpaper", ""),
        "wallpaperDir": pack.get("wallpaperDir", ""),
    }


def build(root: Path) -> dict:
    themes = root / "profiles" / "themes"
    entries = []
    for path in sorted(themes.glob("*/theme.json")):
        pack = json.loads(path.read_text(encoding="utf-8"))
        entries.append(entry(pack))
    entries.sort(key=lambda e: e["id"])
    return {
        "schemaVersion": 1,
        "source": "profiles/themes",
        "count": len(entries),
        "entries": entries,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", default=".")
    parser.add_argument("--out", default="catalogue/registry.json")
    args = parser.parse_args(argv)
    root = Path(args.root)
    doc = build(root)
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(doc, indent=2, ensure_ascii=False) + "\n",
                   encoding="utf-8")
    print(f"CATALOGUE-PASS: {doc['count']} entries -> {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
