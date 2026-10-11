# HorneroOS wallpaper and visual-asset audit

Audit date: 2026-10-11. This report covers wallpaper files and wallpaper-like previews across the HorneroOS organization, plus the pinned optional media source used by the personal dotfiles setup. The machine-readable inventories are `profiles/themes/organization-wallpaper-inventory.json` and `profiles/themes/dotfiles-wallpaper-audit.json`.

## Product wallpaper sources

| Repository | Paths reviewed | Classification | Product status |
| --- | --- | --- | --- |
| `HorneroOS/config` | `assets/brand/wallpaper/` | Hornero-authored procedural SVG sources and package-rendered raster outputs | MIT; flagship defaults |
| `HorneroOS/config` | `assets/wallpapers/argentina/` | Six genuine, source-verified photographs | CC BY 2.0 or CC BY-SA 4.0; defaults shipped in `hornero-config` |
| `HorneroOS/config` | `profiles/themes/*` and `wallpapers.manifest.json` | Twenty theme-to-wallpaper references | Six photo defaults, two procedural flagship defaults; remaining media optional |
| `HorneroOS/website` | `assets/screenshots/theme-wallpapers/` | Fifteen theme visual previews; six replaced with licensed photographs in this change | Website imagery; origin/license of other previews is recorded as unverified, not inferred |
| `HorneroOS/website` | `public/wallpapers/argentina/` | 720px and 1280px WebP derivatives of the six approved package photographs | Website-only optimized previews; captions expose attribution and license |
| `ulises-jeremias/dotfiles` | `home/dot_local/share/hornero/wallpapers/` at commit `88a34fd58699fe4941b5b17c455df181479a2a57` | Sixty-two raster image files plus two text placeholders with `.png` suffixes | Optional user media; not redistributed by HorneroOS/config unless separately cleared |

The website also has two retained photo copies in `assets/screenshots/wallpapers/`; their provenance and hashes are included in the organization inventory. `assets/brand/buenos-aires-cyberpunk.webp` is explicitly conceptual artwork, not a documentary photo or shipped wallpaper.

## Other organization image assets

The scan distinguished image content from wallpaper payloads. `HorneroOS/greeter/media/` contains login-scene videos and posters; `HorneroOS/shell/assets/companion/` contains Companion artwork; `shell/screens/qa/`, `shell/docs/assets/`, `docs/desktop/assets/`, `qa/screens/`, and installer documentation directories contain screenshots or test evidence. These are catalogued as related visual assets rather than product wallpapers. Repository path, purpose, and ownership boundary are recorded in `organization-wallpaper-inventory.json`. Style alone was not used to classify photography or generated imagery.

## Argentina replacement decisions

Five dotfiles regional artworks (Buenos Aires Nocturno, Fin del Mundo, Iberá, Patagonia and Quebrada) are explicitly described as original generated artworks in the pinned wallpaper README. Pampa had no source or creation metadata, so it is classified as uncertain stylized artwork, not asserted to be AI-generated. All six received a legally redistributable photographic counterpart because they are Hornero product defaults and their intended regional atmosphere is clear. The optional source files remain in the read-only dotfiles source; HorneroOS/config does not alter that repository.

The selected photographs retain the theme silhouette and palette direction: amber-lit urban night; Beagle Channel blue hour; a green Iberá lagoon; an aerial humid-pampas waterway; Perito Moreno ice and mountain panorama; and Hornocal’s natural rose/ochre mineral bands. The images are photographic crops, not reconstructed or generatively altered scenes.

Other dotfiles images are untouched. The pinned audit has per-file paths, hashes, dimensions, format, folder/theme relation, source URL if recorded, geographic association, visual notes where known, origin confidence, and rights status. No source/license metadata was found for those optional files, so they are not approved for HorneroOS redistribution. That limitation is explicit rather than filled with guessed attribution.

## Credits and licenses

The six package assets have verifiable Commons file pages and licenses. See [`profiles/themes/WALLPAPER-CREDITS.md`](../profiles/themes/WALLPAPER-CREDITS.md) for photographer attribution, source links, license URLs, and modification statement. Their source and derivative checksums, dimensions, crop recipes and website preview hashes are in `profiles/themes/wallpaper-provenance.json`. The Arch package declares the applicable per-image Creative Commons license identifiers and installs the attribution text with the assets.
