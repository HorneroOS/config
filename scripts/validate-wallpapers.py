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

Optional audit/budget flags (non-breaking to scripts/validate.sh):
  --audit-licenses          Print verified vs unverified provenance & size summary
  --json                    Emit audit report as JSON (implies --audit-licenses)
  --max-unverified-bytes N  Fail if total unverified legacy bytes exceed N
  --max-file-bytes N        Fail if any single collection file exceeds N bytes
"""
from __future__ import annotations

import argparse
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
BRAND_WALLPAPERS = ROOT / "assets/brand/wallpaper"
UNKNOWN_NOTE = "owner-curated 2026-11-19, license unverified"
SIGNAL_GENERATED = {"hornero-signal-day-01.png", "hornero-signal-night-01.png"}
APPROVED_LICENSES = {"CC BY 2.0", "CC BY-SA 4.0", "CC0 1.0", "CC0"}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _fmt_size(num_bytes: int) -> str:
    if num_bytes >= 1024 * 1024:
        return f"{num_bytes / (1024 * 1024):.2f} MiB ({num_bytes:,} B)"
    if num_bytes >= 1024:
        return f"{num_bytes / 1024:.1f} KiB ({num_bytes:,} B)"
    return f"{num_bytes:,} B"


def validate_all(
    root: Path = ROOT,
    *,
    max_unverified_bytes: int | None = None,
    max_file_bytes: int | None = None,
) -> tuple[list[str], dict]:
    provenance_path = root / "profiles/themes/wallpaper-provenance.json"
    collection_path = root / "profiles/themes/wallpaper-collection.json"
    manifest_path = root / "profiles/themes/wallpapers.manifest.json"
    candidates_path = root / "profiles/themes/wallpaper-candidates.json"
    org_inventory_path = root / "profiles/themes/organization-wallpaper-inventory.json"
    dotfiles_audit_path = root / "profiles/themes/dotfiles-wallpaper-audit.json"
    brand_wallpapers_dir = root / "assets/brand/wallpaper"

    data = json.loads(provenance_path.read_text(encoding="utf-8"))
    collection = json.loads(collection_path.read_text(encoding="utf-8"))
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    candidates = json.loads(candidates_path.read_text(encoding="utf-8"))
    org_inventory = json.loads(org_inventory_path.read_text(encoding="utf-8"))
    dotfiles_audit = json.loads(dotfiles_audit_path.read_text(encoding="utf-8"))
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
        path = root / item["file"]
        if not path.is_file():
            errors.append(f"{ident}: missing file {item['file']}")
            continue
        if sha256(path) != item.get("sha256"):
            errors.append(f"{ident}: SHA-256 mismatch")
        if item.get("sha256") != item.get("sourceSha256"):
            errors.append(f"{ident}: shipped file is not byte-identical to curated source")
        if path.stat().st_size != item.get("bytes"):
            errors.append(f"{ident}: file size mismatch")
        if max_file_bytes is not None and item.get("bytes", 0) > max_file_bytes:
            errors.append(
                f"{ident}: size {item.get('bytes')} B exceeds max-file-bytes budget {max_file_bytes} B"
            )
        if item.get("themeId"):
            theme = themes.get(item["themeId"])
            if not theme:
                errors.append(f"{ident}: unknown theme {item['themeId']!r}")
            elif theme["defaultWallpaper"] != path.name or theme["wallpaperDir"] != item.get("installDir"):
                errors.append(f"{ident}: theme default and collection file disagree")

    on_disk = {str(p.relative_to(root)) for p in (root / "assets/wallpapers").rglob("*") if p.is_file()}
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
        for field in (
            "title", "place", "photographer", "sourcePage", "originalImageSource",
            "license", "licenseUrl", "attribution", "modification",
        ):
            if not item.get(field):
                errors.append(f"{ident}: missing {field}")
        if item.get("license") not in APPROVED_LICENSES:
            errors.append(f"{ident}: unapproved license {item.get('license')!r}")
        coll = by_file.get(item.get("processedFile"))
        if not coll or coll.get("license") != item.get("license"):
            errors.append(f"{ident}: licensed item missing from collection with same license")
        theme = themes.get(item.get("themeId"))
        if not theme:
            errors.append(f"{ident}: unknown theme {item.get('themeId')!r}")
        elif theme["defaultWallpaper"] != Path(item["processedFile"]).name:
            errors.append(f"{ident}: default wallpaper and processed file disagree")
        path = root / item["processedFile"]
        if not path.is_file():
            errors.append(f"{ident}: missing processed file {path.relative_to(root)}")
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

    brand_svgs = sorted(brand_wallpapers_dir.glob("*.svg")) if brand_wallpapers_dir.is_dir() else []
    audit = build_license_audit(root, collection["items"], data["items"], brand_svgs)
    if max_unverified_bytes is not None and audit["summary"]["unverifiedBytes"] > max_unverified_bytes:
        errors.append(
            f"unverified legacy assets total {audit['summary']['unverifiedBytes']} B, "
            f"exceeding max-unverified-bytes budget {max_unverified_bytes} B"
        )

    context = {
        "collection_count": len(cids),
        "licensed_count": len(ids),
        "audit": audit,
    }
    return errors, context


def build_license_audit(
    root: Path,
    collection_items: list[dict],
    licensed_items: list[dict],
    brand_svgs: list[Path],
) -> dict:
    verified: list[dict] = []
    unverified: list[dict] = []
    by_license: dict[str, dict[str, int]] = {}
    by_status: dict[str, dict[str, int]] = {}

    for item in collection_items:
        lic = item.get("license") or "missing"
        size = int(item.get("bytes") or 0)
        status = item.get("curationStatus") or "unspecified"

        lic_bucket = by_license.setdefault(lic, {"count": 0, "bytes": 0})
        lic_bucket["count"] += 1
        lic_bucket["bytes"] += size

        st_bucket = by_status.setdefault(
            status, {"count": 0, "bytes": 0, "verifiedCount": 0, "verifiedBytes": 0,
                     "unverifiedCount": 0, "unverifiedBytes": 0}
        )
        st_bucket["count"] += 1
        st_bucket["bytes"] += size

        if lic == "unknown":
            st_bucket["unverifiedCount"] += 1
            st_bucket["unverifiedBytes"] += size
            unverified.append({
                "id": item.get("id"),
                "file": item.get("file"),
                "bytes": size,
                "format": item.get("format"),
                "dimensions": item.get("dimensions"),
                "curationStatus": status,
                "themeId": item.get("themeId"),
                "flags": item.get("flags"),
            })
        else:
            st_bucket["verifiedCount"] += 1
            st_bucket["verifiedBytes"] += size
            verified.append({
                "id": item.get("id"),
                "file": item.get("file"),
                "license": lic,
                "bytes": size,
                "themeId": item.get("themeId"),
                "attribution": item.get("attribution"),
            })

    original_procedural = [
        {
            "file": str(p.relative_to(root)),
            "license": "MIT",
            "bytes": p.stat().st_size,
        }
        for p in brand_svgs
    ]

    total_count = len(collection_items)
    total_bytes = sum(int(i.get("bytes") or 0) for i in collection_items)
    verified_count = len(verified)
    verified_bytes = sum(i["bytes"] for i in verified)
    unverified_count = len(unverified)
    unverified_bytes = sum(i["bytes"] for i in unverified)
    original_count = len(original_procedural)
    original_bytes = sum(i["bytes"] for i in original_procedural)

    unverified_sorted = sorted(unverified, key=lambda x: x["bytes"], reverse=True)
    verified_sorted = sorted(verified, key=lambda x: x["bytes"], reverse=True)

    return {
        "summary": {
            "totalCollectionAssets": total_count,
            "totalCollectionBytes": total_bytes,
            "verifiedAssets": verified_count,
            "verifiedBytes": verified_bytes,
            "verifiedPercentCount": round((verified_count / total_count * 100.0) if total_count else 0.0, 2),
            "verifiedPercentBytes": round((verified_bytes / total_bytes * 100.0) if total_bytes else 0.0, 2),
            "unverifiedAssets": unverified_count,
            "unverifiedBytes": unverified_bytes,
            "unverifiedPercentCount": round((unverified_count / total_count * 100.0) if total_count else 0.0, 2),
            "unverifiedPercentBytes": round((unverified_bytes / total_bytes * 100.0) if total_bytes else 0.0, 2),
            "originalProceduralAssets": original_count,
            "originalProceduralBytes": original_bytes,
            "provenanceRecords": len(licensed_items),
        },
        "byLicense": dict(sorted(by_license.items())),
        "byCurationStatus": dict(sorted(by_status.items())),
        "verified": verified_sorted,
        "originalProcedural": original_procedural,
        "unverifiedBySize": unverified_sorted,
    }


def format_audit_report(audit: dict) -> str:
    s = audit["summary"]
    lines = [
        "=== Wallpaper License Provenance & Size Budget Audit ===",
        f"Collection assets : {s['totalCollectionAssets']} files, {_fmt_size(s['totalCollectionBytes'])}",
        f"  Verified CC/CC0 : {s['verifiedAssets']} files ({s['verifiedPercentCount']}%), "
        f"{_fmt_size(s['verifiedBytes'])} ({s['verifiedPercentBytes']}%)",
        f"  Unverified      : {s['unverifiedAssets']} files ({s['unverifiedPercentCount']}%), "
        f"{_fmt_size(s['unverifiedBytes'])} ({s['unverifiedPercentBytes']}%)",
        f"First-party SVG   : {s['originalProceduralAssets']} files, "
        f"{_fmt_size(s['originalProceduralBytes'])} (MIT, assets/brand/wallpaper/)",
        "",
        "By license:",
    ]
    for lic, bucket in audit["byLicense"].items():
        lines.append(f"  {lic:<16} {bucket['count']:>3} files  {_fmt_size(bucket['bytes'])}")
    lines.extend(["", "By curationStatus:"])
    for status, bucket in audit["byCurationStatus"].items():
        lines.append(
            f"  {status:<22} {bucket['count']:>3} files  {_fmt_size(bucket['bytes'])}"
            f"  (verified={bucket['verifiedCount']}, unverified={bucket['unverifiedCount']})"
        )
    lines.extend(["", "Verified CC/CC0 assets:"])
    for row in audit["verified"]:
        lines.append(f"  [{row['license']}] {_fmt_size(row['bytes']):>24}  {row['file']}")
    lines.extend(["", "First-party original procedural assets (MIT):"])
    for row in audit["originalProcedural"]:
        lines.append(f"  [{row['license']}]       {_fmt_size(row['bytes']):>24}  {row['file']}")
    lines.extend(["", "Largest unverified legacy assets (top 10 replacement targets):"])
    for row in audit["unverifiedBySize"][:10]:
        theme = row["themeId"] or "-"
        lines.append(
            f"  {_fmt_size(row['bytes']):>24}  {row['curationStatus']:<20}  theme={theme:<16}  {row['file']}"
        )
    over_1mib = [r for r in audit["unverifiedBySize"] if r["bytes"] > 1024 * 1024]
    lines.append(
        f"  ({len(over_1mib)} unverified assets > 1.00 MiB, totaling "
        f"{_fmt_size(sum(r['bytes'] for r in over_1mib))})"
    )
    return "\n".join(lines)


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--audit-licenses",
        action="store_true",
        help="Print verified vs unverified license provenance and byte-size budget summary",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Emit machine-readable JSON audit report (implies --audit-licenses)",
    )
    parser.add_argument(
        "--max-unverified-bytes",
        type=int,
        default=None,
        help="Fail if total unverified legacy bytes exceed this threshold",
    )
    parser.add_argument(
        "--max-file-bytes",
        type=int,
        default=None,
        help="Fail if any single collection file exceeds this byte threshold",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    errors, ctx = validate_all(
        ROOT,
        max_unverified_bytes=args.max_unverified_bytes,
        max_file_bytes=args.max_file_bytes,
    )
    if errors:
        print("WALLPAPER-FAIL:", file=sys.stderr)
        for error in errors:
            print(f"  - {error}", file=sys.stderr)
        return 1

    if args.json:
        print(json.dumps(ctx["audit"], indent=2))
        return 0

    print(
        f"WALLPAPER-PASS: {ctx['collection_count']} collection assets "
        f"({ctx['licensed_count']} licensed) and theme references validated"
    )
    if args.audit_licenses:
        print()
        print(format_audit_report(ctx["audit"]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
