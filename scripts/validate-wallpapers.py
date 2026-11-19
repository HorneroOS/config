#!/usr/bin/env python3
"""Validate distributed wallpaper metadata, checksums, and theme references.

Two tiers:
- Licensed tier (wallpaper-provenance.json): verified CC photographs with
  full attribution and 2560x1440 processed derivatives.
- Collection tier (wallpaper-collection.json): the owner-curated set.
  license=unknown is allowed only with the explicit owner-curated note;
  no license is ever inferred.
Every file under assets/wallpapers/ must be listed in the collection, and
every non-Signal theme default must resolve to a shipped file.
"""
from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROVENANCE = ROOT / "profiles/themes/wallpaper-provenance.json"
COLLECTION = ROOT / "profiles/themes/wallpaper-collection.json"
MANIFEST = ROOT / "profiles/themes/wallpapers.manifest.json"
CANDIDATES = ROOT / "profiles/themes/wallpaper-candidates.json"
ORG_INVENTORY = ROOT / "profiles/themes/organization-wallpaper-inventory.json"
DOTFILES_AUDIT = ROOT / "profiles/themes/dotfiles-wallpaper-audit.json"
UNKNOWN_NOTE = "owner-curated 2026-11-19, license unverified"
SIGNAL_GENERATED = {"hornero-signal-day-01.png", "hornero-signal-night-01.png"}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    data = json.loads(PROVENANCE.read_text())
    collection = json.loads(COLLECTION.read_text())
    manifest = json.loads(MANIFEST.read_text())
    candidates = json.loads(CANDIDATES.read_text())
    org_inventory = json.loads(ORG_INVENTORY.read_text())
    dotfiles_audit = json.loads(DOTFILES_AUDIT.read_text())
    themes = {row["id"]: row for row in manifest["themes"]}
    errors: list[str] = []

    # --- collection tier ---
    by_file: dict[str, dict] = {}
    cids: set[str] = set()
    for item in collection["items"]:
        ident = item.get("id")
        if not ident or ident in cids:
            errors.append(f"missing or duplicate collection id: {ident!r}")
        cids.add(ident)
        by_file[item.get("file")] = item
        if not item.get("sourceFile") or not item.get("sourceSha256"):
            errors.append(f"{ident}: missing sourceFile/sourceSha256")
        if item.get("license") == "unknown":
            if item.get("note") != UNKNOWN_NOTE:
                errors.append(f"{ident}: unknown license requires note {UNKNOWN_NOTE!r}")
        elif not item.get("license"):
            errors.append(f"{ident}: missing license")
        path = ROOT / item["file"]
        if not path.is_file():
            errors.append(f"{ident}: missing file {item['file']}")
            continue
        if sha256(path) != item.get("sha256"):
            errors.append(f"{ident}: SHA-256 mismatch")
        if item.get("sha256") != item.get("sourceSha256"):
            errors.append(f"{ident}: shipped file is not byte-identical to curated source")
        if path.stat().st_size != item.get("bytes"):
            errors.append(f"{ident}: file size mismatch")
        if item.get("themeId"):
            theme = themes.get(item["themeId"])
            if not theme:
                errors.append(f"{ident}: unknown theme {item['themeId']!r}")
            elif theme["defaultWallpaper"] != path.name or theme["wallpaperDir"] != item.get("installDir"):
                errors.append(f"{ident}: theme default and collection file disagree")
    on_disk = {str(p.relative_to(ROOT)) for p in (ROOT / "assets/wallpapers").rglob("*") if p.is_file()}
    for extra in sorted(on_disk - set(by_file)):
        errors.append(f"unregistered wallpaper file: {extra}")
    for row in manifest["themes"]:
        if row["defaultWallpaper"] in SIGNAL_GENERATED:
            continue
        rel = f"assets/wallpapers/{row['wallpaperDir']}/{row['defaultWallpaper']}"
        if rel not in by_file:
            errors.append(f"{row['id']}: default wallpaper is not shipped: {rel}")

    # --- licensed tier ---
    ids: set[str] = set()
    for item in data["items"]:
        ident = item.get("id")
        if not ident or ident in ids:
            errors.append(f"missing or duplicate wallpaper id: {ident!r}")
        ids.add(ident)
        for field in ("title", "place", "photographer", "sourcePage", "originalImageSource", "license", "licenseUrl", "attribution", "modification"):
            if not item.get(field):
                errors.append(f"{ident}: missing {field}")
        if item.get("license") not in {"CC BY 2.0", "CC BY-SA 4.0"}:
            errors.append(f"{ident}: unapproved license {item.get('license')!r}")
        coll = by_file.get(item.get("processedFile"))
        if not coll or coll.get("license") != item.get("license"):
            errors.append(f"{ident}: licensed item missing from collection with same license")
        theme = themes.get(item.get("themeId"))
        if not theme:
            errors.append(f"{ident}: unknown theme {item.get('themeId')!r}")
        elif theme["defaultWallpaper"] != Path(item["processedFile"]).name:
            errors.append(f"{ident}: default wallpaper and processed file disagree")
        path = ROOT / item["processedFile"]
        if not path.is_file():
            errors.append(f"{ident}: missing processed file {path.relative_to(ROOT)}")
            continue
        if sha256(path) != item.get("processedSha256"):
            errors.append(f"{ident}: processed SHA-256 mismatch")
        if path.stat().st_size != item.get("processedBytes"):
            errors.append(f"{ident}: processed file size mismatch")
        if item.get("processedDimensions") != {"width": 2560, "height": 1440}:
            errors.append(f"{ident}: expected 2560x1440 output")
    selected = {row["themeId"] for row in candidates.get("themes", [])}
    if selected != {item["themeId"] for item in data["items"]}:
        errors.append("candidate report selections do not cover the licensed distributed photos")
    for row in candidates.get("themes", []):
        if not row.get("candidates") or sum(c.get("decision") == "selected" for c in row["candidates"]) != 1:
            errors.append(f"{row.get('themeId')}: candidate report must identify exactly one selected source")
    if org_inventory.get("schemaVersion") != 1 or not org_inventory.get("repositoryPins"):
        errors.append("organization inventory is missing repository coverage")
    if dotfiles_audit.get("sourceCommit") != "88a34fd58699fe4941b5b17c455df181479a2a57":
        errors.append("dotfiles audit is not pinned to the audited source commit")
    if len(dotfiles_audit.get("items", [])) != 64:
        errors.append("dotfiles audit does not cover all 64 source-root entries")
    if errors:
        print("WALLPAPER-FAIL:", file=sys.stderr)
        for error in errors:
            print(f"  - {error}", file=sys.stderr)
        return 1
    print(f"WALLPAPER-PASS: {len(cids)} collection assets ({len(ids)} licensed) and theme references validated")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
