# Factory defaults — fresh boot is Hornero Dark

## Contract

`profiles/factory.json` is the machine-readable record: `defaultTheme`
is `hornero-dark`, plus the compositor/terminal/Qt/GTK/font/icon/wallpaper
pointers a first boot resolves. Everything it points at is a static file
in this repo installed by `scripts/materialize.sh` (user scope) or the
generic `PKGBUILD` staged-HOME loop (system `/etc/xdg` scope). No step
fetches, clones, or otherwise depends on `ulises-jeremias/dotfiles` at
runtime — that repo is a read-only extraction source (see
`docs/DECISIONS.md` "Ownership"); the packaging-time `guard-personal-data`
check and `tests/test_desktop_integration.sh` assert no new runtime
reference is introduced.

## How each default lands without user setup

| Default | Ships as | Lands at |
|---|---|---|
| Hyprland borders/groups/shadow (dark) | `desktop/hypr/hyprland.conf.d/colors.conf` + `hyprland.conf` fallbacks | `{config}/hypr/…` → `/etc/xdg/hypr/…` |
| Kitty palette (dark) | `desktop/kitty/hornero-dark.conf`, included by `kitty.conf` | `{config}/kitty/…` → `/etc/xdg/kitty/…` |
| Qt6 style/fonts (dark-adjacent) | `desktop/qt6ct/qt6ct.conf` + existing `QT_QPA_PLATFORMTHEME=qt6ct` pin | `{config}/qt6ct/…` → `/etc/xdg/qt6ct/…` |
| Theme recipes + factory record | `profiles/themes/*` + `profiles/factory.json` | `{data}/hornero/…` → `/usr/share/hornero/…` |
| GTK theme/icons/dark preference | `desktop/gtk/settings.ini` | **config-gtk worker** (recorded in `factory.json` only) |
| Wallpaper | ref `hornero-dark-01.jpg` | release pipeline (binaries never vendored) |

## Fonts and icon packages (Arch)

Declared in `packaging/PKGBUILD` optdepends so the factory default has
named readers; verified against the Arch extra repo on 2026-09-13:

- `extra/ttf-material-symbols-variable` — Material Symbols icon font
  declared in `shell/shell.default.json`
  (`appearance.font.family.material = "Material Symbols Rounded"`).
- `extra/papirus-icon-theme` — provides `Papirus-Dark` (factory dark).
- `extra/orchis-theme` — provides `Orchis-Dark-Compact` (factory) and
  `Orchis-Light-Compact` (light), the GTK themes the flagship recipes pin.
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

`hornero-light` recipes, `desktop/kitty/hornero-light.conf`, and
`desktop/hypr/hyprland.conf.d/hornero-light.conf` ship alongside for an
explicit opt-in (documented switch lines in `kitty.conf`/`hyprland.conf`).
Nothing auto-switches today; a future dots-appearance day/night policy may
consume `availableThemes` + the GTK preference to flip all three surfaces
together.
