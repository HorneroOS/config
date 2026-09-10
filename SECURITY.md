# Security policy for HorneroOS config

## Scope

This repository ships static desktop defaults, helper shell libraries, and
small CLI adapters. It contains no network services, no privileged code, and
— by policy — no credentials of any kind.

## Reporting a vulnerability

Open a GitHub issue in `HorneroOS/config` with `[security]` in the title, or
contact the HorneroOS maintainers through the organization profile. Please
include the affected path, the branch or commit, and (for config issues) the
smallest reproduction using `scripts/materialize.sh --dest <tmpdir>`.

## Guarantees and non-guarantees

- CI runs `scripts/guard-personal-data.sh` on every push and PR: mailbox
  strings, secret assignments, chezmoi identity variables, hardcoded
  `/home/<name>` paths, and `[user]` identity stanzas in shipped git config
  all fail the build.
- The guard is syntactic. Reviewers still read diffs for semantic leaks
  (hostnames in comments, personal SSIDs in examples, tokens in fixtures).
- Helper scripts in `lib/dots` and `bin/` execute with user privileges and
  must never `curl | sh`, exfiltrate, or write outside XDG locations without
  an explicit flag. Report any script violating that as a security issue.
- Git identity is intentionally **not** shipped: if you find a `user.name`
  or `user.email` value anywhere under `desktop/`, `xdg/`, `profiles/`,
  `lib/`, `bin/`, `scripts/`, or `shell/`, treat it as a leak and report it.

## Supported versions

Only the `main` branch is supported. Fix branches are cut from `main` and
merged back; no long-lived release lines exist yet.
