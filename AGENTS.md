# AGENTS.md — working rules for HorneroOS config

## Ownership

- This repo owns **curated reusable defaults only**. Personal workstation
  configuration belongs in `ulises-jeremias/dotfiles`, never here.
- The dotfiles repo is **read-only** to this project: clone it, read from a
  pinned commit, `cp` what is approved. Never add a remote, never push there,
  never move files out of it.
- The desktop shell belongs to `HorneroOS/shell`, distribution composition to
  `HorneroOS/hornero`. Do not absorb either here.

## Personal vs default

A file may enter this repo only if it is meaningful with **no** username,
email, hostname, SSID, token, API key, monitor serial, or `/home/<someone>`
path. Ask for each candidate:

1. Does it render identically for two different users? If not, exclude it.
2. Does it reference a machine (outputs, drivers, PCI paths)? If yes,
   replace with a generic fallback and document it in `docs/DECISIONS.md`.
3. Does it carry identity via template (`{{ .chezmoi.* }}`, `{{ .gitconfig.* }}`)?
   Materialize the generic parts; leave identity behind with an overlay hook.

`scripts/guard-personal-data.sh` encodes these rules and must stay green.
Copyright attributions and `ulises-jeremias/dotfiles` provenance URLs are
explicitly allowlisted — they are attribution, not personal data.

## Shell standards

- All shell files: `set -euo pipefail`, POSIX-leaning bash, no bashisms
  without reason.
- XDG-aware: config under `${XDG_CONFIG_HOME:-~/.config}`, data under
  `${XDG_DATA_HOME:-~/.local/share}`, state under
  `${XDG_STATE_HOME:-~/.local/state}`, cache under
  `${XDG_CACHE_HOME:-~/.cache}`. Never hardcode `/home/<name>`.
- `--dest` installs must be hermetic: temp-HOME tests must not read or write
  the real HOME. Honor ambient XDG variables only for real-HOME installs.
- No secrets in code, comments, or fixtures. Scan before every commit.

## Change discipline

- Small coherent commits (`chore:` / `feat:` / `refactor:` / `test:` /
  `docs:`) with provenance in the message.
- Every extraction updates `docs/DECISIONS.md` (copied / excluded /
  deferred), `scripts/validate.sh` coverage where formats change, and the
  temp-HOME test where install mapping changes.
- Keep CI green: `scripts/validate.sh` + `tests/test_materialize.sh` +
  `pre-commit run --all-files`. Fix failures; never disable checks to get
  green. The shellcheck gate severity is `error` (documented in DECISIONS) —
  that is the configured gate, not a skipped check.
