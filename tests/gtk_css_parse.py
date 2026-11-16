#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Parse GTK CSS files with the real GTK parser (no display needed).

Usage: tests/gtk_css_parse.py <3.0|4.0> FILE...  (exit 1 on any parsing error)
"""
import sys

import gi

VERSION = sys.argv[1]
gi.require_version("Gtk", VERSION)
from gi.repository import Gtk  # noqa: E402


def parse(path: str) -> list[str]:
    errors: list[str] = []
    provider = Gtk.CssProvider()

    def on_error(_provider, section, error):
        if VERSION == "4.0":
            line = section.get_start_location().lines + 1
        else:
            line = section.get_start_line() + 1
        errors.append(f"{line}: {error.message}")

    provider.connect("parsing-error", on_error)
    try:
        provider.load_from_path(path)
    except Exception as exc:  # noqa: BLE001 - GTK 3 also raises GLib.Error
        errors.append(str(exc))
    return errors


def main() -> int:
    failed = 0
    for path in sys.argv[2:]:
        errors = parse(path)
        failed += bool(errors)
        print(f"GTK{VERSION} {'FAIL' if errors else 'OK'} {path}")
        for error in errors[:5]:
            print(f"  {error}")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
