#!/usr/bin/env bash
# test_desktop_integration.sh - P2 desktop integration: Hyprland semantic
# colors, Kitty flagship palettes, Qt decision artifacts, and Hornero Dark
# factory defaults. Materializes into a temp HOME; no system mutation.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_HOME="$(mktemp -d)"
trap 'rm -rf "$TMP_HOME"' EXIT

"$REPO_ROOT/scripts/materialize.sh" --dest "$TMP_HOME" >/dev/null

pass() { echo "TEST-PASS: $1"; }
fail() { echo "TEST-FAIL: $1" >&2; exit 1; }

# --- (1) Hyprland semantic integration ---------------------------------------
# Factory borders/gradient come from the flagship dark tokens (terracotta
# primary E07856, amber accent F2B749, clay border 6B4E3B), not neon.
grep -qi "e07856" "$TMP_HOME/.config/hypr/hyprland.lua.d/smart-colors.lua" \
  || fail "hyprland lua missing flagship terracotta active border"
grep -qi "f2b749" "$TMP_HOME/.config/hypr/hyprland.lua.d/smart-colors.lua" \
  || fail "hyprland lua missing flagship amber gradient stop"
grep -qi "6b4e3b" "$TMP_HOME/.config/hypr/hyprland.lua.d/smart-colors.lua" \
  || fail "hyprland lua missing clay inactive border"
grep -qi "0f0b08" "$TMP_HOME/.config/hypr/hyprland.lua.d/static.lua" \
  || fail "hyprland lua shadow not tinted with flagship scrim"
# No neon-rainbow leftovers (catppuccin mauve/blue placeholders).
if grep -qi "cba6f7\|89b4fa\|45475a" "$TMP_HOME/.config/hypr/hyprland.lua.d/smart-colors.lua" \
    "$TMP_HOME/.config/hypr/hyprland.lua.d/smart-colors.lua"; then
  fail "catppuccin placeholder borders still shipped"
fi
pass "hyprland factory borders/shadow are flagship dark, no neon leftovers"
# Group + groupbar colors present in smart-colors.lua.
for token in e07856 6b4e3b f2b749 3c2c21 2b1f18; do
  grep -qi "$token" "$TMP_HOME/.config/hypr/hyprland.lua.d/smart-colors.lua" \
    || fail "smart-colors.lua missing flagship token $token"
done
pass "hyprland smart-colors.lua carries active/inactive/group/groupbar set"
# Light fragment ships with the same structure for the documented opt-in.
[[ -f "$TMP_HOME/.config/hypr/hyprland.lua.d/hornero-light.lua" ]] \
  || fail "hornero-light.lua not materialized"
grep -qi "b24827" "$TMP_HOME/.config/hypr/hyprland.lua.d/hornero-light.lua" \
  || fail "hornero-light.lua missing flagship light primary"
pass "hyprland light fragment materialized with flagship light tokens"
# Hyprlock Smart Colors override must source the canonical Hornero cache path.
grep -q "source = ~/.cache/hornero/smart-colors/colors-hyprlock.conf" \
  "$TMP_HOME/.config/hypr/hyprlock.conf" \
  || fail "hyprlock.conf does not source the canonical Smart Colors override"
pass "hyprlock sources canonical Smart Colors override"
# hyprlock carries no date label by design (see path-contract test):
# neither $DATE nor cmd[] output renders in this hyprlock build.
if grep -q 'text = \$DATE\|text = cmd' \
  "$TMP_HOME/.config/hypr/hyprlock.conf"; then
  fail "hyprlock.conf carries a dead date label"
fi
pass "hyprlock carries no dead date label"

# --- (2) Kitty palettes --------------------------------------------------------
[[ -f "$TMP_HOME/.config/kitty/hornero-dark.conf" ]] \
  || fail "kitty hornero-dark.conf not materialized"
[[ -f "$TMP_HOME/.config/kitty/hornero-light.conf" ]] \
  || fail "kitty hornero-light.lua not materialized"
grep -q "include hornero-dark.conf" "$TMP_HOME/.config/kitty/kitty.conf" \
  || fail "kitty.conf does not include the Hornero Dark factory palette"
if grep -q "202734\|CBCCC6" "$TMP_HOME/.config/kitty/kitty.conf"; then
  fail "kitty.conf still carries the pre-flagship fallback palette"
fi
pass "kitty factory default includes hornero-dark, old fallback gone"
# Terminal readability gate (normals AA, brights large-text floor, R/G/Y
# distinguishable, ramps stepped) over both shipped palettes.
python3 "$REPO_ROOT/scripts/check-terminal-contrast.py" \
  --kitty-dir "$REPO_ROOT/desktop/kitty" \
  || fail "terminal contrast gate"
pass "kitty palettes pass readability + distinguishability gate"

# --- (3) Qt decision -----------------------------------------------------------
[[ -f "$TMP_HOME/.config/qt6ct/qt6ct.conf" ]] \
  || fail "qt6ct.conf not materialized"
grep -q "^style=Fusion" "$TMP_HOME/.config/qt6ct/qt6ct.conf" \
  || fail "qt6ct.conf does not pin Fusion style"
grep -q "Papirus-Dark" "$TMP_HOME/.config/qt6ct/qt6ct.conf" \
  || fail "qt6ct.conf missing factory icon theme"
grep -q '"QT_QPA_PLATFORMTHEME", "qt6ct"' \
  "$TMP_HOME/.config/hypr/hyprland.lua.d/environment.lua" \
  || fail "hypr environment no longer pins qt6ct platformtheme"
[[ -f "$REPO_ROOT/docs/QT_DECISION.md" ]] \
  || fail "docs/QT_DECISION.md missing"
# No Kvantum config ships (deferred by evidence: no Plasma session).
if find "$TMP_HOME" -iname "*kvantum*" | grep -q .; then
  fail "kvantum artifacts materialized despite deferral"
fi
pass "qt6ct factory default + platformtheme pin, kvantum deferred"
# Generated per-theme palettes ship with the factory defaults and match
# the generator (drift gate: regenerate must diff clean).
for _qt in hornero-dark hornero-light pampa; do
  [[ -f "$TMP_HOME/.config/qt6ct/colors/$_qt.conf" ]] \
    || fail "qt6ct colors/$_qt.conf not materialized"
  grep -q "^\[ColorScheme\]" "$TMP_HOME/.config/qt6ct/colors/$_qt.conf" \
    || fail "qt6ct colors/$_qt.conf missing [ColorScheme]"
  for _key in active_colors inactive_colors disabled_colors; do
    grep -q "^$_key=" "$TMP_HOME/.config/qt6ct/colors/$_qt.conf" \
      || fail "qt6ct colors/$_qt.conf missing $_key"
  done
done
_QTDRIFT="$(mktemp -d)"
python3 "$REPO_ROOT/scripts/generate-qt-schemes.py" --out "$_QTDRIFT" >/dev/null \
  || fail "qt scheme generator exits 0"
for _qt in hornero-dark hornero-light pampa; do
  cmp -s "$_QTDRIFT/$_qt.conf" "$TMP_HOME/.config/qt6ct/colors/$_qt.conf" \
    || fail "qt6ct colors/$_qt.conf drifts from the generator"
done
grep -q '^; Default wallpaper: pampa-01.jpg\.$' \
  "$TMP_HOME/.config/qt6ct/colors/pampa.conf" \
  || fail "Pampa qt6ct scheme does not document its default wallpaper"
rm -rf "$_QTDRIFT"
pass "qt6ct per-theme palettes materialized and drift-free"

# --- (4) Factory defaults: fresh boot = Hornero Dark ---------------------------
[[ -f "$TMP_HOME/.local/share/hornero/factory.json" ]] \
  || fail "factory.json not materialized"
python3 - "$REPO_ROOT/profiles/factory.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["defaultTheme"] == "hornero-dark", "defaultTheme is not hornero-dark"
assert "hornero-dark" in d["availableThemes"] and "hornero-light" in d["availableThemes"]
assert d["fonts"]["material"] == "Material Symbols Rounded"
assert "extra/ttf-material-symbols-variable" in d["fonts"]["packages"]
assert d["icons"]["theme"] == "Papirus-Dark"
PY
pass "factory.json declares Hornero Dark + fonts/icons with dep names"
# Factory record agrees with the flagship recipes it points at.
python3 - "$REPO_ROOT/profiles/factory.json" "$REPO_ROOT/profiles/themes" <<'PY'
import json, sys
factory = json.load(open(sys.argv[1]))
base = sys.argv[2]
for mode in factory["availableThemes"]:
    theme = json.load(open(f"{base}/{mode}/theme.json"))
    assert theme["id"] == mode, f"recipe id mismatch: {mode}"
assert factory["defaultTheme"] == "hornero-dark"
assert factory["wallpaper"]["defaultWallpaper"] == json.load(
    open(f"{base}/hornero-dark/theme.json"))["defaultWallpaper"]
PY
pass "factory record matches flagship theme recipes"

# Niri binds must pass the required pane argument to the Shell IPC contract,
# and the package-owned Exo helper must resolve the default terminal without
# a personal dotfiles checkout.
grep -Fq '"controlCenter" "open" "appearance"' "$TMP_HOME/.config/niri/config.kdl" \
  || fail "Niri Settings shortcut does not pass a valid Control Center pane"
grep -Fq '"terminal-file" "--new-window" "--last-dir"' "$TMP_HOME/.config/niri/config.kdl" \
  || fail "Niri terminal file-manager shortcut does not use the configured terminal"
grep -Fq 'horneroctl apps terminal-file --new-window --last-dir' \
  "$TMP_HOME/.config/hypr/hyprland.lua.d/keybindings.lua" \
  || fail "Hyprland terminal file-manager shortcut does not use the configured terminal"
grep -Fq 'horneroctl apps terminal-file --new-window --path "%f"' "$TMP_HOME/.config/Thunar/uca.xml" \
  || fail "Thunar Yazi action does not use the configured terminal"
grep -Fq 'class = "^(yazi-popup|com\\.horneroos\\.yazi-popup)$"' \
  "$TMP_HOME/.config/hypr/hyprland.lua.d/window-rules.lua" \
  || fail "Yazi popup rule does not recognize Ghostty's GTK application ID"
grep -Fq 'match app-id=r#"^(yazi-popup|com\.horneroos\.yazi-popup)$"#' \
  "$TMP_HOME/.config/niri/config.kdl" \
  || fail "Niri Yazi popup rule does not recognize Ghostty's application ID"
grep -qx 'TerminalEmulator=kitty' "$TMP_HOME/.config/xfce4/helpers.rc" \
  || fail "Exo default terminal is missing from the materialized Hornero profile"
pass "Niri, Hyprland and Thunar use the package-owned default terminal"

# Optional terminal configs use their native lookup paths and all share the
# same dynamic Hornero palette output. Kitty remains Exo's default terminal.
grep -Fq 'import = ["hornero-dark.toml", "hornero-colors.toml"]' \
  "$TMP_HOME/.config/alacritty/alacritty.toml" \
  || fail "Alacritty does not import its static and generated palette files"
grep -Fq 'live_config_reload = true' "$TMP_HOME/.config/alacritty/alacritty.toml" \
  || fail "Alacritty generated colors will not live-reload"
grep -qx 'theme = Hornero Dynamic' "$TMP_HOME/.config/ghostty/config.ghostty" \
  || fail "Ghostty does not select Hornero Dynamic"
python3 - "$REPO_ROOT" <<'PY'
import json, re, sys
from pathlib import Path

root = Path(sys.argv[1])
terminal = json.loads((root / "profiles/factory.json").read_text())["terminal"]
integrations = terminal["integrations"]
ids = [integration["id"] for integration in integrations]
assert ids == ["kitty", "alacritty", "ghostty"], ids
assert terminal["default"] == "kitty"
assert [item["id"] for item in integrations if item["role"] == "default"] == ["kitty"]
assert all(item["role"] in {"default", "optional"} for item in integrations)
assert all(item["package"] == item["id"] for item in integrations)
package_metadata = (root / "packaging/PKGBUILD").read_text()
optdepends_match = re.search(r"(?ms)^optdepends=\(\n(.*?)^\)", package_metadata)
assert optdepends_match, "packaging/PKGBUILD has no optdepends array"
optdepends = optdepends_match.group(1)
appearance = (root / "lib/hornero/apply-appearance.sh").read_text()
for integration in integrations:
    config = root / integration["configSource"]
    assert config.is_file(), f"missing {integration['id']} source: {config}"
    expected_target = integration["configSource"].removeprefix("desktop/")
    assert integration["configPath"] == "{config}/" + expected_target
    assert integration["configExample"] in config.read_text(), (
        f"{integration['id']} example drifted from {config}"
    )
    assert re.search(rf"^\s*'{re.escape(integration['package'])}:", optdepends, re.M), (
        f"{integration['id']} has no matching package optdep"
    )
    assert integration["palette"] and integration["palettePath"]
    path_prefix = {
        "{cache}": "${XDG_CACHE_HOME:-$HOME/.cache}",
        "{config}": "${XDG_CONFIG_HOME:-$HOME/.config}",
    }
    output_path = integration["palettePath"]
    for token, expansion in path_prefix.items():
        output_path = output_path.replace(token, expansion)
    expected_output = f'--{integration["id"]}-output "{output_path}{integration["palette"]}"'
    assert expected_output in appearance, (
        f"{integration['id']} palette output drifted: expected {expected_output}"
    )
    assert integration["detail"] and integration["note"]
PY
pass "factory terminal catalogue matches installed configs and Kitty remains the default"
python3 - "$REPO_ROOT" <<'PY'
import json, re, sys
from pathlib import Path

root = Path(sys.argv[1])
factory = json.loads((root / "profiles/factory.json").read_text())
integrations = factory["paletteApplications"]
ids = [item["id"] for item in integrations]
assert ids == ["btop", "cava"], ids
assert len(ids) == len(set(ids)), "duplicate palette application id"
assert all(item["role"] == "optional" for item in integrations)
assert all(item["package"] == item["id"] for item in integrations)
package_metadata = (root / "packaging/PKGBUILD").read_text()
optdepends_match = re.search(r"(?ms)^optdepends=\(\n(.*?)^\)", package_metadata)
assert optdepends_match, "packaging/PKGBUILD has no optdepends array"
optdepends = optdepends_match.group(1)
appearance = (root / "lib/hornero/apply-appearance.sh").read_text()
output_flags = {"btop": "--btop-output", "cava": "--cava-output"}
for item in integrations:
    config = root / item["configSource"]
    assert config.is_file(), f"missing {item['id']} source: {config}"
    assert item["configPath"].startswith("{config}/")
    assert item["theme"] in config.read_text(), f"{item['id']} does not select {item['theme']}"
    theme_path = root / item["themeSource"]
    assert theme_path.is_file(), f"missing {item['id']} packaged palette theme: {theme_path}"
    assert re.search(rf"^\s*'{re.escape(item['package'])}:", optdepends, re.M), (
        f"{item['id']} has no matching package optdep"
    )
    assert item["detail"] and item["note"] and item["category"]
    output = item["themePath"].removeprefix("{config}")
    assert output_flags[item["id"]] in appearance and output in appearance, (
        f"{item['id']} palette path is not generated by the appearance renderer"
    )
PY
pass "factory palette application catalogue matches packaged configs, optional packages, and renderer outputs"
python3 - "$REPO_ROOT" <<'PY'
import re, sys, tomllib
from pathlib import Path
root = Path(sys.argv[1])
for name, kitty_name in (("hornero-dark", "hornero-dark.conf"),
                         ("hornero-light", "hornero-light.conf")):
    toml = tomllib.loads((root / "desktop/alacritty" / f"{name}.toml").read_text())
    kitty = {}
    for line in (root / "desktop/kitty" / kitty_name).read_text().splitlines():
        match = re.match(r"^(background|foreground|color([0-9]|1[0-5]))\s+(#[0-9A-Fa-f]{6})$", line)
        if match:
            kitty[match.group(1)] = match.group(3)
    assert toml["colors"]["primary"]["background"] == kitty["background"]
    assert toml["colors"]["primary"]["foreground"] == kitty["foreground"]
    assert [toml["colors"]["normal"][key] for key in
            ("black", "red", "green", "yellow", "blue", "magenta", "cyan", "white")] == [
                kitty[f"color{i}"] for i in range(8)]
    assert [toml["colors"]["bright"][key] for key in
            ("black", "red", "green", "yellow", "blue", "magenta", "cyan", "white")] == [
                kitty[f"color{i}"] for i in range(8, 16)]
ghostty = {}
for line in (root / "desktop/ghostty/themes/Hornero Dynamic").read_text().splitlines():
    match = re.match(r"^palette = ([0-9]|1[0-5])=(#[0-9A-Fa-f]{6})$", line)
    if match:
        ghostty[int(match.group(1))] = match.group(2)
assert [ghostty[i] for i in range(16)] == [
    re.search(rf"^color{i}\s+(#[0-9A-Fa-f]{{6}})$",
              (root / "desktop/kitty/hornero-dark.conf").read_text(), re.M).group(1)
    for i in range(16)
]
PY
pass "Alacritty static variants and Ghostty fallback match Hornero's tested Kitty palettes"
# No runtime dependency on ulises-jeremias/dotfiles in anything new or
# materialized: that repo is a read-only extraction source (provenance
# mentions in DECISIONS/docs stay allowlisted per AGENTS.md).
# NOTE: this test file itself is excluded from the search below because it
# necessarily spells out the forbidden patterns to assert their absence.
if grep -rn "git clone.*dotfiles\|curl.*dotfiles\|wget.*dotfiles\|github.com/ulises-jeremias/dotfiles.*clone\|raw.githubusercontent.*dotfiles" \
    "$REPO_ROOT/desktop/kitty" "$REPO_ROOT/desktop/alacritty" "$REPO_ROOT/desktop/ghostty" \
    "$REPO_ROOT/desktop/hypr" "$REPO_ROOT/desktop/qt6ct" \
    "$REPO_ROOT/profiles/factory.json" "$REPO_ROOT/scripts/check-terminal-contrast.py" \
    2>/dev/null | grep -v "test_desktop_integration" ; then
  fail "new desktop-integration files reference a dotfiles runtime fetch"
fi
pass "no dotfiles runtime dependency in desktop-integration files"

# Theme switch re-themes kitty + libadwaita atomically (Preview 2 QA: light
# shell with a dark terminal, or Adwaita-blue GTK4 under dark, is a
# half-applied desktop). Exercises the installed lib against the TMP stage.
export XDG_CONFIG_HOME="$TMP_HOME/.config" XDG_DATA_HOME="$TMP_HOME/.local/share"
export HOME="$TMP_HOME" REPO_ROOT="$REPO_ROOT"
bash -c '
    source "$REPO_ROOT/lib/hornero/apply-appearance.sh"
    _hornero_appearance_sync_kitty hornero-light
    grep -qx "include hornero-light.conf" "$XDG_CONFIG_HOME/kitty/kitty.conf" || exit 11
    _hornero_appearance_sync_recolor hornero-light
    cmp -s "$XDG_DATA_HOME/themes/Hornero-Light/gtk-4.0/recolor.css" \
           "$XDG_CONFIG_HOME/gtk-4.0/gtk.css" || exit 12
    _hornero_appearance_sync_kitty hornero-dark
    grep -qx "include hornero-dark.conf" "$XDG_CONFIG_HOME/kitty/kitty.conf" || exit 13
    _hornero_appearance_sync_recolor hornero-dark
    cmp -s "$XDG_DATA_HOME/themes/Hornero-Dark/gtk-4.0/recolor.css" \
           "$XDG_CONFIG_HOME/gtk-4.0/gtk.css" || exit 14
  ' || fail "theme switch does not re-theme kitty + recolor atomically ($?)"
pass "theme switch re-themes kitty + libadwaita recolor"

echo "test_desktop_integration.sh: ALL GREEN"
