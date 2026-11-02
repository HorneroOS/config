"""Bluetooth config contracts: BlueZ template, WirePlumber policy, preset."""
from __future__ import annotations

import configparser
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MAIN = ROOT / "desktop/bluetooth/main.conf"
WP = ROOT / "desktop/wireplumber/wireplumber.conf.d/51-hornero-bluetooth.conf"
PRESET = ROOT / "desktop/systemd/90-hornero-bluetooth.preset"


def _main() -> configparser.ConfigParser:
    cp = configparser.ConfigParser(strict=True)
    cp.optionxform = str
    cp.read_string(MAIN.read_text(encoding="utf-8"))
    return cp


def test_bluez_power_persistence_and_pairing_security():
    cp = _main()
    # AutoEnable=false forces controllers off at boot and never restores
    # the user's last Powered state; true is the only correct value.
    assert cp["Policy"]["AutoEnable"] == "true"
    assert cp["General"]["JustWorksRepairing"] == "never"
    assert cp["General"]["AlwaysPairable"] == "false"
    assert cp["General"]["ControllerMode"] == "dual"
    assert 0 < int(cp["General"]["DiscoverableTimeout"]) <= 300
    active = [l for l in MAIN.read_text().splitlines() if l.strip() and not l.lstrip().startswith("#")]
    assert not any("/var/lib/bluetooth" in l for l in active)


def test_wireplumber_codecs_roles_and_no_global_autosuspend_disable():
    text = WP.read_text(encoding="utf-8")
    codecs = re.search(r"bluez5\.codecs\s*=\s*\[([^\]]+)\]", text)
    assert codecs and codecs.group(1).split() == [
        "ldac", "aptx_hd", "aptx", "sbc_xq", "aac", "sbc"]
    for needle in ("bluez5.enable-sbc-xq = true", "bluez5.enable-msbc = true",
                   "bluez5.enable-hw-volume = true", 'bluez5.hfphsp-backend = "native"',
                   "a2dp_sink", "hfp_hf",
                   "bluetooth.autoswitch-to-headset-profile = true",
                   "bluez5.auto-connect = [ a2dp_sink a2dp_source ]"):
        assert needle in text, needle
    # Global autosuspend disables (usbcore -1 / btusb 0) are forbidden.
    assert not re.search(r"autosuspend\w*\s*=\s*(-1|false|0)\b", text)


def test_preset_and_install_scriptlet_use_preset_only():
    assert PRESET.read_text().strip().splitlines()[-1] == "enable bluetooth.service"
    install = (ROOT / "packaging/hornero-config.install").read_text()
    assert "systemctl preset bluetooth.service" in install
    assert "systemctl enable" not in install
    pkgbuild = (ROOT / "packaging/PKGBUILD").read_text()
    assert "install=hornero-config.install" in pkgbuild
    assert "etc/wireplumber/wireplumber.conf.d/51-hornero-bluetooth.conf" in pkgbuild
    assert "usr/lib/systemd/system-preset/90-hornero-bluetooth.preset" in pkgbuild
    assert "usr/share/hornero/bluetooth/main.conf" in pkgbuild
    # The package must never own BlueZ's path or BlueZ paired-device state.
    assert '"$pkgdir/etc/bluetooth' not in pkgbuild
    assert "/var/lib/bluetooth" not in pkgbuild


def test_materialize_and_profile_never_write_etc_bluetooth():
    materialize = (ROOT / "scripts/materialize.sh").read_text()
    assert 'install_dir "desktop/wireplumber" "$CONFIG_HOME/wireplumber"' in materialize
    assert 'install_dir "desktop/bluetooth" "$CONFIG_HOME/hornero/bluetooth"' in materialize
    assert '"$CONFIG_HOME/bluetooth"' not in materialize  # never write the system path
    profile = (ROOT / "profiles/base/profile.toml").read_text()
    assert 'source = "desktop/bluetooth"' in profile
    assert 'source = "desktop/wireplumber"' in profile
