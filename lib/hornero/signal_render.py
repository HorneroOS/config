#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Render native application themes from one Hornero Signal theme.

Every renderer maps from schema-v2 roles only (RFC 0001 §3): no wallpaper
synthesis, no Material roles. The repository generator
(scripts/generate-appearance.py) uses these functions for the shipped
static files; the apply pipeline (apply-appearance.sh) uses the CLI below
to refresh the user's "Hornero Dynamic" copies when a theme is applied.

    python3 signal_render.py --theme <theme.json|scheme.json> \
        [--kitty-output P] [--alacritty-output P] [--ghostty-output P] \
        [--btop-output P] [--cava-output P] [--hyprland-output P] \
        [--hyprlock-output P] [--scheme-output P]

Input may be a theme pack (profiles/themes/<id>/theme.json) or the live
scheme document; both carry `id`, `mode`, `palette` and `terminal`.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import signal_theme as st  # noqa: E402

ANSI_NAMES = ("black", "red", "green", "yellow", "blue", "magenta", "cyan", "white")
FONT_SANS = "IBM Plex Sans"
FONT_MONO = "IBM Plex Mono"
FONT_DISPLAY = "IBM Plex Sans Condensed"


def _p(theme: dict, role: str) -> str:
    palette = theme["palette"]
    if role not in palette and role in st.OPTIONAL_ROLES:
        return palette[st.OPTIONAL_ROLES[role]]
    return palette[role]


def _t(theme: dict, index: int) -> str:
    return theme["terminal"][index]


def _header(theme: dict, comment: str = "#") -> str:
    return (
        f"{comment} Hornero Signal palette for {theme['id']} — GENERATED from schema-v2 roles\n"
        f"{comment} (lib/hornero/signal_render.py); do not hand-edit."
    )


def _rgba(hex_color: str, alpha: int) -> str:
    return f"rgba({hex_color.lstrip('#').lower()}{alpha:02x})"


# --- terminals ------------------------------------------------------------------

def render_kitty(theme: dict) -> str:
    lines = [
        _header(theme),
        f"background {_p(theme, 'base')}",
        f"foreground {_p(theme, 'ink')}",
        f"cursor {_p(theme, 'signal')}",
        f"cursor_text_color {_p(theme, 'onSignal')}",
        f"selection_background {_p(theme, 'cueWell')}",
        f"selection_foreground {_p(theme, 'onCueWell')}",
        f"url_color {_p(theme, 'cue')}",
        f"active_border_color {_p(theme, 'signal')}",
        f"inactive_border_color {_p(theme, 'rule')}",
        f"active_tab_foreground {_p(theme, 'ink')}",
        f"active_tab_background {_p(theme, 'raised')}",
        f"inactive_tab_foreground {_p(theme, 'inkMuted')}",
        f"inactive_tab_background {_p(theme, 'base')}",
        f"tab_bar_background {_p(theme, 'ground')}",
        f"mark1_background {_p(theme, 'signal')}",
        f"mark1_foreground {_p(theme, 'onSignal')}",
    ]
    lines.extend(f"color{i} {_t(theme, i)}" for i in range(16))
    return "\n".join(lines) + "\n"


def render_alacritty(theme: dict) -> str:
    lines = [
        _header(theme),
        "[colors.primary]",
        f'background = "{_p(theme, "base")}"',
        f'foreground = "{_p(theme, "ink")}"',
        "",
        "[colors.cursor]",
        f'cursor = "{_p(theme, "signal")}"',
        f'text = "{_p(theme, "onSignal")}"',
        "",
        "[colors.selection]",
        f'background = "{_p(theme, "cueWell")}"',
        f'text = "{_p(theme, "onCueWell")}"',
    ]
    for group, start in (("normal", 0), ("bright", 8)):
        lines.extend(("", f"[colors.{group}]"))
        lines.extend(f'{name} = "{_t(theme, start + i)}"' for i, name in enumerate(ANSI_NAMES))
    return "\n".join(lines) + "\n"


def render_ghostty(theme: dict) -> str:
    lines = [_header(theme)]
    lines.extend(f"palette = {i}={_t(theme, i)}" for i in range(16))
    lines.extend((
        f"background = {_p(theme, 'base')}",
        f"foreground = {_p(theme, 'ink')}",
        f"cursor-color = {_p(theme, 'signal')}",
        f"cursor-text = {_p(theme, 'onSignal')}",
        f"selection-background = {_p(theme, 'cueWell')}",
        f"selection-foreground = {_p(theme, 'onCueWell')}",
    ))
    return "\n".join(lines) + "\n"


def render_btop(theme: dict) -> str:
    """btop's 42 native theme keys from Signal roles (meters read as VU)."""
    p = lambda role: _p(theme, role)  # noqa: E731
    values = {
        "main_bg": "",
        "main_fg": p("ink"),
        "title": p("ink"),
        "hi_fg": p("signal"),
        "selected_bg": p("cueWell"),
        "selected_fg": p("onCueWell"),
        "inactive_fg": p("inkFaint"),
        "graph_text": p("inkMuted"),
        "meter_bg": p("sunken"),
        "proc_misc": p("cue"),
        "cpu_box": p("ruleStrong"),
        "mem_box": p("ruleStrong"),
        "net_box": p("ruleStrong"),
        "proc_box": p("ruleStrong"),
        "div_line": p("rule"),
        "temp_start": p("phosphor"),
        "temp_mid": p("signal"),
        "temp_end": p("alert"),
        "cpu_start": p("phosphor"),
        "cpu_mid": p("signal"),
        "cpu_end": p("alert"),
        "free_start": p("phosphorWell"),
        "free_mid": p("phosphor"),
        "free_end": p("phosphor"),
        "cached_start": p("cueWell"),
        "cached_mid": p("cue"),
        "cached_end": p("cue"),
        "available_start": p("phosphorWell"),
        "available_mid": p("phosphor"),
        "available_end": p("cue"),
        "used_start": p("signalWell"),
        "used_mid": p("signal"),
        "used_end": p("alert"),
        "download_start": p("cueWell"),
        "download_mid": p("cue"),
        "download_end": p("ink"),
        "upload_start": p("signalWell"),
        "upload_mid": p("signal"),
        "upload_end": p("ink"),
        "process_start": p("phosphor"),
        "process_mid": p("signal"),
        "process_end": p("alert"),
    }
    lines = [_header(theme)]
    lines.extend(f'theme[{name}]="{value}"' for name, value in values.items())
    return "\n".join(lines) + "\n"


def render_cava(theme: dict) -> str:
    values = (
        ("background", f"'{_p(theme, 'base')}'"),
        ("foreground", f"'{_p(theme, 'ink')}'"),
        ("gradient", "1"),
        ("gradient_count", "4"),
        ("gradient_color_1", f"'{_p(theme, 'phosphor')}'"),
        ("gradient_color_2", f"'{_p(theme, 'cue')}'"),
        ("gradient_color_3", f"'{_p(theme, 'signal')}'"),
        ("gradient_color_4", f"'{_p(theme, 'alert')}'"),
    )
    lines = [_header(theme), "[color]", *(f"{k} = {v}" for k, v in values)]
    return "\n".join(lines) + "\n"


# --- Qt (qt6ct [ColorScheme]) --------------------------------------------------

# QPalette::ColorRole order (Qt 6): index == enum value, 22 roles.
QT_ROLES = (
    "WindowText", "Button", "Light", "Midlight", "Dark", "Mid",
    "Text", "BrightText", "ButtonText", "Base", "Window", "Shadow",
    "Highlight", "HighlightedText", "Link", "LinkVisited",
    "AlternateBase", "NoRole", "ToolTipBase", "ToolTipText",
    "PlaceholderText", "Accent",
)


def _argb(hex_color: str, alpha: int = 0xFF) -> str:
    return f"#{alpha:02x}{hex_color.lstrip('#').lower()}"


def render_qt6ct(theme: dict) -> str:
    """Selection is the celeste cue; Accent (checked/primary) is the signal."""
    dark = theme["mode"] == "dark"
    p = lambda role: _p(theme, role)  # noqa: E731
    active = {
        "WindowText": p("ink"),
        "Button": p("raised"),
        "Light": p("lifted"),
        "Midlight": st.mix(p("raised"), p("lifted"), 0.5),
        "Dark": p("sunken"),
        "Mid": p("ruleStrong"),
        "Text": p("ink"),
        "BrightText": "#FFFFFF" if dark else "#000000",
        "ButtonText": p("ink"),
        "Base": p("sunken"),
        "Window": p("base"),
        "Shadow": p("shadow"),
        "Highlight": p("cue"),
        "HighlightedText": p("onCue"),
        "Link": p("cue"),
        "LinkVisited": p("inkMuted"),
        "AlternateBase": p("panel"),
        "NoRole": "#000000",
        "ToolTipBase": p("lifted"),
        "ToolTipText": p("ink"),
        "PlaceholderText": p("inkMuted"),
        "Accent": p("signal"),
    }
    disabled = dict(active)
    for role in ("WindowText", "Text", "ButtonText", "HighlightedText", "PlaceholderText"):
        disabled[role] = p("inkFaint")
    disabled["Highlight"] = p("cueWell")
    disabled["Accent"] = p("signalWell")

    def row(values: dict) -> str:
        return ", ".join(_argb(values[r]) for r in QT_ROLES)

    lines = [
        f"; qt6ct colour scheme for {theme['id']} — GENERATED from schema-v2 roles",
        "; (lib/hornero/signal_render.py via scripts/generate-appearance.py).",
        f"; Default wallpaper: {theme.get('defaultWallpaper', '')}.",
        "; Roles follow QPalette::ColorRole order. Selection = cue, Accent = signal.",
        "[ColorScheme]",
        f"active_colors={row(active)}",
        f"inactive_colors={row(active)}",
        f"disabled_colors={row(disabled)}",
    ]
    return "\n".join(lines) + "\n"


# --- GTK ------------------------------------------------------------------------

def _snake(role: str) -> str:
    out = ""
    for ch in role:
        out += f"_{ch.lower()}" if ch.isupper() else ch
    return out


def gtk_palette_block(theme: dict) -> str:
    p = lambda role: _p(theme, role)  # noqa: E731
    toward = "#FFFFFF" if theme["mode"] == "dark" else "#000000"
    derived = {
        "hs_signal_hover": st.mix(p("signal"), toward, 0.12),
        "hs_signal_active": st.mix(p("signal"), p("base"), 0.18),
        "hs_alert_hover": st.mix(p("alert"), toward, 0.12),
    }
    named = {
        # GTK 3 named colours many apps read directly.
        "theme_bg_color": p("base"),
        "theme_fg_color": p("ink"),
        "theme_base_color": p("panel"),
        "theme_text_color": p("ink"),
        "theme_selected_bg_color": p("cue"),
        "theme_selected_fg_color": p("onCue"),
        "theme_tooltip_bg_color": p("lifted"),
        "theme_tooltip_fg_color": p("ink"),
        "theme_unfocused_bg_color": p("base"),
        "theme_unfocused_fg_color": p("inkMuted"),
        "theme_unfocused_base_color": p("panel"),
        "theme_unfocused_text_color": p("inkMuted"),
        "theme_unfocused_selected_bg_color": p("cueWell"),
        "theme_unfocused_selected_fg_color": p("onCueWell"),
        "insensitive_bg_color": p("panel"),
        "insensitive_fg_color": p("inkFaint"),
        "insensitive_base_color": p("panel"),
        "borders": p("ruleStrong"),
        "unfocused_borders": p("rule"),
        "warning_color": p("signal"),
        "error_color": p("alert"),
        "success_color": p("phosphor"),
    }
    lines = [f"/* ---- Palette: profiles/themes/{theme['id']}/theme.json (schema v2) ---- */"]
    lines.extend(f"@define-color hs_{_snake(r)} {p(r)};" for r in (*st.ROLES, *st.OPTIONAL_ROLES))
    lines.extend(f"@define-color {k} {v};" for k, v in derived.items())
    lines.extend(f"@define-color {k} {v};" for k, v in named.items())
    return "\n".join(lines) + "\n"


def render_gtk_css(theme: dict, widget_css: str, tree: str) -> str:
    head = (
        f"/* {tree} — Hornero Signal GTK 3 + GTK 4 theme (MIT, HorneroOS).\n"
        " * GENERATED by scripts/generate-appearance.py from\n"
        f" * profiles/themes/{theme['id']}/theme.json and desktop/gtk-theme/src/signal.css;\n"
        " * do not hand-edit. */\n\n"
    )
    return head + gtk_palette_block(theme) + "\n" + widget_css


def render_recolor(theme: dict, tree: str) -> str:
    """libadwaita public-palette redefinition (no widget rules)."""
    p = lambda role: _p(theme, role)  # noqa: E731
    pairs = (
        ("accent_bg_color", p("signal")),
        ("accent_fg_color", p("onSignal")),
        ("accent_color", p("signal")),
        ("destructive_bg_color", p("alert")),
        ("destructive_fg_color", p("onAlert")),
        ("destructive_color", p("alert")),
        ("success_bg_color", p("phosphor")),
        ("success_fg_color", p("onPhosphor")),
        ("success_color", p("phosphor")),
        ("warning_bg_color", p("signal")),
        ("warning_fg_color", p("onSignal")),
        ("warning_color", p("signal")),
        ("error_bg_color", p("alert")),
        ("error_fg_color", p("onAlert")),
        ("error_color", p("alert")),
        ("window_bg_color", p("base")),
        ("window_fg_color", p("ink")),
        ("view_bg_color", p("panel")),
        ("view_fg_color", p("ink")),
        ("headerbar_bg_color", p("base")),
        ("headerbar_fg_color", p("ink")),
        ("headerbar_border_color", p("rule")),
        ("sidebar_bg_color", p("sunken")),
        ("sidebar_fg_color", p("ink")),
        ("card_bg_color", p("panel")),
        ("card_fg_color", p("ink")),
        ("dialog_bg_color", p("panel")),
        ("dialog_fg_color", p("ink")),
        ("popover_bg_color", p("panel")),
        ("popover_fg_color", p("ink")),
        ("thumbnail_bg_color", p("raised")),
        ("thumbnail_fg_color", p("ink")),
    )
    head = (
        f"/* {tree} libadwaita recolouring — GENERATED from schema-v2 roles of\n"
        f" * profiles/themes/{theme['id']}/theme.json (scripts/generate-appearance.py).\n"
        " * Installed as ~/.config/gtk-4.0/gtk.css; public named colours only. */\n"
    )
    return head + "\n".join(f"@define-color {k} {v};" for k, v in pairs) + "\n"


def render_index_theme(theme: dict, tree: str) -> str:
    return (
        "[Desktop Entry]\n"
        "Type=X-GNOME-Metatheme\n"
        f"Name={tree}\n"
        f"Comment=Hornero Signal GTK theme generated from {theme['id']}\n"
        "Encoding=UTF-8\n"
        "\n"
        "[X-GNOME-Metatheme]\n"
        f"GtkTheme={tree}\n"
        f"MetacityTheme={tree}\n"
        f"IconTheme={theme['iconTheme']}\n"
        "CursorTheme=elementary\n"
        "ButtonLayout=close,minimize,maximize:\n"
    )


# --- Hyprland + hyprlock --------------------------------------------------------

def hyprland_table(theme: dict) -> str:
    """Lua table literal for hl.config(): 1 px matte borders, signal = active."""
    p = lambda role: _p(theme, role)  # noqa: E731
    return (
        "{\n"
        "\tgeneral = {\n"
        "\t\tcol = {\n"
        f'\t\t\tactive_border = "{_rgba(p("signal"), 0xEE)}",\n'
        f'\t\t\tinactive_border = "{_rgba(p("rule"), 0xCC)}",\n'
        "\t\t},\n"
        "\t},\n"
        "\tgroup = {\n"
        "\t\tcol = {\n"
        f'\t\t\tborder_active = "{_rgba(p("signal"), 0xEE)}",\n'
        f'\t\t\tborder_inactive = "{_rgba(p("ruleStrong"), 0xAA)}",\n'
        f'\t\t\tborder_locked_active = "{_rgba(p("cue"), 0xEE)}",\n'
        f'\t\t\tborder_locked_inactive = "{_rgba(p("cueWell"), 0xAA)}",\n'
        "\t\t},\n"
        "\t\tgroupbar = {\n"
        "\t\t\tcol = {\n"
        f'\t\t\t\tactive = "{_rgba(p("signal"), 0xEE)}",\n'
        f'\t\t\t\tinactive = "{_rgba(p("raised"), 0xEE)}",\n'
        f'\t\t\t\tlocked_active = "{_rgba(p("cue"), 0xEE)}",\n'
        f'\t\t\t\tlocked_inactive = "{_rgba(p("cueWell"), 0xEE)}",\n'
        "\t\t\t},\n"
        "\t\t},\n"
        "\t},\n"
        "\tdecoration = {\n"
        "\t\tshadow = {\n"
        f'\t\t\tcolor = "{_rgba(p("shadow"), 0x59)}",\n'
        "\t\t},\n"
        "\t},\n"
        "}"
    )


def render_hyprland(theme: dict) -> str:
    """Generated cache module loaded by smart-colors.lua on every reload."""
    return (
        _header(theme, "--") + "\n"
        "-- luacheck: globals hl\n"
        f"hl.config({hyprland_table(theme)})\n"
    )


HYPRLOCK_VARS = (
    ("hs_ground", "ground"), ("hs_sunken", "sunken"), ("hs_panel", "panel"),
    ("hs_ink", "ink"), ("hs_ink_muted", "inkMuted"), ("hs_rule_strong", "ruleStrong"),
    ("hs_signal", "signal"), ("hs_glow", "glow"), ("hs_cue", "cue"), ("hs_alert", "alert"),
)


def render_hyprlock_colors(theme: dict) -> str:
    """hyprlang variables only; desktop/hypr/hyprlock.conf sources this file
    before declaring its widgets, so a refresh never duplicates widgets."""
    lines = [_header(theme)]
    lines.extend(f"${name} = {_rgba(_p(theme, role), 0xFF)}" for name, role in HYPRLOCK_VARS)
    return "\n".join(lines) + "\n"


# --- CLI ------------------------------------------------------------------------

RENDERERS = {
    "kitty": render_kitty,
    "alacritty": render_alacritty,
    "ghostty": render_ghostty,
    "btop": render_btop,
    "cava": render_cava,
    "hyprland": render_hyprland,
    "hyprlock": render_hyprlock_colors,
}


def load_theme_or_scheme(path: str | Path) -> dict:
    doc = st.load(path)
    if "gtkTheme" in doc:
        errors = st.validate(doc)
    else:
        # A live scheme carries only id/mode/palette/terminal; validate it
        # against the same role and contrast rules.
        probe = dict(doc)
        probe.update({k: "x" for k in ("name", "gtkTheme", "iconTheme", "defaultWallpaper", "wallpaperDir")})
        probe.pop("$schema", None)
        errors = st.validate(probe)
    if errors:
        raise ValueError("; ".join(errors))
    return doc


def render_outputs(theme: dict, outputs: dict[str, str | Path | None]) -> dict[str, str]:
    """Render every requested format first, then write all atomically."""
    written = {
        str(path): RENDERERS[name](theme)
        for name, path in outputs.items()
        if path is not None
    }
    for path, contents in written.items():
        st.atomic_write(path, contents)
    return written


def main(argv: list[str]) -> int:
    import argparse

    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--theme", required=True, help="schema-v2 theme.json or live scheme.json")
    for name in RENDERERS:
        parser.add_argument(f"--{name}-output")
    parser.add_argument("--scheme-output", help="also write the live scheme document")
    args = parser.parse_args(argv)
    outputs = {name: getattr(args, f"{name}_output") for name in RENDERERS}
    if not any(outputs.values()) and not args.scheme_output:
        parser.error("at least one output path is required")
    try:
        theme = load_theme_or_scheme(args.theme)
        written = render_outputs(theme, outputs)
        if args.scheme_output:
            st.atomic_write(args.scheme_output, json.dumps(st.live_scheme(theme), indent=2) + "\n")
            written[args.scheme_output] = ""
    except (OSError, ValueError, KeyError, json.JSONDecodeError) as error:
        print(f"signal-render: {error}", file=sys.stderr)
        return 1
    for path in written:
        print(f"wrote {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
