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

First extraction (this branch): Hyprland, kitty, GTK 2/3, fontconfig,
fastfetch, btop, cava, Thunar, CopyQ, handlr, git-minus-identity, 12 theme
packs (recipes only), `lib/dots` implementation libraries and the
`dots-gtk-theme`-family CLI adapters. See `docs/DECISIONS.md` for the full
copied / excluded-as-personal / deferred accounting.

## Layout

```text
desktop/    per-application defaults      -> ~/.config/<app>, ~/.gtkrc-2.0
xdg/        git (no identity) + handlr    -> ~/.config/git, ~/.config/handlr
profiles/   base profile manifest + 12 theme packs -> ~/.local/share/dots/…
shell/      stub note (interactive shell deferred)
lib/dots/   appearance/GTK/wallpaper implementation libs -> ~/.local/lib/dots
bin/        dots-gtk-theme-family CLIs    -> ~/.local/bin
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
dots-gtk-theme theme vapor-dreams
```

## Provenance

Every curated file traces to `ulises-jeremias/dotfiles@b26db04`; per-file
decisions live in `docs/DECISIONS.md`. Upstream is read-only to this project:
we copy, we never move, and we never push there.

## License

[MIT](LICENSE).
