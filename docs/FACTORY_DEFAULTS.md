# Factory defaults — fresh boot is Hornero Dark

## Contract

`profiles/factory.json` is the machine-readable record: `defaultTheme`
is `hornero-dark`, plus the compositor/terminal/Qt/GTK/font/icon/wallpaper
pointers a first boot resolves. Everything it points at is a static file
in this repo installed by `scripts/materialize.sh` (user scope) or the
`PKGBUILD`'s upstream-compatible system fallback locations. No step
fetches, clones, or otherwise depends on `ulises-jeremias/dotfiles` at
runtime — that repo is a read-only extraction source (see
`docs/DECISIONS.md` "Ownership"); the packaging-time `guard-personal-data`
check and `tests/test_desktop_integration.sh` assert no new runtime
reference is introduced.

The same factory record's `terminal.integrations` catalogue identifies each
supported terminal, its package, source and installed config paths, palette
output, and a verified config example. The website generates its terminal
showcase data from the pinned factory record; the desktop integration test
checks that the examples still exist in their packaged source files.

## How each default lands without user setup

| Default | Ships as | Lands at |
|---|---|---|
| Hyprland borders/groups/shadow (dark) | `desktop/hypr/hyprland.conf.d/colors.conf` + `hyprland.conf` fallbacks | `{config}/hypr/…` → `/etc/xdg/hypr/…` |
| Kitty palette (dark) | `desktop/kitty/hornero-dark.conf`, included by `kitty.conf` | `{config}/kitty/…` → `/etc/xdg/kitty/…` |
| Alacritty (optional) | `desktop/alacritty/alacritty.toml` imports the active generated palette over a Hornero Dark fallback | `{config}/alacritty/…` → `/etc/alacritty/…` |
| Ghostty (optional) | `desktop/ghostty/config.ghostty` selects `Hornero Dynamic`; the package seeds new homes and installs a matching system theme fallback | `{config}/ghostty/…`; `/etc/skel/.config/ghostty/…`; `/usr/share/ghostty/themes/…` |
| Qt6 style/fonts (dark-adjacent) | `desktop/qt6ct/qt6ct.conf` + existing `QT_QPA_PLATFORMTHEME=qt6ct` pin | `{config}/qt6ct/…` → `/etc/xdg/qt6ct/…` |
| Theme recipes + factory record | `profiles/themes/*` + `profiles/factory.json` | `{data}/hornero/…` → `/usr/share/hornero/…` |
| GTK theme/icons/dark preference | `desktop/gtk/settings.ini` | **config-gtk worker** (recorded in `factory.json` only) |
| Wallpaper | procedural source `assets/brand/wallpaper/hornero-dark.svg` | rendered into the package at build time; regional photo defaults are shipped as licensed JPEG assets |

## Fonts and icon packages (Arch)

Declared in `packaging/PKGBUILD` optdepends so the factory default has
named readers; verified against the Arch extra repo on 2026-09-13:

- `extra/ttf-material-symbols-variable` — Material Symbols icon font
  declared in `shell/shell.default.json`
  (`appearance.font.family.material = "Material Symbols Rounded"`).
- `extra/papirus-icon-theme` — provides `Papirus-Dark` (factory dark).
- Hornero GTK styles — factory appearances use `Hornero-Dark` or
  `Hornero-Light` to match their selected mode. GTK 2 remains on its toolkit
  default because Hornero ships GTK 3 and GTK 4 theme trees only; the Hornero
  appearance catalogue does not need a third-party theme package.
- `extra/qt6ct` — reader for the shipped Qt6 platform-theme default.
- Light icon set `Numix-Circle` has no extra package
  (`chaotic-aur/numix-circle-icon-theme-git` only, checked 2026-09-13),
  so like the Rubik/CaskaydiaCove families it stays a recorded preference
  with non-extra provisioning.
- `sans = Rubik` and `mono = CaskaydiaCove NF` are recorded from
  `shell/shell.default.json`; no same-named package exists in Arch extra
  (checked `pacman -Ss rubik|cascadiacode`, 2026-09-13), so they stay a
  recorded preference with AUR-side provisioning, not a hard package dep.

## Light variant

`hornero-light` recipes, Kitty's `desktop/kitty/hornero-light.conf`,
Alacritty's `desktop/alacritty/hornero-light.toml`, and
`desktop/hypr/hyprland.conf.d/hornero-light.conf` ship as static fallbacks.
When Hornero applies an appearance or regenerates wallpaper colors, one
Material scheme renders Kitty, Alacritty, and Ghostty files in their native
formats. The cursor text uses `onPrimary` over `primary`, and generated
surface, selection, cursor, and ANSI text pairs pass contrast checks before
the palette files are written. Kitty and Alacritty live-reload their
configuration; Ghostty uses the stable `Hornero Dynamic` theme name, whose
file is regenerated in the user theme directory. Alacritty and Ghostty remain
optional applications; Kitty remains the factory/default terminal.
