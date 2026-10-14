#!/usr/bin/env python3
"""Load shipped Kitty configs with Kitty's parser and reject ignored settings."""

from __future__ import annotations

import os
import sys
import tempfile
from pathlib import Path

import kitty.config
import kitty.conf.utils

errors: list[str] = []


def capture_error(message: str) -> None:
    errors.append(message)


# Kitty logs unknown options and missing includes without raising. Turn those
# diagnostics into a failing check so upstream config changes cannot silently
# disable Hornero defaults.
kitty.config.log_error = capture_error
kitty.conf.utils.log_error = capture_error

# Guard the validator itself: Kitty intentionally logs unknown keys instead of
# raising, so this harness must prove it detects that diagnostic.
kitty.config.parse_config(["hornero_validator_probe_unknown_option yes"])
if not errors:
    raise SystemExit("Kitty parser diagnostic capture is not working")
errors.clear()


def was_loaded(config_path: Path, options: object) -> bool:
    loaded_paths = getattr(options, "config_paths", ())
    return config_path.resolve() in {Path(path).resolve() for path in loaded_paths}


# Kitty can return defaults after ignoring a missing requested file. Prove the
# validator distinguishes that case from a successfully parsed configuration.
missing_probe = Path(tempfile.gettempdir()) / f"hornero-kitty-missing-{os.getpid()}.conf"
missing_options = kitty.config.load_config(str(missing_probe), accumulate_bad_lines=[])
if was_loaded(missing_probe, missing_options):
    raise SystemExit("Kitty parser unexpectedly reported a missing config as loaded")
errors.clear()

config_paths = [Path(path) for path in sys.argv[2:]]
if not config_paths:
    raise SystemExit("usage: validate_kitty_config.py <config> [<config> ...]")

for config_path in config_paths:
    bad_lines = []
    options = kitty.config.load_config(str(config_path), accumulate_bad_lines=bad_lines)
    if not was_loaded(config_path, options):
        errors.append(f"{config_path}: Kitty did not load the requested file")
    for bad_line in bad_lines:
        errors.append(f"{config_path}:{bad_line.number}: {bad_line.line}")

if errors:
    for error in errors:
        print(f"KITTY-CONFIG-FAIL: {error}", file=sys.stderr)
    raise SystemExit(1)

for config_path in config_paths:
    print(f"KITTY-CONFIG-PASS: {config_path}")
