#!/usr/bin/env bash
# test_contrast.sh - Hornero Signal theme contract (schema v2 + WCAG).
# Fails (nonzero exit) on any violation so CI stays red.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

pass() { echo "TEST-PASS: $1"; }
fail() { echo "TEST-FAIL: $1" >&2; exit 1; }

# Every shipped theme: schema v2 structure, WCAG text/boundary/terminal gates.
"$REPO_ROOT/scripts/check-contrast.py" --themes-dir "$REPO_ROOT/profiles/themes" \
  || fail "schema v2 + WCAG gate"
pass "every theme passes schema v2 + WCAG gates"

# The validator must reject what the contract forbids (negative fixtures).
python3 - "$REPO_ROOT" <<'PY' || fail "validator accepts invalid themes"
import copy, json, sys
from pathlib import Path
root = Path(sys.argv[1])
sys.path.insert(0, str(root / "lib/hornero"))
import signal_theme as st
good = json.loads((root / "profiles/themes/hornero-signal-night/theme.json").read_text())
assert st.validate(good) == []
def broken(mutate):
    doc = copy.deepcopy(good); mutate(doc); return st.validate(doc)
assert broken(lambda d: d["palette"].pop("cue")), "missing role accepted"
assert broken(lambda d: d["palette"].update(primary="#FFFFFF")), "Material role accepted"
assert not broken(lambda d: d["palette"].pop("glow")), "optional glow treated as required"
assert broken(lambda d: d["palette"].update(inkMuted=d["palette"]["sunken"])), "text on sunken wells unchecked"
assert broken(lambda d: d.update(schemeType="tonal-spot")), "M3 field accepted"
assert broken(lambda d: d["palette"].update(ink="#fff")), "short hex accepted"
assert broken(lambda d: d["palette"].update(inkMuted=d["palette"]["raised"])), "low-contrast text accepted"
assert broken(lambda d: d["palette"].update(ruleStrong=d["palette"]["rule"])), "invisible control boundary accepted"
assert broken(lambda d: d["palette"].update(onSignal=d["palette"]["signal"])), "unreadable on-pair accepted"
assert broken(lambda d: d["terminal"].pop()), "15-colour terminal accepted"
assert broken(lambda d: d.update(schemaVersion=1)), "schema v1 accepted"
PY
pass "validator rejects missing roles, M3 fields, bad hex, low contrast, short terminals"

# Flagship hex values are the RFC 0001 §3.2 contract (with amendment 2) the shell embeds; they
# must stay byte-identical (the High Contrast anchors are pinned too).
python3 - "$REPO_ROOT/profiles/themes" <<'PY' || fail "flagship palettes drift from RFC 0001 §3.2"
import json, sys
base = sys.argv[1]
night = json.load(open(f"{base}/hornero-signal-night/theme.json"))
day = json.load(open(f"{base}/hornero-signal-day/theme.json"))
hc = json.load(open(f"{base}/hornero-signal-contrast/theme.json"))
rfc = {
 "ground": ("#0C0F13", "#E6E1D5"), "sunken": ("#101419", "#DCD6C8"),
 "base": ("#13171D", "#F2EEE5"), "panel": ("#181D24", "#F7F4EE"),
 "raised": ("#1F252E", "#FBF9F5"), "lifted": ("#283039", "#FFFFFF"),
 "ink": ("#ECE6DA", "#1B1E22"), "inkMuted": ("#A8ABAD", "#4E545B"),
 "inkFaint": ("#737980", "#7A8086"), "rule": ("#2C333C", "#D3CCBD"),
 "ruleStrong": ("#707A85", "#736D62"), "focus": ("#7EC1EA", "#1A5F88"),
 "signal": ("#F2A33A", "#8F4B00"), "onSignal": ("#1A1205", "#FFFFFF"),
 "signalWell": ("#3A2A12", "#F6DDB8"), "onSignalWell": ("#FFD9A3", "#3D2200"),
 "cue": ("#7EC1EA", "#1A5F88"), "onCue": ("#06151F", "#FFFFFF"),
 "cueWell": ("#16303F", "#D3E7F3"), "onCueWell": ("#CDE8F8", "#0B2E44"),
 "phosphor": ("#8BD49A", "#256A3B"), "onPhosphor": ("#07170C", "#FFFFFF"),
 "phosphorWell": ("#173222", "#D5EBD9"), "onPhosphorWell": ("#CDEFD4", "#0E2E17"),
 "alert": ("#F0705A", "#A8341C"), "onAlert": ("#1E0905", "#FFFFFF"),
 "alertWell": ("#3D1A14", "#F7D7D0"), "onAlertWell": ("#FFD3CA", "#4A1209"),
 "inverse": ("#ECE6DA", "#1B1E22"), "onInverse": ("#181D24", "#F2EEE5"),
 "inverseSignal": ("#8A5200", "#F2A33A"), "scrim": ("#000000", "#000000"),
 "shadow": ("#000000", "#000000"),
 "glow": ("#FFB650", "#8F4B00"),
}
for role, (n, d) in rfc.items():
    assert night["palette"][role] == n, (role, night["palette"][role], n)
    assert day["palette"][role] == d, (role, day["palette"][role], d)
assert night["mode"] == "dark" and day["mode"] == "light" and hc["mode"] == "dark"
p = hc["palette"]
assert (p["ground"], p["ink"], p["signal"], p["cue"], p["ruleStrong"]) == (
    "#000000", "#FFFFFF", "#FFC247", "#8FD3FF", "#FFFFFF")
PY
pass "Signal Night/Day match RFC 0001 §3.2 + amendment 2 byte-for-byte; High Contrast anchors pinned"

# The JSON Schema file describes the same contract as the validator.
python3 - "$REPO_ROOT" <<'PY' || fail "tokens.schema.json drifts from signal_theme.py"
import json, sys
from pathlib import Path
root = Path(sys.argv[1])
sys.path.insert(0, str(root / "lib/hornero"))
import signal_theme as st
schema = json.loads((root / "profiles/themes/tokens.schema.json").read_text())
assert schema["properties"]["schemaVersion"] == {"const": 2}
assert schema["required"] == list(st.REQUIRED_KEYS)
assert set(schema["properties"]) == set(st.REQUIRED_KEYS) | set(st.OPTIONAL_KEYS)
assert schema["properties"]["palette"]["required"] == list(st.ROLES)
assert schema["properties"]["palette"]["additionalProperties"] is False
assert schema["properties"]["terminal"]["minItems"] == schema["properties"]["terminal"]["maxItems"] == 16
try:
    import jsonschema
except ImportError:
    print("SCHEMA-NOTE: python jsonschema not installed; structural parity checked only")
else:
    for path in sorted((root / "profiles/themes").glob("*/theme.json")):
        jsonschema.validate(json.loads(path.read_text()), schema)
    print("SCHEMA-PASS: every theme validates against tokens.schema.json")
PY
pass "tokens.schema.json and signal_theme.py describe one contract"

# MIT-only: no GPL-licensed code in the shipped appearance artifacts
# (this test file itself names the forbidden strings, so it is not scanned).
if grep -ri "GPL\|General Public License" "$REPO_ROOT/profiles/themes/hornero-signal-night" \
    "$REPO_ROOT/profiles/themes/hornero-signal-day" "$REPO_ROOT/profiles/themes/tokens.schema.json" \
    "$REPO_ROOT/lib/hornero/signal_theme.py" "$REPO_ROOT/lib/hornero/signal_render.py" \
    "$REPO_ROOT/scripts/check-contrast.py" 2>/dev/null; then
  fail "GPL reference in appearance deliverable (MIT-only)"
fi
pass "appearance deliverable MIT-only (no GPL references)"

# Wallpapers stay refs-only: no binaries vendored under the theme packs.
if find "$REPO_ROOT/profiles/themes" \( -iname '*.jpg' -o -iname '*.png' -o -iname '*.webp' \) | grep -q .; then
  fail "binary wallpaper vendored under profiles/themes"
fi
pass "theme packs carry no binary wallpapers"

echo "test_contrast.sh: ALL GREEN"
