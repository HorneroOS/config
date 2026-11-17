#!/usr/bin/env bash
# Fastfetch card contract: Signal palette roles only, generated logos in sync,
# hornero-fetch behaviour (facts, logo selection, knobs, privacy, speed).
# Hermetic: facts come from tests/fixtures/fastfetch, logo selection is checked
# against a recording fastfetch shim, and the real binary is only used for a
# render smoke test when installed.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
D="$REPO_ROOT/desktop/fastfetch"
FETCH="$REPO_ROOT/bin/hornero-fetch"
FIX="$REPO_ROOT/tests/fixtures/fastfetch"
fail() { echo "FASTFETCH-FAIL: $*" >&2; exit 1; }
pass() { echo "ok  $*"; }

# --- 1. static contract ------------------------------------------------------
python3 - "$D" <<'PY' || exit 1
import json, re, sys, pathlib
d = pathlib.Path(sys.argv[1])
raw = (d / "config.jsonc").read_text()
text = re.sub(r"(?m)^\s*//.*$", "", raw)
cfg = json.loads(text)
pua = re.compile("[-\U000f0000-\U0010ffff]")
if pua.search(raw):
    sys.exit("FASTFETCH-FAIL: config.jsonc contains private-use (Nerd Font only) glyphs")
if re.search(r"38;5|38;2|48;5|48;2|#[0-9A-Fa-f]{6}", raw):
    sys.exit("FASTFETCH-FAIL: config.jsonc must use ANSI palette roles only (no 256/RGB/hex)")
if cfg["logo"]["type"] != "file-raw":
    sys.exit("FASTFETCH-FAIL: default logo must be the generated ANSI art (type file-raw)")
mods = [m for m in cfg["modules"] if isinstance(m, dict)]
types = {m["type"] for m in mods}
need = {"kernel", "uptime", "packages", "shell", "wm", "terminal", "terminalfont", "cpu",
        "gpu", "memory", "disk", "battery", "command", "custom"}
if need - types:
    sys.exit(f"FASTFETCH-FAIL: modules missing: {sorted(need - types)}")
for forbidden in ("localip", "publicip", "wifi", "dns", "weather", "netio", "users", "host", "title"):
    if forbidden in types:
        sys.exit(f"FASTFETCH-FAIL: privacy: module '{forbidden}' must not be in the default card")
for m in mods:
    if m["type"] == "command" and "hornero" not in m.get("text", ""):
        sys.exit("FASTFETCH-FAIL: command modules may only call hornero-fetch")
sgr_ok = set(range(30, 38)) | set(range(40, 48)) | set(range(90, 98)) | set(range(100, 108)) | {0, 7}
for name, maxw, maxh in (("hornero.txt", 36, 20), ("hornero-mini.txt", 22, 10)):
    logo = (d / name).read_text()
    if pua.search(logo) or "$" in logo:
        sys.exit(f"FASTFETCH-FAIL: {name}: no private-use glyphs or $ markers")
    for seq in re.findall(r"\x1b\[([0-9;]*)m", logo):
        for code in (int(c) if c else 0 for c in seq.split(";")):
            if code not in sgr_ok:
                sys.exit(f"FASTFETCH-FAIL: {name}: SGR {code} is not a 16-colour palette role")
    lines = logo.splitlines()
    width = max(len(re.sub(r"\x1b\[[0-9;]*m", "", l)) for l in lines)
    if width > maxw or len(lines) > maxh:
        sys.exit(f"FASTFETCH-FAIL: {name}: {width}x{len(lines)} exceeds {maxw}x{maxh}")
svg = (d / "art" / "hornero-nest.svg").read_text()
if "<text" in svg or "href" in svg or "<script" in svg:
    sys.exit("FASTFETCH-FAIL: logo svg must be plain rectangles")
print("ok  config + logo contract")
PY

python3 "$REPO_ROOT/scripts/gen-fastfetch-logo.py" --check >/dev/null \
  || fail "generated logos are stale (run scripts/gen-fastfetch-logo.py)"
pass "generated logos match art/*.pix"

# --- 2. facts ---------------------------------------------------------------
bash -n "$FETCH" || fail "hornero-fetch has a syntax error"
# shellcheck source=/dev/null
source "$FIX/env.sh"
[[ "$("$FETCH" fact edition)" == "Desktop (preview)" ]] || fail "edition fact"
[[ "$("$FETCH" fact mode)" == "signal / cockpit" ]] || fail "mode fact"
[[ "$("$FETCH" fact theme)" == "hornero-signal-night (dark)" ]] || fail "theme fact"
[[ "$("$FETCH" fact chroma)" == "wallpaper / vibrant" ]] || fail "chroma fact"
[[ "$("$FETCH" fact build)" == "shell 1.2.79 / ctl 0.2.0-p45" ]] || fail "build fact"
[[ "$("$FETCH" fact release)" == "rolling / config 0.3.21" ]] || fail "release fact"
[[ -z "$(XDG_STATE_HOME=$FIX/missing "$FETCH" fact mode)" ]] || fail "missing state must print nothing"
[[ -z "$("$FETCH" fact identity)" ]] || fail "identity must be off by default"
[[ "$(HORNERO_FETCH_IDENTITY=1 "$FETCH" fact identity)" == "$(id -un)@$(uname -n)" ]] || fail "identity opt-in"
if "$FETCH" fact nonsense 2>/dev/null; then fail "unknown fact must fail"; fi
pass "facts (fixtures, empty when unknown, identity opt-in)"

start=$(date +%s%N); for _ in 1 2 3 4 5 6; do "$FETCH" fact theme >/dev/null; done
fact_ms=$(( ($(date +%s%N) - start) / 6000000 ))
((fact_ms < 40)) || fail "a fact took ${fact_ms} ms (budget 40)"
pass "fact speed ${fact_ms} ms each"

# --- 3. logo selection and knobs (recording fastfetch shim) -----------------
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/home/.config/fastfetch" "$T/cache"
cp -r "$D"/. "$T/home/.config/fastfetch/"
cat >"$T/bin/fastfetch" <<'SHIM'
#!/usr/bin/env bash
printf '%s\n' "$*"
SHIM
chmod +x "$T/bin/fastfetch"
run() { # <columns> [VAR=value ...] -- [hornero-fetch args]
  local cols="$1"; shift; local envs=()
  while [[ $# -gt 0 && $1 != "--" ]]; do envs+=("$1"); shift; done
  shift || true
  env -i PATH="$T/bin:/usr/bin:/bin" HOME="$T/home" XDG_CONFIG_HOME="$T/home/.config" \
    XDG_CACHE_HOME="$T/cache" XDG_STATE_HOME="$T/none" COLUMNS="$cols" \
    HORNERO_FETCH_ASSUME_TTY=1 ${envs[@]+"${envs[@]}"} "$FETCH" "$@"
}
expect() { grep -q -- "$2" <<<"$1" || fail "$3: expected '$2' in: $1"; }
refuse() { if grep -q -- "$2" <<<"$1"; then fail "$3: unexpected '$2' in: $1"; fi; }

out="$(run 120 --)";   expect "$out" "file-raw --logo $T/home/.config/fastfetch/hornero.txt" "wide uses full art"
out="$(run 90 --)";    expect "$out" "hornero.txt" "90 cols uses full art"
out="$(run 89 --)";    expect "$out" "hornero-mini.txt" "89 cols uses compact art"
out="$(run 60 --)";    expect "$out" "hornero-mini.txt" "60 cols uses compact art"
out="$(run 59 --)";    expect "$out" "--logo none" "<60 cols drops the logo"; expect "$out" "--percent-type 1" "<60 cols drops bars"
out="$(run 120 -- --logo none)"; expect "$out" "--logo none" "--logo none"
out="$(run 120 -- --logo mini)"; expect "$out" "hornero-mini.txt" "--logo mini"
out="$(run 120 HORNERO_FETCH_LOGO=none --)"; expect "$out" "--logo none" "env knob"
mkdir -p "$T/home/.config/hornero"
printf '# comment\nlogo = mini   # inline\n' >"$T/home/.config/hornero/fastfetch.conf"
out="$(run 120 --)"; expect "$out" "hornero-mini.txt" "user file knob"
out="$(run 120 HORNERO_FETCH_LOGO=ansi --)"; expect "$out" "hornero.txt" "env beats user file"
out="$(run 120 -- --logo ansi)"; expect "$out" "hornero.txt" "cli beats user file"
rm "$T/home/.config/hornero/fastfetch.conf"
if run 120 -- --logo bogus 2>/dev/null; then fail "bad --logo must fail"; fi

# image logo: only in kitty-graphics terminals, never by auto, ANSI fallback elsewhere
printf 'png' >"$T/pic.png"
out="$(run 120 TERM=xterm-kitty -- --logo image --image "$T/pic.png")"
expect "$out" "kitty-direct --logo $T/pic.png" "image in kitty"
out="$(run 120 TERM=xterm-256color -- --logo image --image "$T/pic.png")"
expect "$out" "file-raw" "image falls back to ANSI art without a graphics protocol"; refuse "$out" "kitty-direct" "no kitty-direct on alacritty"
out="$(run 120 TERM=xterm-kitty -- --logo image --image "$T/missing.png" 2>/dev/null)"
expect "$out" "file-raw" "unreadable image falls back"
out="$(run 120 TERM=xterm-kitty --)"; refuse "$out" "kitty-direct" "auto never picks an image"
# no tty (pipe/file): plain rows, no art
out="$(env -i PATH="$T/bin:/usr/bin:/bin" HOME="$T/home" XDG_CONFIG_HOME="$T/home/.config" COLUMNS=120 "$FETCH")"
expect "$out" "--logo none" "non-tty gets no art"
# a user's own config wins
mkdir -p "$T/own"; echo '{}' >"$T/own/config.jsonc"
out="$(run 120 -- --config "$T/own/config.jsonc")"; expect "$out" "-c $T/own/config.jsonc" "--config"
pass "logo selection, knobs, image fallback, non-tty"

# --- 4. real render smoke + privacy + speed ----------------------------------
if command -v fastfetch >/dev/null 2>&1; then
  rt="$(mktemp -d)"; cp -r "$D" "$rt/fastfetch"
  start=$(date +%s%N)
  out="$(env HOME="$rt" XDG_CONFIG_HOME="$rt" XDG_CACHE_HOME="$rt/cache" PATH="$REPO_ROOT/bin:$PATH" \
    "$FETCH" --config "$rt/fastfetch/config.jsonc" --pipe 2>&1)" || fail "fastfetch did not render"
  ms=$(( ($(date +%s%N) - start) / 1000000 ))
  for key in KERNEL UPTIME PACKAGES SHELL CPU MEMORY DISK SYSTEM HARDWARE "HORNERO OS"; do
    grep -q "$key" <<<"$out" || fail "row '$key' missing from the card"
  done
  if grep -q -i -F "$(uname -n)" <<<"$out"; then fail "privacy: hostname leaked into the card"; fi
  if grep -E -q '\b[0-9]{1,3}(\.[0-9]{1,3}){3}\b' <<<"$out"; then fail "privacy: an IPv4 address leaked into the card"; fi
  ((ms < 400)) || fail "card took ${ms} ms (CI budget 400 ms; target < 150 ms on hardware)"
  rm -rf "$rt"
  pass "fastfetch renders the card, no host/IP, ${ms} ms"
else
  echo "FASTFETCH-SKIP: fastfetch not installed (render smoke skipped)" >&2
fi
echo "FASTFETCH-PASS"
