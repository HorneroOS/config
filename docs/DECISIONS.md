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
