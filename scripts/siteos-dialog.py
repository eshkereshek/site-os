#!/usr/bin/env python3
"""Site OS Error and Alert Dialog.

Matches assets/reference/Site OS — desktop mockup.html .win.err 1:1:
  - Gradient background: linear-gradient(135deg, #59414F, #3C4655)
  - Glowing circular badge: radial-gradient(circle at 35% 30%, #FF9AA2, #C2414C 60%, #7C2630)
  - Header text: #FFD3D6 (25px VT323)
  - Message text: #E8EAF0 (21px VT323)
  - Styled OK / Cancel buttons: linear-gradient(180deg, #C8CCE4, #9096B8)
"""
import argparse
import sys
import gi

gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
from gi.repository import Gdk, Gtk

CSS_DATA = b"""
window.siteos-dialog {
  background-color: transparent;
}

#dialog-container {
  background-image: linear-gradient(180deg, rgba(104, 115, 134, 0.94), rgba(60, 70, 85, 0.94));
  border: 1px solid rgba(210, 220, 235, 0.38);
  padding: 0 7px 7px;
  box-shadow: 0 6px 22px rgba(0, 0, 0, 0.45);
}

#titlebar-box {
  min-height: 30px;
  padding: 2px 4px;
}

.title-text {
  font-family: "VT323", "DejaVu Sans Mono", monospace;
  font-size: 18px;
  color: #E8EAF0;
}

.title-dot {
  min-width: 12px;
  min-height: 12px;
  border-radius: 50%;
  margin-right: 6px;
  border: 1px solid rgba(0, 0, 0, 0.3);
}

.dot-close {
  background-color: #B25A62;
}

.dot-min {
  background-color: #6F7B8E;
}

#dialog-body {
  background-image: linear-gradient(135deg, #59414F, #3C4655);
  padding: 16px 16px 10px;
}

.dialog-badge {
  min-width: 46px;
  min-height: 46px;
  border-radius: 50%;
  background-image: radial-gradient(circle at 35% 30%, #FF9AA2, #C2414C 60%, #7C2630);
  box-shadow: 0 0 14px rgba(255, 90, 100, 0.5);
  margin-right: 14px;
}

.dialog-badge-info {
  background-image: radial-gradient(circle at 35% 30%, #8CA6C0, #46576D 60%, #202A36);
  box-shadow: 0 0 14px rgba(100, 140, 190, 0.5);
}

.badge-symbol {
  font-family: "VT323", "DejaVu Sans Mono", monospace;
  font-size: 32px;
  font-weight: bold;
  color: #FFFFFF;
}

.header-text {
  font-family: "VT323", "DejaVu Sans Mono", monospace;
  font-size: 25px;
  color: #FFD3D6;
  margin-bottom: 4px;
}

.header-text-info {
  color: #D6E4FF;
}

.message-text {
  font-family: "VT323", "DejaVu Sans Mono", monospace;
  font-size: 21px;
  color: #E8EAF0;
  line-height: 1.1;
}

#button-bar {
  padding: 10px 4px 6px;
}

.siteos-btn {
  font-family: "VT323", "DejaVu Sans Mono", monospace;
  font-size: 20px;
  color: #1E2530;
  border: 1px solid rgba(255, 255, 255, 0.35);
  background-image: linear-gradient(180deg, #C8CCE4, #9096B8);
  padding: 3px 22px;
  border-radius: 0;
  box-shadow: none;
}

.siteos-btn:hover {
  background-image: linear-gradient(180deg, #DCE0F5, #A3A9CC);
}
"""


class SiteOSDialog(Gtk.Window):
    def __init__(self, title, header, message, is_info=False):
        super().__init__(type=Gtk.WindowType.TOPLEVEL)
        self.set_title(title)
        self.set_decorated(False)
        self.set_position(Gtk.WindowPosition.CENTER)
        self.set_default_size(440, -1)
        self.set_keep_above(True)
        self.get_style_context().add_class("siteos-dialog")

        # Container
        container = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        container.set_name("dialog-container")
        self.add(container)

        # Title bar
        tbar = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=4)
        tbar.set_name("titlebar-box")
        container.pack_start(tbar, False, False, 0)

        dot_c = Gtk.Box()
        dot_c.get_style_context().add_class("title-dot")
        dot_c.get_style_context().add_class("dot-close")
        tbar.pack_start(dot_c, False, False, 0)

        dot_m = Gtk.Box()
        dot_m.get_style_context().add_class("title-dot")
        dot_m.get_style_context().add_class("dot-min")
        tbar.pack_start(dot_m, False, False, 0)

        t_lbl = Gtk.Label(label=title)
        t_lbl.get_style_context().add_class("title-text")
        tbar.pack_start(t_lbl, False, False, 4)

        # Body
        body = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        body.set_name("dialog-body")
        container.pack_start(body, True, True, 0)

        content_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        body.pack_start(content_box, True, True, 0)

        # Badge
        badge = Gtk.Box()
        badge.get_style_context().add_class("dialog-badge")
        if is_info:
            badge.get_style_context().add_class("dialog-badge-info")
        sym_lbl = Gtk.Label(label="i" if is_info else "!")
        sym_lbl.get_style_context().add_class("badge-symbol")
        badge.pack_start(sym_lbl, True, True, 0)
        content_box.pack_start(badge, False, False, 0)

        # Texts
        text_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        h_lbl = Gtk.Label(label=header or title)
        h_lbl.get_style_context().add_class("header-text")
        if is_info:
            h_lbl.get_style_context().add_class("header-text-info")
        h_lbl.set_xalign(0.0)
        text_box.pack_start(h_lbl, False, False, 0)

        m_lbl = Gtk.Label(label=message)
        m_lbl.get_style_context().add_class("message-text")
        m_lbl.set_xalign(0.0)
        m_lbl.set_line_wrap(True)
        text_box.pack_start(m_lbl, False, False, 0)
        content_box.pack_start(text_box, True, True, 0)

        # Buttons
        btn_bar = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        btn_bar.set_name("button-bar")
        btn_bar.set_halign(Gtk.Align.END)
        body.pack_end(btn_bar, False, False, 0)

        ok_btn = Gtk.Button(label="OK")
        ok_btn.get_style_context().add_class("siteos-btn")
        ok_btn.connect("clicked", lambda w: Gtk.main_quit())
        btn_bar.pack_start(ok_btn, False, False, 0)

        self.connect("key-press-event", self.on_key)
        self.connect("destroy", lambda w: Gtk.main_quit())

    def on_key(self, w, e):
        if e.keyval in (Gdk.KEY_Escape, Gdk.KEY_Return, Gdk.KEY_KP_Enter):
            Gtk.main_quit()
            return True
        return False


def main():
    parser = argparse.ArgumentParser(description="Site OS Dialog")
    parser.add_argument("--title", default="Notice")
    parser.add_argument("--header", default="")
    parser.add_argument("--message", "--text", dest="message", default="")
    parser.add_argument("--error", action="store_true")
    parser.add_argument("--info", action="store_true")
    args, unknown = parser.parse_known_args()

    # Fallback text parsing if passed like zenity
    msg = args.message
    if not msg and unknown:
        msg = " ".join(unknown)

    css_provider = Gtk.CssProvider()
    css_provider.load_from_data(CSS_DATA)
    Gtk.StyleContext.add_provider_for_screen(
        Gdk.Screen.get_default(), css_provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
    )

    is_info = args.info and not args.error
    win = SiteOSDialog(args.title, args.header or args.title, msg, is_info=is_info)
    win.show_all()
    Gtk.main()


if __name__ == "__main__":
    main()
