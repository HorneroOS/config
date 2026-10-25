"""Studio application preset contract tests (HorneroOS/config#99)."""
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PRESETS = ROOT / "desktop" / "studio-presets"
INDEX = PRESETS / "presets.json"

# Application IDs from the canonical Hornero catalogue (hornero#285).
CATALOGUE_APPS = {
    "ardour", "guitarix", "carla", "audacity", "reaper", "yabridge",
    "obs-studio", "kdenlive", "blender", "krita", "gimp", "inkscape",
    "darktable", "rawtherapee", "graphite", "penpot", "scribus",
    "freecad", "godot",
}

SECRET_PATTERNS = [
    re.compile(r"stream[_-]?key", re.IGNORECASE),
    re.compile(r"(api[_-]?key|access[_-]?token|password|passwd|secret)\s*=", re.IGNORECASE),
    re.compile(r"/home/[a-z0-9._-]+/", re.IGNORECASE),
    re.compile(r"\b(bitrate|vbv|crf)\b\s*=", re.IGNORECASE),
]


def _index() -> dict:
    return json.loads(INDEX.read_text(encoding="utf-8"))


def test_preset_index_schema_and_catalogue_apps():
    index = _index()
    assert index["schemaVersion"] == 1
    assert index["presets"], "at least one preset is required"
    for preset in index["presets"]:
        assert preset["id"] and preset["version"] >= 1
        assert preset["app"] in CATALOGUE_APPS, preset["app"]
        assert preset["strategy"] == "create-if-absent"
        assert preset["source"] and preset["license"]
        assert preset["files"], "a preset must ship at least one template file"
        for entry in preset["files"]:
            assert (PRESETS / entry["template"]).is_file(), entry["template"]
            target = entry["target"]
            assert target.startswith(".config/"), target
            assert ".." not in Path(target).parts


def test_preset_templates_omit_secrets_bitrates_and_personal_paths():
    for template in PRESETS.rglob("*"):
        if not template.is_file() or template == INDEX:
            continue
        text = template.read_text(encoding="utf-8")
        for pattern in SECRET_PATTERNS:
            assert not pattern.search(text), f"{pattern.pattern} in {template}"


def test_obs_baseline_is_recording_only_and_not_streaming():
    preset = _index()["presets"][0]
    assert preset["app"] == "obs-studio"
    ini = (PRESETS / "obs-studio" / "basic.ini").read_text(encoding="utf-8")
    assert "RecFormat=mkv" in ini
    assert "server" not in ini.lower()
    assert "key" not in ini.lower()


def test_presets_install_as_data_never_into_app_config():
    profile = (ROOT / "profiles" / "base" / "profile.toml").read_text(encoding="utf-8")
    assert 'source = "desktop/studio-presets"' in profile
    assert 'target = "{config}/hornero/studio-presets"' in profile
    materialize = (ROOT / "scripts" / "materialize.sh").read_text(encoding="utf-8")
    assert 'install_dir "desktop/studio-presets" "$CONFIG_HOME/hornero/studio-presets"' in materialize
    # The destructive direction (writing into the app's own config tree)
    # must never appear in the install path.
    assert "obs-studio/basic" not in materialize
