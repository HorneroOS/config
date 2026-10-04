# HorneroOS Desktop on Niri

Niri is an experimental Wayland compositor backend for HorneroOS Desktop.
Hyprland remains the validated default. A packaged Niri config and shared
Shell backend are not enough to call the session supported; the current
acceptance covers a single-output graphical VM journey, with multi-output and
portal/recording coverage still open.

## Session configuration

`desktop/niri/config.kdl` starts from Niri 26.04's upstream default
configuration. Hornero keeps the native Niri overview, column/window
navigation, workspace controls, media keys, monitor power action and
screenshot actions. It replaces the sample Waybar startup and app bindings
with Hornero Shell/`horneroctl` entry points.

The config package materializes the same file to `~/.config/niri/config.kdl`
for user setup and to `/etc/niri/config.kdl` as a fallback. Niri checks the
user's XDG config first and falls back to `/etc/niri/config.kdl`. The package
does not install the Niri compositor itself or overwrite a user's Niri file
during the running session. Install Niri separately to experiment with this
backend.

| Key | Hornero action |
| --- | --- |
| `Super+D` | Hornero app launcher |
| `Super+Shift+D` | Dashboard |
| `Super+Shift+B` | Layout Picker |
| `Super+X` | Session menu |
| `Super+,` | Appearance in Control Center |
| `Super+E` | Terminal file manager |
| `Super+V` | Clipboard history |
| `Super+L` | Lock session |
| `Print` | Niri screenshot selection UI |
| `Ctrl+Print` | Niri screen capture |
| `Alt+Print` | Niri focused-window capture |

`Super+Space` toggles a window between floating and tiling, and `Super+Shift+V`
moves focus between those groups. The Shell's Layout Picker configures Shell
surfaces and bars; it does not change Niri's native column layout.

## Shared Shell behavior and capability gaps

The backend consumes Niri's JSON event stream for workspaces, windows, focus,
and keyboard layouts. Shared UI can show workspace occupancy, list and focus
windows, close a window, toggle floating, request fullscreen, and focus
workspaces. Niri's native `niri msg action screenshot` picker handles region
selection because the Shell's current overlay picker relies on Hyprland window
geometry. The native Niri picker follows Niri's configured `screenshot-path`
and clipboard behavior; a custom `horneroctl --output` destination is not
available through that action.

Niri does not advertise Shell support for special workspaces, dynamic
Hyprland-specific output metadata, native window thumbnails, workspace
creation/renaming, Hyprland layer/window rules, or global shortcuts through
Quickshell's Hyprland-only protocol. Controls that require those capabilities
stay hidden or disabled. They are not emulated.

Niri ships its own `niri-portals.conf` selection. Install the Niri-recommended
GNOME portal backend for screencasting where needed, and `xwayland-satellite`
for X11 applications. These dependencies are optional and do not enter the
Hyprland default package set. OBS and screen recording still need graphical
acceptance under Niri before the edition can claim those workflows.

## Validation boundary

The configuration is based on upstream Niri v26.04 and `scripts/validate.sh`
runs `NIRI_CONFIG=... niri validate` when the Niri executable is available. In
environments without Niri, static validation checks only the file and key
product bindings. A QEMU guest running Niri v26.04 at 1280×800 has been
booted and exercised through keyboard and pointer input: Shell startup,
Launcher, Dashboard, Control Center, Appearance, a Hornero Light theme change,
Layout Picker/Hornero Left, workspace switching, and native screenshot
selection. This proves a real one-output session rather than config parsing
alone. The host itself remains on Hyprland. Multi-output focus, lock/session
recovery, OBS/screencast through the selected portal, external GTK/Qt app
agreement, and the remaining supported-shell surfaces still need graphical
acceptance before Niri can move beyond experimental.

## Upstream references

- [Niri configuration loading and validation](https://niri-wm.github.io/niri/Configuration%3A-Introduction.html)
- [Niri key bindings](https://niri-wm.github.io/niri/Configuration%3A-Key-Bindings.html)
- [Niri IPC integration](https://niri-wm.github.io/niri/IPC.html)
- [Niri v26.04 default config](https://github.com/niri-wm/niri/blob/v26.04/resources/default-config.kdl)
- [Arch Linux Niri package and optional dependencies](https://archlinux.org/packages/extra/x86_64/niri/)
