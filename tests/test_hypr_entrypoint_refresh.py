#!/usr/bin/env python3
"""Contract for lib/hornero/refresh-hypr-entrypoint.py (config#124).

Additive-only refresh of a skel-seeded user hyprland.lua: missing
factory dofile lines are inserted in factory order, user content is
preserved byte-for-byte, dry-run writes nothing, restructured files
are refused. Runs entirely in temp dirs; never touches a real HOME.
"""
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "lib" / "hornero" / "refresh-hypr-entrypoint.py"
FACTORY = ROOT / "desktop" / "hypr" / "hyprland.lua"

failures = []


def check(name, cond, detail=""):
    if cond:
        print(f"TEST-PASS: {name}")
    else:
        failures.append(name)
        print(f"TEST-FAIL: {name} {detail}", file=sys.stderr)


def run(factory, target, *extra):
    return subprocess.run(
        [sys.executable, str(SCRIPT), "--factory", str(factory), "--target", str(target), *extra],
        capture_output=True,
        text=True,
    )


def stale_user_entrypoint(factory_text: str) -> str:
    # A user file predating monitors-user, with local edits elsewhere.
    lines = [l for l in factory_text.splitlines() if "monitors-user" not in l]
    lines.append('-- my local tweak: keep me')
    return "\n".join(lines) + "\n"


with tempfile.TemporaryDirectory() as td:
    tmp = Path(td)
    factory_text = FACTORY.read_text()
    target = tmp / "hyprland.lua"
    target.write_text(stale_user_entrypoint(factory_text))

    # Dry-run: reports the insertion, writes nothing.
    r = run(FACTORY, target)
    check("dry-run exits 0", r.returncode == 0, r.stderr)
    check("dry-run names insertion", "monitors-user.lua" in r.stdout, r.stdout)
    check("dry-run writes nothing", "monitors-user" not in target.read_text())

    # Apply: inserted in factory position, user edit preserved.
    r = run(FACTORY, target, "--apply")
    check("apply exits 0", r.returncode == 0, r.stderr)
    out = target.read_text()
    check("apply inserts monitors-user", 'load_user("monitors-user.lua")' in out)
    check(
        "factory order kept",
        out.index('"monitors.lua"') < out.index('"monitors-user.lua"') < out.index('"autostart.lua"'),
    )
    check("user edit preserved", "-- my local tweak: keep me" in out)
    check("backup written", (tmp / "hyprland.lua.pre-refresh").is_file())

    # Idempotent: second apply is a no-op report.
    before = target.read_text()
    r = run(FACTORY, target, "--apply")
    check("idempotent exits 0", r.returncode == 0, r.stderr)
    check("idempotent reports up to date", "already up to date" in r.stdout)
    check("idempotent leaves file unchanged", target.read_text() == before)

    # Only additive: refreshed file differs from stale file by exactly one line.
    stale = stale_user_entrypoint(factory_text)
    check(
        "diff is exactly one inserted line",
        len(out.splitlines()) == len(stale.splitlines()) + 1,
    )

    # Legacy pre-config#184 entrypoint (`local here =` + `dofile(here .. ...)`)
    # still refreshes additively with valid legacy syntax.
    legacy = tmp / "legacy.lua"
    legacy.write_text(
        'local here = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") .. "/hyprland.lua.d/"\n'
        'dofile(here .. "monitors.lua")\n'
        'dofile(here .. "autostart.lua")\n'
        '-- legacy local tweak\n'
    )
    r = run(FACTORY, legacy, "--apply")
    check("legacy apply exits 0", r.returncode == 0, r.stderr)
    legacy_out = legacy.read_text()
    check("legacy inserts dofile monitors-user", 'dofile(here .. "monitors-user.lua")' in legacy_out)
    check(
        "legacy factory order kept",
        legacy_out.index('"monitors.lua"') < legacy_out.index('"monitors-user.lua"') < legacy_out.index('"autostart.lua"'),
    )
    check("legacy user edit preserved", "-- legacy local tweak" in legacy_out)

    # Restructured target: refused, untouched.
    bad = tmp / "bad.lua"
    bad.write_text('-- fully custom\ndofile("elsewhere.lua")\n')
    r = run(FACTORY, bad, "--apply")
    check("restructured refused", r.returncode == 1)
    check("restructured untouched", bad.read_text().startswith("-- fully custom"))

    # Missing target: actionable error.
    r = run(FACTORY, tmp / "missing.lua")
    check("missing target exits 1", r.returncode == 1)
    check("missing target prints example", "Example:" in r.stderr)

# The canonical copy lives in lib/hornero so both install paths ship
# it: materialize (user scope) and the PKGBUILD staging of the same dir.
materialize = (ROOT / "scripts" / "materialize.sh").read_text()
check("materialize installs lib/hornero", 'install_dir "lib/hornero"' in materialize)
pkgbuild = (ROOT / "packaging" / "PKGBUILD").read_text()
check("PKGBUILD stages lib/hornero payload", ".local/lib/hornero" in pkgbuild)

if failures:
    print(f"{len(failures)} failure(s)", file=sys.stderr)
    sys.exit(1)
print("ALL PASS")
