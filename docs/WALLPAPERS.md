# Wallpaper sources, packaging, and provenance

HorneroOS keeps theme recipes in `profiles/themes/<theme-id>/theme.json` and the selection index in `profiles/themes/wallpapers.manifest.json`. `catalogue/registry.json` is generated from those recipes with `scripts/generate-catalogue.py`; do not edit it by hand.

The reusable config package ships its procedural flagship SVG wallpapers and six licensed photographic Hornero Originals. Optional wallpaper collections in `ulises-jeremias/dotfiles` remain personal/user media and are not redistributed by this package. The pinned audit at `profiles/themes/dotfiles-wallpaper-audit.json` inventories that source without changing it. An unknown provenance or license means the image is not approved for HorneroOS distribution; visual style alone is never enough to label an image AI-generated.

## Photo source of truth

`profiles/themes/wallpaper-provenance.json` is the canonical per-image record: source page and original image URL, creator, location, source dimensions and checksum, license, modification, output path/dimensions/checksum, and theme association. The corresponding files live under `assets/wallpapers/argentina/`. Package builds stage these files under `/usr/share/hornero/wallpapers/<theme-id>/`; attribution and license records are installed under `/usr/share/licenses/hornero-config/WALLPAPER-CREDITS.md` and `/usr/share/hornero/wallpapers/wallpaper-provenance.json`.

The selected sources are Wikimedia Commons files under CC BY 2.0 or CC BY-SA 4.0. Per-photo details are documented in [WALLPAPER-CREDITS.md](../profiles/themes/WALLPAPER-CREDITS.md). Recheck the source page before changing a file or license. Do not use publicly viewable photos without a license that permits redistribution.

## Reproducing the derivatives

Original masters are intentionally not checked into Git. Fetch each original from its recorded `originalImageSource`, then verify the `originalSha256` from `wallpaper-provenance.json` before processing. A master is rejected if its checksum differs. The production recipe is:

1. Decode the recorded original JPEG without applying generative edits.
2. Apply the crop documented in its provenance record to a 16:9 composition. The crop is selected to preserve the visual subject and its negative space.
3. Resize to 2560×1440 with Pillow LANCZOS, convert to RGB, and write JPEG quality 88 with optimization enabled.
4. Verify dimensions and the processed SHA-256 recorded in the manifest.

This yields 2560×1440 derivatives totalling about 7.5 MB. Website previews are separate smaller files derived from these packaged derivatives; the website never needs to serve original masters. Run `python3 scripts/validate-wallpapers.py` after changing the manifest, images, or theme references. The validation checks paths, IDs, sizes, checksums, theme references, and license/attribution fields. `scripts/materialize.sh --dest <temporary-home>` checks the package-only mapping without writing to a real user home.

## Collection audit

`profiles/themes/dotfiles-wallpaper-audit.json` records every wallpaper file found under the pinned dotfiles media root, including file path, commit, dimensions, format, checksum, folder/theme association, provenance classification and Hornero redistribution status. Five regional images explicitly documented as generated and one stylized image with unverified provenance were replaced in the product catalog. Other optional non-Argentina illustrations and uncertain images remain untouched in dotfiles; they are neither promoted nor bundled by HorneroOS/config. Text files with `.png` names are identified as placeholders, not images.

The organization-wide scope review distinguishes wallpaper media from greeter scenes, desktop/QA screenshots, website previews, brand marks, and conceptual artwork. Those related visuals are not product wallpapers and are not classified by style alone. New files in those categories are documented in the website asset manifest and their owning repository.
