# Contributing to HorneroOS config

## Ground rules

- You may only contribute **generic, reusable defaults**. Re-read
  `AGENTS.md` (personal-vs-default rules) before proposing anything.
- Upstream dotfiles are read-only: pin the source commit in your PR
  description and copy, never move.

## Adding or updating curated defaults

1. Name the upstream path and commit (`ulises-jeremias/dotfiles@<sha>`).
2. Copy it into the Hornero layout (`desktop/<app>`, `xdg/`, `profiles/`,
   `lib/dots/`, `bin/`) with `cp`; strip `executable_` prefixes and `.tmpl`
   suffixes at copy time, materialize template variables, keep `+x` where the
   file must execute.
3. Record the decision in `docs/DECISIONS.md`: what was copied, what sibling
   content was excluded as personal, what is deferred.
4. Extend `scripts/materialize.sh` mapping if the install target is new, and
   `scripts/validate.sh` if the format is new. Extend
   `tests/test_materialize.sh` with an installed-file assertion.
5. Run the full gate locally and keep it green:

```sh
scripts/validate.sh
tests/test_materialize.sh
pre-commit run --all-files
```

## Commit messages

Small coherent commits with `chore:` / `feat:` / `refactor:` / `test:` /
`docs:` prefixes and provenance (upstream path + commit) in the body.

## Reviews

Expect reviewers to check: no identity or secrets (the guard script is
necessary but not sufficient — read your own diff), XDG-awareness, hermetic
`--dest` behavior, and DECISIONS coverage. Happy-path-only extractions will
be sent back: error paths, missing-file behavior, and machine variance must
be handled or documented.
