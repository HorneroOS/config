#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

HOME_TEST="$TMP/home"
mkdir -p "$HOME_TEST/.local/lib/hornero" "$HOME_TEST/.local/share/hornero/themes/patagonia" \
	"$TMP/bin" "$TMP/config"
cp "$ROOT/lib/hornero/snappy-switcher-manager.sh" "$HOME_TEST/.local/lib/hornero/"
cat > "$HOME_TEST/.local/share/hornero/themes/patagonia/theme.json" <<'EOF'
{"id":"patagonia","name":"Patagonia","darkMode":true,"snappyTheme":"patagonia.ini"}
EOF
cat > "$TMP/bin/snappy-switcher" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$TMP/bin/snappy-switcher"

HOME="$HOME_TEST" \
XDG_DATA_HOME="$HOME_TEST/.local/share" \
XDG_CONFIG_HOME="$TMP/config" \
PATH="$TMP/bin:$PATH" \
	"$ROOT/bin/hornero-snappy-switcher" apply-theme-pack patagonia

grep -q '^name = patagonia.ini$' "$TMP/config/snappy-switcher/config.ini"
grep -q '^mode = context$' "$TMP/config/snappy-switcher/config.ini"

if HOME="$HOME_TEST" XDG_DATA_HOME="$HOME_TEST/.local/share" XDG_CONFIG_HOME="$TMP/config" \
	PATH="$TMP/bin:$PATH" "$ROOT/bin/hornero-snappy-switcher" apply-theme-pack >/dev/null 2>&1; then
	echo "FAIL: missing theme id accepted" >&2
	exit 1
fi

echo "snappy switcher helper: PASS"
