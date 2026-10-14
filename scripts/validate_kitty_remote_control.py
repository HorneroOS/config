#!/usr/bin/env python3
"""Validate Kitty's effective remote-control setting."""

from __future__ import annotations

import re
import sys
from pathlib import Path


SETTING = "allow_remote_control"


def values_in_order(config_text: str, setting: str = SETTING) -> list[str]:
    """Return active single-value directives, preserving Kitty file order."""
    values = []
    for line in config_text.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue

        match = re.match(r"^(\S+)(?:[ \t]+|=)(.*)$", stripped)
        if match and match.group(1) == setting:
            values.append(match.group(2).strip())
    return values


def validate(config_text: str) -> tuple[bool, str]:
    """Require the last active setting to disable Kitty remote control."""
    values = values_in_order(config_text)
    if not values:
        return False, f"{SETTING} must be explicitly set to no"
    if values[-1] != "no":
        return False, f"effective {SETTING} value must be no; got {values[-1]!r}"
    return True, "remote control disabled"


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {Path(sys.argv[0]).name} <kitty.conf>", file=sys.stderr)
        return 2

    config_path = Path(sys.argv[1])
    try:
        content = config_path.read_text(encoding="utf-8")
    except OSError as error:
        print(f"{config_path}: {error}", file=sys.stderr)
        return 2

    valid, message = validate(content)
    if not valid:
        print(f"{config_path}: {message}", file=sys.stderr)
        return 1
    print(f"VALIDATE-PASS: {config_path}: {message}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
