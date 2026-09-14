# Hornero GTK theme (GTK 3 + GTK 4, MIT-native)

Real `Hornero-Dark` / `Hornero-Light` GTK themes built from the flagship
token palettes (`profiles/themes/hornero-dark|light/theme.json`,
terracotta/clay/sunset family). No GTK 2 is shipped and none is claimed:
there is no `gtk-2.0/` engine dir; the legacy `desktop/gtk/gtkrc-2.0`
settings skeleton is untouched and out of scope.

## Layout

```text
desktop/gtk-theme/
  src/hornero-dark.css    # source of truth (dark)
  src/hornero-light.css   # source of truth (light, first-class ramp)
  build.sh                # copies src/ -> 4 shipped gtk.css outputs
  Hornero-Dark/{index.theme,gtk-3.0/gtk.css,gtk-4.0/gtk.css}
  Hornero-Light/{index.theme,gtk-3.0/gtk.css,gtk-4.0/gtk.css}
  gallery.py              # widget-gallery fixture (GTK 4 preferred, GTK 3 fallback)
```

After editing `src/`, run `./build.sh`; `tests/test_gtk_theme.sh` fails CI
when the shipped copies drift (`build.sh --check`).

## Source architecture (why hand-structured CSS, no SCSS)

Colloid/Orchis/Graphite generate their themes from large SCSS trees, but
those trees are copyleft-licensed and cannot be vendored into this MIT-only repo
(`tests/test_contrast.sh` already gates the appearance deliverable as
MIT-only). An SCSS pipeline would also add a toolchain dependency to CI and
`makepkg` for zero styling gain at this fidelity. So the theme is original
hand-structured CSS: a `@define-color` palette block (one name per token,
derived interaction shades precomputed as flat hex so both parsers accept
the file with no color functions) followed by one section per widget family —
the same architecture those projects use, without their code. The GTK 3 and
GTK 4 outputs are byte-exact copies of one source per variant: v1 styles use
only the portable property subset valid in both parsers (no engine
properties, no `-gtk-gradient`, no `shade()`/`mix()`/`alpha()` calls), which
`tests/test_gtk_theme.sh` asserts by checking both files parse and carry the
same selector set.

## Libadwaita decision: palette-level integration, no restyle

Libadwaita applications ignore GTK themes by design — they ship their own
stylesheet and expose recoloring through `org.gnome.desktop.interface
color-scheme` / `gtk-application-prefer-dark-theme`, both of which
`lib/dots/gtk-theme-manager.sh` already drives (`apply_gtk_color_scheme`,
persisted policy, `sync_gtk_color_scheme` on login). Two options were
considered:

1. **Palette-level (chosen).** The Hornero themes style plain GTK 3/GTK 4
   widgets; Libadwaita apps follow via the existing prefer-dark /
   color-scheme policy. Nothing pins Libadwaita internals, so GNOME point
   releases cannot break the desktop.
2. **Restyle (rejected).** Forcing the theme with `GTK_THEME=` or overriding
   `~/.config/gtk-4.0/gtk.css` with widget rules reaches into Libadwaita's
   private CSS nodes, which upstream renames freely — every GNOME upgrade
   risks visual breakage, and `GTK_THEME` additionally breaks Flatpak
   portals' expectations.

Users who still want Hornero colors inside Libadwaita windows can opt in
without touching this repo:

```css
/* ~/.config/gtk-4.0/gtk.css — opt-in only, never installed by materialize */
@import url("../../.local/share/themes/Hornero-Dark/gtk-4.0/gtk.css");
```

## Install paths and package ownership

| Repo source              | User install (`materialize.sh --dest`) | Package (`PKGBUILD`)        |
| ------------------------ | -------------------------------------- | --------------------------- |
| `desktop/gtk-theme/Hornero-Dark` | `~/.local/share/themes/Hornero-Dark` | `/usr/share/themes/Hornero-Dark` |
| `desktop/gtk-theme/Hornero-Light` | `~/.local/share/themes/Hornero-Light` | `/usr/share/themes/Hornero-Light` |
| `desktop/gtk-theme/{build.sh,gallery.py,src/*,README.md}` | not installed (dev-only) | not installed |

No file is owned twice: the recipe JSONs stay under
`/usr/share/hornero/themes` (token packs), while the compiled GTK theme
trees live only under `/usr/share/themes`. `src/`, `build.sh`, and
`gallery.py` are development sources and never enter the package.

## Applying

```sh
dots-gtk-theme theme hornero-dark    # sets Hornero-Dark + Papirus-Dark + prefer-dark
dots-gtk-theme theme hornero-light   # sets Hornero-Light + Numix-Circle + prefer-light
python3 desktop/gtk-theme/gallery.py --theme Hornero-Dark
```
