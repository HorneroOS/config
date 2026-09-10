# hornero-config packaging

Arch package `hornero-config`: system-wide install of the curated
HorneroOS desktop defaults owned by this repo.

## Profiles

Select a profile with the `HORNERO_PROFILE` environment variable:

| Requested value | Resolves to         | Notes                                 |
| --------------- | ------------------- | ------------------------------------- |
| `base`          | `profiles/base`     | Default curated desktop composition.  |
| `desktop`       | `profiles/base`     | Alias of `base` until a curated desktop composition lands. |
| `developer`     | `profiles/base`     | Alias of `base` until a curated developer composition lands. |

```sh
HORNERO_PROFILE=desktop makepkg -s
```

The requested name is recorded in `/usr/share/hornero/HORNERO_PROFILE`;
the resolved manifest is installed both as
`/usr/share/hornero/profiles/base/profile.toml` and as the stable path
`/usr/share/hornero/profile.toml`.

## Layout

`package()` reuses the canonical mapping instead of duplicating it: it
calls `scripts/materialize.sh --dest` into a staging HOME and rearranges
that staged HOME into the system layout. Per-application file lists live
only in `scripts/materialize.sh`; the PKGBUILD loop over the staged
`.config` tree is generic so new modules flow through unchanged.

| Staged HOME path (via `materialize.sh`) | Package path                          |
| --------------------------------------- | ------------------------------------- |
| `.config/*`                             | `/etc/xdg/*`                          |
| `.gtkrc-2.0`                            | `/etc/xdg/gtkrc-2.0` (skeleton; copy to `~/.gtkrc-2.0` to use) |
| `.local/lib/dots`                       | `/usr/share/hornero/lib/dots`         |
| `.local/bin/dots-*`                     | `/usr/share/hornero/bin/dots-*`       |
| `.local/share/dots/themes`              | `/usr/share/hornero/themes`           |
| `profiles/base/profile.toml`            | `/usr/share/hornero/profiles/base/profile.toml` and `/usr/share/hornero/profile.toml` |
| Selection name                          | `/usr/share/hornero/HORNERO_PROFILE`  |
| `LICENSE`                               | `/usr/share/licenses/hornero-config/LICENSE` |

Only `/etc/xdg` and `/usr/share/hornero` (plus the standard license dir)
are written.

## Personal-data guarantee

`package()` re-runs `scripts/guard-personal-data.sh` before staging. The
build fails on leaked identity or secrets, exactly like `scripts/validate.sh`.
Git identity is never shipped: configure it per user after install:

```sh
git config --file ~/.config/git/config.user user.name "Your Name"
git config --file ~/.config/git/config.user user.email "you@example.com"
```

## Build and verify

Run from this directory:

```sh
bash -n PKGBUILD
shellcheck -S error PKGBUILD
makepkg --printsrcinfo
HORNERO_PROFILE=desktop makepkg -s
```

Full repo gates (must stay green; this package changes no install mapping,
so the temp-HOME test is unaffected):

```sh
scripts/validate.sh
tests/test_materialize.sh
pre-commit run --all-files
```

## Use after install

```sh
# Preview what the package ships (same content as a user install):
scripts/materialize.sh --dry-run

# Copy system defaults into a user (XDG-aware):
cp -r /etc/xdg/hypr ~/.config/hypr

# CLI adapters live outside PATH by design; add them explicitly:
export PATH="/usr/share/hornero/bin:$PATH"
dots-gtk-theme theme vapor-dreams
```

## License

MIT, see `LICENSE` (also shipped as
`/usr/share/licenses/hornero-config/LICENSE`).
