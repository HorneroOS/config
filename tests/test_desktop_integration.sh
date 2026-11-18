#!/usr/bin/env bash
# test_desktop_integration.sh - desktop integration: Hyprland Signal
# colours, Kitty per-theme palettes, Qt artifacts, and Hornero Signal Night
# factory defaults. Materializes into a temp HOME; no system mutation.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_HOME="$(mktemp -d)"
trap 'rm -rf "$TMP_HOME"' EXIT

"$REPO_ROOT/scripts/materialize.sh" --dest "$TMP_HOME" >/dev/null

pass() { echo "TEST-PASS: $1"; }
fail() { echo "TEST-FAIL: $1" >&2; exit 1; }

# --- (1) Hyprland Signal integration ------------------------------------------
# Factory borders/groups come from Signal Night roles (generated): amber
# signal = active, rule = inactive, celeste cue = locked groups.
python3 - "$REPO_ROOT" "$TMP_HOME/.config/hypr/hyprland.lua.d" <<'PY' || fail "Hyprland factory colours drift from Signal Night"
import json, sys
from pathlib import Path
root, hypr = Path(sys.argv[1]), Path(sys.argv[2])
p = json.loads((root / "profiles/themes/hornero-signal-night/theme.json").read_text())["palette"]
lua = (hypr / "smart-colors.lua").read_text().lower()
for role in ("signal", "rule", "ruleStrong", "cue", "cueWell", "raised", "shadow"):
    assert p[role].lstrip("#").lower() in lua, role
static = (hypr / "static.lua").read_text()
assert "border_size = 1," in static and "rounding = 5," in static, "Signal geometry"
assert "rgba(" not in static, "static.lua must not override generated colours"
day = json.loads((root / "profiles/themes/hornero-signal-day/theme.json").read_text())["palette"]
assert day["signal"].lstrip("#").lower() in (hypr / "signal-day.lua").read_text().lower()
PY
pass "hyprland factory borders/groups/shadow are Signal Night roles; day fragment ships"
grep -q "source = ~/.cache/hornero/smart-colors/colors-hyprlock.conf" \
  "$TMP_HOME/.config/hypr/hyprlock.conf" \
  || fail "hyprlock.conf does not source the canonical Smart Colors override"
python3 - "$TMP_HOME/.config/hypr/hyprlock.conf" <<'PY' || fail "hyprlock.conf variable order"
import sys
text = open(sys.argv[1]).read()
src = text.index("source = ~/.cache/hornero/smart-colors/colors-hyprlock.conf")
assert text.index("$hs_ground =") < src < text.index("background {"), "vars, then source, then widgets"
assert "IBM Plex" in text and "blur_passes" not in text
PY
pass "hyprlock: fallback vars, then the Smart Colors source, then matte Plex widgets"
if grep -q 'text = \$DATE\|text = cmd' "$TMP_HOME/.config/hypr/hyprlock.conf"; then
  fail "hyprlock.conf carries a dead date label"
fi
pass "hyprlock carries no dead date label"

# --- (2) Kitty palettes --------------------------------------------------------
for tid in $(python3 -c "import glob,os;print(' '.join(sorted(os.path.basename(os.path.dirname(p)) for p in glob.glob('$REPO_ROOT/profiles/themes/*/theme.json'))))"); do
  [[ -f "$TMP_HOME/.config/kitty/$tid.conf" ]] || fail "kitty $tid.conf not materialized"
done
grep -qx "include hornero-signal-night.conf" "$TMP_HOME/.config/kitty/kitty.conf" \
  || fail "kitty.conf does not include the Signal Night factory palette"
if grep -q "smart-colors/colors-kitty.conf" "$TMP_HOME/.config/kitty/kitty.conf"; then
  fail "kitty.conf still includes the retired wallpaper palette cache"
fi
grep -qx "font_family IBM Plex Mono" "$TMP_HOME/.config/kitty/kitty.conf" \
  || fail "kitty.conf font is not IBM Plex Mono"
pass "kitty ships every theme palette, includes Signal Night, uses IBM Plex Mono"

# --- (3) Qt decision -----------------------------------------------------------
[[ -f "$TMP_HOME/.config/qt6ct/qt6ct.conf" ]] \
  || fail "qt6ct.conf not materialized"
grep -q "^style=Fusion" "$TMP_HOME/.config/qt6ct/qt6ct.conf" \
  || fail "qt6ct.conf does not pin Fusion style"
grep -q "Papirus-Dark" "$TMP_HOME/.config/qt6ct/qt6ct.conf" \
  || fail "qt6ct.conf missing factory icon theme"
grep -q "^general=IBM Plex Sans," "$TMP_HOME/.config/qt6ct/qt6ct.conf" \
  && grep -q "^fixed=IBM Plex Mono," "$TMP_HOME/.config/qt6ct/qt6ct.conf" \
  || fail "qt6ct.conf fonts are not IBM Plex"
grep -q '"QT_QPA_PLATFORMTHEME", "qt6ct:qt5ct"' \
  "$TMP_HOME/.config/hypr/hyprland.lua.d/environment.lua" \
  || fail "hypr environment no longer pins the qt6ct:qt5ct platformtheme list"
[[ -f "$TMP_HOME/.config/qt5ct/qt5ct.conf" ]] \
  || fail "qt5ct.conf not materialized"
grep -q "^custom_palette=true" "$TMP_HOME/.config/qt5ct/qt5ct.conf" \
  || fail "qt5ct.conf does not enable the Signal palette"
# Upgrade safety: re-materializing must not clobber a user-edited qt6ct.conf.
printf '[Appearance]\nstyle=Breeze\n' >"$TMP_HOME/.config/qt6ct/qt6ct.conf"
bash "$REPO_ROOT/scripts/materialize.sh" --dest "$TMP_HOME" >/dev/null 2>&1 || true
grep -q "^style=Breeze" "$TMP_HOME/.config/qt6ct/qt6ct.conf" \
  || fail "materialize overwrote a user-edited qt6ct.conf"
[[ -f "$REPO_ROOT/docs/QT_DECISION.md" ]] \
  || fail "docs/QT_DECISION.md missing"
if find "$TMP_HOME" -iname "*kvantum*" | grep -q .; then
  fail "kvantum artifacts materialized despite deferral"
fi
pass "qt6ct factory default + platformtheme pin, kvantum deferred"
for _qt in "$REPO_ROOT"/desktop/qt6ct/colors/*.conf; do
  _qt="$(basename "$_qt")"
  cmp -s "$REPO_ROOT/desktop/qt6ct/colors/$_qt" "$TMP_HOME/.config/qt6ct/colors/$_qt" \
    || fail "qt6ct colors/$_qt not materialized byte-exact"
  for _key in active_colors inactive_colors disabled_colors; do
    grep -q "^$_key=" "$TMP_HOME/.config/qt6ct/colors/$_qt" \
      || fail "qt6ct colors/$_qt missing $_key"
  done
done
for _qt in "$REPO_ROOT"/desktop/qt5ct/colors/*.conf; do
  _qt="$(basename "$_qt")"
  [[ "$(grep '^active_colors=' "$REPO_ROOT/desktop/qt5ct/colors/$_qt" | tr -cd ',' | wc -c)" -eq 20 ]] \
    || fail "qt5ct colors/$_qt is not 21 QPalette roles"
done
python3 "$REPO_ROOT/scripts/generate-appearance.py" --check >/dev/null \
  || fail "generated qt6ct/kitty/GTK files drift from the themes"
pass "qt6ct per-theme palettes materialized and drift-free"

# --- (4) Factory defaults: fresh boot = Hornero Signal Night + Cockpit ----------
[[ -f "$TMP_HOME/.local/share/hornero/factory.json" ]] \
  || fail "factory.json not materialized"
python3 - "$REPO_ROOT/profiles/factory.json" "$REPO_ROOT/profiles/themes" <<'PY' || fail "factory record"
import json, sys
d = json.load(open(sys.argv[1]))
base = sys.argv[2]
assert d["defaultTheme"] == "hornero-signal-night"
assert d["availableThemes"] == ["hornero-signal-night", "hornero-signal-day", "hornero-signal-contrast"]
assert d["shellLayout"]["preset"] == "cockpit"
assert (d["fonts"]["sans"], d["fonts"]["mono"], d["fonts"]["display"]) == (
    "IBM Plex Sans", "IBM Plex Mono", "IBM Plex Sans Condensed")
assert "extra/ttf-ibm-plex" in d["fonts"]["packages"]
assert "material symbols" not in json.dumps(d).lower() and "rubik" not in json.dumps(d).lower()
assert d["icons"]["theme"] == "Papirus-Dark"
for tid in d["availableThemes"]:
    assert json.load(open(f"{base}/{tid}/theme.json"))["id"] == tid
night = json.load(open(f"{base}/hornero-signal-night/theme.json"))
assert d["wallpaper"]["defaultWallpaper"] == night["defaultWallpaper"]
assert d["gtk"]["theme"] == night["gtkTheme"] and d["gtk"]["iconTheme"] == night["iconTheme"]
PY
pass "factory.json declares Signal Night + Cockpit + IBM Plex, matching the recipes"

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

# Both compositors must start a polkit authentication agent (hornero#366):
# without a registered session agent every pkexec flow fails with
# "No session for cookie". The polkit-gnome package itself comes from the
# edition catalogue desktop set; these lines are the config-side contract.
grep -Fq '/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1' \
  "$TMP_HOME/.config/hypr/hyprland.lua.d/autostart.lua" \
  || fail "Hyprland autostart does not start the polkit agent"
grep -Fq 'spawn-at-startup "/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1"' \
  "$TMP_HOME/.config/niri/config.kdl" \
  || fail "Niri config does not spawn the polkit agent at startup"
pass "Hyprland and Niri both start the polkit authentication agent"

# Optional terminal configs use their native lookup paths and all share the
# same dynamic Hornero palette output. Kitty remains Exo's default terminal.
grep -Fq 'import = ["hornero-signal-night.toml", "hornero-colors.toml"]' \
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
    if integration["id"] == "kitty":
        # Kitty switches its include line to the shipped <theme-id>.conf.
        assert (root / "desktop/kitty" / integration["palette"]).is_file()
    else:
        output_path = integration["palettePath"].replace("{config}", "${XDG_CONFIG_HOME:-$HOME/.config}")
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
import json, re, sys, tomllib
from pathlib import Path
root = Path(sys.argv[1])
for tid in ("hornero-signal-night", "hornero-signal-day"):
    theme = json.loads((root / "profiles/themes" / tid / "theme.json").read_text())
    toml = tomllib.loads((root / "desktop/alacritty" / f"{tid}.toml").read_text())
    assert toml["colors"]["primary"]["background"] == theme["palette"]["base"]
    assert toml["colors"]["primary"]["foreground"] == theme["palette"]["ink"]
    assert list(toml["colors"]["normal"].values()) + list(toml["colors"]["bright"].values()) == theme["terminal"]
night = json.loads((root / "profiles/themes/hornero-signal-night/theme.json").read_text())
ghostty = dict(re.findall(r"^palette = ([0-9]+)=(#[0-9A-F]{6})$",
               (root / "desktop/ghostty/themes/Hornero Dynamic").read_text(), re.M))
assert [ghostty[str(i)] for i in range(16)] == night["terminal"]
PY
pass "Alacritty static variants and Ghostty fallback match the Signal theme roles"
# No runtime dependency on ulises-jeremias/dotfiles in anything new or
# materialized: that repo is a read-only extraction source (provenance
# mentions in DECISIONS/docs stay allowlisted per AGENTS.md).
# NOTE: this test file itself is excluded from the search below because it
# necessarily spells out the forbidden patterns to assert their absence.
if grep -rn "git clone.*dotfiles\|curl.*dotfiles\|wget.*dotfiles\|github.com/ulises-jeremias/dotfiles.*clone\|raw.githubusercontent.*dotfiles" \
    "$REPO_ROOT/desktop/kitty" "$REPO_ROOT/desktop/alacritty" "$REPO_ROOT/desktop/ghostty" \
    "$REPO_ROOT/desktop/hypr" "$REPO_ROOT/desktop/qt6ct" \
    "$REPO_ROOT/profiles/factory.json" "$REPO_ROOT/lib/hornero/signal_render.py" \
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
    _hornero_appearance_sync_kitty hornero-signal-day
    grep -qx "include hornero-signal-day.conf" "$XDG_CONFIG_HOME/kitty/kitty.conf" || exit 11
    _hornero_appearance_sync_recolor hornero-signal-day
    cmp -s "$XDG_DATA_HOME/themes/Hornero-Signal-Day/gtk-4.0/recolor.css" \
           "$XDG_CONFIG_HOME/gtk-4.0/gtk.css" || exit 12
    _hornero_appearance_sync_kitty pampa
    grep -qx "include pampa.conf" "$XDG_CONFIG_HOME/kitty/kitty.conf" || exit 15
    _hornero_appearance_sync_kitty hornero-signal-night
    grep -qx "include hornero-signal-night.conf" "$XDG_CONFIG_HOME/kitty/kitty.conf" || exit 13
    _hornero_appearance_sync_recolor catppuccin-latte
    cmp -s "$XDG_DATA_HOME/themes/Hornero-Signal-Day/gtk-4.0/recolor.css" \
           "$XDG_CONFIG_HOME/gtk-4.0/gtk.css" || exit 14
  ' || fail "theme switch does not re-theme kitty + recolor atomically ($?)"
pass "theme switch re-themes kitty + libadwaita recolor"

echo "test_desktop_integration.sh: ALL GREEN"
