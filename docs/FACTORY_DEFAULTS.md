# Factory defaults — fresh boot is Hornero Signal Night in Cockpit

## Contract

`profiles/factory.json` is the machine-readable record: `defaultTheme`
is `hornero-signal-night` (RFC 0001 §3.2), `shellLayout.preset` is `cockpit`
(RFC 0001 §5), plus the compositor/terminal/Qt/GTK/font/icon/wallpaper
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

`paletteApplications` lists optional applications whose native themes are
rendered from the applied theme's schema-v2 roles (wallpapers never recolour). The website projects this list
for the workspace palette showcase, while the desktop integration test checks
the package roles, source configs, theme paths, and native renderer outputs.
This keeps palette-app claims aligned with what Hornero Config actually
ships; it does not install btop or Cava.

## How each default lands without user setup

| Default | Ships as | Lands at |
|---|---|---|
| Hyprland borders/groups/shadow | `desktop/hypr/hyprland.lua.d/smart-colors.lua` (generated from Signal Night roles) + `static.lua` geometry (1 px borders, 5 px corners, no blur) | `{config}/hypr/…` → `/etc/xdg/hypr/…` |
| Kitty palette | `desktop/kitty/<theme-id>.conf` for every theme (generated); `kitty.conf` includes `hornero-signal-night.conf` | `{config}/kitty/…` → `/etc/xdg/kitty/…` |
| Alacritty (optional) | `desktop/alacritty/alacritty.toml` imports `hornero-signal-night.toml` then the applied theme's `hornero-colors.toml` | `{config}/alacritty/…` → `/etc/alacritty/…` |
| Ghostty (optional) | `desktop/ghostty/config.ghostty` selects `Hornero Dynamic`; the package seeds new homes and installs a Signal Night system theme fallback | `{config}/ghostty/…`; `/etc/skel/.config/ghostty/…`; `/usr/share/ghostty/themes/…` |
| Qt6 style/fonts/palette | `desktop/qt6ct/qt6ct.conf` (Fusion, IBM Plex, Signal Night scheme) + generated `colors/<theme-id>.conf` + the `QT_QPA_PLATFORMTHEME=qt6ct` pin | `{config}/qt6ct/…` → `/etc/xdg/qt6ct/…` |
| Theme recipes + factory record | `profiles/themes/*` (schema v2) + `profiles/factory.json` | `{data}/hornero/…` → `/usr/share/hornero/…` |
| GTK theme/icons/font/dark preference | `desktop/gtk/settings.ini` (generated: `Hornero-Signal`, `Papirus-Dark`, `IBM Plex Sans 11`) + Signal Night libadwaita recolour | `{config}/gtk-{3,4}.0/…` → `/etc/xdg/gtk-{3,4}.0/…` |
| Lock fallback | `desktop/hypr/hyprlock.conf` (generated; Signal Night variables, matte ground, Plex) | `{config}/hypr/hyprlock.conf` |
| Wallpaper | procedural source `assets/brand/wallpaper/hornero-signal-night.svg` | rendered into the package at build time; regional photo defaults are shipped as licensed JPEG assets |
| Editor contract | `desktop/environmentd/10-hornero-editor.conf` (`EDITOR`/`VISUAL`/`SUDO_EDITOR=nano`) + git `core.editor=nano` | `{config}/environment.d/…` → `/etc/skel/.config/environment.d/…` |
| Session baseline | `desktop/environmentd/20-hornero-session.conf` (XDG dirs, `~/.local/bin` PATH, `TERMINAL=kitty`; no `BROWSER` until a factory browser is chosen) | same environment.d path, all session types |
| Fonts | IBM Plex Sans / Mono (Kitty, GTK, Qt, hyprlock); `desktop/fontconfig/fonts.conf` sans/mono aliases prefer IBM Plex with Noto CJK/emoji fallbacks | `{config}/kitty`, `{config}/fontconfig` |
| XDG defaults | `desktop/xdg/mimeapps.list` (Thunar for directories) + `user-dirs.dirs` | `{config}/mimeapps.list`, `{config}/user-dirs.dirs` |
| Monitor overrides | `desktop/hypr/hyprland.lua.d/monitors-user.lua`, loaded after the generic `monitors.lua` fallback | `{config}/hypr/hyprland.lua.d/monitors-user.lua` |

Existing users keep a skel-seeded entrypoint, so new factory `dofile`
lines never reach them on package upgrade alone.
`lib/hornero/refresh-hypr-entrypoint.py` closes that gap additively: it
inserts only the factory module lines a user `hyprland.lua` is
missing (dry-run diff by default, `--apply` writes with a
`.pre-refresh` backup), preserves every existing line byte-for-byte,
and refuses restructured files instead of guessing.

## Fonts and icon packages (Arch)

- `extra/ttf-ibm-plex` (OFL-1.1) — **hard dependency** of `hornero-config`:
  IBM Plex Sans, IBM Plex Mono and IBM Plex Sans Condensed (RFC 0001 §3.3)
  are named by GTK, Qt, Kitty, fontconfig and hyprlock defaults.
- No system icon font: the shell bundles Hornero Glyphs
  (`assets/fonts/hornero-glyphs.ttf` in HorneroOS/shell). The former icon font
  and the Rubik/CaskaydiaCove recorded preferences were removed with the
  Material stack.
- `extra/papirus-icon-theme` — provides `Papirus-Dark` (night/contrast) and
  `Papirus` (day).
- Hornero GTK styles — generated `Hornero-Signal`, `Hornero-Signal-Day`,
  `Hornero-Signal-Contrast` and one tree per Hornero Original. GTK 2 remains
  on its toolkit default because Hornero ships GTK 3 and GTK 4 trees only.
- `extra/qt6ct` — reader for the shipped Qt6 platform-theme default.

## Day, High Contrast and other themes

Every theme ships static, generated per-theme files (Kitty `<id>.conf`,
qt6ct `colors/<id>.conf`, a GTK tree for Hornero collection themes) and
`desktop/hypr/hyprland.lua.d/signal-day.lua` is an opt-in Day border
fragment. Applying a theme (`horneroctl appearance theme apply <id>`, or
`hornero-appearance theme apply <id>` with the shell down) writes the live
scheme at `${XDG_STATE_HOME}/hornero/signal/scheme.json`, switches the Kitty
include, qt6ct palette and libadwaita recolour, and renders Alacritty,
Ghostty, btop, Cava, Hyprland and hyprlock colours from the theme's roles
(`lib/hornero/signal_render.py`). Every output is validated before any file
is replaced. Changing the wallpaper only moves the wallpaper.
