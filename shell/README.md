# shell/ — deferred

Interactive shell configuration (zsh, p10k, aliases, profile, xinitrc) is
**deliberately not extracted** in this initial pass.

Rationale: the dotfiles shell layer (`dot_zshrc`, `dot_p10k.zsh`,
`dot_zsh_aliases.tmpl`, `executable_dot_profile`, `executable_dot_xinitrc`,
`dot_zprofile`) is personal and prompt-specific. Curating a generic
HorneroOS shell default needs its own design pass (prompt choice, plugin
manager, POSIX vs zsh surface). See `docs/DECISIONS.md` ("Deferred" table).

When that pass happens, its output belongs here (e.g. `shell/zsh/`,
`shell/profile`) and must follow the same rules as this repo: no identity,
no machine specifics, XDG-aware, `set -euo pipefail`, materialized through
`scripts/materialize.sh`, covered by `scripts/validate.sh`.

## Factory shell default (`shell.default.json`)

`shell/shell.default.json` is the factory default for the system location
`/etc/xdg/hornero/shell.json` (path-contract row 6). Content is owned by
`HorneroOS/shell` (`config/shell.default.json`); this repo only packages it.

Provenance lives in `shell/shell.default.source` (`shell_sha=`, the
shell commit the copy was taken from). `tests/test_shell_default_sync.sh`
(CI) fails when the vendored file is not byte-identical to
`config/shell.default.json` at that commit, and emits a warning when
shell main has changed the file since. The release gate is in
`HorneroOS/hornero` `scripts/compose.sh`: a composition fails when its
config pin ships a different factory default than its shell pin.

Refresh rule: copy the file byte-exact from a newer shell commit and
update `shell_sha=` in the same commit. `PKGBUILD` fails the build if
the file is missing; `tests/test_package.sh` asserts the installed
`/etc/xdg/hornero/shell.json` is byte-identical to this copy.

`scripts/materialize.sh` deliberately does **not** install a user-root
`~/.config/hornero/shell.json`: the user file is created by the shell
runtime on first launch (the shell writes `{}` when absent).
Packaging is the only writer of the system default.

## Layout preset catalogue

The layout definitions are authored by HorneroOS/shell in `presets/*.json`.
This repo carries a package copy in `profiles/shell-presets/` so the system
catalogue can work without a user's dotfiles or Shell checkout. Provenance is
recorded in `shell/shell-presets.source`; `tests/test_shell_presets_sync.sh`
requires a byte-exact match at that shell commit and warns when shell main
advances the catalogue.

`scripts/materialize.sh` puts the same files under the canonical user data
path `~/.local/share/hornero/shell-presets/`, while `packaging/PKGBUILD`
installs the read-only package copy at `/usr/share/hornero/shell-presets/`.
`horneroctl shell preset list` resolves user data first and then the system
catalogue, so a deliberate user override still wins.

Refresh the package copy from a reviewed HorneroOS/shell commit, update the
source SHA, and run the sync test. Shell schema and layout rendering tests
remain in HorneroOS/shell and HorneroOS/qa.
