#!/usr/bin/env bash

## Copyright (C) 2019-2025 Ulises Jeremias Cornejo Fandos
## Licensed under MIT.
##
## GTK Theme Manager for Appearance Integration
##
## This library provides functions to manage GTK themes for the appearance system,
## allowing for automatic theme switching based on theme preferences and color schemes.
##
## Usage:
##     source ~/.local/lib/hornero/gtk-theme-manager.sh
##     apply_gtk_theme "theme-name" "icon-theme-name" [prefer-dark]
##     detect_optimal_gtk_theme
##     apply_theme_gtk_theme
##

set -euo pipefail

# GTK configuration paths
readonly GTK2_CONFIG="$HOME/.gtkrc-2.0"
readonly GTK3_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/gtk-3.0/settings.ini"
readonly GTK4_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/gtk-4.0/settings.ini"
# Appearance state and theme packs use one Hornero-owned XDG namespace.
HORNERO_SCHEME_STATE="${HORNERO_SCHEME_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/hornero/scheme/state.json}"
HORNERO_THEMES_DIR="${HORNERO_THEMES_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/hornero/themes}"

_gtk_resolve_state_for_read() { printf '%s\n' "$HORNERO_SCHEME_STATE"; }
_gtk_resolve_state_for_write() { printf '%s\n' "$HORNERO_SCHEME_STATE"; }
_gtk_resolve_theme_json() { printf '%s\n' "$HORNERO_THEMES_DIR/${1:-}/theme.json"; }

# Function to log messages
log() {
	local level="$1"
	shift
	local message="$*"
	local timestamp
	timestamp="$(date '+%Y-%m-%d %H:%M:%S')"

	echo "[$timestamp] [GTK-THEME] [$level] $message" >&2
}

# Function to check if a GTK theme is installed
is_gtk_theme_installed() {
	local theme_name="$1"

	# Check in common theme directories
	local theme_dirs=(
		"/usr/share/themes"
		"/usr/local/share/themes"
		"$HOME/.themes"
		"$HOME/.local/share/themes"
	)

	for theme_dir in "${theme_dirs[@]}"; do
		if [[ -d "$theme_dir/$theme_name" ]]; then
			return 0
		fi
	done

	return 1
}

# Function to check if an icon theme is installed
is_icon_theme_installed() {
	local icon_theme="$1"

	# Check in common icon directories
	local icon_dirs=(
		"/usr/share/icons"
		"/usr/local/share/icons"
		"$HOME/.icons"
		"$HOME/.local/share/icons"
	)

	for icon_dir in "${icon_dirs[@]}"; do
		if [[ -d "$icon_dir/$icon_theme" ]]; then
			return 0
		fi
	done

	return 1
}

# Function to apply GTK theme with fallbacks
apply_gtk_theme() {
	local gtk_theme="$1"
	local icon_theme="${2:-elementary}"

	log "INFO" "Applying GTK theme: $gtk_theme, icons: $icon_theme"

	# Validate theme availability with fallbacks
	if ! is_gtk_theme_installed "$gtk_theme"; then
		log "WARN" "GTK theme '$gtk_theme' not found, trying fallbacks..."

		# Keep GTK applications inside the Hornero appearance family. A missing
		# pack style falls back to the matching Hornero surface, never a random
		# third-party theme with unrelated geometry or colors.
		local effective_scheme fallback_theme
		effective_scheme="$(effective_gtk_color_scheme "${3:-follow}")"
		if [[ $effective_scheme == "prefer-light" ]] ||
			[[ $effective_scheme == "default" && $(read_live_shell_mode) == "light" ]]; then
			fallback_theme="Hornero-Signal-Day"
		else
			fallback_theme="Hornero-Signal"
		fi
		if is_gtk_theme_installed "$fallback_theme"; then
			gtk_theme="$fallback_theme"
			log "INFO" "Using Hornero fallback theme: $gtk_theme"
		fi

		if ! is_gtk_theme_installed "$gtk_theme"; then
			log "ERROR" "No suitable GTK theme found, keeping current theme"
			return 1
		fi
	fi

	# Validate icon theme with fallbacks
	if ! is_icon_theme_installed "$icon_theme"; then
		log "WARN" "Icon theme '$icon_theme' not found, trying fallbacks..."

		local fallback_icons=(
			"Numix-Circle"
			"elementary"
			"hicolor"
		)

		for fallback in "${fallback_icons[@]}"; do
			if is_icon_theme_installed "$fallback"; then
				icon_theme="$fallback"
				log "INFO" "Using fallback icon theme: $icon_theme"
				break
			fi
		done
	fi

	# Update GTK2 configuration
	if [[ -f $GTK2_CONFIG ]]; then
		sed -i "s/^gtk-theme-name=.*/gtk-theme-name=\"$gtk_theme\"/" "$GTK2_CONFIG"
		sed -i "s/^gtk-icon-theme-name=.*/gtk-icon-theme-name=\"$icon_theme\"/" "$GTK2_CONFIG"
		log "INFO" "Updated GTK2 configuration"
	else
		log "WARN" "GTK2 config not found, creating basic configuration"
		cat > "$GTK2_CONFIG" << EOF
# DO NOT EDIT! This file will be overwritten by LXAppearance.
# Any customization should be done in ~/.gtkrc-2.0.mine instead.

include "/home/\$USER/.gtkrc-2.0.mine"
gtk-theme-name="$gtk_theme"
gtk-icon-theme-name="$icon_theme"
gtk-font-name="sans 11"
gtk-cursor-theme-name="elementary"
gtk-cursor-theme-size=24
gtk-toolbar-style=GTK_TOOLBAR_ICONS
gtk-toolbar-icon-size=GTK_ICON_SIZE_SMALL_TOOLBAR
gtk-button-images=1
gtk-menu-images=1
gtk-enable-event-sounds=1
gtk-enable-input-feedback-sounds=0
gtk-xft-antialias=1
gtk-xft-hinting=1
gtk-xft-hintstyle="hintslight"
gtk-xft-rgba="rgb"
EOF
	fi

	# Update GTK3 configuration (color-scheme / prefer-dark is applied below).
	if [[ -f $GTK3_CONFIG ]]; then
		sed -i "s/^gtk-theme-name=.*/gtk-theme-name=$gtk_theme/" "$GTK3_CONFIG"
		sed -i "s/^gtk-icon-theme-name=.*/gtk-icon-theme-name=$icon_theme/" "$GTK3_CONFIG"
		log "INFO" "Updated GTK3 configuration"
	else
		log "WARN" "GTK3 config not found, creating configuration"
		mkdir -p "$(dirname "$GTK3_CONFIG")"
		cat > "$GTK3_CONFIG" << EOF
[Settings]
gtk-theme-name=$gtk_theme
gtk-icon-theme-name=$icon_theme
gtk-font-name=sans 11
gtk-cursor-theme-name=elementary
gtk-cursor-theme-size=24
gtk-toolbar-style=GTK_TOOLBAR_ICONS
gtk-toolbar-icon-size=GTK_ICON_SIZE_SMALL_TOOLBAR
gtk-button-images=1
gtk-menu-images=1
gtk-enable-event-sounds=1
gtk-enable-input-feedback-sounds=0
gtk-xft-antialias=1
gtk-xft-hinting=1
gtk-xft-hintstyle=hintslight
gtk-xft-rgba=rgb
gtk-modules=colorreload-gtk-module
EOF
	fi

	# Notify running GTK applications to reload themes
	if command -v gsettings > /dev/null 2>&1; then
		gsettings set org.gnome.desktop.interface gtk-theme "$gtk_theme" 2> /dev/null || true
		gsettings set org.gnome.desktop.interface icon-theme "$icon_theme" 2> /dev/null || true
		log "INFO" "Updated gsettings"
	fi

	_gtk_ini_set "$GTK4_CONFIG" "gtk-theme-name" "$gtk_theme"
	_gtk_ini_set "$GTK4_CONFIG" "gtk-icon-theme-name" "$icon_theme"

	# Color-scheme is independent of the GTK theme name. An explicit 3rd arg
	# (true/false or a gtkColorScheme policy) sets/persists policy; otherwise
	# re-apply the live policy so a theme-name change cannot clobber it.
	if [[ -n ${3:-} ]]; then
		local policy
		policy="$(normalize_gtk_color_scheme "$3")"
		if [[ $policy == "invalid" ]]; then
			log "WARN" "Unknown GTK color-scheme '$3', re-applying live policy"
			sync_gtk_color_scheme
		else
			apply_gtk_color_scheme "$policy"
		fi
	else
		sync_gtk_color_scheme
	fi

	log "INFO" "GTK theme applied successfully: $gtk_theme"
	return 0
}

# Canonical gtkColorScheme policy: follow | default | prefer-light | prefer-dark
# Aliases: light→prefer-light, dark→prefer-dark, auto→default.
normalize_gtk_color_scheme() {
	local raw
	raw="$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]' | tr '_' '-')"
	case "$raw" in
		follow | follow-mode | follow-theme | follow-theme-mode) printf 'follow\n' ;;
		default | auto | apps | apps-decide) printf 'default\n' ;;
		prefer-light | light) printf 'prefer-light\n' ;;
		prefer-dark | dark) printf 'prefer-dark\n' ;;
		true | 1 | yes) printf 'prefer-dark\n' ;;
		false | 0 | no) printf 'prefer-light\n' ;;
		*) printf 'invalid\n' ;;
	esac
}

# Shell mode = the applied theme's mode, read from the live Hornero Signal
# scheme (written by theme apply); legacy state.json only as a fallback.
read_live_shell_mode() {
	local mode="dark"
	local state_file
	local signal_scheme="${HORNERO_SIGNAL_SCHEME:-${XDG_STATE_HOME:-$HOME/.local/state}/hornero/signal/scheme.json}"
	state_file="$(_gtk_resolve_state_for_read)"
	if [[ -f $signal_scheme ]]; then
		mode="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1], encoding="utf-8")).get("mode", "dark"))' "$signal_scheme" 2> /dev/null || echo dark)"
	elif [[ -f $state_file ]]; then
		mode="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1], encoding="utf-8")).get("mode", "dark"))' "$state_file" 2> /dev/null || echo dark)"
	fi
	if [[ $mode == "light" || $mode == "dark" ]]; then
		printf '%s\n' "$mode"
	else
		printf 'dark\n'
	fi
}

# Persisted policy. Missing key → follow (GTK tracks shell mode).
read_live_gtk_color_scheme() {
	local policy=""
	local state_file
	state_file="$(_gtk_resolve_state_for_read)"
	if [[ -f $state_file ]]; then
		policy="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1], encoding="utf-8")).get("gtkColorScheme", "") or "")' "$state_file" 2> /dev/null || true)"
	fi
	policy="$(normalize_gtk_color_scheme "${policy:-follow}")"
	if [[ $policy == "invalid" ]]; then
		policy="follow"
	fi
	printf '%s\n' "$policy"
}

write_live_gtk_color_scheme() {
	local policy="$1"
	policy="$(normalize_gtk_color_scheme "$policy")"
	[[ $policy != "invalid" ]] || return 1
	local state_file
	state_file="$(_gtk_resolve_state_for_write)"
	mkdir -p "$(dirname "$state_file")" 2> /dev/null || true
	python3 - "$state_file" "$policy" << 'PY' || true
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
policy = sys.argv[2]
try:
    data = json.loads(path.read_text(encoding="utf-8"))
except Exception:
    data = {}
if not isinstance(data, dict):
    data = {}
data["gtkColorScheme"] = policy
# No "mode" here: the applied theme owns mode (live Signal scheme). A
# defaulted dark went stale on first write and broke later light applies
# (see tests/test_gtk_state.sh).
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
PY
}

# Resolve follow → prefer-light|prefer-dark from shell mode. Other policies pass through.
effective_gtk_color_scheme() {
	local policy
	policy="$(normalize_gtk_color_scheme "${1:-}")"
	if [[ $policy == "invalid" ]]; then
		policy="$(read_live_gtk_color_scheme)"
	fi
	if [[ $policy == "follow" ]]; then
		local mode
		mode="$(read_live_shell_mode)"
		if [[ $mode == "light" ]]; then
			printf 'prefer-light\n'
		else
			printf 'prefer-dark\n'
		fi
		return 0
	fi
	printf '%s\n' "$policy"
}

_gtk_ini_set() {
	local file="$1"
	local key="$2"
	local value="$3"
	mkdir -p "$(dirname "$file")" || return 1
	if [[ ! -f $file ]]; then
		printf '[Settings]\n%s=%s\n' "$key" "$value" > "$file" || return 1
		return 0
	fi
	if grep -q "^${key}=" "$file" 2> /dev/null; then
		sed -i "s|^${key}=.*|${key}=${value}|" "$file"
	else
		if ! grep -q '^\[Settings\]' "$file" 2> /dev/null; then
			printf '[Settings]\n' >> "$file"
		fi
		printf '%s=%s\n' "$key" "$value" >> "$file"
	fi
}

_gtk_write_prefer_dark() {
	local prefer_dark="$1"
	_gtk_ini_set "$GTK3_CONFIG" "gtk-application-prefer-dark-theme" "$prefer_dark"
	_gtk_ini_set "$GTK4_CONFIG" "gtk-application-prefer-dark-theme" "$prefer_dark"
}

# Sync GTK/libadwaita color-scheme without changing the theme name.
# Accepts follow|default|prefer-light|prefer-dark|light|dark.
# Persists gtkColorScheme in state.json — never writes shell `mode`.
apply_gtk_color_scheme() {
	local requested="${1:-follow}"
	local policy
	policy="$(normalize_gtk_color_scheme "$requested")"
	if [[ $policy == "invalid" ]]; then
		log "ERROR" "apply_gtk_color_scheme: expected follow|default|prefer-light|prefer-dark|light|dark (got: $requested)"
		return 1
	fi

	write_live_gtk_color_scheme "$policy"

	local effective prefer_dark="false" color_scheme="prefer-dark"
	effective="$(effective_gtk_color_scheme "$policy")"
	case "$effective" in
		default)
			prefer_dark="false"
			color_scheme="default"
			;;
		prefer-light)
			prefer_dark="false"
			color_scheme="prefer-light"
			;;
		*)
			prefer_dark="true"
			color_scheme="prefer-dark"
			;;
	esac

	_gtk_write_prefer_dark "$prefer_dark"

	if command -v gsettings > /dev/null 2>&1; then
		gsettings set org.gnome.desktop.interface gtk-application-prefer-dark-theme "$prefer_dark" > /dev/null 2>&1 || true
		gsettings set org.gnome.desktop.interface color-scheme "$color_scheme" > /dev/null 2>&1 || true
	fi
	log "INFO" "GTK color-scheme policy=$policy effective=$color_scheme"
	return 0
}

# Re-apply persisted policy (follow resolves from current shell mode).
sync_gtk_color_scheme() {
	apply_gtk_color_scheme "$(read_live_gtk_color_scheme)"
}

get_current_gtk_color_scheme() {
	read_live_gtk_color_scheme
}

# The GTK theme follows the applied Hornero Signal theme, never the
# wallpaper (RFC 0001). Prints "<gtk-theme>:<prefer-dark true|false>".
detect_optimal_gtk_theme() {
	local signal_scheme="${HORNERO_SIGNAL_SCHEME:-${XDG_STATE_HOME:-$HOME/.local/state}/hornero/signal/scheme.json}"
	local theme_id="" gtk_theme="" mode
	mode="$(read_live_shell_mode)"
	if [[ -f $signal_scheme ]]; then
		theme_id="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1], encoding="utf-8")).get("id", ""))' "$signal_scheme" 2> /dev/null || true)"
	fi
	if [[ -n $theme_id && -f "$(_gtk_resolve_theme_json "$theme_id")" ]]; then
		gtk_theme="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1], encoding="utf-8")).get("gtkTheme", ""))' "$(_gtk_resolve_theme_json "$theme_id")" 2> /dev/null || true)"
	fi
	if [[ -z $gtk_theme ]]; then
		if [[ $mode == "light" ]]; then gtk_theme="Hornero-Signal-Day"; else gtk_theme="Hornero-Signal"; fi
	fi
	local prefer_dark="true"
	[[ $mode == "light" ]] && prefer_dark="false"
	log "INFO" "GTK theme for the applied Signal theme: $gtk_theme (dark: $prefer_dark)"
	echo "$gtk_theme:$prefer_dark"
}

normalize_prefer_dark() {
	case "${1:-auto}" in
		true | 1 | yes | dark) echo "true" ;;
		false | 0 | no | light) echo "false" ;;
		*) echo "auto" ;;
	esac
}

# Apply GTK/icons from an appearance theme pack (one-shot recipe).
apply_theme_gtk_theme() {
	local theme_id="${1:-}"

	if [[ -z $theme_id ]]; then
		log "INFO" "No theme specified, following the applied Signal theme"
		local theme_info prefer_dark
		theme_info="$(detect_optimal_gtk_theme)"
		prefer_dark="$(normalize_prefer_dark "${theme_info#*:}")"
		apply_gtk_theme "${theme_info%:*}" "Papirus-Dark" "$prefer_dark"
		return
	fi

	log "INFO" "Applying GTK theme from appearance pack: $theme_id"

	local gtk_theme="" icon_theme="Numix-Circle" color_scheme="prefer-dark"
	local theme_json
	theme_json="$(_gtk_resolve_theme_json "$theme_id")"

	if [[ ! -f $theme_json ]]; then
		log "ERROR" "Theme pack not found: $theme_id ($theme_json)"
		return 1
	fi

	local meta
	meta="$(
		python3 - "$theme_json" << 'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
gtk = data.get("gtkTheme") or "auto"
icon = data.get("iconTheme") or "Papirus-Dark"
scheme = data.get("gtkColorScheme")
if scheme:
    prefer = str(scheme)
else:
    prefer = "prefer-light" if data.get("mode") == "light" else "prefer-dark"
print(gtk)
print(icon)
print(prefer)
PY
	)"
	gtk_theme="$(sed -n '1p' <<< "$meta")"
	icon_theme="$(sed -n '2p' <<< "$meta")"
	color_scheme="$(sed -n '3p' <<< "$meta")"
	color_scheme="$(normalize_gtk_color_scheme "$color_scheme")"
	if [[ $color_scheme == "invalid" ]]; then
		color_scheme="prefer-dark"
	fi

	if [[ -z $gtk_theme ]] || [[ $gtk_theme == "auto" ]]; then
		if [[ $color_scheme == "prefer-light" ]]; then
			gtk_theme="Hornero-Signal-Day"
		else
			gtk_theme="Hornero-Signal"
		fi
	fi

	apply_gtk_theme "$gtk_theme" "$icon_theme" "$color_scheme"
}

# Function to get current GTK theme
get_current_gtk_theme() {
	local value=""
	if [[ -f $GTK3_CONFIG ]]; then
		value="$(grep "^gtk-theme-name=" "$GTK3_CONFIG" 2> /dev/null | cut -d'=' -f2 || true)"
	fi
	if [[ -z $value && -f $GTK2_CONFIG ]]; then
		value="$(grep "^gtk-theme-name=" "$GTK2_CONFIG" 2> /dev/null | cut -d'"' -f2 || true)"
	fi
	if [[ -z $value ]] && command -v gsettings > /dev/null 2>&1; then
		value="$(gsettings get org.gnome.desktop.interface gtk-theme 2> /dev/null | tr -d "'" || true)"
	fi
	printf '%s\n' "${value:-Unknown}"
	return 0
}

# Function to get current icon theme
get_current_icon_theme() {
	local value=""
	if [[ -f $GTK3_CONFIG ]]; then
		value="$(grep "^gtk-icon-theme-name=" "$GTK3_CONFIG" 2> /dev/null | cut -d'=' -f2 || true)"
	fi
	if [[ -z $value ]] && command -v gsettings > /dev/null 2>&1; then
		value="$(gsettings get org.gnome.desktop.interface icon-theme 2> /dev/null | tr -d "'" || true)"
	fi
	if [[ -z $value && -f $GTK2_CONFIG ]]; then
		value="$(grep "^gtk-icon-theme-name=" "$GTK2_CONFIG" 2> /dev/null | cut -d'"' -f2 || true)"
	fi
	printf '%s\n' "${value:-}"
	return 0
}

# Function to list installed GTK themes
list_installed_gtk_themes() {
	local themes=()

	local theme_dirs=(
		"/usr/share/themes"
		"/usr/local/share/themes"
		"$HOME/.themes"
		"$HOME/.local/share/themes"
	)

	for theme_dir in "${theme_dirs[@]}"; do
		if [[ -d $theme_dir ]]; then
			while IFS= read -r -d '' theme_path; do
				local theme_name
				theme_name=$(basename "$theme_path")
				if [[ -d "$theme_path/gtk-2.0" ]] || [[ -d "$theme_path/gtk-3.0" ]]; then
					themes+=("$theme_name")
				fi
			done < <(find "$theme_dir" -maxdepth 1 -type d -print0)
		fi
	done

	# Remove duplicates and sort
	printf '%s\n' "${themes[@]}" | sort -u
}
