#!/usr/bin/env python3
"""Validate distributed photo metadata, checksums, and theme references."""
from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROVENANCE = ROOT / "profiles/themes/wallpaper-provenance.json"
MANIFEST = ROOT / "profiles/themes/wallpapers.manifest.json"
CANDIDATES = ROOT / "profiles/themes/wallpaper-candidates.json"
ORG_INVENTORY = ROOT / "profiles/themes/organization-wallpaper-inventory.json"
DOTFILES_AUDIT = ROOT / "profiles/themes/dotfiles-wallpaper-audit.json"


def main() -> int:
    data = json.loads(PROVENANCE.read_text())
    manifest = json.loads(MANIFEST.read_text())
    candidates = json.loads(CANDIDATES.read_text())
    org_inventory = json.loads(ORG_INVENTORY.read_text())
    dotfiles_audit = json.loads(DOTFILES_AUDIT.read_text())
    themes = {row["id"]: row for row in manifest["themes"]}
    errors: list[str] = []
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
        theme = themes.get(item.get("themeId"))
        if not theme:
            errors.append(f"{ident}: unknown theme {item.get('themeId')!r}")
        elif theme["defaultWallpaper"] != Path(item["processedFile"]).name:
            errors.append(f"{ident}: default wallpaper and processed file disagree")
        path = ROOT / item["processedFile"]
        if not path.is_file():
            errors.append(f"{ident}: missing processed file {path.relative_to(ROOT)}")
            continue
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        if digest != item.get("processedSha256"):
            errors.append(f"{ident}: processed SHA-256 mismatch")
        if path.stat().st_size != item.get("processedBytes"):
            errors.append(f"{ident}: processed file size mismatch")
        if item.get("processedDimensions") != {"width": 2560, "height": 1440}:
            errors.append(f"{ident}: expected 2560x1440 output")
    if len(data["items"]) != 9:
        errors.append(f"expected nine curated regional photos, got {len(data['items'])}")
    selected = {row["themeId"] for row in candidates.get("themes", [])}
    if selected != {item["themeId"] for item in data["items"]}:
        errors.append("candidate report selections do not cover the nine distributed photos")
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
    print(f"WALLPAPER-PASS: {len(ids)} licensed photo assets and theme references validated")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
