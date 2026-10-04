# shellcheck shell=bash
# Resolve a Python interpreter that can import materialyoucolor.
# Prefer /usr/bin/python3 (Arch python-materialyoucolor) over pyenv shims.

hornero_python_m3() {
	if [[ -x /usr/bin/python3 ]] && /usr/bin/python3 -c 'import materialyoucolor' > /dev/null 2>&1; then
		printf '%s\n' /usr/bin/python3
		return 0
	fi
	if command -v python3 > /dev/null 2>&1 && python3 -c 'import materialyoucolor' > /dev/null 2>&1; then
		command -v python3
		return 0
	fi
	return 1
}

# Run generate-m3-colors.py with the resolved interpreter.
# Usage: hornero_run_m3_colors --image ... --output ...
hornero_run_m3_colors() {
	local script="${HORNERO_M3_SCRIPT:-$HOME/.local/lib/hornero/generate-m3-colors.py}"
	local py
	[[ -f $script ]] || {
		echo "hornero_run_m3_colors: missing $script" >&2
		return 1
	}
	py="$(hornero_python_m3)" || {
		echo "hornero_run_m3_colors: materialyoucolor not found (install python-materialyoucolor)" >&2
		return 1
	}
	"$py" "$script" "$@"
}
