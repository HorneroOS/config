"""Studio storage policy contract tests (HorneroOS/config#100)."""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
POLICY = ROOT / "desktop" / "studio-storage" / "storage-policy.json"


def _policy() -> dict:
    return json.loads(POLICY.read_text(encoding="utf-8"))


def test_storage_classes_and_backup_semantics():
    policy = _policy()
    assert policy["schemaVersion"] == 1
    locations = policy["locations"]
    assert set(locations) == {"projects", "assets", "cache", "scratch"}
    for name in ("projects", "assets"):
        assert locations[name]["class"] == "user-owned"
        assert locations[name]["backup"] == "include"
        assert locations[name]["autoDelete"] is False
    for name in ("cache", "scratch"):
        assert locations[name]["class"] in ("regenerable", "temporary")
        assert locations[name]["backup"] == "exclude"
        assert locations[name]["autoDelete"] == "preview-only"


def test_storage_defaults_are_portable_home_relative_paths():
    for location in _policy()["locations"].values():
        default = location["default"]
        assert default.startswith("~/"), default
        assert "/home/" not in default
        assert "nocow" not in default.lower()


def test_storage_thresholds_are_ordered_and_actionable():
    thresholds = _policy()["thresholds"]
    assert 0 < thresholds["stopRenderBelowFreePercent"] < thresholds["warnBelowFreePercent"] < 50


def test_storage_rules_forbid_destructive_behaviour():
    rules = " ".join(_policy()["rules"]).lower()
    assert "never auto-deleted" in rules
    assert "preview" in rules
    assert "no filesystem is formatted" in rules


def test_storage_policy_installs_as_data():
    profile = (ROOT / "profiles" / "base" / "profile.toml").read_text(encoding="utf-8")
    assert 'target = "{config}/hornero/studio-storage"' in profile
    materialize = (ROOT / "scripts" / "materialize.sh").read_text(encoding="utf-8")
    assert 'install_dir "desktop/studio-storage" "$CONFIG_HOME/hornero/studio-storage"' in materialize
