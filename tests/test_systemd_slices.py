"""Systemd user resource isolation slice contracts (app-models, app-agents)."""
from __future__ import annotations

import configparser
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SYSTEMD_USER = ROOT / "desktop/systemd/user"
MODELS_SLICE = SYSTEMD_USER / "app-models.slice"
AGENTS_SLICE = SYSTEMD_USER / "app-agents.slice"
OLLAMA_DROPIN = SYSTEMD_USER / "ollama.service.d/10-hornero.conf"
LLAMA_DROPIN = SYSTEMD_USER / "llama-server@.service.d/10-hornero.conf"


def _parse_unit(path: Path) -> configparser.ConfigParser:
    cp = configparser.ConfigParser(strict=True, interpolation=None)
    cp.optionxform = str
    cp.read_string(path.read_text(encoding="utf-8"))
    return cp


def test_app_models_slice():
    cp = _parse_unit(MODELS_SLICE)
    assert "Unit" in cp and cp["Unit"].get("Description")
    assert "Slice" in cp
    s = cp["Slice"]
    assert s["Slice"] == "app.slice"
    assert s["CPUWeight"] == "20"
    assert s["IOWeight"] == "20"
    assert s["CPUAccounting"] == "true"
    assert s["IOAccounting"] == "true"
    assert s["MemoryAccounting"] == "true"
    assert s["ManagedOOMSwap"] == "kill"
    assert s["ManagedOOMMemoryPressure"] == "kill"


def test_app_agents_slice():
    cp = _parse_unit(AGENTS_SLICE)
    assert "Unit" in cp and cp["Unit"].get("Description")
    assert "Slice" in cp
    s = cp["Slice"]
    assert s["Slice"] == "app.slice"
    assert s["CPUWeight"] == "50"
    assert s["CPUAccounting"] == "true"
    assert s["MemoryAccounting"] == "true"
    assert s["ManagedOOMSwap"] == "kill"
    assert s["ManagedOOMMemoryPressure"] == "kill"


def test_service_dropins_target_app_models_slice():
    for dropin in (OLLAMA_DROPIN, LLAMA_DROPIN):
        cp = _parse_unit(dropin)
        assert "Service" in cp, f"{dropin} missing [Service] section"
        assert cp["Service"]["Slice"] == "app-models.slice"


def test_materialize_and_profile_wire_systemd_user():
    materialize = (ROOT / "scripts/materialize.sh").read_text(encoding="utf-8")
    assert 'install_dir "desktop/systemd/user" "$CONFIG_HOME/systemd/user"' in materialize
    profile = (ROOT / "profiles/base/profile.toml").read_text(encoding="utf-8")
    assert 'source = "desktop/systemd/user"' in profile
    assert 'target = "{config}/systemd/user"' in profile


if __name__ == "__main__":
    test_app_models_slice()
    test_app_agents_slice()
    test_service_dropins_target_app_models_slice()
    test_materialize_and_profile_wire_systemd_user()
    print("test_systemd_slices.py: ALL GREEN")
