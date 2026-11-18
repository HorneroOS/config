# Qt decision — qt6ct/qt5ct, live palette, Kvantum deferred

## Which Qt apps ship in HorneroOS?

Evidence from this repo (inspected, not assumed):

- `desktop/copyq/copyq.conf` + `packaging/PKGBUILD` (`copyq: clipboard
  defaults`) — **CopyQ is the one shipped Qt app.** Verified on the
  reference host: `copyq 16.0.0` links `libQt6Widgets`/`libQt6Gui`
  (Qt6 Widgets), so it honors `QT_QPA_PLATFORMTHEME`.
- `desktop/hypr/hyprland.lua.d/window-rules.lua` names `dolphin`, `vlc`,
  and `lxqt-config` classes — compatibility float/opacity rules only.
  Neither app ships config or a packaging dependency here; they are
  user-installed, not curated defaults.
- `HorneroOS/shell` (Quickshell) is QtQuick/QML and self-themed from the
  live Hornero Signal scheme (schema-v2 roles); it does not consume a
  Widgets platform theme. It is owned by `HorneroOS/shell`,
  not this repo.
- Everything else curated here (Thunar, pavucontrol references,
  polkit-gnome agent, nm/blueman applets) is GTK.

So the Qt surface that this repo must theme is exactly: **Qt6 Widgets
apps, in practice CopyQ**, running inside a Hyprland session with no
Plasma/KDE component.

## Decision: keep `qt6ct`, defer Kvantum, no native palette

- **Keep `QT_QPA_PLATFORMTHEME=qt6ct`** (already pinned in
  `desktop/hypr/hyprland.lua.d/environment.lua`). qt6ct is the
  lightweight configurator for Qt6-under-Wayland in a non-KDE session;
  the shipped `desktop/qt6ct/qt6ct.conf` sets Fusion style, Papirus-Dark
  icons, and IBM Plex Sans / IBM Plex Mono (RFC 0001 §3.3).
- **Defer Kvantum.** Garuda's Dr460nized uses Kvantum because it is a KDE
  Plasma (KWin) desktop whose Sweet look needs Kvantum's SVG engine and
  translucency (`kvantum-dark` Qt application style next to Sweet GTK;
  see Garuda fastfetch reports and the Garuda review literature). Hornero
  has no Plasma session, no KWin, no Sweet theme — Kvantum would add an
  SVG theme engine plus a theme-authoring burden for zero curated
  consumers. Revisit only if a KDE/Plasma session or a Kvantum-native Qt
  app set is ever curated here.
- **Generated custom palette (correction 2026-09-15).** The earlier
  claim that qt6ct palettes are binary-only was wrong: verified against
  upstream qt6ct source (`Qt6CT::loadColorScheme`), the platform theme
  reads plain-text INI schemes (`[ColorScheme]` with `active_colors`,
  `inactive_colors`, `disabled_colors` — 22 `#AARRGGBB` entries in
  `QPalette::ColorRole` order) selected via `color_scheme_path` +
  `custom_palette=true` in `qt6ct.conf`. So each official theme ships a
  generated scheme (`desktop/qt6ct/colors/<id>.conf`, produced by
  `scripts/generate-appearance.py` from the schema-v2 roles), and applying
  a theme points qt6ct at it (`_hornero_appearance_sync_qt`). The factory
  default points at the packaged Signal Night scheme. Inactive mirrors
  active; disabled uses `inkFaint`. Highlight/HighlightedText carry the
  celeste `cue`/`onCue` pair (selection) and Accent carries the amber
  `signal` (RFC 0001 §2), both contrast-gated by `scripts/check-contrast.py`.
- **qt5ct (2026-11-17, hornero#439).** Qt5 apps use the qt5ct platform
  theme, which reads the same INI format with 21 roles (Qt5 has no Accent).
  `desktop/qt5ct/qt5ct.conf` and generated `desktop/qt5ct/colors/<id>.conf`
  ship as the fresh-install starting point; the Hyprland env pins
  `QT_QPA_PLATFORMTHEME=qt6ct:qt5ct` (Qt tries each name in order, so Qt6
  apps load qt6ct and Qt5 apps load qt5ct; verified on Qt 6.12).

## Implemented

- `desktop/qt6ct/qt6ct.conf` (installed to `{config}/qt6ct` via the
  `[modules.qt6ct]` row — flows into `/etc/xdg/qt6ct` through the generic
  PKGBUILD loop).
- `desktop/qt6ct/colors/<theme-id>.conf` for every theme (generated,
  drift-tested).
- `lib/hornero/signal_render.py` `render_qt6ct` (Signal roles → QPalette
  roles), driven by `scripts/generate-appearance.py`.
- `_hornero_appearance_sync_qt` in `lib/hornero/apply-appearance.sh` (per-theme
  `color_scheme_path` + `custom_palette=true`, comment-preserving).
- `QT_QPA_PLATFORMTHEME=qt6ct` pin left untouched (pre-existing evidence,
  not new authorship).
- `packaging/PKGBUILD` optdepends gains `qt6ct` so the factory default has
  a declared reader.

## The live-palette consumer (2026-11-17, hornero#439)

Why Dolphin stayed light: qt6ct reads the FIRST config file that exists, so
a user `~/.config/qt6ct/qt6ct.conf` from before Signal (`custom_palette=false`,
no scheme) shadowed the packaged `/etc/xdg/qt6ct/qt6ct.conf` and nothing ever
repointed it (the old sync only edited an existing per-theme file in the user
dir, which a normal install never had).

`horneroctl appearance sync-qt --yes` (also run by every theme apply, by
Chromatic and by `appearance sync`, and by the QS-down shell fallback in
`lib/hornero/apply-appearance.sh`) now:

- renders the **live** Signal/Chromatic scheme into
  `~/.config/<toolkit>/colors/hornero-signal.conf` (byte-compatible with
  `scripts/generate-appearance.py`, parity-tested in horneroctl), so dark,
  light and Chromatic palettes all work without per-theme files;
- manages exactly two keys of the user's `[Appearance]` group,
  `custom_palette` and `color_scheme_path`. The durable ownership marker is
  the scheme path (qt6ct rewrites its config through QSettings and drops
  comments; a `; hornero-managed:` comment is only a courtesy). Every other
  key, group and comment is preserved;
- migrates a stale pre-Signal config (`custom_palette` not true, or a
  retired/packaged Hornero scheme) after copying it to
  `~/.local/state/hornero/qt/backups/<toolkit>/<timestamp>-<toolkit>.conf`;
- leaves a user's own palette alone (reported as a doctor warning) unless
  they opt in with `appearance set-qt <toolkit>=force`.

KDE Frameworks apps (Dolphin, Kate, Okular) are a second consumer: they
draw views and windows from KColorScheme, which outside Plasma uses the
scheme named by `kdeglobals` `[UiSettings] ColorScheme` and otherwise falls
back to Breeze Light. With only a dark qt6ct palette Dolphin rendered light
backgrounds with light text (verified with the real Dolphin 26.08 on the
reference host, rendered on Qt's VNC platform). So `sync-qt` also renders
`~/.local/share/color-schemes/HorneroSignal.colors` from the live roles
(views on `sunken`, windows on `base`, buttons on `raised`, selection on
`cue`) and manages that one kdeglobals key; other kdeglobals groups survive,
an unset/stale kdeglobals is backed up first, and a scheme the user picked
(for example BreezeDark) is kept unless forced.

Per-toolkit policy (`state.json`: `qt6ctConsumer`, `qt5ctConsumer`,
`kdeConsumer`):
`follow` (default), `force`, `off` (never touch that toolkit's files). Set
with `horneroctl appearance set-qt qt6ct=off --yes`.
`horneroctl appearance doctor` reports `qt-qt6ct`, `qt-qt5ct`, `qt-kde`,
`qt-platformtheme` and `qt-kvantum` honestly (missing config, stale config,
drift from the live theme, user palette, opt-out, plugin not installed,
env list lacking a toolkit).

Kvantum stays unmanaged: it is optional, draws its own SVG theme and would
bypass the palette. The doctor warns when a config selects a Kvantum style.
`scripts/materialize.sh` seeds the qt dirs with `preserve` so re-running it
never overwrites a user-edited `qt6ct.conf`/`qt5ct.conf`.
