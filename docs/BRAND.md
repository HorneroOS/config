# HorneroOS brand identity

Canonical vector identity for HorneroOS: warm clay, sunset and earth tones
with a rufous-hornero bird mark. Explicitly NOT a Garuda-style dragon and
NOT generic cyberpunk neon.

## Direction

A hornero (rufous hornero, the ovenbird) silhouette perched on a branch,
set against a setting-sun disc. The mark references the bird the project
is named after and the mud-oven nest it builds (the arch/contour motif
reused in the wallpapers). Palette is taken from the flagship
`hornero-dark` / `hornero-light` token ramps so the identity always matches
the default desktop (`pampa`, the grassland-night third flagship, reuses
the same bird mark and arch/contour motif in its own green-and-gold ramp).

Canonical palette:

| Role             | Dark surface | Light surface |
|---|---|---|
| Sunset amber     | `#F2B749` | `#F2B749` |
| Ember terracotta | `#E07856` | `#B24827` |
| Fired clay       | `#D9A05F` | `#7C4A2C` |
| Night adobe      | `#1D1410` | — |
| Morning paper    | — | `#FAF1E3` |
| Cream text       | `#F6E9DB` | — |
| Adobe text       | — | `#2B1A11` |

## Files (`assets/brand/`)

| File | Use |
|---|---|
| `logo.svg` | Canonical full-color mark (transparent ground) |
| `logo-dark.svg` | Cream bird for dark backgrounds |
| `logo-light.svg` | Deep-adobe bird for light backgrounds (same art as canonical) |
| `logo-symbolic.svg` | Single-color `currentColor` mark, bird knocked out (panels, tray) |
| `logo-mono.svg` | Pure-black mark (print, engraving, single ink) |
| `wordmark.svg` | `HORNERO OS` wordmark (`currentColor` + terracotta `OS`); set in the local system sans, weight 800 |
| `icons/hornero-app.svg` | Squircle app icon (launchers, docks, app grids) |
| `icons/hornero-system.svg` | Roundel system icon (settings, about dialogs) |
| `favicon.svg` | Small-size optical variant: enlarged bird, no eye detail, heavier branch — use at 16–48 px |
| `wallpaper/hornero-{dark,light}.svg` + `wallpaper/pampa.svg` | Procedural wallpaper sources (16:9) |

All SVGs are hand-authored, well-formed XML, vector-only (no `<image>`,
no `data:` URIs) and self-contained (no external references).
`scripts/validate.sh` enforces all three; `scripts/render-brand-assets.sh`
validates and renders PNGs.

## Fastfetch

`desktop/fastfetch/hornero.txt` is the ASCII mark (perched bird on a sun
disc + wordmark). It ships with the fastfetch defaults via materialize and
renders with e.g.:

```
fastfetch --logo-type file \
  --logo ~/.config/fastfetch/hornero.txt \
  --logo-color-1 yellow --logo-color-2 red
```

## Wallpaper solution (no vendored binaries)

Wallpaper binaries are never vendored (see `docs/DECISIONS.md`). Fresh
boot shows intentional Hornero visuals through this chain:

1. Source: `assets/brand/wallpaper/hornero-{dark,light}.svg` +
   `assets/brand/wallpaper/pampa.svg` (procedural, on-palette, 16:9).
2. Render on the target machine:
   `scripts/render-brand-assets.sh --wallpapers ~/.local/share/hornero/wallpapers`
   produces `<id>/<id>-01.png` (1920x1080) per flagship theme
   (`hornero-dark`, `hornero-light`, `pampa`)
   plus HiDPI `...-02-hidpi.png` (2560x1440).
3. The flagship `theme.json` packs and `wallpapers.manifest.json` point
   `defaultWallpaper` at those PNG names, so the normal resolver picks
   them up once rendered.
4. Missing-file behavior is unchanged: `bin/dots-wallpaper-set` exits 1
   with `Error: wallpaper file not found` and the empty state stays the
   fallback until packs are rendered or fetched.

## Size recognizability

Rendered with `scripts/render-brand-assets.sh` and inspected at
16/24/32/48/64/128/256/512 px. The full mark reads down to ~32 px; below
that use `favicon.svg`, whose enlarged silhouette stays legible at 16 px.
