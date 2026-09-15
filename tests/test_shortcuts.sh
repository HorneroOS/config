#!/usr/bin/env bash
# test_shortcuts.sh - the shortcut manifest contract.
#
# generate-shortcuts.py must parse every bind in keybindings.conf into a
# deterministic shortcuts.json, and every curated Welcome id must resolve
# to a real binding. If a binding is renamed, this test fails until the
# curated list (and the shell catalog) is updated: Welcome can never show
# a stale shortcut.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_HOME="$(mktemp -d)"
trap 'rm -rf "$TMP_HOME"' EXIT

# Curated ids referenced by the Welcome Center (shell modules/welcome).
# Format: one id per line; the check requires a global (submap="") entry.
CURATED_IDS="exec-launcher
app-terminalemulator
app-filemanager
app-webbrowser
ipc-dashboard-toggle
ipc-layoutpicker-toggle
ipc-lock-lock
movefocus:l
movewindow:l
workspace:1
togglefloating:unnamed
fullscreen:1
exec-screenshooter
exec-clipboard"

OUT="$TMP_HOME/shortcuts.json"
"$REPO_ROOT/scripts/generate-shortcuts.py" --root "$REPO_ROOT" --out "$OUT" >/dev/null

python3 - "$OUT" <<'EOF'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as fh:
    doc = json.load(fh)
assert doc["schemaVersion"] == 1, "schemaVersion must be 1"
assert doc["source"].endswith("keybindings.conf"), "source must name keybindings.conf"
entries = doc["entries"]
assert len(entries) > 50, f"expected the full binding table, got {len(entries)}"
for e in entries:
    for key in ("id", "mods", "key", "dispatcher", "args", "submap", "flags"):
        assert key in e, f"entry missing {key}: {e}"
    assert e["id"] and e["key"] and e["dispatcher"], f"empty core field: {e}"
    assert isinstance(e["mods"], list), f"mods must be a list: {e}"
    assert not any("$" in m for m in e["mods"]), f"unexpanded var in {e}"

curated = """exec-launcher
app-terminalemulator
app-filemanager
app-webbrowser
ipc-dashboard-toggle
ipc-layoutpicker-toggle
ipc-lock-lock
movefocus:l
movewindow:l
workspace:1
togglefloating:unnamed
fullscreen:1
exec-screenshooter
exec-clipboard""".splitlines()
by_id = {}
for e in entries:
    if e["submap"] == "":
        by_id.setdefault(e["id"], e)
missing = [i for i in curated if i not in by_id]
assert not missing, f"curated Welcome ids without a global binding: {missing}"
print(f"SHORTCUTS-TEST-PASS: {len(entries)} entries, {len(curated)} curated ids resolve")
EOF

# Determinism: regenerate byte-identical.
OUT2="$TMP_HOME/shortcuts2.json"
"$REPO_ROOT/scripts/generate-shortcuts.py" --root "$REPO_ROOT" --out "$OUT2" >/dev/null
if ! cmp -s "$OUT" "$OUT2"; then
  echo "TEST-FAIL: shortcuts.json is not deterministic" >&2
  exit 1
fi

# materialize installs the manifest to the canonical data path.
"$REPO_ROOT/scripts/materialize.sh" --dest "$TMP_HOME/stage" >/dev/null
if [[ ! -f "$TMP_HOME/stage/.local/share/hornero/shortcuts.json" ]]; then
  echo "TEST-FAIL: materialize did not install hornero/shortcuts.json" >&2
  exit 1
fi
echo "TEST-PASS: shortcuts contract holds"
