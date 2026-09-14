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

## Libadwaita decision: public-palette redefinition, no restyle

Libadwaita applications ignore GTK theme trees by design — Preview 2 VM QA
proved it on pixels: with only prefer-dark/color-scheme policy, GTK4 apps
render stock Adwaita blue accents. The supported fix is Libadwaita's public
recoloring API: `~/.config/gtk-4.0/gtk.css` redefining documented named
colors (`accent_bg_color`, `window_bg_color`, ...), the same mechanism
Gradience uses. That file carries NO widget rules and touches no private
CSS nodes, so GNOME point releases cannot break it the way a restyle would.

Concretely: each variant ships `gtk-4.0/recolor.css` (values wired to
`theme.json`, gated by `tests/test_gtk_theme.sh`). `materialize.sh`
installs the factory-default (dark) copy as `~/.config/gtk-4.0/gtk.css`,
and `lib/dots/apply-appearance.sh` swaps it on theme set
(`_dots_aa_sync_recolor`). Still rejected: `GTK_THEME=` overrides and any
`gtk.css` with widget selectors (private-node coupling + Flatpak portal
risk).

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
