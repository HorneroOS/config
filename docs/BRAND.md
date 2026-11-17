# HorneroOS brand identity — Hornero Signal

HorneroOS speaks one visual language, **Hornero Signal**
([RFC 0001](https://github.com/HorneroOS/docs/blob/main/development/rfc-0001-hornero-signal.md)):
a contemporary engineering workstation from an alternate 1990s Argentina —
broadcast control rooms, oscilloscope bezels, test cards, technical drawing
sheets and the 45° diagonal of La Plata — executed with modern restraint.
The rufous-hornero bird mark stays the project's signature. Explicitly not
Material, not a Garuda-style dragon, not generic neon.

## Principles (RFC 0001 §2)

1. **Work first.** Chrome is quiet and matte. Amber `signal` means
   live / active / primary; celeste `cue` means focus / selection /
   information. Accents are signals, never decoration.
2. **Instrument, not toy.** Hairline rules, small radii (3/5/8 px), tabular
   numerals, segmented meters, labelled channels. No pills-everywhere, no
   bounce, no glass, no neon gradients.
3. **Legible at a glance.** Every text role passes WCAG AA (4.5:1) on every
   surface it is used on; control boundaries pass 3:1. Enforced for every
   shipped theme by `scripts/check-contrast.py`.
4. **One language everywhere.** Shell, extensions, GTK/Qt apps, terminals,
   compositor, lock, greeter, installer and website map from the same roles.

Signature details: Plex Mono uppercase **eyebrows** (`01 · AUDIO`), the
2×10 px `signal` **registration tick** on the active panel, the 2–3 px
**on-air bar** for active strips and tabs, **segmented meters**, and the
La Plata **diagonal** — only on brand surfaces (lock, greeter, installer,
website hero, wallpapers), never inside controls.

## Palette roles

The token contract is `profiles/themes/tokens.schema.json` (schema v2);
`lib/hornero/signal_theme.py` validates it and every generator maps from
these roles only. Flagship values (RFC 0001 §3.2 with amendment 2):

| Role | Use | Signal Night | Signal Day |
|---|---|---|---|
| `ground` | Desktop, lock background | `#0C0F13` | `#E6E1D5` |
| `sunken` | Inputs, tracks, wells | `#101419` | `#DCD6C8` |
| `base` | Bars, window body | `#13171D` | `#F2EEE5` |
| `panel` | Cards, popouts, menus | `#181D24` | `#F7F4EE` |
| `raised` | Hover/selected rows | `#1F252E` | `#FBF9F5` |
| `lifted` | Tooltips, pressed | `#283039` | `#FFFFFF` |
| `ink` / `inkMuted` / `inkFaint` | Text tiers | `#ECE6DA` `#A8ABAD` `#737980` | `#1B1E22` `#4E545B` `#7A8086` |
| `rule` / `ruleStrong` | Hairlines / control boundaries | `#2C333C` `#707A85` | `#D3CCBD` `#736D62` |
| `signal` (+`on`, `Well`, `onWell`) | Primary, live, active (amber) | `#F2A33A` | `#8F4B00` |
| `glow` (optional) | Live-signal emphasis; defaults to `signal` | `#FFB650` | `#8F4B00` |
| `cue` / `focus` | Focus ring, selection, info (celeste) | `#7EC1EA` | `#1A5F88` |
| `phosphor` | Healthy, connected | `#8BD49A` | `#256A3B` |
| `alert` | Destructive, error | `#F0705A` | `#A8341C` |
| `inverse` / `onInverse` / `inverseSignal` | Snackbars | `#ECE6DA` `#181D24` `#8A5200` | `#1B1E22` `#F2EEE5` `#F2A33A` |

**Signal High Contrast** keeps the roles with a `#000000` ground, `#FFFFFF`
ink and rules, `#FFC247` signal and `#8FD3FF` cue. Hornero Originals
(Patagonia, Quebrada, Iberá, Fin del Mundo, Buenos Aires Nocturno, Pampa,
Cuyo, Iguazú, Sierras) are regional palettes in the same spirit: instrument
surfaces tinted by place, one warm signal, a celeste cue.

## Typography (RFC 0001 §3.3)

| Family | Font | Use |
|---|---|---|
| `sans` | IBM Plex Sans | UI text (GTK `gtk-font-name`, Qt `general`) |
| `mono` | IBM Plex Mono | Readouts, numerals, eyebrows, code, terminals |
| `display` | IBM Plex Sans Condensed | Clock, lock, large headings |

Shipped by Arch `extra/ttf-ibm-plex` (OFL-1.1), a hard dependency of
`hornero-config`. Numbers always use tabular figures. The shell's icons are
Hornero Glyphs (Tabler-derived, MIT), bundled by HorneroOS/shell.

## Files (`assets/brand/`)

The bird mark is unchanged; its colours are bound to Signal roles (sun disc
`glow` → `signal` → Day `signal`, bird in Day `ink`, light-ground bird in
Night `ink`).

| File | Use |
|---|---|
| `logo.svg` | Canonical full-colour mark (transparent ground) |
| `logo-dark.svg` | Ink-cream bird for dark backgrounds |
| `logo-light.svg` | Ink-black bird for light backgrounds (same art as canonical) |
| `logo-symbolic.svg` | Single-colour `currentColor` mark (panels, tray) |
| `logo-mono.svg` | Pure-black mark (print, single ink) |
| `wordmark.svg` | `HORNERO OS` wordmark in IBM Plex Sans Condensed Bold, outlined to paths (`currentColor` + signal `OS`; the amber `OS` is decorative, use `logo-symbolic.svg` when a single colour must pass AA on a light ground) |
| `icons/hornero-app.svg` | Squircle app icon |
| `icons/hornero-system.svg` | Roundel system icon |
| `favicon.svg` | Small-size optical variant for 16–48 px |
| `wallpaper/hornero-signal-{night,day}.svg` | Procedural Signal wallpapers drawn from the theme roles: drafting grid, La Plata diagonal in `signal`, `cue` registration marks, ruler scale |

All SVGs are hand-authored, well-formed XML, vector-only and
self-contained; `scripts/validate.sh` enforces this and
`scripts/render-brand-assets.sh` validates and renders PNGs.

## Fastfetch

`desktop/fastfetch/hornero.txt` is the ASCII mark. The shipped config
colours it and its keys with ANSI names, so it follows the applied theme's
terminal palette (yellow = `signal`, blue = `cue`, green = `phosphor`).

## Wallpapers

Wallpapers never recolour the UI. Signal Night/Day (and High Contrast,
which reuses Night) render from the procedural SVGs on the target machine:
`scripts/render-brand-assets.sh --wallpapers <dir>` produces
`<wallpaperDir>/<wallpaperDir>-01.png` (1920×1080) and `-02-hidpi.png`
(2560×1440). The nine Hornero Originals ship licensed Argentine photographs
whose attribution and licences are in `profiles/themes/WALLPAPER-CREDITS.md`
and `profiles/themes/wallpaper-provenance.json`; see `docs/WALLPAPERS.md`.
The retired Hornero Dark/Light/199X artwork is no longer shipped.

## Size recognizability

Rendered with `scripts/render-brand-assets.sh` and inspected at
16/24/32/48/64/128/256/512 px. The full mark reads down to ~32 px; below
that use `favicon.svg`.

## Where the mark may appear

The bird is the signature, not a chrome element. Large on brand surfaces only
(lock, greeter, installer, website hero, social previews, boot); in the
workstation UI it stays a 16-32 px identifier (OS icon in a bar, About tile,
Welcome header) on an `inverse` or `panel` tile. Never tile or watermark it
behind controls.

## Social previews and copies

`assets/social/` holds the 1280x640 repository cards (generated, see its
README for the manual upload steps; GitHub has no API for this). Other
repositories vendor copies of the marks (shell `assets/logo.svg`, installer
`image/calamares/branding/hornero/`, website `public/favicon.svg` and
`src/assets/brand/`). A vendored copy must be byte-identical to the matching
file here, or a documented derivative; re-copy from this directory when the
mark changes.
