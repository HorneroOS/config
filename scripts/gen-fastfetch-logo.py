#!/usr/bin/env python3
"""Generate the fastfetch logos from their pixel sources (stdlib only, MIT).

  scripts/gen-fastfetch-logo.py            write the generated files
  scripts/gen-fastfetch-logo.py --check    exit 1 if a generated file is stale

Source of truth: desktop/fastfetch/art/*.pix (see the header of each file).
Outputs:
  desktop/fastfetch/hornero.txt        from hornero-nest.pix       (half blocks)
  desktop/fastfetch/hornero-mini.txt   from hornero-nest-mini.pix  (half blocks)
  desktop/fastfetch/art/hornero-nest.svg  crisp SVG of the full art, used for
      the optional image logo (rasterised on demand with rsvg-convert)

Terminal output uses 16-colour SGR roles only, so it follows whatever palette
the terminal applied (Signal Night/Day/Dusk/Contrast, Hornero Chromatic).
The SVG is the one place with fixed colours (Signal Night values), because an
image has no terminal palette.
"""
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
FF = ROOT / "desktop" / "fastfetch"
ART = FF / "art"

# Signal Night ANSI values, for the image logo only.
SVG_HEX = {"31": "#FF8494", "32": "#8DDBAF", "33": "#F2AC52", "34": "#8BCEF0",
           "35": "#C9A5F5", "36": "#76D8CE", "37": "#C5D0DC", "90": "#8393A6",
           "93": "#FFC87D"}


def load(path):
    legend, rows = {}, []
    for line in path.read_text(encoding="utf8").splitlines():
        if line.startswith("@"):
            parts = line.split()
            legend[parts[1]] = parts[2]
        elif line.startswith("#") or not line.strip():
            continue
        else:
            rows.append(line)
    width = max(len(r) for r in rows)
    rows = [r.ljust(width, ".") for r in rows]
    # Trim empty margins so the logo sits flush with the info column. Top
    # trimming stays on an even row so half-block pairs keep their alignment.
    while rows and set(rows[-1]) == {"."}:
        rows.pop()
    top = 0
    while top < len(rows) and set(rows[top]) == {"."}:
        top += 1
    rows = rows[top - top % 2:]
    left = min(len(r) - len(r.lstrip(".")) for r in rows)
    rows = [r[left:] for r in rows]
    width = max(len(r) for r in rows)
    rows = [r.ljust(width, ".") for r in rows]
    if len(rows) % 2:
        rows.append("." * width)
    for r in rows:
        for ch in r:
            if ch != "." and ch not in legend:
                raise SystemExit(f"{path}: pixel {ch!r} has no legend entry")
    return legend, rows


def colour(legend, ch):
    if ch == "." or legend[ch] == "none":
        return None
    return legend[ch]


def bg(code):
    return str(int(code) + 10)


def to_ansi(path):
    legend, rows = load(path)
    out = []
    for y in range(0, len(rows), 2):
        line, last = [], None
        for x in range(len(rows[0])):
            top, bot = colour(legend, rows[y][x]), colour(legend, rows[y + 1][x])
            if top is None and bot is None:
                seq, ch = "", " "
            elif top == bot:
                seq, ch = f"0;{top}", "█"
            elif bot is None:
                seq, ch = f"0;{top}", "▀"
            elif top is None:
                seq, ch = f"0;{bot}", "▄"
            else:
                seq, ch = f"0;{top};{bg(bot)}", "▀"
            if seq != last:
                line.append(f"\x1b[{seq}m" if seq else "\x1b[0m")
                last = seq
            line.append(ch)
        out.append("".join(line).rstrip(" ") + "\x1b[0m")
    return "\n".join(out) + "\n"


def to_svg(path):
    legend, rows = load(path)
    w, h = len(rows[0]), len(rows)
    parts = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" '
             f'width="{w}" height="{h}" shape-rendering="crispEdges">',
             "<title>HorneroOS hornero on its nest</title>"]
    for y, row in enumerate(rows):
        x = 0
        while x < w:
            col = colour(legend, row[x])
            if col is None:
                x += 1
                continue
            end = x
            while end < w and colour(legend, row[end]) == col:
                end += 1
            parts.append(f'<rect x="{x}" y="{y}" width="{end - x}" height="1" fill="{SVG_HEX[col]}"/>')
            x = end
    parts.append("</svg>")
    return "\n".join(parts) + "\n"


def outputs():
    return {
        FF / "hornero.txt": to_ansi(ART / "hornero-nest.pix"),
        FF / "hornero-mini.txt": to_ansi(ART / "hornero-nest-mini.pix"),
        ART / "hornero-nest.svg": to_svg(ART / "hornero-nest.pix"),
    }


def main():
    check = "--check" in sys.argv[1:]
    stale = []
    for path, text in outputs().items():
        if check:
            if not path.exists() or path.read_text(encoding="utf8") != text:
                stale.append(path.relative_to(ROOT))
        else:
            path.write_text(text, encoding="utf8")
    if stale:
        sys.exit("stale generated logo files (run scripts/gen-fastfetch-logo.py): "
                 + ", ".join(map(str, stale)))
    print("fastfetch logos " + ("in sync" if check else "written"))


if __name__ == "__main__":
    main()
