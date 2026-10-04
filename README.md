# HorneroOS config

Curated, reusable desktop defaults for Hornero OS: compositor, terminal,
GTK, fonts, and common desktop applications — plus the theme packs and
helper libraries that apply them. Extracted (never moved) from the generic
parts of [ulises-jeremias/dotfiles](https://github.com/ulises-jeremias/dotfiles).

## What this repo owns

Generic product defaults that define the Hornero desktop out of the box.
Everything here must be safe for every machine: no usernames, no emails, no
host-specific outputs, no secrets. `scripts/guard-personal-data.sh` enforces
that in CI.

## What this repo does NOT own

- **Personal configuration.** Anything specific to one person's workstation
  stays in the dotfiles repo. Rule of thumb: if a file needs a name, an
  email, a hostname, a monitor model, or a `/home/<someone>` path to make
  sense, it does not belong here.
- **The desktop shell.** The Quickshell/QML shell lives in
  [HorneroOS/shell](https://github.com/HorneroOS/shell); this repo only holds
  the configuration that shell (and the compositor underneath it) consumes.
- **Distribution composition.** Releases, manifests, packaging live in
  [HorneroOS/hornero](https://github.com/HorneroOS/hornero).
- **Shell boundary heuristic.** `shell/` currently holds only a stub note:
  the interactive-shell layer (zsh, prompts, aliases) is personal enough to
  need its own curation pass before anything lands here. Until that pass,
  shell defaults are out of scope — see `docs/DECISIONS.md`.

## Status

HorneroOS Desktop is Wayland-first. Hyprland remains the validated session;
Niri has a curated session configuration and Shell integration marked
experimental until graphical acceptance runs cover the real session. The
defaults include Niri's upstream 26.04 configuration as a starting point,
Hornero Shell startup, Hornero shortcuts, native screenshot selection, and
the compositor-specific `/etc/niri/config.kdl` package fallback. This does
not claim full feature parity: Niri currently has no special workspaces,
Hyprland-native window previews, or Hyprland window geometry picker. See
[`docs/NIRI.md`](docs/NIRI.md) and the Shell's
[`docs/COMPOSITORS.md`](https://github.com/HorneroOS/shell/blob/main/docs/COMPOSITORS.md).

Curated from the generic parts of the dotfiles: Hyprland, Niri, kitty,
GTK 2/3, Qt6ct, fontconfig, fastfetch, btop, cava, Thunar, CopyQ,
handlr, git-minus-identity, 20 theme packs (8 Hornero Originals, including
three semantic-token themes and five wallpaper-led looks, plus 12 other
curated looks), `lib/hornero`
implementation libraries and the `hornero-gtk-theme`-family CLI adapters.
See `docs/DECISIONS.md` for the full copied / excluded-as-personal /
deferred accounting.

## Layout

```text
desktop/    per-application defaults      -> ~/.config/<app>, ~/.gtkrc-2.0
xdg/        git (no identity) + handlr    -> ~/.config/git, ~/.config/handlr
profiles/   base desktop profile + 20 theme packs -> ~/.local/share/hornero/…
shell/      stub note (interactive shell deferred)
lib/hornero/   appearance/GTK/wallpaper implementation libs -> ~/.local/lib/hornero
bin/        hornero-gtk-theme-family CLIs    -> ~/.local/bin
scripts/    materialize.sh, validate.sh, guard-personal-data.sh
tests/      temp-HOME materialization test
docs/       DECISIONS.md (per-item provenance)
```

## Usage

Preview what an install would do:

```sh
scripts/materialize.sh --dry-run
```

Install into the current user (XDG-aware):

```sh
scripts/materialize.sh
```

Install into an isolated directory (hermetic — XDG variables ignored):

```sh
scripts/materialize.sh --dest /tmp/hornero-home
```

Validate everything without writing to any HOME:

```sh
scripts/validate.sh
```

Run the temp-HOME materialization test:

```sh
tests/test_materialize.sh
```

After install, identity overlay (the one thing this repo refuses to ship):

```sh
git config --file ~/.config/git/config.user user.name "Your Name"
git config --file ~/.config/git/config.user user.email "you@example.com"
```

Apply a theme pack (recipes reference wallpaper packs fetched separately):

```sh
export PATH="$HOME/.local/bin:$PATH"
hornero-gtk-theme theme vapor-dreams
```

## Provenance

Every curated file traces to `ulises-jeremias/dotfiles@b26db04`; per-file
decisions live in `docs/DECISIONS.md`. Upstream is read-only to this project:
we copy, we never move, and we never push there.

## License

[MIT](LICENSE).
