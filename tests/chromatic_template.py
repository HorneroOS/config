# SPDX-License-Identifier: MIT
"""Reference implementation of the Hornero Chromatic template grammar.

This is the executable spec used by config CI to render the shipped
templates against a Signal scheme; horneroctl implements the same grammar
in V and consumes the same goldens (tests/golden/chromatic). Test support
only: it is not installed.

Grammar (RFC 0002 §12.2 + the implementation contract):
  {{ role }} {{ role.hex }}      #RRGGBB
  {{ role.bare }}                RRGGBB
  {{ role.rgb }}                 r, g, b            (decimal 0-255)
  {{ role.r }} .g .b             one decimal channel
  {{ role.rgba A }}              rgba(r, g, b, A)   (A in 0..1, two decimals)
  {{ termN }}                    N in 0..15, same filters
  {{ mode }} {{ id }}            "dark"/"light", scheme id
  {{#dark}}..{{/dark}}  {{#light}}..{{/light}}      no nesting
Optional roles absent from the scheme resolve to their fallback (glow -> signal).
Anything else is an error carrying file:line:col.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "lib" / "hornero"))
import signal_theme as st  # noqa: E402

TAG = re.compile(r"\{\{(.*?)\}\}", re.S)
IDENT = re.compile(r"^(?P<name>[A-Za-z][A-Za-z0-9]*)(?:\.(?P<filter>[a-z]+))?(?:\s+(?P<arg>[0-9.]+))?$")
TERM = re.compile(r"^term(1[0-5]|[0-9])$")
FILTERS = ("hex", "bare", "rgb", "r", "g", "b", "rgba")


class TemplateError(Exception):
    def __init__(self, source: str, line: int, col: int, message: str):
        super().__init__(f"{source}:{line}:{col}: {message}")


def _pos(text: str, offset: int) -> tuple[int, int]:
    line = text.count("\n", 0, offset) + 1
    return line, offset - (text.rfind("\n", 0, offset) + 1) + 1


def _colour(scheme: dict, name: str) -> str | None:
    match = TERM.match(name)
    if match:
        return scheme["terminal"][int(match.group(1))]
    palette = scheme["palette"]
    if name in palette:
        return palette[name]
    if name in st.OPTIONAL_ROLES:
        return palette[st.OPTIONAL_ROLES[name]]
    return None


def _filtered(hex_color: str, filt: str | None, arg: str | None) -> str | None:
    r, g, b = st.rgb(hex_color)
    if filt in (None, "hex"):
        return None if arg else hex_color
    if filt == "bare":
        return None if arg else hex_color[1:]
    if filt == "rgb":
        return None if arg else f"{r}, {g}, {b}"
    if filt in ("r", "g", "b"):
        return None if arg else str({"r": r, "g": g, "b": b}[filt])
    if filt == "rgba":
        if arg is None:
            return None
        try:
            alpha = float(arg)
        except ValueError:
            return None
        if not 0.0 <= alpha <= 1.0:
            return None
        return f"rgba({r}, {g}, {b}, {alpha:.2f})"
    return None


def _no_stray(text: str, start: int, end: int, source: str) -> None:
    """Literal text may not contain braces pairs: an unterminated tag is an error."""
    for marker in ("{{", "}}"):
        at = text.find(marker, start, end)
        if at != -1:
            line, col = _pos(text, at)
            raise TemplateError(source, line, col, f"stray {marker!r}")


def render(text: str, scheme: dict, source: str = "<template>") -> str:
    out: list[str] = []
    cursor = 0
    section: str | None = None
    section_at = 0
    for tag in TAG.finditer(text):
        line, col = _pos(text, tag.start())
        body = tag.group(1).strip()
        keep = section is None or section == scheme["mode"]
        _no_stray(text, cursor, tag.start(), source)
        if keep:
            out.append(text[cursor:tag.start()])
        cursor = tag.end()
        if body in ("#dark", "#light"):
            if section is not None:
                raise TemplateError(source, line, col, "sections cannot nest")
            section, section_at = body[1:], tag.start()
            continue
        if body in ("/dark", "/light"):
            if section != body[1:]:
                raise TemplateError(source, line, col, f"unmatched {{{{{body}}}}}")
            section = None
            continue
        if body.startswith(("#", "/")):
            raise TemplateError(source, line, col, f"unknown section {body!r}")
        if not keep:
            continue
        if body in ("mode", "id"):
            out.append(str(scheme["mode"] if body == "mode" else scheme["id"]))
            continue
        match = IDENT.match(body)
        if not match:
            raise TemplateError(source, line, col, f"malformed placeholder {body!r}")
        filt = match.group("filter")
        if filt is not None and filt not in FILTERS:
            raise TemplateError(source, line, col, f"unknown filter {filt!r}")
        colour = _colour(scheme, match.group("name"))
        if colour is None:
            raise TemplateError(source, line, col, f"unknown role {match.group('name')!r}")
        value = _filtered(colour, filt, match.group("arg"))
        if value is None:
            raise TemplateError(source, line, col, f"bad filter arguments in {body!r}")
        out.append(value)
    if section is not None:
        line, col = _pos(text, section_at)
        raise TemplateError(source, line, col, f"unclosed section {{{{#{section}}}}}")
    _no_stray(text, cursor, len(text), source)
    out.append(text[cursor:])
    return "".join(out)
