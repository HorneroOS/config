#!/usr/bin/env python3
"""Build the shell.json migration golden cases.

Inputs are written from the pinned factory snapshots in `factory/`:
  shell-v1.2.79.json   HorneroOS/shell v1.2.79 (92e11e56), the last
                       pre-Signal release, config/shell.default.json
  shell-fd620daf.json  HorneroOS/shell fd620daf, the Signal factory default
                       vendored by this repo when the cases were cut

Expected outputs (`plan.json`, `migrated.json`) come from
`scripts/shell_migrate.py`. Regenerate with `--update` only when the table
or the semantics change on purpose, and review the diff: the golden files
are the reviewed record of what an update does to a user's settings.

  python3 tests/golden/shell-migrations/build.py           # check
  python3 tests/golden/shell-migrations/build.py --update  # rewrite
"""
from __future__ import annotations

import copy
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import shell_migrate as sm  # noqa: E402

OLD = "factory/shell-v1.2.79.json"
NEW = "factory/shell-fd620daf.json"

# 50+ overrides across 12 Control Center panes, written the way a v1.2.79
# shell saves shell.json (every key serialised, overrides in place).
PRE_SIGNAL_OVERRIDES = {
    # Appearance (scales, fonts, transparency, motion, theme)
    "appearance.theme": "neon-city",
    "appearance.highContrast": True,
    "appearance.rounding.scale": 1.4,
    "appearance.spacing.scale": 1.2,
    "appearance.padding.scale": 0.9,
    "appearance.font.size.scale": 1.1,
    "appearance.font.family.sans": "Inter",
    "appearance.font.family.mono": "CaskaydiaCove NF",
    "appearance.font.family.clock": "Bebas Neue",
    "appearance.transparency.enabled": True,
    "appearance.transparency.base": 0.7,
    "appearance.anim.durations.scale": 0.8,
    "appearance.anim.curves.standard": [0.3, 0, 0, 1, 1, 1],
    # Background
    "background.desktopClock.enabled": True,
    "background.desktopClock.position": "top-left",
    "background.desktopClock.scale": 1.5,
    "background.visualiser.enabled": True,
    "background.video.pauseOnGameMode": True,
    "background.video.batteryLimit": 35,
    # Taskbar
    "bar.persistent": False,
    "bar.showOnHover": False,
    "bar.workspaces.shown": 8,
    "bar.workspaces.activeTrail": True,
    "bar.clock.showDate": True,
    "bar.status.showMicrophone": True,
    "bar.status.showBattery": False,
    "bar.status.showAudio": True,
    "bar.sizes.innerWidth": 32,
    "bar.tray.compact": True,
    "bar.legacyPill": True,
    # Border
    "border.thickness": 6,
    "border.rounding": 18,
    # Dashboard
    "dashboard.showOnHover": False,
    "dashboard.mediaUpdateInterval": 1000,
    "dashboard.performance.showGpu": False,
    "dashboard.workspaces.maxAppIcons": 6,
    "dashboard.workspaces.previewHeight": 240,
    "dashboard.sizes.weatherWidth": 300,
    # Control Center
    "controlCenter.sizes.heightMult": 0.8,
    "controlCenter.appearanceExpandedSections": ["themes", "fonts"],
    # Launcher
    "launcher.maxShown": 10,
    "launcher.maxWallpapers": 12,
    "launcher.vimKeybinds": True,
    "launcher.useFuzzy.apps": True,
    "launcher.useFuzzy.schemes": True,
    "launcher.sizes.wallpaperWidth": 320,
    "launcher.favouriteApps": ["org.mozilla.firefox", "foot"],
    # Notifications
    "notifs.defaultExpireTimeout": 8000,
    "notifs.actionOnClick": True,
    "notifs.openExpanded": True,
    "notifs.groupPreviewNum": 5,
    "notifs.sizes.width": 440,
    # OSD
    "osd.hideDelay": 1500,
    "osd.enableMicrophone": True,
    "osd.sizes.sliderHeight": 180,
    # Session
    "session.vimKeybinds": True,
    "session.sizes.button": 96,
    # Lock screen
    "lock.hideNotifs": False,
    "lock.maxFprintTries": 5,
    "lock.sizes.centerWidth": 640,
    # Toasts / utilities
    "utilities.maxToasts": 3,
    "utilities.toasts.nowPlaying": True,
    "utilities.toasts.gameModeChanged": False,
    # Sidebar
    "sidebar.dragThreshold": 60,
    "sidebar.sizes.width": 480,
    # Services and general
    "services.useFahrenheit": True,
    "services.audioIncrement": 0.05,
    "services.defaultPlayer": "mpv",
    "general.idle.inhibitWhenAudio": False,
    "general.battery.criticalLevel": 5,
}


def _apply(base: dict, overrides: dict) -> dict:
    flat = sm.flatten(copy.deepcopy(base))
    for path, value in overrides.items():
        sm.put(flat, sm.split(path), value)
    return sm.unflatten(flat)


def _load(rel: str) -> dict:
    return json.loads((HERE / rel).read_text(encoding="utf-8"))


def cases() -> dict[str, dict]:
    old, new = _load(OLD), _load(NEW)
    return {
        # Pre-Signal user with many overrides: the update acceptance case.
        "pre-signal-many-overrides": {"user": _apply(old, PRE_SIGNAL_OVERRIDES), "old": OLD, "new": NEW},
        # Never customised: every changed default reaches the user.
        "pre-signal-untouched": {"user": copy.deepcopy(old), "old": OLD, "new": NEW},
        # Hand-written sparse file: absent keys follow the factory.
        "sparse-user": {"user": {"appearance": {"rounding": {"scale": 1.3}}, "bar": {"persistent": False}}, "old": OLD, "new": NEW},
        # Both the old and the new key are set: the new key wins, the old
        # value is reported as a conflict instead of being dropped.
        "rename-conflict": {
            "user": {"utilities": {"toasts": {"gameModeChanged": True}}, "experience": {"toasts": False}},
            "old": OLD, "new": NEW,
        },
        # Already on Signal and up to date: nothing to do.
        "signal-current": {"user": _apply(new, {"bar.persistent": False, "appearance.glow.intensity": 0.6}), "old": NEW, "new": NEW},
    }


def render(obj) -> str:
    return json.dumps(obj, indent=2, ensure_ascii=False) + "\n"


def main(argv: list[str]) -> int:
    update = "--update" in argv
    table = json.loads(sm.DEFAULT_TABLE.read_text(encoding="utf-8"))
    bad = 0
    for name, case in cases().items():
        d = HERE / name
        report, migrated = sm.plan(case["user"], _load(case["old"]), _load(case["new"]), table)
        files = {
            "case.json": render({"user": "user.json", "old": "../" + case["old"], "new": "../" + case["new"]}),
            "user.json": render(case["user"]),
            "plan.json": render(report),
            "migrated.json": render(migrated),
        }
        for fname, text in files.items():
            p = d / fname
            if update:
                d.mkdir(parents=True, exist_ok=True)
                p.write_text(text, encoding="utf-8")
            elif not p.is_file() or p.read_text(encoding="utf-8") != text:
                print(f"GOLDEN-DIFF: {name}/{fname}", file=sys.stderr)
                bad += 1
    if update:
        print("golden cases rewritten; review the diff")
        return 0
    print("golden cases match" if not bad else f"{bad} golden file(s) differ; run with --update and review")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
