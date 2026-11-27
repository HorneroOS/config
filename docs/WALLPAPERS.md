# Wallpaper sources, packaging, and provenance

HorneroOS keeps theme recipes in `profiles/themes/<theme-id>/theme.json` and the selection index in `profiles/themes/wallpapers.manifest.json`. `catalogue/registry.json` is generated from those recipes with `scripts/generate-catalogue.py`; do not edit it by hand.

The reusable config package ships its procedural flagship SVG wallpapers and the owner's definitive 57-file curated collection (2026-11-19), catalogued in `profiles/themes/wallpaper-collection.json` under `assets/wallpapers/<wallpaperDir>/` (theme dirs plus category dirs the Shell picker scans recursively). **License policy (changed 2026-11-19, see DECISIONS.md): no license is ever invented or inferred. 54 files are `license: unknown` and ship only with the explicit note `owner-curated 2026-11-19, license unverified`; this is a known redistribution risk accepted by the owner for this set, not a clearance. Only the three CC BY 2.0 photographs in `wallpaper-provenance.json` are verified for redistribution.** Visual style alone is never enough to label an image AI-generated. The factory default remains the procedural Signal Night (no license risk).

## Photo source of truth

`profiles/themes/wallpaper-provenance.json` is the canonical record for the licensed tier (three CC BY 2.0 photographs): source page and original image URL, creator, location, source dimensions and checksum, license, modification, output path/dimensions/checksum, and theme association. `profiles/themes/wallpaper-collection.json` is the catalogue of record for all 57 shipped files (content-derived name, curated-source filename + SHA-256, category, flags, license). Files live under `assets/wallpapers/<wallpaperDir>/` and stage 1:1 to `/usr/share/hornero/wallpapers/<wallpaperDir>/`; attribution and license records are installed under `/usr/share/licenses/hornero-config/WALLPAPER-CREDITS.md` and `/usr/share/hornero/wallpapers/` (`wallpaper-provenance.json` + `wallpaper-collection.json`). Collection files are byte-identical copies of the curated sources (SHA-256 verified); `scripts/process-wallpapers.py` was not re-run on them — it remains the recipe that produced the three licensed derivatives, and neither flattens the animated GIF nor re-encodes PNG/WebP originals.

The licensed-tier sources are Wikimedia Commons files under CC BY 2.0. Per-photo details are documented in [WALLPAPER-CREDITS.md](../profiles/themes/WALLPAPER-CREDITS.md). Recheck the source page before changing a file or license. Files outside the licensed tier must never be described as permitted for redistribution.

## Reproducing the derivatives

Original masters are intentionally not checked into Git. Fetch each original from its recorded `originalImageSource`, then verify the `originalSha256` from `wallpaper-provenance.json` before processing. A master is rejected if its checksum differs. The production recipe is:

1. Decode the recorded original JPEG without applying generative edits.
2. Apply the crop documented in its provenance record to a 16:9 composition. The crop is selected to preserve the visual subject and its negative space.
3. Resize to 2560×1440 with Pillow LANCZOS, convert to RGB, and write JPEG quality 88 with optimization enabled.
4. Verify dimensions and the processed SHA-256 recorded in the manifest.

This yields 2560×1440 derivatives for the licensed tier. Website previews are separate smaller files derived from these packaged derivatives; the website never needs to serve original masters. Run `python3 scripts/validate-wallpapers.py` after changing the manifest, images, or theme references. The validation checks paths, IDs, sizes, checksums, theme references, and license/attribution fields. `scripts/materialize.sh --dest <temporary-home>` checks the package-only mapping without writing to a real user home.

## License provenance & size budget audit

Use `scripts/validate-wallpapers.py --audit-licenses` (and `--json` for machine-readable output) to inspect the split between verified licensed photos, first-party MIT procedural SVG wallpapers, and unverified legacy collection files with exact byte totals:

- **Verified licensed tier**: 3 CC BY 2.0 photographs (`1.98 MiB` / `2,071,389 B`, 5.88% by count, 2.89% by size).
- **First-party procedural originals**: 2 MIT SVG wallpapers in `assets/brand/wallpaper/` (`16.1 KiB` / `16,474 B`).
- **Unverified legacy collection**: 48 `license=unknown` files (`66.38 MiB` / `69,599,707 B`, 94.12% by count, 97.11% by size; 11 files over `1.00 MiB` account for `50.03 MiB`).

Optional enforcement flags `--max-unverified-bytes N` and `--max-file-bytes N` allow CI or replacement PRs to gate total unverified footprint and per-file size budgets mechanically without altering the default `scripts/validate.sh` run.

## Collection audit

`profiles/themes/dotfiles-wallpaper-audit.json` records every wallpaper file found under the pinned dotfiles media root, including file path, commit, dimensions, format, checksum, folder/theme association, provenance classification and Hornero redistribution status. Five regional images explicitly documented as generated and one stylized image with unverified provenance were replaced in the product catalog. Other optional non-Argentina illustrations and uncertain images remain untouched in dotfiles; they are neither promoted nor bundled by HorneroOS/config. Text files with `.png` names are identified as placeholders, not images.

The organization-wide scope review distinguishes wallpaper media from greeter scenes, desktop/QA screenshots, website previews, brand marks, and conceptual artwork. Those related visuals are not product wallpapers and are not classified by style alone. New files in those categories are documented in the website asset manifest and their owning repository.
