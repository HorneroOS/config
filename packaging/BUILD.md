# hornero-config build record

Real `makepkg` build of `hornero-config`, installed into a temp
DESTDIR-style root (extracted with `bsdtar`, never installed onto the
host), audited against the layout in `packaging/README.md`.

## Build

- Host: Arch Linux rolling, `pacman 7.1.0.r9.g54d9411-2` (fakeroot build).
- Branch base: `69d5ca3c0a082de88f841882100994bc6c837310`
  (Merge PR #3, `feat/config-packaging`).
- Command (from `packaging/`): `makepkg -s --noconfirm`
- Result: `Finished making: hornero-config 0.1.0-1`
- Artifact: `hornero-config-0.1.0-1-any.pkg.tar.zst`
  (`81701` bytes, default `base` profile)
- SHA256: `9286281c4d7dd3b6ed3aa63c83cc5596705c7d6db1539102a94a18120a3f0abe`
- Install probe (no system mutation):
  `bsdtar -xf hornero-config-0.1.0-1-any.pkg.tar.zst -C <tmp-root>`

## Checks (all green)

- `bash -n PKGBUILD`, `shellcheck -S error PKGBUILD`,
  `makepkg --printsrcinfo`: pass.
- `scripts/validate.sh`: ALL GREEN (shellcheck, structured formats,
  git config syntax, hypr sanity, personal-data guard).
- `tests/test_materialize.sh`: ALL GREEN.
- `tests/test_package.sh`: ALL GREEN (22 checks: real build, DESTDIR
  audit, layout round-trip, prefixes, perms 755/644 with executables
  restored, no identity/secrets in installed tree, installed configs
  parse, profile matrix incl. bogus-profile rejection).
- `package()` re-ran `scripts/guard-personal-data.sh` during the build:
  `guard-personal-data: OK (no personal data or secret hits)`.

## Profile matrix

| `HORNERO_PROFILE` | Build | `/usr/share/hornero/HORNERO_PROFILE` | Tree vs base |
| ----------------- | ----- | ------------------------------------ | ------------ |
| (unset)           | ok    | `base`                               | —            |
| `desktop`         | ok    | `desktop`                            | identical    |
| `developer`       | ok    | `developer`                          | identical    |
| `bogus`           | fails | —                                    | `error: unknown HORNERO_PROFILE='bogus'` in `package()` |

## Installed layout (67 files, 39 dirs under `/etc/xdg` + `/usr/share`)

Nothing is installed outside `/etc/xdg` and `/usr/share/hornero`
(plus `/usr/share/licenses/hornero-config` and the pacman metadata
dotfiles `.PKGINFO`/`.BUILDINFO`/`.MTREE`).

```text
/etc/xdg/btop/btop.conf
/etc/xdg/cava/config
/etc/xdg/copyq/copyq.conf
/etc/xdg/fastfetch/config.jsonc
/etc/xdg/fontconfig/fonts.conf
/etc/xdg/git/config
/etc/xdg/git/ignore
/etc/xdg/gtk-3.0/settings.ini
/etc/xdg/gtkrc-2.0
/etc/xdg/handlr/handlr.toml
/etc/xdg/hypr/hypridle.conf
/etc/xdg/hypr/hyprland.conf
/etc/xdg/hypr/hyprland.conf.d/animations.conf
/etc/xdg/hypr/hyprland.conf.d/animations-cozy.conf
/etc/xdg/hypr/hyprland.conf.d/animations-cyberpunk.conf
/etc/xdg/hypr/hyprland.conf.d/animations-minimal.conf
/etc/xdg/hypr/hyprland.conf.d/animations-nature.conf
/etc/xdg/hypr/hyprland.conf.d/animations-vaporwave.conf
/etc/xdg/hypr/hyprland.conf.d/autostart.conf
/etc/xdg/hypr/hyprland.conf.d/colors.conf
/etc/xdg/hypr/hyprland.conf.d/environment.conf
/etc/xdg/hypr/hyprland.conf.d/input.conf
/etc/xdg/hypr/hyprland.conf.d/keybindings.conf
/etc/xdg/hypr/hyprland.conf.d/layout.conf
/etc/xdg/hypr/hyprland.conf.d/monitors.conf
/etc/xdg/hypr/hyprland.conf.d/plugins.conf
/etc/xdg/hypr/hyprland.conf.d/window-rules.conf
/etc/xdg/hypr/hyprlock.conf
/etc/xdg/hypr/scripts/gaps-interactive.sh (755)
/etc/xdg/hypr/scripts/notification-handler.sh (755)
/etc/xdg/hypr/scripts/smart-float.sh (755)
/etc/xdg/kitty/kitty.conf
/etc/xdg/Thunar/accels.scm
/etc/xdg/Thunar/renamerc
/etc/xdg/Thunar/uca.xml
/usr/share/hornero/HORNERO_PROFILE
/usr/share/hornero/bin/dots-appearance (755)
/usr/share/hornero/bin/dots-gtk-theme (755)
/usr/share/hornero/bin/dots-hyprlock-theme (755)
/usr/share/hornero/bin/dots-theme-selector (755)
/usr/share/hornero/lib/dots/apply-appearance.sh
/usr/share/hornero/lib/dots/apply-shell-preset.py
/usr/share/hornero/lib/dots/dots-scripts.sh
/usr/share/hornero/lib/dots/easy-options/easyoptions.sh
/usr/share/hornero/lib/dots/generate-m3-colors.py
/usr/share/hornero/lib/dots/gtk-theme-manager.sh
/usr/share/hornero/lib/dots/list-themes.py
/usr/share/hornero/lib/dots/logging.sh
/usr/share/hornero/lib/dots/python-m3.sh
/usr/share/hornero/lib/dots/snappy-switcher-manager.sh
/usr/share/hornero/lib/dots/wallpaper-resolver.sh
/usr/share/hornero/profile.toml
/usr/share/hornero/profiles/base/profile.toml
/usr/share/hornero/themes/catppuccin-latte/theme.json
/usr/share/hornero/themes/catppuccin-mocha/theme.json
/usr/share/hornero/themes/everforest/theme.json
/usr/share/hornero/themes/gruvbox/theme.json
/usr/share/hornero/themes/landscape/theme.json
/usr/share/hornero/themes/monochrome/theme.json
/usr/share/hornero/themes/neon-city/theme.json
/usr/share/hornero/themes/nord-dreams/theme.json
/usr/share/hornero/themes/rose-pine/theme.json
/usr/share/hornero/themes/soft-morning/theme.json
/usr/share/hornero/themes/vapor-dreams/theme.json
/usr/share/hornero/themes/wallpapers.manifest.json
/usr/share/hornero/themes/warm-sunset/theme.json
/usr/share/licenses/hornero-config/LICENSE
```

Verification detail:

- Every staged `~/.config/*` entry from `scripts/materialize.sh --dest`
  exists under `/etc/xdg`, and `diff -r` of the staged tree vs
  `/etc/xdg` is identical except the documented extra `gtkrc-2.0`.
- `lib/dots`, `bin/dots-*`, and `themes` are byte-identical to the
  staged HOME; both `profile.toml` copies match `profiles/base/`.
- Dirs are `755`; files are `644` except the restored executables above.
- Installed-tree scans: no `[user]` stanza, no mailbox strings, no
  secret assignments, no hardcoded home paths. The single `/home/user`
  hit is the allowlisted upstream LXAppearance skeleton placeholder in
  `gtkrc-2.0` (`include "/home/user/.gtkrc-2.0.mine"`), identical to the
  repo source.
- Installed `git/config` parses via `git config --list`; installed
  `handlr.toml` and `profile.toml` parse via stdlib `tomllib`.

## Defects found and fixed

1. Makepkg byproducts (`*.pkg.tar.zst`, `src/`, `pkg/`) were untracked
   and showed up in `git status`, risking an accidental binary commit.
   Fixed at source with new `packaging/.gitignore`
   (commit `facb780`).
2. Considered, not changed: no `backup=()` array for `/etc/xdg/*`.
   These are copy-from defaults (README documents copying into `$HOME`,
   never editing in place), so pacman overwriting them on upgrade is
   the intended behavior.

## Reproduce

```sh
cd packaging && makepkg -s --noconfirm
rm -rf /tmp/hc-root && mkdir -p /tmp/hc-root
bsdtar -xf hornero-config-0.1.0-1-any.pkg.tar.zst -C /tmp/hc-root
bash ../scripts/validate.sh
bash ../tests/test_package.sh   # skips cleanly without makepkg/bsdtar
```
