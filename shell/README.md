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
