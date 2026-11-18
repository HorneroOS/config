#!/usr/bin/env python3
"""Reference implementation of the shell.json migration table.

`shell/shell-migrations.json` (hornero/shell-migrations@1) is the contract;
`horneroctl update plan` (HorneroOS/hornero) is the product implementation and
must produce the same plan for the golden cases in
`tests/golden/shell-migrations/`. This script exists so the table can be
validated and its effect reviewed without building horneroctl.

Usage:
  scripts/shell_migrate.py validate [--table PATH] [--defaults PATH]
  scripts/shell_migrate.py plan --user U --old O --new N [--table PATH]
                                [--out REPORT] [--write-migrated FILE]

`plan` never touches U. `--write-migrated` writes the migrated document to a
separate file (for tests and review).

Semantics (shared with horneroctl):
  * Paths are dotted. A document is handled as an ordered list of leaves;
    non-empty objects are containers, everything else (scalars, arrays, {})
    is a leaf.
  * Ops run in `version` order and are idempotent:
      rename     from -> to. Moves the value (or subtree). If `to` already
                 holds a value that is neither the moved value nor the new
                 factory default, `to` wins and the moved value is reported
                 as a conflict (never silently dropped).
      map-value  replaces a string value found in `map`.
      remove     deletes a retired path; its value goes into the report.
      set-once   when `marker` is not true, sets each path and the marker.
  * Old factory defaults are migrated with the same table, so overrides are
    judged in the new key space.
  * Override: a user value that differs from the (migrated) old default.
    Overrides are always kept.
  * Untouched value (equal to the old default, or absent) whose default
    changed: it follows the new default ("defaults that change for you"),
    except below a `userData` prefix (bars, app lists, layouts, plugins):
    those stay as they are and are listed as kept.
  * A user key that is neither a setting of the new defaults nor below a
    free-form container of them is reported as removed (reason: unknown).
  * `lost` counts original user values that end up nowhere: not in the new
    document, not adopted, not migrated, not in the report. It must be 0.
"""
from __future__ import annotations

import argparse
import copy
import json
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_TABLE = ROOT / "shell" / "shell-migrations.json"
DEFAULT_FACTORY = ROOT / "shell" / "shell.default.json"
TABLE_SCHEMA = "hornero/shell-migrations@1"
PLAN_SCHEMA = "hornero/update-plan@1"
UNKNOWN_REASON = "Not a setting in this HorneroOS version; the shell ignores it. The value is kept in this report and in the pre-update backup."

Path_ = tuple[str, ...]


# ---- flat documents ---------------------------------------------------------

def flatten(obj: Any, prefix: Path_ = (), out: dict[Path_, Any] | None = None) -> dict[Path_, Any]:
    out = {} if out is None else out
    if isinstance(obj, dict) and (obj or not prefix):
        for k, v in obj.items():
            p = prefix + (k,)
            if isinstance(v, dict) and v:
                flatten(v, p, out)
            else:
                out[p] = v
    else:
        out[prefix] = obj
    return out


def unflatten(flat: dict[Path_, Any]) -> dict[str, Any]:
    doc: dict[str, Any] = {}
    for path, value in flat.items():
        cur = doc
        for k in path[:-1]:
            nxt = cur.get(k)
            if not isinstance(nxt, dict):
                nxt = {}
                cur[k] = nxt
            cur = nxt
        cur[path[-1]] = copy.deepcopy(value)
    return doc


def split(path: str) -> Path_:
    return tuple(path.split("."))


def dotted(path: Path_) -> str:
    return ".".join(path)


def under(path: Path_, prefix: Path_) -> bool:
    return path[: len(prefix)] == prefix


def subtree(flat: dict[Path_, Any], prefix: Path_) -> dict[Path_, Any]:
    return {p: v for p, v in flat.items() if under(p, prefix)}


def value_at(flat: dict[Path_, Any], prefix: Path_) -> Any:
    """Leaf value, or the rebuilt subtree for a container prefix."""
    if prefix in flat:
        return flat[prefix]
    sub = subtree(flat, prefix)
    if not sub:
        return None
    rebuilt: Any = unflatten({p[len(prefix):]: v for p, v in sub.items()})
    return rebuilt


def has(flat: dict[Path_, Any], prefix: Path_) -> bool:
    return any(under(p, prefix) for p in flat)


def drop(flat: dict[Path_, Any], prefix: Path_) -> None:
    for p in [p for p in flat if under(p, prefix)]:
        del flat[p]


def put(flat: dict[Path_, Any], prefix: Path_, value: Any) -> None:
    drop(flat, prefix)
    # A leaf on an ancestor path would hide the new key; replace it.
    for i in range(1, len(prefix)):
        flat.pop(prefix[:i], None)
    if isinstance(value, dict) and value:
        for p, v in flatten(value).items():
            flat[prefix + p] = v
    else:
        flat[prefix] = value


def same(a: Any, b: Any) -> bool:
    if isinstance(a, bool) or isinstance(b, bool):
        return a is b if isinstance(a, bool) and isinstance(b, bool) else False
    if isinstance(a, (int, float)) and isinstance(b, (int, float)):
        return abs(float(a) - float(b)) < 1e-9
    if isinstance(a, list) and isinstance(b, list):
        return len(a) == len(b) and all(same(x, y) for x, y in zip(a, b))
    if isinstance(a, dict) and isinstance(b, dict):
        return a.keys() == b.keys() and all(same(a[k], b[k]) for k in a)
    return a == b and type(a) is type(b)


# ---- table ------------------------------------------------------------------

def load_json(path: Path) -> Any:
    return json.loads(Path(path).read_text(encoding="utf-8"))


def validate_table(table: Any, factory: dict[str, Any] | None = None) -> list[str]:
    errs: list[str] = []
    if not isinstance(table, dict) or table.get("schema") != TABLE_SCHEMA:
        return [f"schema must be {TABLE_SCHEMA}"]
    migs = table.get("migrations")
    if not isinstance(migs, list):
        return ["migrations must be a list"]
    versions = [m.get("version") for m in migs]
    if versions != sorted(versions) or len(set(versions)) != len(versions):
        errs.append("migration versions must be unique and increasing")
    if migs and table.get("schemaVersion") != versions[-1]:
        errs.append("schemaVersion must equal the highest migration version")
    ids = [m.get("id") for m in migs]
    if len(set(ids)) != len(ids):
        errs.append("migration ids must be unique")
    fac = flatten(factory) if factory is not None else None
    # userData prefixes may name sections a newer shell adds (e.g. layouts),
    # so they are not required to exist in this factory copy.
    if len(set(table.get("userData", []))) != len(table.get("userData", [])):
        errs.append("userData prefixes must be unique")
    for m in migs:
        for k in ("version", "id", "summary", "ops"):
            if k not in m:
                errs.append(f"migration {m.get('id')}: missing {k}")
        for op in m.get("ops", []):
            kind = op.get("op")
            where = f"{m.get('id')}/{kind}"
            if kind == "rename":
                if not {"from", "to"} <= op.keys():
                    errs.append(f"{where}: needs from and to")
                elif fac is not None:
                    if not has(fac, split(op["to"])):
                        errs.append(f"{where}: target {op['to']} is not in the factory defaults")
                    if has(fac, split(op["from"])):
                        errs.append(f"{where}: source {op['from']} is still in the factory defaults")
            elif kind == "map-value":
                if not isinstance(op.get("map"), dict) or not op.get("path"):
                    errs.append(f"{where}: needs path and map")
                elif fac is not None and split(op["path"]) not in fac:
                    errs.append(f"{where}: {op['path']} is not in the factory defaults")
            elif kind == "remove":
                if not op.get("path") or not op.get("reason"):
                    errs.append(f"{where}: needs path and reason")
                elif fac is not None:
                    if has(fac, split(op["path"])):
                        errs.append(f"{where}: {op['path']} is still in the factory defaults")
                    if op.get("replacedBy") and not has(fac, split(op["replacedBy"])):
                        errs.append(f"{where}: replacedBy {op['replacedBy']} is not in the factory defaults")
            elif kind == "set-once":
                if not op.get("marker") or not isinstance(op.get("set"), dict):
                    errs.append(f"{where}: needs marker and set")
                elif fac is not None:
                    for p in [op["marker"], *op["set"].keys()]:
                        if split(p) not in fac:
                            errs.append(f"{where}: {p} is not in the factory defaults")
            else:
                errs.append(f"{where}: unknown op")
    return errs


def migrate(doc: dict[str, Any], table: dict[str, Any], factory: dict[str, Any] | None = None):
    """Return (flat migrated doc, migrated entries, removed entries, conflicts)."""
    flat = flatten(doc)
    fac = flatten(factory) if factory is not None else {}
    migrated: list[dict[str, Any]] = []
    removed: list[dict[str, Any]] = []
    conflicts: list[dict[str, Any]] = []
    for m in sorted(table["migrations"], key=lambda x: x["version"]):
        for op in m["ops"]:
            kind = op["op"]
            tag = {"migration": m["id"], "version": m["version"], "op": kind}
            if kind == "rename":
                src, dst = split(op["from"]), split(op["to"])
                if not has(flat, src):
                    continue
                moved = value_at(flat, src)
                if has(flat, dst):
                    existing = value_at(flat, dst)
                    if not same(existing, moved) and not same(existing, value_at(fac, dst)):
                        drop(flat, src)
                        conflicts.append({**tag, "path": op["to"], "from": op["from"], "kept": existing, "dropped": moved})
                        continue
                drop(flat, src)
                put(flat, dst, moved)
                migrated.append({**tag, "path": op["to"], "from": op["from"], "before": moved, "after": moved})
            elif kind == "map-value":
                p = split(op["path"])
                v = flat.get(p)
                if isinstance(v, str) and v in op["map"]:
                    flat[p] = op["map"][v]
                    migrated.append({**tag, "path": op["path"], "before": v, "after": op["map"][v]})
            elif kind == "remove":
                p = split(op["path"])
                if not has(flat, p):
                    continue
                entry = {**tag, "path": op["path"], "value": value_at(flat, p), "reason": op["reason"]}
                if op.get("replacedBy"):
                    entry["replacedBy"] = op["replacedBy"]
                drop(flat, p)
                removed.append(entry)
            elif kind == "set-once":
                marker = split(op["marker"])
                if flat.get(marker) is True:
                    continue
                for path, value in op["set"].items():
                    p = split(path)
                    before = flat.get(p)
                    put(flat, p, value)
                    if before is None or not same(before, value):
                        migrated.append({**tag, "path": path, "before": before, "after": value})
                put(flat, marker, True)
            else:
                raise ValueError(f"unknown op {kind}")
    return flat, migrated, removed, conflicts


def _known(path: Path_, new_flat: dict[Path_, Any]) -> bool:
    if path in new_flat:
        return True
    return any(path[:i] in new_flat for i in range(1, len(path)))


def plan(user: dict[str, Any], old: dict[str, Any], new: dict[str, Any], table: dict[str, Any]):
    """Return (report core dict, migrated user document)."""
    flat, migrated, removed, conflicts = migrate(copy.deepcopy(user), table, new)
    old_flat, _, _, _ = migrate(copy.deepcopy(old), table, new)
    new_flat = flatten(new)

    user_data = [split(p) for p in table.get("userData", [])]
    kept: list[dict[str, Any]] = []
    changing: list[dict[str, Any]] = []
    unknown: list[dict[str, Any]] = []
    for path in sorted(flat):
        value = flat[path]
        if not _known(path, new_flat):
            unknown.append({"path": dotted(path), "value": value, "reason": UNKNOWN_REASON})
            continue
        has_old, has_new = path in old_flat, path in new_flat
        old_v, new_v = old_flat.get(path), new_flat.get(path)
        default_changed = has_old and has_new and not same(old_v, new_v)
        is_user_data = any(under(path, p) for p in user_data)
        untouched = (has_old and same(value, old_v)) or (not has_old and has_new and same(value, new_v))
        if untouched and not (default_changed and is_user_data):
            if default_changed:
                changing.append({"path": dotted(path), "before": value, "after": new_v, "pinned": True})
            continue
        kept.append({
            "path": dotted(path), "value": value,
            "oldDefault": old_v if has_old else None,
            "newDefault": new_v if has_new else None,
            "defaultChanged": default_changed,
            "userData": is_user_data,
        })
    for path in sorted(new_flat):
        if path in flat or has(flat, path) or path not in old_flat:
            continue
        if not same(old_flat[path], new_flat[path]):
            changing.append({"path": dotted(path), "before": old_flat[path], "after": new_flat[path], "pinned": False})
    changing.sort(key=lambda c: c["path"])

    for u in unknown:
        drop(flat, split(u["path"]))
    for c in changing:
        put(flat, split(c["path"]), c["after"])
    new_settings = sorted(dotted(p) for p in new_flat if p not in old_flat)

    report = {
        "schema": PLAN_SCHEMA,
        "schemaVersion": {"table": table.get("schemaVersion", 0)},
        "summary": {},
        "kept": kept,
        "defaultsChanging": changing,
        "migrated": migrated,
        "removed": removed + unknown,
        "conflicts": conflicts,
        "newSettings": new_settings,
    }
    report["summary"] = {
        "kept": len(kept), "defaultsChanging": len(changing), "migrated": len(migrated),
        "removed": len(removed) + len(unknown), "conflicts": len(conflicts),
        "newSettings": len(new_settings), "lost": len(lost_values(user, flat, report)),
    }
    return report, unflatten(flat)


def lost_values(user: dict[str, Any], result_flat: dict[Path_, Any], report: dict[str, Any]) -> list[str]:
    """Original user leaves that the result and the report do not account for."""
    accounted: list[tuple[Path_, Any, bool]] = []  # (path, value, prefix-match)
    for c in report["defaultsChanging"]:
        if c["pinned"]:
            accounted.append((split(c["path"]), c["before"], False))
    for m in report["migrated"]:
        accounted.append((split(m.get("from", m["path"])), m["before"], m["op"] == "rename"))
    for r in report["removed"]:
        accounted.append((split(r["path"]), r["value"], True))
    for c in report["conflicts"]:
        accounted.append((split(c["from"]), c["dropped"], True))
    lost: list[str] = []
    for path, value in flatten(user).items():
        if path in result_flat and same(result_flat[path], value):
            continue
        ok = False
        for a_path, a_value, prefix in accounted:
            if a_path == path and same(a_value, value):
                ok = True
            elif prefix and under(path, a_path) and same(value_at(flatten({"_": a_value}), ("_",) + path[len(a_path):]), value):
                ok = True
            if ok:
                break
        if not ok:
            lost.append(dotted(path))
    return lost


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    v = sub.add_parser("validate")
    v.add_argument("--table", type=Path, default=DEFAULT_TABLE)
    v.add_argument("--defaults", type=Path, default=DEFAULT_FACTORY)
    p = sub.add_parser("plan")
    p.add_argument("--user", type=Path, required=True)
    p.add_argument("--old", type=Path, required=True)
    p.add_argument("--new", type=Path, required=True)
    p.add_argument("--table", type=Path, default=DEFAULT_TABLE)
    p.add_argument("--out", type=Path)
    p.add_argument("--write-migrated", type=Path)
    args = ap.parse_args(argv)
    if args.cmd == "validate":
        errs = validate_table(load_json(args.table), load_json(args.defaults))
        for e in errs:
            print(f"error: {e}", file=sys.stderr)
        print("ok" if not errs else f"{len(errs)} error(s)")
        return 1 if errs else 0
    report, doc = plan(load_json(args.user), load_json(args.old), load_json(args.new), load_json(args.table))
    text = json.dumps(report, indent=2, ensure_ascii=False) + "\n"
    if args.out:
        args.out.write_text(text, encoding="utf-8")
    else:
        sys.stdout.write(text)
    if args.write_migrated:
        args.write_migrated.write_text(json.dumps(doc, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return 1 if report["summary"]["lost"] else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
