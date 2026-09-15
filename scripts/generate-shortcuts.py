#!/usr/bin/env python3
"""Generate a machine-readable shortcut manifest from keybindings.conf.

Reads the authoritative Hyprland bindings
(desktop/hypr/hyprland.conf.d/keybindings.conf) and emits
`shortcuts.json`:

    {"schemaVersion": 1, "source": "<relpath>", "entries": [
      {"id": "exec:dots-launcher", "mods": ["SUPER"], "key": "SPACE",
       "dispatcher": "exec", "args": "...", "submap": ""}, ...]}

Entry ids are stable slugs of dispatcher + first argument token. The
Welcome Center resolves a curated subset of these ids at runtime; unknown
ids render no badge (never a wrong shortcut). Deterministic output
(sorted entries, trailing newline) so tests can regenerate + diff.

Usage: python3 scripts/generate-shortcuts.py [--root DIR] [--out PATH]
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

BIND_RE = re.compile(r"^bind([a-z]*)\s*=\s*([^,]*),([^,]*),([^,]+?)(?:,(.*))?$")
SUBMAP_RE = re.compile(r"^submap\s*=\s*(.*)$")
VAR_RE = re.compile(r"^\$([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(\S+)\s*$")


def slug(text: str) -> str:
    text = text.strip().lower()
    text = re.sub(r"\.sh$", "", text)
    text = re.sub(r"[^a-z0-9]+", "-", text).strip("-")
    return text or "unnamed"


def expand_vars(text: str, variables: dict[str, str]) -> str:
    for name, value in variables.items():
        text = text.replace(f"${name}", value)
    return text


def entry_id(dispatcher: str, args: str) -> str:
    """Stable action-oriented id (machine key, never UX copy)."""
    if dispatcher == "exec":
        tokens = args.replace(",", " ").split()
        if "ipc" in tokens:
            rest = tokens[tokens.index("ipc") + 1 :]
            return f"ipc-{slug('-'.join(rest))}"
        if "exo-open" in tokens and "--launch" in tokens:
            launched = tokens[tokens.index("--launch") + 1 :]
            return f"app-{slug('-'.join(launched))}"
        prog_tokens = [
            tok.split("/")[-1]
            for tok in tokens
            if not tok.startswith("-") and not tok.startswith("$")
        ]
        # `dots <subcommand>` is a multi-call binary: name the subcommand.
        if prog_tokens and prog_tokens[0] == "dots" and len(prog_tokens) > 1:
            return f"exec-{slug(prog_tokens[1])}"
        for prog in prog_tokens:
            prog = re.sub(r"^dots-", "", prog)
            if prog:
                return f"exec-{slug(prog)}"
        return "exec-custom"
    first = args.strip().split(",", 1)[0].strip()
    return f"{slug(dispatcher)}:{slug(first)}"


def parse_bindings(conf: Path) -> list[dict]:
    entries: list[dict] = []
    variables: dict[str, str] = {}
    submap = ""
    for lineno, raw in enumerate(conf.read_text(encoding="utf-8").splitlines(), 1):
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        var = VAR_RE.match(line)
        if var:
            variables[var.group(1)] = var.group(2)
            continue
        sub = SUBMAP_RE.match(line)
        if sub:
            submap = sub.group(1).strip()
            continue
        m = BIND_RE.match(line)
        if not m:
            continue
        flags, mods_raw, key, dispatcher, args = (
            m.group(1),
            m.group(2),
            m.group(3).strip(),
            m.group(4).strip(),
            (m.group(5) or "").strip(),
        )
        mods = [
            expand_vars(x.strip(), variables)
            for x in mods_raw.split()
            if x.strip()
        ]
        key = expand_vars(key, variables)
        if not key or not dispatcher:
            raise ValueError(f"{conf}:{lineno}: unparsable bind: {raw!r}")
        entries.append(
            {
                "id": entry_id(dispatcher, args),
                "mods": mods,
                "key": key,
                "dispatcher": dispatcher,
                "args": args,
                "submap": "" if submap.lower() == "reset" else submap,
                "flags": flags,
            }
        )
    # Deterministic order for diffable output.
    entries.sort(
        key=lambda e: (e["submap"], e["dispatcher"], e["key"], e["id"], e["flags"])
    )
    return entries


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Generate shortcuts.json.")
    parser.add_argument("--root", default=None, help="Repository root")
    parser.add_argument("--out", default=None, help="Output path")
    args = parser.parse_args(argv)
    root = Path(args.root) if args.root else Path(__file__).resolve().parent.parent
    conf = root / "desktop" / "hypr" / "hyprland.conf.d" / "keybindings.conf"
    if not conf.is_file():
        print(f"SHORTCUTS-FAIL: {conf} not found")
        return 1
    try:
        entries = parse_bindings(conf)
    except (OSError, ValueError) as exc:
        print(f"SHORTCUTS-FAIL: {exc}")
        return 1
    if not entries:
        print("SHORTCUTS-FAIL: no bindings parsed")
        return 1
    doc = {
        "schemaVersion": 1,
        "source": "desktop/hypr/hyprland.conf.d/keybindings.conf",
        "entries": entries,
    }
    out = Path(args.out) if args.out else root / "shortcuts.json"
    out.write_text(json.dumps(doc, indent=2, sort_keys=False) + "\n", encoding="utf-8")
    print(f"SHORTCUTS-PASS: {len(entries)} entries -> {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
