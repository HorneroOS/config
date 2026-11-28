"""Hornero Apps runtime configuration contracts (HorneroOS/config#198)."""
from __future__ import annotations

import configparser
import json
import os
import shutil
import stat
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FLATHUB_ENSURE = ROOT / "bin" / "hornero-flathub-ensure"
FLATHUB_SERVICE = ROOT / "desktop" / "systemd" / "user" / "hornero-flathub-setup.service"
HYPR_PORTALS = ROOT / "desktop" / "xdg-desktop-portal" / "hyprland-portals.conf"
NIRI_PORTALS = ROOT / "desktop" / "xdg-desktop-portal" / "niri-portals.conf"
APPS_DESKTOP = ROOT / "share" / "applications" / "hornero-apps.desktop"
APPIMAGE_DESKTOP = ROOT / "share" / "applications" / "hornero-appimage-import.desktop"
POLICY_JSON = ROOT / "desktop" / "hornero-apps" / "policy.json"
PKGBUILD = ROOT / "packaging" / "PKGBUILD"
MATERIALIZE = ROOT / "scripts" / "materialize.sh"
PROFILE = ROOT / "profiles" / "base" / "profile.toml"

REQUIRED_PORTAL_INTERFACES = (
    "FileChooser",
    "OpenURI",
    "Notification",
    "ScreenCast",
    "Screenshot",
    "GlobalShortcuts",
    "Settings",
)


def _parse_ini(path: Path) -> configparser.ConfigParser:
    cp = configparser.ConfigParser(strict=True, interpolation=None)
    cp.optionxform = str
    cp.read_string(path.read_text(encoding="utf-8"))
    return cp


def _write_mock_flatpak(bin_dir: Path, system_remotes: str = "", user_remotes: str = "", fail_remote_add: bool = False) -> Path:
    log_file = bin_dir / "flatpak.log"
    script = bin_dir / "flatpak"
    script.write_text(
        f"""#!/usr/bin/env bash
set -euo pipefail
printf '%s\\n' "$*" >> "{log_file}"
case "${{1:-}}" in
  remotes)
    if [[ "$*" == *"--system"* ]]; then
      printf '%s' "{system_remotes}"
    else
      printf '%s' "{user_remotes}"
    fi
    ;;
  remote-add)
    if [[ "{1 if fail_remote_add else 0}" -eq 1 ]]; then
      echo "error: network unreachable" >&2
      exit 1
    fi
    ;;
  update)
    ;;
  *)
    echo "unexpected flatpak args: $*" >&2
    exit 1
    ;;
esac
""",
        encoding="utf-8",
    )
    script.chmod(0o755)
    return log_file


def test_flathub_ensure_executable_and_shellcheck() -> None:
    assert FLATHUB_ENSURE.is_file(), "missing bin/hornero-flathub-ensure"
    mode = FLATHUB_ENSURE.stat().st_mode
    assert mode & stat.S_IXUSR, "bin/hornero-flathub-ensure must be executable"
    help_res = subprocess.run([str(FLATHUB_ENSURE), "--help"], capture_output=True, text=True, check=False)
    assert help_res.returncode == 0, help_res.stderr
    if shutil.which("shellcheck"):
        sc = subprocess.run(
            ["shellcheck", "-S", "warning", str(FLATHUB_ENSURE)],
            capture_output=True,
            text=True,
            check=False,
        )
        assert sc.returncode == 0, sc.stdout + sc.stderr


def test_flathub_ensure_missing_flatpak_exits_cleanly() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        tmp_path = Path(tmp)
        env = {
            "PATH": "/usr/bin:/bin",
            "HOME": str(tmp_path / "home"),
            "XDG_STATE_HOME": str(tmp_path / "state"),
        }
        # Isolate PATH to an empty dir plus standard basic utilities, ensuring no flatpak exists.
        empty_bin = tmp_path / "empty-bin"
        empty_bin.mkdir()
        for tool in ("bash", "sh", "dirname", "mkdir", "date", "printf", "sed", "grep", "timeout"):
            resolved = shutil.which(tool)
            if resolved:
                (empty_bin / tool).symlink_to(resolved)
        env["PATH"] = str(empty_bin)
        res = subprocess.run([str(FLATHUB_ENSURE)], env=env, capture_output=True, text=True, check=False)
        assert res.returncode == 0, res.stderr
        assert "not installed" in res.stdout.lower()
        assert not (tmp_path / "state" / "hornero" / "flathub-bootstrapped").exists()


def test_flathub_ensure_existing_system_or_user_remote_skips_add() -> None:
    for scope, sys_rem, usr_rem in (
        ("system", "flathub\n", ""),
        ("user", "", "flathub\n"),
    ):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            mock_bin = tmp_path / "bin"
            mock_bin.mkdir()
            log_file = _write_mock_flatpak(mock_bin, system_remotes=sys_rem, user_remotes=usr_rem)
            env = {
                **os.environ,
                "PATH": f"{mock_bin}:{os.environ.get('PATH', '')}",
                "HOME": str(tmp_path / "home"),
                "XDG_STATE_HOME": str(tmp_path / "state"),
                "HORNERO_FLATHUB_OFFLINE": "1",
            }
            res = subprocess.run([str(FLATHUB_ENSURE)], env=env, capture_output=True, text=True, check=False)
            assert res.returncode == 0, f"{scope}: {res.stderr}"
            calls = log_file.read_text(encoding="utf-8")
            assert "remote-add" not in calls, f"{scope} duplicate remote-add: {calls}"
            assert (tmp_path / "state" / "hornero" / "flathub-bootstrapped").is_file()


def test_flathub_ensure_adds_user_remote_and_refreshes_appstream_when_online() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        tmp_path = Path(tmp)
        mock_bin = tmp_path / "bin"
        mock_bin.mkdir()
        log_file = _write_mock_flatpak(mock_bin)
        env = {
            **os.environ,
            "PATH": f"{mock_bin}:{os.environ.get('PATH', '')}",
            "HOME": str(tmp_path / "home"),
            "XDG_STATE_HOME": str(tmp_path / "state"),
            "HORNERO_FLATHUB_ONLINE": "1",
        }
        res = subprocess.run([str(FLATHUB_ENSURE)], env=env, capture_output=True, text=True, check=False)
        assert res.returncode == 0, res.stderr
        calls = log_file.read_text(encoding="utf-8").splitlines()
        assert any(
            line == "remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo"
            for line in calls
        ), calls
        assert any(line == "update --appstream --noninteractive" for line in calls), calls
        assert (tmp_path / "state" / "hornero" / "flathub-bootstrapped").is_file()


def test_flathub_ensure_offline_failure_never_fails_boot_or_stamps() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        tmp_path = Path(tmp)
        mock_bin = tmp_path / "bin"
        mock_bin.mkdir()
        _write_mock_flatpak(mock_bin, fail_remote_add=True)
        env = {
            **os.environ,
            "PATH": f"{mock_bin}:{os.environ.get('PATH', '')}",
            "HOME": str(tmp_path / "home"),
            "XDG_STATE_HOME": str(tmp_path / "state"),
            "HORNERO_FLATHUB_OFFLINE": "1",
        }
        res = subprocess.run([str(FLATHUB_ENSURE)], env=env, capture_output=True, text=True, check=False)
        assert res.returncode == 0, res.stderr
        assert not (tmp_path / "state" / "hornero" / "flathub-bootstrapped").exists()


def test_flathub_systemd_user_unit() -> None:
    assert FLATHUB_SERVICE.is_file(), "missing desktop/systemd/user/hornero-flathub-setup.service"
    cp = _parse_ini(FLATHUB_SERVICE)
    assert "Unit" in cp and "Service" in cp and "Install" in cp
    assert cp["Unit"]["After"] == "network-online.target"
    cond = cp["Unit"]["ConditionPathExists"]
    assert cond.startswith("!") and "flathub-bootstrapped" in cond
    assert cp["Service"]["Type"] == "oneshot"
    assert "hornero-flathub-ensure" in cp["Service"]["ExecStart"]
    assert cp["Install"]["WantedBy"] == "default.target"


def test_xdg_desktop_portals_completeness() -> None:
    hypr = _parse_ini(HYPR_PORTALS)
    niri = _parse_ini(NIRI_PORTALS)

    assert hypr["preferred"]["default"] == "hyprland;gtk;"
    assert hypr["preferred"]["org.freedesktop.impl.portal.FileChooser"] == "gtk;"
    for iface in REQUIRED_PORTAL_INTERFACES:
        key = f"org.freedesktop.impl.portal.{iface}"
        assert key in hypr["preferred"], f"hyprland-portals.conf missing {key}"
        assert hypr["preferred"][key].endswith(";"), f"hyprland {key} must end with ';'"

    assert niri["preferred"]["default"] == "gtk;"
    assert niri["preferred"]["org.freedesktop.impl.portal.FileChooser"] == "gtk;"
    assert niri["preferred"]["org.freedesktop.impl.portal.Screencast"] == "gnome;"
    for iface in REQUIRED_PORTAL_INTERFACES:
        key = f"org.freedesktop.impl.portal.{iface}"
        assert key in niri["preferred"], f"niri-portals.conf missing {key}"
        assert niri["preferred"][key].endswith(";"), f"niri {key} must end with ';'"


def test_desktop_entries() -> None:
    apps = _parse_ini(APPS_DESKTOP)
    entry = apps["Desktop Entry"]
    assert entry["Type"] == "Application"
    assert entry["Name"] == "Hornero Apps"
    assert entry["GenericName"] == "Software Center"
    assert entry["GenericName[es]"] == "Centro de aplicaciones"
    assert entry["Comment"] == "Discover, install, and manage applications on HorneroOS"
    assert entry["Comment[es]"] == "Descubrí, instalá y gestioná aplicaciones en HorneroOS"
    assert entry["Exec"] == "horneroctl store gui"
    assert entry["Icon"] == "system-software-install"
    assert entry["Categories"] == "System;PackageManager;"
    assert entry["Keywords"] == "apps;store;software;install;flatpak;appimage;webapp;"

    appimg = _parse_ini(APPIMAGE_DESKTOP)
    aentry = appimg["Desktop Entry"]
    assert aentry["Type"] == "Application"
    assert aentry["Exec"] == "horneroctl store appimage import %f --gui"
    assert aentry["NoDisplay"] == "false"
    assert aentry["MimeType"] == "application/vnd.appimage;application/x-iso9660-appimage;"

    if shutil.which("desktop-file-validate"):
        for path in (APPS_DESKTOP, APPIMAGE_DESKTOP):
            res = subprocess.run(
                ["desktop-file-validate", str(path)],
                capture_output=True,
                text=True,
                check=False,
            )
            assert res.returncode == 0, f"{path}: {res.stdout}{res.stderr}"


def test_software_policy_json() -> None:
    data = json.loads(POLICY_JSON.read_text(encoding="utf-8"))
    assert data["apiVersion"] == "hornero.os/v1"
    assert data["kind"] == "SoftwarePolicy"
    assert data["allowedSources"] == [
        "arch_official",
        "hornero_official",
        "flathub_verified",
        "flathub_community",
        "vendor_official",
        "appimage",
        "webapp",
    ]
    assert data["aurPolicy"] == "explicit_opt_in"
    assert data["proprietaryPolicy"] == "explicit_consent"
    assert data["flatpakDefaultScope"] == "user"
    assert data["verifiedOnly"] is False
    assert data["openSourceOnly"] is False


def test_packaging_materialize_and_profile_coverage() -> None:
    pkg = PKGBUILD.read_text(encoding="utf-8")
    for needle in (
        "usr/share/applications",
        "desktop/hornero-apps/policy.json",
        "usr/share/hornero/apps/policy.json",
        "hornero-flathub-setup.service",
        "default.target.wants/hornero-flathub-setup.service",
    ):
        assert needle in pkg, f"PKGBUILD missing {needle}"

    mat = MATERIALIZE.read_text(encoding="utf-8")
    for needle in (
        'install_file "desktop/hornero-apps/policy.json" "$CONFIG_HOME/hornero/apps/policy.json"',
        'install_file "desktop/xdg-desktop-portal/hyprland-portals.conf"',
        'install_dir "share/applications" "$DATA_HOME/applications"',
    ):
        assert needle in mat, f"materialize.sh missing {needle}"

    prof = PROFILE.read_text(encoding="utf-8")
    for needle in (
        "desktop/xdg-desktop-portal/hyprland-portals.conf",
        "desktop/hornero-apps/policy.json",
        "share/applications",
    ):
        assert needle in prof, f"profile.toml missing {needle}"


if __name__ == "__main__":
    test_flathub_ensure_executable_and_shellcheck()
    test_flathub_ensure_missing_flatpak_exits_cleanly()
    test_flathub_ensure_existing_system_or_user_remote_skips_add()
    test_flathub_ensure_adds_user_remote_and_refreshes_appstream_when_online()
    test_flathub_ensure_offline_failure_never_fails_boot_or_stamps()
    test_flathub_systemd_user_unit()
    test_xdg_desktop_portals_completeness()
    test_desktop_entries()
    test_software_policy_json()
    test_packaging_materialize_and_profile_coverage()
    print("test_hornero_apps_config.py: ALL GREEN")
