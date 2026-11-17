# Boot experience - GRUB and Plymouth

Boot is a brand surface of Hornero Signal
([RFC 0001](https://github.com/HorneroOS/docs/blob/main/development/rfc-0001-hornero-signal.md),
`development/signal-visual-language.md`): matte `ground`, the hornero mark, Plex
Mono uppercase eyebrows with the 2 x 10 px registration tick, `signal` amber as
the only accent, and a segmented meter. No glitch, no neon, no blur. Boot always
uses the factory **Signal Night** roles: nothing at boot time can follow the
user's chosen theme or Hornero Chromatic palette.

## Ownership

| Surface | Lives in | Why |
|---|---|---|
| GRUB theme (installed system) | `HorneroOS/config` `desktop/boot/grub` | config owns factory defaults and theme assets; hornero-config ships it |
| Plymouth theme (installed system) | `HorneroOS/config` `desktop/boot/plymouth` | same; plymouth stays an optional package |
| Enabling them | `bin/hornero-boot-theme` (config), called by the installer for GRUB | boot config is edited only by an explicit, idempotent tool |
| Live ISO syslinux menu | `HorneroOS/installer` `image/archiso/syslinux` | the ISO profile is the installer repo's; splash rendered from config art |
| Calamares chrome | `HorneroOS/installer` | unchanged here |

## Sources and build

* `desktop/boot/art/*.svg` - vector sources. Text is **outlined** by
  `scripts/generate-boot-art.py` (development-time, needs fontTools and IBM
  Plex Mono) so builds and the initramfs need no fonts.
* `desktop/boot/grub/fonts/*.pf2` - IBM Plex (OFL-1.1) converted with
  `grub-mkfont` (committed binary, a few KB each; regenerate with
  `grub-mkfont --range=0x20-0x7e,0xa0-0xff,0x2022-0x2022,0x2026-0x2026 -s <px> <ttf>`),
  so the package needs no `grub` makedepend.
* `scripts/render-boot-assets.sh --out DIR` renders PNGs with `rsvg-convert`
  (already a makedepend) and stages `grub/`, `plymouth/` and `iso/splash.png`.
  `packaging/PKGBUILD` runs it and installs the two themes at their canonical
  paths, inert.

## Enabling

```sh
sudo /usr/share/hornero/bin/hornero-boot-theme status
sudo /usr/share/hornero/bin/hornero-boot-theme apply --grub        # needs grub
sudo /usr/share/hornero/bin/hornero-boot-theme apply --plymouth    # needs plymouth
sudo /usr/share/hornero/bin/hornero-boot-theme remove
```

* GRUB: the theme is **copied to `/boot/grub/themes/hornero-signal`** because
  GRUB cannot read `/usr` on an encrypted root; `GRUB_THEME`,
  `GRUB_GFXMODE=auto`, `GRUB_GFXPAYLOAD_LINUX=keep` are written to
  `/etc/default/grub` tagged `# hornero-boot-theme`; `grub-mkconfig` runs.
  Re-run `apply` after a hornero-config update to refresh the copy.
* Plymouth: inserts the `plymouth` hook after `udev`, writes
  `/etc/plymouth/plymouthd.conf`, adds `splash` to the kernel command line and
  rebuilds the initramfs. A single backup `mkinitcpio.conf.hornero-bak` is kept.
  On an **encrypted root** it refuses unless `--allow-encrypted` is given,
  because the passphrase prompt through Plymouth is not validated on a real
  encrypted install yet.
* If `grub` or `plymouth` is not installed the component is skipped with exit 0.
  `--root DIR` operates on a directory tree and never runs `grub-mkconfig` or
  `mkinitcpio` (used by the tests and image builds); `--dry-run` prints edits.

## Motion and accessibility

Plymouth cannot read the desktop's reduced-motion setting, so the theme is the
reduced-motion variant by construction: no fades, easing or pulsing. The only
change over time is the meter lighting whole segments (24; plymouthd's boot
progress, or one step per 0.5 s up to 20/24 on a first boot without a recorded
duration). A typed disk passphrase shows one block per character, never the
text. Status is conveyed by position and count, not by colour alone. Text sizes
are 14-18 px in GRUB with text contrast >= 7:1 (`inkMuted`/`ink` on `ground`).

## Verification (what was and was not seen)

* GRUB: a real GRUB 2.16 (x86_64-efi, built with `grub-mkstandalone`) booted
  under OVMF in QEMU with the rendered theme; the frame was captured and
  inspected (selection bar, Plex Sans items, mono eyebrow/timeout/help).
* Live-ISO syslinux: real syslinux 6.04 `vesamenu.c32` under SeaBIOS in QEMU
  with the exact `syslinux.cfg` and `splash.png` (installer repo).
* Plymouth: `tests/test_boot_theme.py` validates descriptor, assets and that the
  script is static. A real `plymouthd` 26.134 (Arch `plymouth` package,
  signature checked, installed into the disposable QA VM from the shell
  image) rendered the theme on a real DRM display (virtio-gpu, 1280x800):
  logo, eyebrow and 24-segment meter at about one quarter and at 20/24
  progress, and the disk-passphrase prompt with one block per typed
  character. The frames were captured and inspected. Two harness details
  matter for anyone repeating it: the guest kernel command line carries
  `console=ttyS0`, which makes plymouth force the text splash, so pass
  `plymouth.ignore-serial-consoles` (`plymouthd --kernel-command-line=...`);
  and the compositor session must be stopped first so plymouth can take the
  DRM master. This is a **running-session** render, not an initramfs boot: a
  real boot of an installed image with `hornero-boot-theme apply --plymouth`
  (initramfs hook, early KMS handover, encrypted root) is still owed.
* Not exercised anywhere: encrypted-root passphrase prompt, HiDPI scaling,
  Secure Boot chains.

## Not covered

* UEFI live ISO boots through systemd-boot, which cannot be themed beyond its
  text menu; see HorneroOS/installer docs for the follow-up.
* Secure Boot signed shim/GRUB chains and non-x86 are unchanged.
