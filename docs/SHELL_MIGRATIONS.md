# shell.json migrations

Updates must never eat customisations. When a HorneroOS/shell release renames,
reshapes or retires a key in `shell.json`, the change is recorded here first,
in `shell/shell-migrations.json` (`hornero/shell-migrations@1`), so the value a
user stored under the old key reaches the new key before the new shell reads
the file.

## Files

- `shell/shell-migrations.json`: the migration table, installed at
  `/usr/share/hornero/shell-migrations.json`.
- `shell/shell-migrations.schema.json`: JSON Schema for the table, installed
  next to it.
- `scripts/shell_migrate.py`: reference implementation (`validate`, `plan`).
- `tests/golden/shell-migrations/`: golden cases (user file, factory pins,
  expected plan and migrated file).
- `tests/test_shell_migrations.py`: CI gate for the schema, the golden
  cases, zero lost values and idempotence.

The product implementation is `horneroctl update plan` (HorneroOS/hornero).
It reads the installed table and must produce the same plan as the reference
for the golden cases. The Control Center shows the result under
Customisation > After the last update (HorneroOS/shell).

## Versioning

`schemaVersion` equals the highest `version` in `migrations`. Versions are
unique and increasing; a released migration is never edited or renumbered,
only followed by a new one. Every op is idempotent, so running the table
again on an already migrated file changes nothing; the version is a record,
not a gate.

## Ops

- `rename` (`from`, `to`): moves the value or subtree. If `to` already holds
  a value that is neither the moved value nor the new factory default, `to`
  wins and the old value is reported as a conflict.
- `map-value` (`path`, `map`): replaces a retired string value (theme ids,
  fonts) with its successor.
- `remove` (`path`, `reason`, optional `replacedBy`): retires a key with no
  equivalent. The old value stays in the report and the pre-update backup.
  `reason` is user-facing text.
- `set-once` (`marker`, `set`): sets values once, then sets `marker` to
  `true` so a later choice is never reset.

`userData` lists path prefixes that are the user's data (bars, app lists,
layouts, plugins). A plan never moves them to a new default on its own, even
when they still equal the old one; they are listed as kept.

## How a plan judges each value

The old factory default is migrated with the same table, so every value is
compared in the new key space:

- **Kept override**: differs from the old default. Always kept, also when the
  new default changed (the report shows both).
- **Default that changes for you**: equal to the old default (or absent) and
  the default changed. It follows the new default; the report shows the old
  value so the user can keep it.
- **Migrated**: changed by a `rename`, `map-value` or `set-once` op.
- **Removed**: retired by a `remove` op, or not a setting of the new version
  at all (unknown key). The value is in the report.
- **Lost**: an original value accounted for nowhere above. A plan with
  `lost > 0` is a bug; `horneroctl update plan --apply` refuses it.

## Adding a migration

1. Change the key in HorneroOS/shell and note the old name in the PR.
2. Add a migration with the next `version`, bump `schemaVersion`, and give
   every `remove` a `reason` a user can act on.
3. Add or extend a golden case under `tests/golden/shell-migrations/`
   (`build.py` lists the cases), run
   `python3 tests/golden/shell-migrations/build.py --update`, and review the
   diff of `plan.json` and `migrated.json`.
4. Run `python3 tests/test_shell_migrations.py`.
5. Copy the golden case into HorneroOS/hornero `cli/testdata/update-plan/`
   so `horneroctl` is held to the same result.
