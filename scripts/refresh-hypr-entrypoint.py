#!/usr/bin/env python3
"""Additively refresh a user Hyprland entrypoint from the factory one.

Existing users keep a skel-seeded ~/.config/hypr/hyprland.lua, so
packaged entrypoint changes (new dofile module lines such as
monitors-user.lua) never reach them (HorneroOS/config#124). This tool
inserts only the factory `dofile(here .. "...")` lines the user file
is missing, in factory order, at the position of their factory
neighbours. It never deletes, reorders, or rewrites any existing
line, and never touches *-user.lua overrides.

Default is a dry-run that prints a unified diff; --apply writes
atomically and keeps a `<file>.pre-refresh` backup of the original.
Refuses (exit 1) when the target is missing or restructured (no
`local here =` anchor), instead of guessing.
"""

import argparse
import difflib
import re
import shutil
import sys
from pathlib import Path

DOFILE_RE = re.compile(r'^dofile\(here \.\. "([^"]+)"\)\s*$')


def factory_modules(lines):
    return [m.group(1) for line in lines if (m := DOFILE_RE.match(line.strip()))]


def refresh(factory_lines, target_lines):
    """Return the target lines with missing factory dofiles inserted."""
    factory = factory_modules(factory_lines)
    present = set(factory_modules(target_lines))
    missing = [mod for mod in factory if mod not in present]
    if not missing:
        return target_lines, []
    out = list(target_lines)
    for mod in missing:
        line = f'dofile(here .. "{mod}")'
        idx = factory.index(mod)
        # Anchor after the nearest factory predecessor already present,
        # else before the nearest present successor, else append.
        anchor = None
        for prev in reversed(factory[:idx]):
            for i, existing in enumerate(out):
                m = DOFILE_RE.match(existing.strip())
                if m and m.group(1) == prev:
                    anchor = i + 1
                    break
            if anchor is not None:
                break
        if anchor is None:
            for nxt in factory[idx + 1:]:
                for i, existing in enumerate(out):
                    m = DOFILE_RE.match(existing.strip())
                    if m and m.group(1) == nxt:
                        anchor = i
                        break
                if anchor is not None:
                    break
        if anchor is None:
            anchor = len(out)
        out.insert(anchor, line)
        present.add(mod)
    return out, missing


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Additively refresh a user hyprland.lua from the factory entrypoint (default: dry-run)."
    )
    parser.add_argument("--factory", required=True, help="Packaged factory hyprland.lua")
    parser.add_argument("--target", required=True, help="User hyprland.lua to refresh")
    parser.add_argument("--apply", action="store_true", help="Write changes (default prints a diff)")
    args = parser.parse_args(argv)

    factory_path = Path(args.factory)
    target_path = Path(args.target)
    if not factory_path.is_file():
        print(f"error: factory entrypoint not found: {factory_path}", file=sys.stderr)
        return 1
    if not target_path.is_file():
        print(
            f"error: target entrypoint not found: {target_path}\n"
            "Example: refresh-hypr-entrypoint.py --factory /etc/xdg/hypr/hyprland.lua "
            "--target ~/.config/hypr/hyprland.lua --dry-run",
            file=sys.stderr,
        )
        return 1

    target_lines = target_path.read_text(encoding="utf-8").splitlines()
    if not any(line.startswith("local here =") for line in target_lines):
        print(
            "error: target has no `local here =` anchor; it looks restructured. "
            "Refusing to guess — reconcile it manually against the factory entrypoint.",
            file=sys.stderr,
        )
        return 1

    factory_lines = factory_path.read_text(encoding="utf-8").splitlines()
    new_lines, inserted = refresh(factory_lines, target_lines)
    if not inserted:
        print(f"{target_path}: already up to date (all factory modules loaded)")
        return 0

    diff = difflib.unified_diff(
        target_lines,
        new_lines,
        fromfile=str(target_path),
        tofile=f"{target_path} (refreshed)",
        lineterm="",
    )
    print("\n".join(diff))
    if not args.apply:
        print(f"\nDry run: would insert {len(inserted)} line(s): {', '.join(inserted)}. Re-run with --apply to write.")
        return 0

    backup = target_path.with_name(target_path.name + ".pre-refresh")
    shutil.copy2(target_path, backup)
    tmp = target_path.with_name(target_path.name + ".tmp-refresh")
    tmp.write_text("\n".join(new_lines) + "\n", encoding="utf-8")
    tmp.replace(target_path)
    print(f"\nApplied: inserted {len(inserted)} line(s): {', '.join(inserted)}. Backup: {backup}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
