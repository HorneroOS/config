#!/usr/bin/env bash
# Fastfetch defaults: Signal contract (ANSI palette only, no Nerd Font-only
# glyphs, logo markers). Renders with an isolated HOME when fastfetch exists.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
D="$REPO_ROOT/desktop/fastfetch"
fail() { echo "FASTFETCH-FAIL: $*" >&2; exit 1; }
pass() { echo "ok  $*"; }

python3 - "$D" <<'PY' || exit 1
import re, sys, pathlib
d = pathlib.Path(sys.argv[1])
cfg = (d / "config.jsonc").read_text()
logo = (d / "hornero.txt").read_text()
pua = re.compile("[-\U000f0000-\U0010ffff]")
for name, text in (("config.jsonc", cfg), ("hornero.txt", logo)):
    if pua.search(text):
        sys.exit(f"FASTFETCH-FAIL: {name} contains private-use (Nerd Font only) glyphs")
if re.search(r"38;5|38;2|#[0-9A-Fa-f]{6}", cfg):
    sys.exit("FASTFETCH-FAIL: config.jsonc must use ANSI colours only (no 256/RGB/hex)")
if set(re.findall(r"\$(\w)", logo)) - {"1", "2"}:
    sys.exit("FASTFETCH-FAIL: hornero.txt may only use $1 (sun) and $2 (bird) markers")
lines = logo.splitlines()
if not 8 <= len(lines) <= 24:
    sys.exit("FASTFETCH-FAIL: logo height out of range")
width = max(len(re.sub(r"\$\d", "", l)) for l in lines)
if width > 44:
    sys.exit(f"FASTFETCH-FAIL: logo too wide ({width})")
print("ok  config + logo contract")
PY

if command -v fastfetch >/dev/null 2>&1; then
  T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
  mkdir -p "$T/.config"; cp -r "$D" "$T/.config/fastfetch"
  out="$(HOME="$T" XDG_CONFIG_HOME="$T/.config" fastfetch -c "$T/.config/fastfetch/config.jsonc" --pipe 2>&1)" \
    || fail "fastfetch did not render"
  grep -q "SYSTEM" <<<"$out" || fail "section eyebrow missing"
  pass "fastfetch renders"
else
  echo "FASTFETCH-SKIP: fastfetch not installed" >&2
fi
echo "FASTFETCH-PASS"
