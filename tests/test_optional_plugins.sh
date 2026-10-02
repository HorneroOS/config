#!/usr/bin/env bash
# test_optional_plugins.sh - plugin-only config must not break a plugin-less session.
#
# Hyprland plugins (hyprpm) are optional. Their dispatchers, config keys and
# keywords do not exist until the plugin loads, and every unknown line shows
# the red config-error banner. Each such line must sit inside a
# `# hyprlang noerror true` ... `# hyprlang noerror false` block, and the
# blocks must be balanced. Found by Hornero QA (smoke/no-config-errors).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONF_DIR="$REPO_ROOT/desktop/hypr/hyprland.conf.d"
PLUGIN_RE='scrolloverview'
fail=0

for f in "$CONF_DIR"/*.conf; do
    out="$(awk -v re="$PLUGIN_RE" -v file="${f#"$REPO_ROOT"/}" '
        /^# hyprlang noerror true[[:space:]]*$/ {
            if (open) { printf "%s:%d: nested noerror block\n", file, NR; bad = 1 }
            open = 1; next
        }
        /^# hyprlang noerror false[[:space:]]*$/ {
            if (!open) { printf "%s:%d: noerror false without true\n", file, NR; bad = 1 }
            open = 0; next
        }
        /^[[:space:]]*#/ { next }
        # Every line inside a `plugin { ... }` block is plugin config,
        # whatever its key is, so track brace depth from the opener.
        $0 ~ /^[[:space:]]*plugin[[:space:]]*[{]/ { depth = 0; inplugin = 1 }
        {
            plugin_line = inplugin || $0 ~ re
            if (inplugin) {
                depth += gsub(/[{]/, "{") - gsub(/[}]/, "}")
                if (depth <= 0) inplugin = 0
            }
        }
        plugin_line && !open { printf "%s:%d: plugin line outside a noerror block: %s\n", file, NR, $0; bad = 1 }
        END {
            if (open) { printf "%s: unterminated noerror block\n", file; bad = 1 }
            exit bad
        }' "$f")" || {
        printf '%s\n' "$out" >&2
        fail=1
    }
done

if [[ "$fail" -ne 0 ]]; then
    echo "FAIL: wrap optional-plugin config in '# hyprlang noerror true/false'" >&2
    exit 1
fi
echo "ok: optional-plugin config is guarded by noerror blocks"
