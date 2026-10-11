#!/usr/bin/env python3
"""Recreate the licensed regional wallpaper derivatives from verified masters.

Usage: python3 scripts/process-wallpapers.py --source-dir /path/to/masters
Original source files are intentionally not stored in this repository.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "profiles/themes/wallpaper-provenance.json"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-dir", required=True, type=Path, help="directory containing the six source masters")
    parser.add_argument("--accept-output", action="store_true", help="review derivatives and refresh their recorded hashes")
    args = parser.parse_args()
    manifest = json.loads(MANIFEST.read_text())
    for item in manifest["items"]:
        source = args.source_dir / Path(item["processedFile"]).name
        if not source.is_file() or sha256(source) != item["originalSha256"]:
            print(f"WALLPAPER-FAIL: missing or checksum-mismatched source for {item['id']}", file=sys.stderr)
            return 1
        crop = item["crop"]
        with Image.open(source) as image:
            if [image.width, image.height] != [item["originalDimensions"]["width"], item["originalDimensions"]["height"]]:
                print(f"WALLPAPER-FAIL: source dimensions mismatch for {item['id']}", file=sys.stderr)
                return 1
            if crop["method"] == "center-crop-16:9":
                x, y, width, height = (crop[k] for k in ("x", "y", "width", "height"))
                image = image.crop((x, y, x + width, y + height))
            elif crop["method"] != "none":
                print(f"WALLPAPER-FAIL: invalid crop recipe for {item['id']}", file=sys.stderr)
                return 1
            image = image.resize((2560, 1440), Image.Resampling.LANCZOS).convert("RGB")
            output = ROOT / item["processedFile"]
            output.parent.mkdir(parents=True, exist_ok=True)
            temporary = output.with_suffix(output.suffix + ".tmp")
            image.save(temporary, format="JPEG", quality=88, optimize=True, progressive=False, subsampling=0)
        output_hash = sha256(temporary)
        if output_hash != item["processedSha256"] and not args.accept_output:
            temporary.unlink()
            print(f"WALLPAPER-FAIL: output differs from reviewed derivative for {item['id']}; inspect, then use --accept-output", file=sys.stderr)
            return 1
        os.replace(temporary, output)
        item["processedSha256"] = output_hash
        item["processedBytes"] = output.stat().st_size
        print(f"WALLPAPER-PASS: {item['id']}")
    if args.accept_output:
        MANIFEST.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n")
        print("WALLPAPER-INFO: recorded output hashes; inspect derivatives before committing")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
