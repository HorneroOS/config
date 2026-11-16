# Qt decision — qt6ct kept, Kvantum deferred

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
- **No `qt5ct` file.** The shipped Qt app is Qt6; Qt5 theming is out of
  scope until a Qt5 app is curated.

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
