# Decisions — initial config extraction

Source: `ulises-jeremias/dotfiles@b26db04`, read-only. Every imported file
below was copied (`cp`, never moved); the dotfiles checkout is untouched.
Template variables (`{{ .chezmoi.* }}`, `{{ .gitconfig.* }}`) were
materialized into final config; no raw personal template variable ships here.

## What was copied (and why it is safe)

| Shipped as | From | Notes |
|---|---|---|
| `desktop/hypr/` (main conf, 13 `conf.d` modules, `hypridle.conf`, `hyprlock.conf`, 3 helper scripts) | `home/dot_config/hypr/` | No template vars, no identity. `monitors.conf` is a generic autodetect fallback written for this repo (see excluded row). |
| `desktop/kitty/kitty.conf` | `home/dot_config/kitty/` | Static palette + fonts. The `include ~/.cache/dots/smart-colors/…` line is a generated-cache hook, benign when absent. |
| `desktop/gtk/settings.ini` | `home/dot_config/gtk-3.0/settings.ini` | Static theme/font/cursor defaults. |
| `desktop/gtk/gtkrc-2.0` | `home/dot_gtkrc-2.0` | Byte-identical. The `include "/home/user/.gtkrc-2.0.mine"` line is upstream's generic LXAppearance override hook, not a real user path. |
| `desktop/fontconfig/fonts.conf` | `home/dot_config/fontconfig/` | Generic hinting/rendering defaults. |
| `desktop/fastfetch/config.jsonc` | `home/dot_config/fastfetch/` | No image path set (upstream default requires none). |
| `desktop/btop/btop.conf` | `home/dot_config/btop/` | Stock settings, TTY theme. |
| `desktop/cava/config` | `home/dot_config/cava/` | All tuned values still commented; ships defaults. |
| `desktop/thunar/` (`accels.scm`, `renamerc`, `uca.xml`) | `home/dot_config/Thunar/` | Two generic custom actions (open terminal, open in yazi). |
| `desktop/copyq/copyq.conf` | `home/dot_config/copyq/copyq.conf.tmpl` | Verified benign: the `.tmpl` suffix is historical, the file contains zero template variables; shipped verbatim minus suffix. |
| `xdg/handlr/handlr.toml` | `home/dot_config/handlr/` | Generic defaults (`enable_selector = false`). |
| `xdg/git/config` + `xdg/git/ignore` | `home/dot_config/git/config.tmpl` + `ignore` | Materialized: `{{ .chezmoi.homeDir }}` → `~`; mergetool range loop expanded to three static stanzas; the `[commit] template` stanza dropped (template file not shipped — a dangling reference would break `git commit`); the `diff-merge-tools`/`gui-config` includes dropped (files not shipped). The `config.user` include is kept as an overlay hook. **No `[user]` stanza ships** (`config.user.tmpl` identity excluded). |
| `profiles/themes/<12 ids>/theme.json` + `wallpapers.manifest.json` | `home/dot_local/share/dots/themes/` | Recipes only. Binary wallpaper packs (~45M upstream) are not vendored; the manifest records each pack's `defaultWallpaper`/`wallpaperDir` refs and where to fetch them. |
| `lib/dots/` (10 implementation files + `easy-options/easyoptions.sh`) | `home/dot_local/lib/dots/` | Appearance/GTK/wallpaper logic plus vendored arg parser. `executable_example.sh` not taken (sample noise). |
| `bin/dots-{gtk-theme,hyprlock-theme,theme-selector,appearance}` | `home/dot_local/bin/executable_dots-*` | The GTK-theme family CLI contract: `dots-gtk-theme` is the canonical apply path into `lib/dots/gtk-theme-manager.sh`; the other three call it (documented in each file's header). `executable_` prefix stripped (chezmoi deploy marker, meaningless here); `+x` preserved. |

## What was excluded as personal

| Not shipped | Reason |
|---|---|
| `home/dot_config/gtk-3.0/bookmarks.tmpl` | Embodes a username (`{{ .chezmoi.username }}`) and personal directory layout. |
| `home/dot_config/git/config.user.tmpl` | Identity (`user.name`/`user.email`). Lives only in the user's own `~/.config/git/config.user`, never here. |
| `home/dot_config/private_credentials/` | API-key templates. Never curated. |
| `hyprland.conf.d/monitors.conf` (upstream content) | Machine-specific `eDP-1`/`HDMI-A-5` bindings for one Intel+NVIDIA laptop. Replaced with a generic autodetect fallback; hosts keep fixed layouts out of tree. |
| `dot_zshrc`, `dot_p10k.zsh`, `dot_zsh_aliases.tmpl`, `dot_zprofile`, `executable_dot_profile`, `executable_dot_xinitrc`, `executable_dot_xprofile`, `dot_zsh/`, `dot_Xresources` | Personal interactive-shell layer → deferred to `shell/` (stub note committed). |
| `.chezmoi*.tmpl`, `.chezmoiscripts/`, `.chezmoiexternal.toml` | Deploy machinery + identity inputs of the dotfiles repo, not product defaults. |
| `private_dot_ssh/`, `dot_clamtk/`, `dot_face.create` | Host identity / device-specific. |

## What was deferred (not personal, just out of scope)

| Deferred | Home |
|---|---|
| `home/dot_config/quickshell/` | `HorneroOS/shell` — real component with its own lifecycle. |
| `home/dot_config/gtk-4.0/` (absent upstream) | Generated at apply time by `dots-gtk-theme`; never hand-edited. |
| `home/dot_config/autostart/*.desktop` | Session composition; revisited with the installer. |
| `sss/`, `tmux/`, `yazi/`, `wpg/`, `lxqt/`, `xfce4/`, `guitarix/`, `REAPER/` | Not in the approved extraction list; future passes decide per app. |
| `home/dot_local/share/dots/shell-presets/` | Quickshell-owned; moves with `shell/`. |
| Wallpaper binaries | Distributed separately (see manifest note). |
| `dots-{color-scheme,wal-reload}` and the wider `dots-*` fleet | Smart-colors/Quickshell runtime; only the GTK-theme family moves in this pass. |

## Tooling decisions

- **shellcheck gate severity is `error`, not `warning`.** Every shipped shell
  file is still checked; pre-existing upstream warnings do not fail the build:
  SC1090 (runtime `~/.local/lib/dots/…` sourcing is by design — repo layout
  differs from install layout), SC2034 (`scripts_list` and palette vars are
  consumed cross-file), SC2154 (`arguments` is provided by easyoptions at
  runtime). Rewriting upstream runtime-sourcing logic to please the linter
  would risk behavior for zero product gain.
- **`scripts/materialize.sh --dest` is hermetic.** XDG variables are honored
  only when installing into the real `$HOME`; a `--dest` install always
  scopes config/data/lib/bin under the destination. (A first version honored
  `XDG_CONFIG_HOME` unconditionally and leaked one test install into the
  developer's real `~/.config`; the affected files were restored byte-exact
  from `dotfiles@b26db04`-rendered content and the hermeticity regression
  test is `tests/test_materialize.sh`.)

## Deferred triage (Track 3c)

Method: read-only reference clone of `ulises-jeremias/dotfiles@b26db04`
(inspected via `cp`-free reads; nothing copied into this repo and nothing
deleted or moved upstream). Each row re-examines one deferred or excluded
item against `AGENTS.md`: renders identically for two users, no machine
specifics, identity only via overlay hooks. No implementation file was
added, moved, or removed in this pass.

| Item | Upstream | Verdict | Reason / owner |
|---|---|---|---|
| autostart | `home/dot_config/autostart/` (3 `.desktop`: safeeyes, thunar-daemon, wal-restore) | KEEP-DEFERRED | Session composition; owner `HorneroOS/installer`. The Hyprland session already starts via `desktop/hypr/hyprland.conf.d/autostart.conf` (`dex --autostart`); thunar-daemon duplicates it, and wal-restore targets the smart-colors runtime (excluded from Hyprland via `NotShowIn`). |
| lxqt | `home/dot_config/lxqt/` (`lxqt.conf`, `lxqt-config-input.conf`) | EXCLUDE | Both files are geometry stubs only (`[General]` plus `__userfile__`); no reusable defaults. LXQt is not the HorneroOS session (Hyprland-first). |
| guitarix | `home/dot_config/guitarix/banks/silentz0r.gx` | EXCLUDE | Single-user amp preset bank; personal artistic tuning, not reusable defaults. Audio-tool presets are out of scope for curated desktop defaults. |
| REAPER | `home/dot_config/REAPER/` (`reaper-fxtags.ini`, one Scarlett-targeted vocal-tracking project template) | EXCLUDE | The session template hardcodes one username home tree and personal media paths and targets one audio interface, so it fails the renders-identically-for-two-users rule (same precedent as the excluded `monitors.conf`). `fxtags` alone is plugin-install-specific taxonomy, not desktop defaults. |
| tmux | `home/dot_config/tmux/` (`tmux.conf`, `tmux.reset.conf`) | ADOPT-COPY | Static, no template vars, no identity or machine paths; generic TPM-based defaults (vi keys, 1-based indexing, clipboard). Recommended for a future extraction pass with materialize/validate wiring; not copied in this pass. |
| yazi | `home/dot_config/yazi/` (`yazi.toml`, `theme.toml`, `keymap.toml`, `init.lua`) | ADOPT-COPY | Static, no identity; curated HorneroConfig headers; flavor refs match shipped theme packs; aligns with the shipped Thunar open-in-yazi actions. Recommended for a future extraction pass; not copied in this pass. |
| bookmarks | `home/dot_config/gtk-3.0/bookmarks.tmpl` | EXCLUDE | Embodies username plus personal directory layout via template; hosts generate GTK bookmarks from XDG dirs at install. Confirms the existing excluded row. |
| config.user | `home/dot_config/git/config.user.tmpl` | EXCLUDE | Identity (`user.name`/`user.email`) by definition; lives only in `~/.config/git/config.user` via the kept `[include]` overlay hook. Confirms the existing excluded row. |
| private_credentials | `home/dot_config/private_credentials/` (2 password-manager-backed key templates) | EXCLUDE | API-key templates resolved from a password manager; never curated, never shipped. Confirms the existing excluded row. |
| wallpaper-binaries | `home/dot_local/share/dots/wallpapers/` (~45M upstream) | EXCLUDE | Binaries are never vendored; `profiles/themes/wallpapers.manifest.json` records refs plus fetch locations and is the distribution contract. Packs ship via the release pipeline, separately. |
| shell-presets | `home/dot_local/share/dots/shell-presets/` (11 layout JSON files) | KEEP-DEFERRED | Quickshell-owned layout presets; owner `HorneroOS/shell`. Moves with `shell/`, same as `quickshell/`. |
| shell-stub | `dot_zshrc`, `dot_p10k.zsh`, aliases, profile, xinitrc, xprofile, `dot_zsh/`, `dot_Xresources` | KEEP-DEFERRED | Owner `HorneroOS/config` shell design pass (see `shell/README.md`): prompt choice, plugin surface, and POSIX-vs-zsh scope are undecided. No generic default invented here. |
| profiles | `profiles/base`, `HORNERO_PROFILE=desktop` / `developer` (packaging matrix) | KEEP-DEFERRED | Owner `HorneroOS/config`. `desktop` and `developer` stay aliases of `base` (the packaging test asserts byte-identical trees) until a real divergence is wanted; no profile invented in this pass. |

Triage counts: ADOPT-COPY 2 (tmux, yazi) / EXCLUDE 7 (lxqt, guitarix,
REAPER, bookmarks, config.user, private_credentials, wallpaper-binaries)
/ KEEP-DEFERRED 4 (autostart, shell-presets, shell-stub, profiles).

Notes: `sss/`, `wpg/`, and `xfce4/` keep their existing deferred status
unchanged (outside this pass's row list). Existing tables above are
untouched; this section only adds verdicts.

## Flagship appearance tokens (new authorship, not extraction)

`profiles/themes/hornero-dark/` + `hornero-light/` are original HorneroOS
flagship themes (terracotta/clay/sunset-warm family), not copies from
`ulises-jeremias/dotfiles`. Each `theme.json` keeps the recipe fields the
apply pipeline already consumes (`schemaVersion`, `id`, `name`,
`darkMode`, `schemeType`, `gtkTheme`, `iconTheme`, `gtkPreferDark`,
`defaultWallpaper`, `wallpaperDir`) and adds the versioned semantic token
model (`family: hornero`, `mode`, `version`, `tokensVersion`,
`palette`, `components`) described by `profiles/themes/tokens.schema.json`
v1.0.0. Dark and light are first-class distinct ramps (deep terracotta
`#B24827`/white for light, ember `#E07856`/espresso for dark), never an
inversion. `scripts/check-contrast.py` (stdlib-only, MIT) gates every
text-on-surface pair at WCAG AA (>= 4.5:1) and runs in `scripts/validate.sh`,
`tests/test_contrast.sh`, and CI; wallpaper binaries stay refs-only in
`wallpapers.manifest.json`. All new code is MIT-only (no GPL).
