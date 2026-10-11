# shellcheck shell=bash
# Shared appearance apply pipeline (QS-down / CLI fallback).
# Theme packs are apply-once recipes — this never writes a "current theme" id.

# All persisted appearance state uses the Hornero XDG roots.
HORNERO_THEMES_DIR="${HORNERO_THEMES_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/hornero/themes}"
HORNERO_WALLPAPERS_DIR="${HORNERO_WALLPAPERS_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/hornero/wallpapers}"
HORNERO_STATE_DIR="${HORNERO_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/hornero}"
HORNERO_CACHE_DIR="${HORNERO_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/hornero}"
HORNERO_WALLPAPER_POINTER_FILE="${HORNERO_WALLPAPER_POINTER_FILE:-$HORNERO_STATE_DIR/wallpaper/path}"
HORNERO_SCHEME_STATE_FILE="${HORNERO_SCHEME_STATE_FILE:-$HORNERO_STATE_DIR/scheme/state.json}"
HORNERO_SCHEME_FILE="${HORNERO_SCHEME_FILE:-$HORNERO_CACHE_DIR/smart-colors/scheme.json}"
HORNERO_M3_SCRIPT="${HORNERO_M3_SCRIPT:-$HOME/.local/lib/hornero/generate-m3-colors.py}"
HORNERO_PICTURES_WALLPAPERS="${HORNERO_PICTURES_WALLPAPERS:-$HOME/Pictures/Wallpapers}"
HORNERO_HYPRLOCK_COLORS="${HORNERO_HYPRLOCK_COLORS:-$HORNERO_CACHE_DIR/smart-colors/colors-hyprlock.conf}"

_hornero_appearance_resolve_theme_json() {
  printf '%s\n' "$HORNERO_THEMES_DIR/${1:-}/theme.json"
}
_hornero_appearance_resolve_state_file() {
  printf '%s\n' "$HORNERO_SCHEME_STATE_FILE"
}
_hornero_appearance_pointer_for_write() {
  printf '%s\n' "$HORNERO_WALLPAPER_POINTER_FILE"
}
_hornero_appearance_scheme_for_write() {
  printf '%s\n' "$HORNERO_SCHEME_FILE"
}

_hornero_appearance_json_get() {
	local file="$1" key="$2" default="${3:-}"
	python3 - "$file" "$key" "$default" << 'PY'
import json, sys
path, key, default = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
except Exception:
    print(default)
    raise SystemExit(0)
val = data.get(key, default)
if isinstance(val, bool):
    print("true" if val else "false")
elif val is None:
    print(default)
else:
    print(val)
PY
}

_hornero_appearance_write_pointer() {
	local path="$1"
	local target
	target="$(_hornero_appearance_pointer_for_write)"
	mkdir -p "$(dirname "$target")"
	printf '%s\n' "$path" > "$target"
}

_hornero_appearance_normalize_scheme_type() {
	local raw="${1:-tonal-spot}"
	raw=$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]' | tr '_' '-' | tr -d ' ')
	case "$raw" in
		vibrant | expressive | fidelity | content | neutral | monochrome) printf '%s\n' "$raw" ;;
		tonalspot | tonal-spot) printf 'tonal-spot\n' ;;
		*) printf 'tonal-spot\n' ;;
	esac
}

# Resolve gtk-application-prefer-dark independently of shell darkMode when possible.
# Priority: theme.json gtkPreferDark → Light/Dark in gtk theme name → shell mode.
_hornero_appearance_resolve_gtk_prefer() {
	local config_json="${1:-}"
	local dark_mode="${2:-dark}"
	local gtk_theme="${3:-}"
	local explicit=""

	if [[ -n $config_json && -f $config_json ]]; then
		explicit="$(_hornero_appearance_json_get "$config_json" gtkPreferDark "")"
	fi
	case "$explicit" in
		true | false)
			printf '%s\n' "$explicit"
			return 0
			;;
	esac

	local gtk_lc
	gtk_lc=$(printf '%s' "$gtk_theme" | tr '[:upper:]' '[:lower:]')
	case "$gtk_lc" in
		*light*)
			printf 'false\n'
			;;
		*dark*)
			printf 'true\n'
			;;
		*)
			if [[ $dark_mode == "light" ]]; then
				printf 'false\n'
			else
				printf 'true\n'
			fi
			;;
	esac
}

_hornero_appearance_resolve_theme_wallpaper() {
	local theme_id="$1"
	local wallpaper_dir="$2"
	local default_name="$3"
	local override="${4:-}"
	local candidate=""

	if [[ -n $override ]]; then
		candidate="$(readlink -f "$override" 2> /dev/null || true)"
		[[ -n ${candidate:-} && -f $candidate ]] && {
			printf '%s\n' "$candidate"
			return 0
		}
	fi

	for base in "$HORNERO_PICTURES_WALLPAPERS/$wallpaper_dir" "$HORNERO_WALLPAPERS_DIR/$wallpaper_dir" "$HORNERO_WALLPAPERS_DIR/$wallpaper_dir"; do
		if [[ -n $default_name && -f $base/$default_name ]]; then
			readlink -f "$base/$default_name"
			return 0
		fi
	done

	for base in "$HORNERO_PICTURES_WALLPAPERS/$wallpaper_dir" "$HORNERO_WALLPAPERS_DIR/$wallpaper_dir" "$HORNERO_WALLPAPERS_DIR/$wallpaper_dir"; do
		[[ -d $base ]] || continue
		candidate="$(
			find -L "$base" -maxdepth 1 \( -type f -o -type l \) \
				\( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" \
				-o -iname "*.gif" -o -iname "*.bmp" \) 2> /dev/null | sort | head -n 1 || true
		)"
		[[ -n ${candidate:-} && -f $candidate ]] && {
			printf '%s\n' "$candidate"
			return 0
		}
	done
	return 1
}

# Re-apply persisted GTK color-scheme policy (follow tracks shell mode).
_hornero_appearance_sync_gtk_color_scheme() {
	if command -v hornero-gtk-theme > /dev/null 2>&1; then
		hornero-gtk-theme -q sync-color-scheme > /dev/null 2>&1 || true
	elif [[ -f $HOME/.local/lib/hornero/gtk-theme-manager.sh ]]; then
		# shellcheck source=/dev/null
		source "$HOME/.local/lib/hornero/gtk-theme-manager.sh" 2> /dev/null || true
		if declare -f sync_gtk_color_scheme > /dev/null 2>&1; then
			sync_gtk_color_scheme > /dev/null 2>&1 || true
		elif declare -f apply_gtk_color_scheme > /dev/null 2>&1; then
			apply_gtk_color_scheme follow > /dev/null 2>&1 || true
		fi
	fi
}

# Switch the installed kitty.conf include to the theme variant so the
# terminal re-themes atomically with the rest (Preview 2 QA: light shell
# with a dark terminal is a half-applied desktop). Best-effort reload via
# SIGUSR1; a missing variant file or kitty.conf skips silently.
_hornero_appearance_sync_kitty() {
	local theme_id="${1:-}"
	local kitty_dir="${XDG_CONFIG_HOME:-$HOME/.config}/kitty"
	local variant="$kitty_dir/${theme_id}.conf"
	[[ -f $kitty_dir/kitty.conf && -f $variant ]] || return 0
	if grep -qE '^include (hornero-(dark|light)|pampa)\.conf$' "$kitty_dir/kitty.conf"; then
		sed -i -E "s#^include (hornero-(dark|light)|pampa)[.]conf\$#include ${theme_id}.conf#" "$kitty_dir/kitty.conf"
	fi
	pkill -SIGUSR1 -x kitty > /dev/null 2>&1 || true
}

# Swap the libadwaita recoloring to the theme variant. libadwaita apps
# ignore gtk.css theme trees (stock Adwaita blue accents) unless
# ~/.config/gtk-4.0/gtk.css redefines the public palette; the per-variant
# recolor.css files ship in the installed theme trees and are test-gated
# against theme.json (tests/test_gtk_theme.sh).
_hornero_appearance_sync_recolor() {
	local theme_id="${1:-}"
	local tree=""
	case "$theme_id" in
		hornero-dark) tree="Hornero-Dark" ;;
		hornero-light) tree="Hornero-Light" ;;
		pampa) tree="Hornero-Pampa" ;;
		*) return 0 ;;
	esac
	local src="${XDG_DATA_HOME:-$HOME/.local/share}/themes/$tree/gtk-4.0/recolor.css"
	local dest="${XDG_CONFIG_HOME:-$HOME/.config}/gtk-4.0/gtk.css"
	[[ -f $src ]] || return 0
	mkdir -p "$(dirname "$dest")"
	cp -f "$src" "$dest"
}

# Point qt6ct at the theme's generated palette. Qt6 Widgets apps read
# ~/.config/qt6ct/qt6ct.conf through QT_QPA_PLATFORMTHEME=qt6ct; the
# per-theme colors/<id>.conf files are generated from canonical tokens
# (scripts/generate-qt-schemes.py) and materialized with the rest of
# desktop/qt6ct. Line-edit preserves the file's comments (no INI
# rewrite). Graceful no-op when the scheme is absent (uncurated theme).
_hornero_appearance_sync_qt() {
	local theme_id="${1:-}"
	local qt_dir="${XDG_CONFIG_HOME:-$HOME/.config}/qt6ct"
	local scheme="$qt_dir/colors/${theme_id}.conf"
	local conf="$qt_dir/qt6ct.conf"
	[[ -f $scheme && -f $conf ]] || return 0
	python3 - "$conf" "$scheme" <<'PY' || return 0
import sys
conf_path, scheme_path = sys.argv[1], sys.argv[2]
lines = open(conf_path, encoding="utf-8").read().splitlines(keepends=True)
out, in_appearance = [], False
seen_palette, seen_path = False, False
for line in lines:
    stripped = line.strip()
    if stripped.startswith("["):
        in_appearance = stripped == "[Appearance]"
    elif in_appearance:
        if stripped.startswith("custom_palette"):
            line = "custom_palette=true\n"
            seen_palette = True
        elif stripped.startswith("color_scheme_path"):
            line = f"color_scheme_path={scheme_path}\n"
            seen_path = True
    out.append(line)
# Ensure both keys exist even if the group had neither: insert right
# after the [Appearance] header (or append the group).
text = "".join(out)
if not seen_palette or not seen_path:
    header = "[Appearance]\n"
    extra = ""
    if not seen_palette:
        extra += "custom_palette=true\n"
    if not seen_path:
        extra += f"color_scheme_path={scheme_path}\n"
    if header in text:
        text = text.replace(header, header + extra, 1)
    else:
        text = text.rstrip("\n") + "\n" + header + extra
    out = text.splitlines(keepends=True)
open(conf_path, "w", encoding="utf-8").writelines(out)
PY
}

# Pack recipe → canonical gtkColorScheme policy.
_hornero_appearance_resolve_gtk_color_scheme() {
	local config_json="${1:-}"
	local dark_mode="${2:-dark}"
	local gtk_theme="${3:-}"
	local explicit=""

	if [[ -n $config_json && -f $config_json ]]; then
		explicit="$(_hornero_appearance_json_get "$config_json" gtkColorScheme "")"
	fi
	case "$explicit" in
		follow | default | prefer-light | prefer-dark)
			printf '%s\n' "$explicit"
			return 0
			;;
		light)
			printf 'prefer-light\n'
			return 0
			;;
		dark)
			printf 'prefer-dark\n'
			return 0
			;;
		auto)
			printf 'default\n'
			return 0
			;;
	esac

	local prefer
	prefer="$(_hornero_appearance_resolve_gtk_prefer "$config_json" "$dark_mode" "$gtk_theme")"
	if [[ $prefer == "false" ]]; then
		printf 'prefer-light\n'
	else
		printf 'prefer-dark\n'
	fi
}

_hornero_appearance_run_palette() {
	local wallpaper="$1"
	local scheme_type="$2"
	local dark_mode="$3"

	if ! command -v wal > /dev/null 2>&1; then
		echo "apply-appearance: wal not found" >&2
		return 1
	fi
	# Drop any prior wal→image symlink before wal runs; echoing a path through
	# that symlink would truncate the wallpaper file itself.
	mkdir -p "$HOME/.cache/wal"
	rm -f "$HOME/.cache/wal/wal"
	if [[ $dark_mode == "light" ]]; then
		wal -i "$wallpaper" -q -l || return 1
	else
		wal -i "$wallpaper" -q || return 1
	fi

	_hornero_appearance_write_pointer "$wallpaper"
	rm -f "$HOME/.cache/wal/wal"
	printf '%s\n' "$wallpaper" > "$HOME/.cache/wal/wal"

	[[ -f $HORNERO_M3_SCRIPT ]] || {
		echo "apply-appearance: missing generate-m3-colors.py" >&2
		return 1
	}
	# Prefer system Python with materialyoucolor over pyenv shims on PATH.
	# shellcheck source=/dev/null
	source "${HOME}/.local/lib/hornero/python-m3.sh" 2> /dev/null || true
	local scheme_out
	scheme_out="$(_hornero_appearance_scheme_for_write)"
	mkdir -p "$(dirname "$scheme_out")"
	if declare -f hornero_run_m3_colors > /dev/null 2>&1; then
		hornero_run_m3_colors \
			--image "$wallpaper" \
			--scheme-type "$scheme_type" \
			--mode "$dark_mode" \
			--output "$scheme_out" || return 1
	elif command -v hornero-m3-colors > /dev/null 2>&1; then
		hornero-m3-colors \
			--image "$wallpaper" \
			--scheme-type "$scheme_type" \
			--mode "$dark_mode" \
			--output "$scheme_out" || return 1
	else
		python3 "$HORNERO_M3_SCRIPT" \
			--image "$wallpaper" \
			--scheme-type "$scheme_type" \
			--mode "$dark_mode" \
			--output "$scheme_out" || return 1
	fi

	if command -v hornero-color-scheme > /dev/null 2>&1; then
		hornero-color-scheme sync-state > /dev/null 2>&1 || return 1
	fi
	_hornero_appearance_sync_gtk_color_scheme "$dark_mode"
	if command -v hornero-hyprlock-theme > /dev/null 2>&1; then
		hornero-hyprlock-theme > /dev/null 2>&1 || true
	fi
	if command -v hyprctl > /dev/null 2>&1; then
		hyprctl reload > /dev/null 2>&1 || true
	fi
	return 0
}

# Apply a theme pack once (no persistent current-theme state).
hornero_apply_theme() {
	local theme_id="${1:-}"
	local wallpaper_override="${2:-}"

	[[ -n $theme_id ]] || {
		echo "hornero_apply_theme: theme id required" >&2
		return 1
	}
	local config_json
	config_json="$(_hornero_appearance_resolve_theme_json "$theme_id")"
	[[ -f $config_json ]] || {
		echo "hornero_apply_theme: theme not found: $theme_id" >&2
		return 1
	}

	local scheme_type dark_mode_raw dark_mode gtk_theme icon_theme theme_name wallpaper_dir default_wp wallpaper
	scheme_type="$(_hornero_appearance_normalize_scheme_type "$(_hornero_appearance_json_get "$config_json" schemeType tonal-spot)")"
	dark_mode_raw="$(_hornero_appearance_json_get "$config_json" darkMode true)"
	if [[ $dark_mode_raw == "false" ]]; then
		dark_mode="light"
	else
		dark_mode="dark"
	fi
	gtk_fallback="Hornero-Dark"
	[[ $dark_mode == "light" ]] && gtk_fallback="Hornero-Light"
	gtk_theme="$(_hornero_appearance_json_get "$config_json" gtkTheme "$gtk_fallback")"
	icon_theme="$(_hornero_appearance_json_get "$config_json" iconTheme Numix-Circle)"
	theme_name="$(_hornero_appearance_json_get "$config_json" name "$theme_id")"
	wallpaper_dir="$(_hornero_appearance_json_get "$config_json" wallpaperDir "$theme_id")"
	default_wp="$(_hornero_appearance_json_get "$config_json" defaultWallpaper "")"

	wallpaper="$(_hornero_appearance_resolve_theme_wallpaper "$theme_id" "$wallpaper_dir" "$default_wp" "$wallpaper_override" || true)"
	[[ -n ${wallpaper:-} && -f $wallpaper ]] || {
		echo "hornero_apply_theme: no wallpaper for theme $theme_id" >&2
		return 1
	}

	_hornero_appearance_run_palette "$wallpaper" "$scheme_type" "$dark_mode" || return 1

	local gtk_policy
	gtk_policy="$(_hornero_appearance_resolve_gtk_color_scheme "$config_json" "$dark_mode" "$gtk_theme")"

	if command -v hornero-gtk-theme > /dev/null 2>&1; then
		if [[ -n $gtk_theme && $gtk_theme != "auto" ]]; then
			hornero-gtk-theme -q apply "$gtk_theme" "${icon_theme:-Numix-Circle}" "$gtk_policy" > /dev/null 2>&1 || true
		elif [[ $gtk_theme == "auto" ]]; then
			hornero-gtk-theme -q theme "$theme_id" > /dev/null 2>&1 || true
			hornero-gtk-theme -q color-scheme "$gtk_policy" > /dev/null 2>&1 || true
		elif [[ -n $icon_theme ]]; then
			hornero-gtk-theme -q set-icons "$icon_theme" > /dev/null 2>&1 || true
			hornero-gtk-theme -q color-scheme "$gtk_policy" > /dev/null 2>&1 || true
		else
			hornero-gtk-theme -q color-scheme "$gtk_policy" > /dev/null 2>&1 || true
		fi
	elif [[ -n $icon_theme ]] && command -v gsettings > /dev/null 2>&1; then
		gsettings set org.gnome.desktop.interface icon-theme "$icon_theme" > /dev/null 2>&1 || true
		_hornero_appearance_sync_gtk_color_scheme
	else
		_hornero_appearance_sync_gtk_color_scheme
	fi

	_hornero_appearance_sync_kitty "$theme_id"
	_hornero_appearance_sync_recolor "$theme_id"
	_hornero_appearance_sync_qt "$theme_id"

	if [[ -f $HOME/.local/lib/hornero/snappy-switcher-manager.sh ]]; then
		# shellcheck source=/dev/null
		source "$HOME/.local/lib/hornero/snappy-switcher-manager.sh" 2> /dev/null || true
		if declare -f apply_theme_snappy_switcher_theme > /dev/null 2>&1; then
			apply_theme_snappy_switcher_theme "$theme_id" > /dev/null 2>&1 || true
		fi
	fi

	if command -v notify-send > /dev/null 2>&1; then
		notify-send "Hornero" "${theme_name} theme applied" > /dev/null 2>&1 || true
	fi
	return 0
}

# Wallpaper-only: live mode/flavour from scheme state.
hornero_apply_wallpaper_only() {
	local wallpaper="${1:-}"
	wallpaper="$(readlink -f "$wallpaper" 2> /dev/null || true)"
	[[ -n ${wallpaper:-} && -f $wallpaper ]] || {
		echo "hornero_apply_wallpaper_only: wallpaper not found" >&2
		return 1
	}

	local scheme_type="tonal-spot" dark_mode="dark"
	local state_file
	state_file="$(_hornero_appearance_resolve_state_file)"
	if [[ -f $state_file ]]; then
		scheme_type="$(_hornero_appearance_normalize_scheme_type "$(_hornero_appearance_json_get "$state_file" flavour tonal-spot)")"
		dark_mode="$(_hornero_appearance_json_get "$state_file" mode dark)"
		[[ $dark_mode == "light" || $dark_mode == "dark" ]] || dark_mode="dark"
	fi

	_hornero_appearance_run_palette "$wallpaper" "$scheme_type" "$dark_mode"
}
