# Shared wallpaper resolution helpers for Hornero applications.
# Quickshell and CLI share this canonical XDG state pointer.
HORNERO_STATE_DIR="${HORNERO_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/hornero}"
HORNERO_WALLPAPER_POINTER_FILE="${HORNERO_WALLPAPER_POINTER_FILE:-$HORNERO_STATE_DIR/wallpaper/path}"

_hornero_resolve_pointer_for_read() { printf '%s\n' "$HORNERO_WALLPAPER_POINTER_FILE"; }
_hornero_resolve_pointer_for_write() { printf '%s\n' "$HORNERO_WALLPAPER_POINTER_FILE"; }

hornero_strip_file_uri() {
	local s="${1:-}"
	s="${s#file://}"
	printf '%s\n' "$s"
}

hornero_resolve_path_candidate() {
	local candidate=""
	candidate="$(hornero_strip_file_uri "${1:-}")"
	[[ -n $candidate ]] || return 1

	local resolved=""
	resolved="$(readlink -f "$candidate" 2> /dev/null || true)"
	if [[ -n $resolved && -f $resolved ]]; then
		printf '%s\n' "$resolved"
		return 0
	fi

	if [[ -f $candidate ]]; then
		printf '%s\n' "$candidate"
		return 0
	fi

	return 1
}

hornero_resolve_from_pointer_file() {
	local pointer_file="${1:-}"
	[[ -n $pointer_file && -e $pointer_file ]] || return 1

	local norm_ptr=""
	norm_ptr="$(readlink -f "$pointer_file" 2> /dev/null || true)"

	# Symlink to image: resolve directly.
	local direct=""
	if [[ -L $pointer_file ]]; then
		if direct="$(hornero_resolve_path_candidate "$pointer_file" 2> /dev/null)"; then
			printf '%s\n' "$direct"
			return 0
		fi
	fi

	if [[ -f $pointer_file ]]; then
		local line=""
		line="$(head -n 1 "$pointer_file" 2> /dev/null || true)"
		line="${line%$'\r'}"
		line="$(hornero_strip_file_uri "$line")"
		if [[ -n $line ]]; then
			# Corrupt pointer: file contains its own path (self-referential).
			local norm_line=""
			norm_line="$(readlink -f "$line" 2> /dev/null || true)"
			if [[ -n $norm_ptr && -n $norm_line && $norm_line == "$norm_ptr" ]]; then
				return 1
			fi
			if [[ $line == "$pointer_file" ]]; then
				return 1
			fi

			local from_line=""
			from_line="$(readlink -f "$line" 2> /dev/null || true)"
			if [[ -n $from_line && -f $from_line && $from_line != "$norm_ptr" ]]; then
				printf '%s\n' "$from_line"
				return 0
			fi
			if [[ -f $line && $line != "$pointer_file" ]]; then
				printf '%s\n' "$line"
				return 0
			fi
		fi
	fi

	return 1
}

hornero_current_wallpaper() {
	local explicit="${1:-}"
	local resolved=""

	if [[ -n $explicit ]]; then
		resolved="$(hornero_resolve_path_candidate "$explicit" 2> /dev/null || true)"
		if [[ -n $resolved ]]; then
			printf '%s\n' "$resolved"
			return 0
		fi
	fi

	local candidates=(
		"$HORNERO_WALLPAPER_POINTER_FILE"
		"$HOME/.cache/wal/wal"
	)

	local candidate=""
	for candidate in "${candidates[@]}"; do
		resolved="$(hornero_resolve_from_pointer_file "$candidate" 2> /dev/null || true)"
		if [[ -n $resolved ]]; then
			printf '%s\n' "$resolved"
			return 0
		fi
	done

	return 1
}
