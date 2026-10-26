#!/usr/bin/env python3
"""Generate a machine-readable shortcut manifest from keybindings.lua.

Reads the authoritative Hyprland bindings
(desktop/hypr/hyprland.lua.d/keybindings.lua) and emits
`shortcuts.json`:

    {"schemaVersion": 1, "source": "<relpath>", "entries": [
      {"id": "exec-launcher", "mods": ["CTRL"], "key": "SPACE",
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

def slug(text: str) -> str:
    text = text.strip().lower()
    text = re.sub(r"\.lua$", "", text)
    text = re.sub(r"\.sh$", "", text)
    text = re.sub(r"[^a-z0-9]+", "-", text).strip("-")
    return text or "unnamed"


LUA_BIND_START = re.compile(r"hl\.bind\(")
SUBMAP_START = re.compile(r'hl\.define_submap\("([^"]+)"')

DIR = {"left": "l", "right": "r", "up": "u", "down": "d"}


def _scan_call(text, start):
    """Return (args_text, end_index) for the call whose '(' is at start-1."""
    depth = 0
    i = start - 1
    in_str = False
    while i < len(text):
        c = text[i]
        if in_str:
            if c == "\\":
                i += 2
                continue
            if c == '"':
                in_str = False
        elif c == '"':
            in_str = True
        elif c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                return text[start:i], i
        i += 1
    raise ValueError("unbalanced hl.bind call")


def _legacy(dsp, inner):
    """Map an hl.dsp expression to the legacy (dispatcher, args) pair."""
    inner = inner.strip()
    if dsp == "exec_cmd":
        cmd = inner.strip('"')
        m = re.match(r"hyprctl dispatch ([^,]+), (.+)$", cmd)
        if m:
            return m.group(1), m.group(2)
        return "exec", cmd
    if dsp == "window.kill":
        return "killactive", ""
    if dsp == "window.float":
        return "togglefloating", ""
    if dsp == "window.fullscreen":
        return "fullscreen", "1" if "maximized" in inner else "0"
    if dsp == "window.pin":
        return "pin", ""
    if dsp == "window.center":
        return "centerwindow", ""
    if dsp == "window.drag":
        return "movewindow", ""
    if dsp == "window.resize":
        if not inner:
            return "resizewindow", ""
        x = re.search(r"x\s*=\s*(-?\d+)", inner)
        y = re.search(r"y\s*=\s*(-?\d+)", inner)
        return "resizeactive", f"{x.group(1) if x else 0} {y.group(1) if y else 0}"
    if dsp == "window.move":
        ws = re.search(r'workspace\s*=\s*"([^"]+)"', inner)
        if ws:
            return ("movetoworkspacesilent" if "follow = false" in inner else "movetoworkspace"), ws.group(1)
        d = re.search(r'direction\s*=\s*"([^"]+)"', inner)
        return "movewindow", DIR.get(d.group(1), d.group(1)) if d else ""
    if dsp == "focus":
        ws = re.search(r'workspace\s*=\s*"([^"]+)"', inner)
        if ws:
            return "workspace", ws.group(1)
        if "last = true" in inner:
            return "focuscurrentorlast", ""
        d = re.search(r'direction\s*=\s*"([^"]+)"', inner)
        return "movefocus", DIR.get(d.group(1), d.group(1)) if d else ""
    if dsp == "layout":
        return "layoutmsg", inner.strip('"')
    if dsp == "group.next":
        return "changegroupactive", "f"
    if dsp == "group.prev":
        return "changegroupactive", "b"
    if dsp == "group.toggle":
        return "togglegroup", ""
    if dsp == "group.lock_active":
        return "lockactivegroup", "toggle"
    if dsp == "workspace.toggle_special":
        return "togglespecialworkspace", inner.strip('"')
    if dsp == "submap":
        return "submap", inner.strip('"')
    if dsp == "exit":
        return "exit", ""
    return dsp, inner.strip('"')


def entry_id(dispatcher: str, args: str) -> str:
    """Stable action-oriented id (machine key, never UX copy)."""
    if dispatcher == "exec":
        tokens = args.replace(",", " ").split()
        prog_tokens = [
            tok.split("/")[-1]
            for tok in tokens
            if not tok.startswith("-") and not tok.startswith("$")
        ]
        # `horneroctl <group> <verb> ...` is the system CLI: name the verb
        # path, with pinned stable ids for the curated Welcome actions so a
        # changing implementation details never renames the id the shell
        # resolves. This runs before the `ipc` rule: `shell ipc -- call ...` is a
        # passthrough whose surface ids are pinned below.
        if prog_tokens and prog_tokens[0] == "horneroctl":
            sub = [t for t in prog_tokens[1:] if t not in ("--",)]
            pinned = {
                ("apps", "launch"): "exec-launcher",
                ("apps", "terminal-file"): "exec-terminal-file",
                ("capture", "clipboard"): "exec-clipboard",
                ("capture", "screenshot"): "exec-screenshooter",
                ("hardware", "keyboard", "keys"): "exec-keyboard-help",
                ("shell", "ipc", "call", "drawers", "toggle", "session"): "exec-power-menu",
                ("shell", "ipc", "call", "drawers", "toggle", "dashboard"): "ipc-dashboard-toggle",
                ("shell", "ipc", "call", "lock", "lock"): "ipc-lock-lock",
            }
            for width in range(len(sub), 1, -1):
                key = tuple(sub[:width])
                if key in pinned:
                    return pinned[key]
            # `shell ipc -- call <a> <b>` passthrough: ipc-<a>-<b>.
            if len(sub) >= 5 and sub[0:3] == ["shell", "ipc", "call"]:
                return f"ipc-{slug('-'.join(sub[3:]))}"
            if len(sub) >= 2:
                return f"exec-horneroctl-{slug('-'.join(sub[:3]))}"
            return "exec-horneroctl"
        if "ipc" in tokens:
            rest = tokens[tokens.index("ipc") + 1 :]
            return f"ipc-{slug('-'.join(rest))}"
        if "exo-open" in tokens and "--launch" in tokens:
            launched = tokens[tokens.index("--launch") + 1 :]
            return f"app-{slug('-'.join(launched))}"
        for prog in prog_tokens:
            prog = re.sub(r"^hornero-", "", prog)
            if prog:
                return f"exec-{slug(prog)}"
        return "exec-custom"
    first = args.strip().split(",", 1)[0].strip()
    return f"{slug(dispatcher)}:{slug(first)}"


def parse_bindings(conf: Path) -> list[dict]:
    text = conf.read_text(encoding="utf-8")
    entries: list[dict] = []
    # Track define_submap spans so binds inside inherit the submap name.
    submap_spans = []
    for m in SUBMAP_START.finditer(text):
        _, end = _scan_call(text, m.start() + len("hl.define_submap("))
        submap_spans.append((m.start(), end, m.group(1)))

    def submap_at(pos):
        for s, e, name in submap_spans:
            if s <= pos <= e:
                return name
        return ""

    for m in LUA_BIND_START.finditer(text):
        args_text, _ = _scan_call(text, m.start() + len("hl.bind("))
        km = re.match(r'\s*"([^"]+)"\s*,\s*(.*)$', args_text, flags=re.S)
        if not km:
            raise ValueError(f"{conf}: unparsable bind at offset {m.start()}")
        key_spec, rest = km.group(1), km.group(2).strip()
        parts = [x.strip() for x in key_spec.split("+")]
        key, mods = parts[-1], parts[:-1]
        dm = re.match(r"hl\.dsp\.([A-Za-z_.]+)\((.*)\)\s*(?:,\s*\{.*\})?$", rest, flags=re.S)
        if not dm:
            raise ValueError(f"{conf}: unparsable dispatcher: {rest[:60]!r}")
        dispatcher, args = _legacy(dm.group(1), dm.group(2))
        flags = ""
        if "repeating = true" in rest:
            flags += "e"
        if "locked = true" in rest:
            flags += "l"
        if "mouse = true" in rest:
            flags += "m"
        entries.append(
            {
                "id": entry_id(dispatcher, args),
                "mods": mods,
                "key": key,
                "dispatcher": dispatcher,
                "args": args,
                "submap": submap_at(m.start()),
                "flags": flags,
            }
        )
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
    conf = root / "desktop" / "hypr" / "hyprland.lua.d" / "keybindings.lua"
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
        "source": "desktop/hypr/hyprland.lua.d/keybindings.lua",
        "entries": entries,
    }
    out = Path(args.out) if args.out else root / "shortcuts.json"
    out.write_text(json.dumps(doc, indent=2, sort_keys=False) + "\n", encoding="utf-8")
    print(f"SHORTCUTS-PASS: {len(entries)} entries -> {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
