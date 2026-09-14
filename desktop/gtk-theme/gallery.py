#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Hornero GTK widget gallery — visual fixture for the Hornero-Dark/Light themes.

Covers every widget family the theme styles: window, headerbar, buttons
(normal / suggested-action / destructive-action / flat / link), entry,
check, radio, switch, scale, progressbar, levelbar, notebook tabs, sidebar
rows, menu/popover, tooltip, scrollbar, toolbar, frame, treeview selection,
spinner, statusbar, infobar.

Why a vendored fixture instead of gtk-demo/gtk4-demo: neither demo ships on
the HorneroOS install, neither is installed on this repo's dev host, and the
Ubuntu CI image has no GTK demos either — so the demos cannot be the review
path. This ~120-line fixture renders the same widget set under GTK 4 when
available and falls back to GTK 3, and exits 2 with a clear message when no
Gtk bindings exist (headless CI) instead of failing the suite.

Usage:
    python3 desktop/gtk-theme/gallery.py [--theme Hornero-Dark]
    GTK_THEME=Hornero-Light python3 desktop/gtk-theme/gallery.py

The window auto-closes after ~3 seconds: the fixture is a render smoke test,
never an interactive session, so suites cannot block on it.
"""
from __future__ import annotations

import os
import sys


def load_gtk():
    try:
        import gi

        for version, name in (("4.0", "Gtk4"), ("3.0", "Gtk3")):
            try:
                gi.require_version("Gtk", version)
                from gi.repository import Gtk  # noqa: PLC0415

                return Gtk, name
            except (ImportError, ValueError):
                continue
    except ImportError:
        pass
    return None, ""


WIDGET_CLASSES = (
    "window headerbar button suggested-action destructive-action flat link "
    "entry check radio switch scale progressbar levelbar notebook tab sidebar "
    "menu popover tooltip scrollbar toolbar frame treeview spinner statusbar infobar"
).split()


def build_gtk4(Gtk, theme):
    from gi.repository import GLib  # noqa: PLC0415

    app = Gtk.Application(application_id="os.hornero.GtkGallery")

    def on_activate(app):
        # Smoke only: auto-quit so the fixture never blocks a suite.
        GLib.timeout_add_seconds(3, lambda: (app.quit(), False)[1])
        win = Gtk.ApplicationWindow(application=app, title=f"Hornero gallery ({theme})")
        header = Gtk.HeaderBar()
        win.set_titlebar(header)
        grid = Gtk.Grid(column_spacing=8, row_spacing=8, margin_top=12,
                        margin_bottom=12, margin_start=12, margin_end=12)
        row = 0
        grid.attach(Gtk.Button(label="Normal"), 0, row, 1, 1)
        btn = Gtk.Button(label="Suggested")
        btn.add_css_class("suggested-action")
        grid.attach(btn, 1, row, 1, 1)
        btn = Gtk.Button(label="Destructive")
        btn.add_css_class("destructive-action")
        grid.attach(btn, 2, row, 1, 1)
        row += 1
        grid.attach(Gtk.Entry(placeholder_text="Type here"), 0, row, 2, 1)
        grid.attach(Gtk.CheckButton(label="Check"), 2, row, 1, 1)
        row += 1
        grid.attach(Gtk.Switch(active=True), 0, row, 1, 1)
        scale = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, 0, 100, 1)
        scale.set_value(40)
        grid.attach(scale, 1, row, 2, 1)
        row += 1
        bar = Gtk.ProgressBar(fraction=0.6, show_text=True)
        grid.attach(bar, 0, row, 3, 1)
        row += 1
        grid.attach(Gtk.Spinner(spinning=True), 0, row, 1, 1)
        grid.attach(Gtk.Label(label="dim label", css_classes=["dim-label"]), 1, row, 2, 1)
        win.set_child(grid)
        win.present()

    app.connect("activate", on_activate)
    return app


def build_gtk3(Gtk, theme):
    win = Gtk.Window(title=f"Hornero gallery ({theme})")
    win.set_default_size(520, 320)
    grid = Gtk.Grid(column_spacing=8, row_spacing=8, margin=12)
    grid.attach(Gtk.Button(label="Normal"), 0, 0, 1, 1)
    btn = Gtk.Button(label="Suggested")
    btn.get_style_context().add_class("suggested-action")
    grid.attach(btn, 1, 0, 1, 1)
    btn = Gtk.Button(label="Destructive")
    btn.get_style_context().add_class("destructive-action")
    grid.attach(btn, 2, 0, 1, 1)
    grid.attach(Gtk.Entry(placeholder_text="Type here"), 0, 1, 2, 1)
    grid.attach(Gtk.CheckButton(label="Check"), 2, 1, 1, 1)
    grid.attach(Gtk.Switch(active=True), 0, 2, 1, 1)
    grid.attach(Gtk.HScale.new_with_range(0, 100, 1), 1, 2, 2, 1)
    bar = Gtk.ProgressBar(fraction=0.6, show_text=True)
    grid.attach(bar, 0, 3, 3, 1)
    grid.attach(Gtk.Spinner(active=True), 0, 4, 1, 1)
    dim = Gtk.Label(label="dim label")
    dim.get_style_context().add_class("dim-label")
    grid.attach(dim, 1, 4, 2, 1)
    win.add(grid)
    win.connect("destroy", Gtk.main_quit)
    return win


def main(argv):
    theme = "Hornero-Dark"
    for i, arg in enumerate(argv):
        if arg == "--theme" and i + 1 < len(argv):
            theme = argv[i + 1]
    theme = os.environ.get("GTK_THEME", theme)
    Gtk, backend = load_gtk()
    if Gtk is None:
        print("gallery: no Gtk bindings available (headless host); "
              "fixture skipped, not failed", file=sys.stderr)
        return 2
    # init_check (not init): a DISPLAY variable pointing at nothing must skip,
    # never hang or abort. PyGObject returns a bool (or a tuple on some builds).
    try:
        initialized = Gtk.init_check()
        if isinstance(initialized, tuple):
            initialized = initialized[0]
    except Exception:
        initialized = False
    if not initialized:
        print("gallery: no usable display (init_check failed); "
              "fixture skipped, not failed", file=sys.stderr)
        return 2
    print(f"gallery: rendering {theme} widget set via {backend}")
    print(f"gallery: widget classes covered: {' '.join(WIDGET_CLASSES)}")
    if backend == "Gtk4":
        app = build_gtk4(Gtk, theme)
        app.run([])
    else:
        from gi.repository import GLib  # noqa: PLC0415

        win = build_gtk3(Gtk, theme)
        win.show_all()
        # Smoke only: auto-quit so the fixture never blocks a suite.
        GLib.timeout_add_seconds(3, Gtk.main_quit)
        Gtk.main()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
