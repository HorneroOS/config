#!/usr/bin/env python3
"""Static validation of the Hornero Signal boot themes (GRUB, Plymouth, ISO).

Covers: assets render, themes reference only files that exist, every colour is
a hornero-signal-night role, the mark has not drifted from assets/brand, the
Plymouth script stays static (reduced motion), and bin/hornero-boot-theme is
idempotent and reversible against a fixture root. What this cannot prove: how
GRUB or Plymouth draw the frames; see docs/BOOT.md for the real-boot evidence.
"""
import json
import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BOOT = ROOT / "desktop" / "boot"
TOOL = ROOT / "bin" / "hornero-boot-theme"
FAILED = []


def check(ok, msg):
    print(("BOOT-PASS: " if ok else "BOOT-FAIL: ") + msg)
    if not ok:
        FAILED.append(msg)


def png_size(p):
    d = p.read_bytes()
    assert d[:8] == b"\x89PNG\r\n\x1a\n", p
    return struct.unpack(">II", d[16:24])


# The canonical mark carries one Day-theme role (the eye), so accept both flagship themes.
palette = set()
for theme_id in ("hornero-signal-night", "hornero-signal-day"):
    palette |= {v.upper() for v in json.loads(
        (ROOT / f"profiles/themes/{theme_id}/theme.json").read_text())["palette"].values()}

# --- colours are theme roles ------------------------------------------------------
hexes = set()
for f in list((BOOT / "art").glob("*.svg")) + [BOOT / "grub/theme.txt"]:
    hexes |= {h.upper() for h in re.findall(r"#[0-9A-Fa-f]{6}\b", f.read_text())}
check(hexes <= palette, f"boot art and GRUB theme use only hornero-signal theme roles (stray: {sorted(hexes - palette)})")

# --- the mark is the canonical dark-ground logo -----------------------------------
check((BOOT / "art/mark.svg").read_bytes() == (ROOT / "assets/brand/logo-dark.svg").read_bytes(),
      "boot mark equals assets/brand/logo-dark.svg")

# --- render ------------------------------------------------------------------------
if not shutil.which("rsvg-convert"):
    print("BOOT-SKIP: rsvg-convert not installed; skipping render checks")
    sys.exit(1 if FAILED else 0)

out = Path(tempfile.mkdtemp(prefix="hornero-boot-"))
try:
    r = subprocess.run([str(ROOT / "scripts/render-boot-assets.sh"), "--out", str(out)],
                       capture_output=True, text=True)
    check(r.returncode == 0, "render-boot-assets.sh succeeds")
    grub = out / "grub/hornero-signal"
    ply = out / "plymouth/hornero-signal"

    check(png_size(grub / "background.png") == (1920, 1080), "GRUB background is 1920x1080")
    check(png_size(out / "iso/splash.png") == (800, 600), "ISO splash is 800x600")
    check(png_size(ply / "mark.png") == (320, 320), "Plymouth mark is 2x (320px)")

    # GRUB: theme references resolve, fonts exist by name, 9-slice complete.
    theme = (grub / "theme.txt").read_text()
    refs = re.findall(r'(?:file|desktop-image)\s*[=:]\s*"([^"]+)"', theme)
    check(bool(refs) and all((grub / n).is_file() for n in refs), f"GRUB theme file refs exist ({refs})")
    slices = [f"select_{p}.png" for p in "c n s e w nw ne sw se".split()]
    check(all((grub / n).is_file() for n in slices), "GRUB selection 9-slice complete")
    names = set()
    for pf in grub.glob("*.pf2"):
        data = pf.read_bytes()
        check(data[:4] == b"FILE" and data[8:12] == b"PFF2", f"{pf.name} is a PFF2 font")
        m = re.search(rb"NAME\x00\x00\x00.([^\x00]+)\x00", data)
        if m:
            names.add(m.group(1).decode())
    fonts = set(re.findall(r'font\s*=\s*"([^"]+)"|item_font\s*=\s*"([^"]+)"', theme))
    wanted = {a or b for a, b in fonts} | set(re.findall(r'terminal-font:\s*"([^"]+)"', theme))
    check(wanted <= names, f"GRUB theme fonts are shipped as pf2 (missing: {sorted(wanted - names)})")

    # Plymouth: descriptor + script consistency and static behaviour.
    desc = (ply / "hornero-signal.plymouth").read_text()
    check("ModuleName=script" in desc and "/usr/share/plymouth/themes/hornero-signal/hornero-signal.script" in desc,
          "Plymouth descriptor points at the script in the installed theme dir")
    script = (ply / "hornero-signal.script").read_text()
    images = set(re.findall(r'(?:scaled|Image)\("([^"]+)"\)', script))
    check(bool(images) and all((ply / n).is_file() for n in images), f"Plymouth script images exist ({sorted(images)})")
    check(not re.search(r"Math\.(Sin|Cos|Tan)|SetOpacity\(\s*[a-z_]*\s*[*/]", script),
          "Plymouth script has no easing/pulsing (static, reduced-motion safe)")
    check("Image.Text" not in script, "Plymouth script needs no font or label plugin")
finally:
    shutil.rmtree(out, ignore_errors=True)

# --- hornero-boot-theme against a fixture root -------------------------------------
def tool(root, *args, env=None):
    e = dict(os.environ, NO_COLOR="1", **(env or {}))
    return subprocess.run([str(TOOL), *args, "--root", str(root)], capture_output=True, text=True, env=e)


def fixture(encrypted=False):
    d = Path(tempfile.mkdtemp(prefix="hornero-bootroot-"))
    (d / "etc/default").mkdir(parents=True)
    (d / "etc/default/grub").write_text(
        'GRUB_TIMEOUT=5\nGRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 quiet"\nGRUB_CMDLINE_LINUX=""\n')
    hooks = "base udev autodetect modconf block " + ("encrypt " if encrypted else "") + "filesystems fsck"
    (d / "etc/mkinitcpio.conf").write_text(f"MODULES=()\nHOOKS=({hooks})\n")
    g = d / "usr/share/grub/themes/hornero-signal"
    g.mkdir(parents=True)
    (g / "theme.txt").write_text("desktop-color: \"#0C0F13\"\n")
    p = d / "usr/share/plymouth/themes/hornero-signal"
    p.mkdir(parents=True)
    (p / "hornero-signal.plymouth").write_text("[Plymouth Theme]\n")
    return d


env_ply = {"HORNERO_BOOT_THEME_ASSUME_PLYMOUTH": "1"}
d = fixture()
try:
    orig_grub = (d / "etc/default/grub").read_text()
    orig_init = (d / "etc/mkinitcpio.conf").read_text()
    r = tool(d, "apply", env=env_ply)
    check(r.returncode == 0, f"apply succeeds ({r.stdout.strip()!r} {r.stderr.strip()!r})")
    g = (d / "etc/default/grub").read_text()
    check('GRUB_THEME="/boot/grub/themes/hornero-signal/theme.txt"' in g, "GRUB_THEME points at the /boot copy")
    check((d / "boot/grub/themes/hornero-signal/theme.txt").is_file(), "theme copied into /boot (readable on encrypted root)")
    check("splash" in g and "quiet" in g, "kernel parameters gain splash, keep quiet")
    check(re.search(r"^HOOKS=.*\budev plymouth\b", (d / "etc/mkinitcpio.conf").read_text(), re.M) is not None,
          "plymouth hook inserted right after udev")
    check("Theme=hornero-signal" in (d / "etc/plymouth/plymouthd.conf").read_text(), "plymouthd.conf selects the theme")
    snap = ((d / "etc/default/grub").read_text(), (d / "etc/mkinitcpio.conf").read_text())
    tool(d, "apply", env=env_ply)
    check(snap == ((d / "etc/default/grub").read_text(), (d / "etc/mkinitcpio.conf").read_text()), "apply is idempotent")
    st = tool(d, "status", env=env_ply).stdout
    check("grub theme applied" in st and "plymouth theme applied" in st, "status reports both applied")
    r = tool(d, "remove", env=env_ply)
    check(r.returncode == 0, "remove succeeds")
    check((d / "etc/default/grub").read_text().split() == orig_grub.split(),
          f"remove restores /etc/default/grub ({(d / 'etc/default/grub').read_text()!r})")
    check((d / "etc/mkinitcpio.conf").read_text() == orig_init, "remove restores mkinitcpio HOOKS")
    check(not (d / "boot/grub/themes/hornero-signal").exists(), "remove deletes the /boot copy")
    # Without plymouth installed the component is skipped, not an error.
    r = tool(d, "apply", "--plymouth")
    check(r.returncode == 0 and "SKIP" in r.stdout, "plymouth absent: graceful skip, exit 0")
    # Dry run changes nothing.
    before = (d / "etc/default/grub").read_text()
    tool(d, "apply", "--dry-run", env=env_ply)
    check((d / "etc/default/grub").read_text() == before, "--dry-run writes nothing")
finally:
    shutil.rmtree(d, ignore_errors=True)

d = fixture(encrypted=True)
try:
    r = tool(d, "apply", "--plymouth", env=env_ply)
    check(r.returncode != 0 and "encrypted" in r.stdout, "encrypted root refuses plymouth without --allow-encrypted")
    check("plymouth" not in (d / "etc/mkinitcpio.conf").read_text(), "encrypted refusal leaves HOOKS untouched")
finally:
    shutil.rmtree(d, ignore_errors=True)

sys.exit(1 if FAILED else 0)
