#!/usr/bin/env python3
"""shell.json migration table: contract, golden cases and no-loss invariants.

Run: python3 tests/test_shell_migrations.py
"""
from __future__ import annotations

import copy
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import shell_migrate as sm  # noqa: E402

GOLDEN = ROOT / "tests" / "golden" / "shell-migrations"
TABLE = json.loads((ROOT / "shell" / "shell-migrations.json").read_text(encoding="utf-8"))
SCHEMA = json.loads((ROOT / "shell" / "shell-migrations.schema.json").read_text(encoding="utf-8"))
FACTORY = json.loads((ROOT / "shell" / "shell.default.json").read_text(encoding="utf-8"))

failures: list[str] = []


def check(name: str, cond: bool, detail: str = "") -> None:
    if cond:
        print(f"PASS: {name}")
    else:
        print(f"FAIL: {name}{': ' + detail if detail else ''}")
        failures.append(name)


def load(p: Path):
    return json.loads(p.read_text(encoding="utf-8"))


def golden_cases():
    for d in sorted(p for p in GOLDEN.iterdir() if (p / "case.json").is_file()):
        case = load(d / "case.json")
        yield d.name, load(d / case["user"]), load((d / case["old"]).resolve()), load((d / case["new"]).resolve()), d


# ---- contract ---------------------------------------------------------------
errs = sm.validate_table(TABLE, FACTORY)
check("table validates against the vendored factory default", not errs, "; ".join(errs))
check("schema id is hornero/shell-migrations@1", SCHEMA["properties"]["schema"]["const"] == sm.TABLE_SCHEMA)
try:
    import jsonschema  # type: ignore[import-not-found]
except ImportError:
    print("SKIP: jsonschema not installed; structural checks above still ran")
else:
    try:
        jsonschema.validate(TABLE, SCHEMA)
        check("table conforms to shell-migrations.schema.json", True)
    except jsonschema.ValidationError as e:
        check("table conforms to shell-migrations.schema.json", False, e.message)

ops = {op["op"] for m in TABLE["migrations"] for op in m["ops"]}
schema_ops = {o["properties"]["op"]["const"] for o in SCHEMA["$defs"]["op"]["oneOf"]}
check("every op kind in the table is in the schema", ops <= schema_ops, str(ops - schema_ops))

# The shell applies the same table at load time (config/Config.qml); its
# legacy theme map must not drift from the table.
theme_map = next(op["map"] for m in TABLE["migrations"] for op in m["ops"]
                 if op["op"] == "map-value" and op["path"] == "appearance.theme")
check("theme map targets are shipped Signal themes",
      set(theme_map.values()) <= {"hornero-signal-night", "hornero-signal-day", "hornero-signal-contrast"})

# ---- golden -----------------------------------------------------------------
rc = subprocess.run([sys.executable, str(GOLDEN / "build.py")], capture_output=True, text=True)
check("golden plans and migrated documents match", rc.returncode == 0, rc.stdout + rc.stderr)

# ---- invariants on every case ------------------------------------------------
for name, user, old, new, d in golden_cases():
    report, migrated = sm.plan(user, old, new, TABLE)
    check(f"{name}: zero lost user values", report["summary"]["lost"] == 0,
          str(sm.lost_values(user, sm.flatten(migrated), report)))
    mflat = sm.flatten(migrated)
    bad = [k["path"] for k in report["kept"] if not sm.same(mflat.get(sm.split(k["path"])), k["value"])]
    check(f"{name}: every kept override is byte-for-byte in the migrated file", not bad, str(bad))
    renamed = [m for m in report["migrated"] if m["op"] == "rename"]
    bad = [m["path"] for m in renamed if not sm.same(sm.value_at(mflat, sm.split(m["path"])), m["after"])]
    check(f"{name}: renamed values land under the new key", not bad, str(bad))
    again, again_doc = sm.plan(migrated, new, new, TABLE)
    check(f"{name}: migrating twice changes nothing",
          again["migrated"] == [] and again["removed"] == [] and again["defaultsChanging"] == []
          and sm.flatten(again_doc) == mflat)
    # Same user file against the factory default this repo ships today.
    live, _ = sm.plan(copy.deepcopy(user), old, FACTORY, TABLE)
    check(f"{name}: zero lost against the current vendored default", live["summary"]["lost"] == 0)

# ---- the acceptance fixture --------------------------------------------------
acc = load(GOLDEN / "pre-signal-many-overrides" / "plan.json")
panes = {k["path"].split(".")[0] for k in acc["kept"]}
check("acceptance fixture keeps at least 50 overrides", acc["summary"]["kept"] >= 50, str(acc["summary"]))
check("acceptance fixture spans at least 10 settings areas", len(panes) >= 10, str(sorted(panes)))
check("acceptance fixture exercises every op kind",
      {m["op"] for m in acc["migrated"]} | ({"remove"} if acc["removed"] else set()) >= {"rename", "map-value", "set-once", "remove"})
rename_conflict = load(GOLDEN / "rename-conflict" / "plan.json")
check("conflicting rename keeps the new key and reports the old value",
      rename_conflict["conflicts"] and rename_conflict["conflicts"][0]["kept"] is False
      and rename_conflict["conflicts"][0]["dropped"] is True)
user_data_kept = [k for k in load(GOLDEN / "pre-signal-untouched" / "plan.json")["kept"] if k["userData"]]
check("user data (bars) is kept even when it still equals the old default",
      any(k["path"] == "bar.bars" for k in user_data_kept))

if failures:
    print(f"\n{len(failures)} check(s) failed")
    sys.exit(1)
print("\nall shell migration checks passed")
