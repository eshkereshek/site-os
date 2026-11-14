#!/usr/bin/env python3
"""Site OS Start Menu.

Matches assets/reference/Site OS — desktop mockup.html 1:1:
  - Left panel (290px): Start title, Programs ▸, Favorites ▸, Settings, Help, fill spacer, user footer with [▲] (eject) and [⏻] (power)
  - Right panel (230-300px): Submenu column popping out with applications or favorites on click / hover
  - Eject button [▲]: toggles optical disc drive (eject -T || eject)
  - Power button [⏻]: launches xfce4-session-logout
  - Single-instance toggle via PID file (click Start to open, click Start again to close)
  - Esc or click outside closes menu
"""
import glob
import os
import signal
import subprocess
import sys

# Single-instance toggle
PID_FILE = f"/tmp/siteos-menu-{os.getuid()}.pid"
if os.path.exists(PID_FILE):
    try:
        with open(PID_FILE, "r") as f:
            old_pid = int(f.read().strip())
        if old_pid != os.getpid():
            os.kill(old_pid, signal.SIGTERM)
            try:
                os.remove(PID_FILE)
            except OSError:
                pass
            sys.exit(0)
    except (ProcessLookupError, ValueError):
        try:
            os.remove(PID_FILE)
        except OSError:
            pass
    except Exception:
        pass

try:
    with open(PID_FILE, "w") as f:
        f.write(str(os.getpid()))
except Exception:
    pass

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
from gi.repository import Gdk, GLib, Gtk

CSS_DATA = b"""
window.menu-window {
  background-color: transparent;
}

#menu-container {
  background-color: transparent;
  padding: 0;
  margin: 0;
}

#menu {
  background-image: linear-gradient(180deg, #3E5063, #5F7689);
  border: 2px solid #2F3B48;
  padding: 6px;
  min-width: 290px;
}

#sub {
  background-color: #C5CAD6;
  border: 2px solid #2F3B48;
  padding: 4px;
  min-width: 230px;
  max-width: 320px;
}

.menu-header {
  font-family: "VT323", "DejaVu Sans Mono", monospace;
  font-size: 16px;
  color: #E8EAF0;
  margin: 0 0 4px 4px;
}

.menu-item,
.menu-item:focus {
  background-image: linear-gradient(90deg, #9096B8, #B5BAD6);
  border: none;
  border-radius: 0;
  padding: 0 10px 0 8px;
  min-height: 34px;
  margin-bottom: 2px;
  box-shadow: none;
  outline: none;
}

.menu-item:hover,
.menu-item.active {
  background-image: linear-gradient(90deg, #A7ACCB, #CDD1E6);
}

.menu-item-text {
  font-family: "VT323", "DejaVu Sans Mono", monospace;
  font-size: 21px;
  color: #1E2530;
}

.menu-dot {
  min-width: 16px;
  min-height: 16px;
  border-radius: 50%;
  background-color: #2A3340;
  border: 1px solid #6F7B8E;
  margin-right: 10px;
}

.menu-arrow {
  font-family: "VT323", "DejaVu Sans Mono", monospace;
  font-size: 18px;
  color: #1E2530;
}

.sub-item,
.sub-item:focus,
.sub-item:active {
  background: transparent;
  background-color: transparent;
  background-image: none;
  border: none;
  border-radius: 0;
  padding: 2px 8px;
  min-height: 30px;
  margin-bottom: 1px;
  box-shadow: none;
  outline: none;
}

.sub-item:hover {
  background-color: #9EA3C2;
  background-image: none;
  border: none;
  box-shadow: none;
}

.sub-item-text {
  font-family: "VT323", "DejaVu Sans Mono", monospace;
  font-size: 20px;
  color: #1E2530;
}

#foot {
  margin-top: 6px;
  padding: 4px 2px 0 4px;
}

.user-label {
  font-family: "VT323", "DejaVu Sans Mono", monospace;
  font-size: 21px;
  font-weight: bold;
  color: #E8EAF0;
}

.sq-button,
.sq-button:focus {
  min-width: 28px;
  min-height: 28px;
  background-color: #C9D1DC;
  background-image: none;
  border: 2px solid #2F3B48;
  border-radius: 0;
  padding: 0;
  margin-left: 6px;
  color: #2F3B48;
  font-size: 15px;
  font-weight: bold;
  box-shadow: none;
  outline: none;
}

.sq-button:hover {
  background-color: #FFFFFF;
  background-image: none;
}

.sub-sep {
  background-color: #2F3B48;
  min-height: 1px;
  margin: 4px 2px;
}

scrollbar, scrollbar.vertical {
  background-color: #B5BAD6;
  border: none;
}
scrollbar slider {
  background-color: #6F7B8E;
  min-width: 8px;
  border-radius: 0;
}
scrollbar slider:hover {
  background-color: #2F3B48;
}
"""


def get_current_user():
    import getpass

    try:
        u = getpass.getuser()
        if u:
            return u
    except Exception:
        pass
    for var in ("USER", "LOGNAME", "USERNAME"):
        if os.environ.get(var):
            return os.environ[var]
    return "user"


def get_installed_apps():
    """Discover installed desktop applications."""
    apps = []
    seen = set()
    dirs = [
        os.path.expanduser("~/.local/share/applications"),
        "/usr/local/share/applications",
        "/usr/share/applications",
    ]
    for d in dirs:
        if not os.path.isdir(d):
            continue
        for fpath in glob.glob(os.path.join(d, "*.desktop")):
            bname = os.path.basename(fpath)
            if bname in seen or "siteos-start" in bname:
                continue
            seen.add(bname)
            name, exec_cmd, no_display = None, None, False
            try:
                with open(fpath, "r", encoding="utf-8", errors="ignore") as f:
                    in_entry = False
                    for line in f:
                        line = line.strip()
                        if line == "[Desktop Entry]":
                            in_entry = True
                            continue
                        elif line.startswith("[") and in_entry:
                            break
                        if in_entry:
                            if line.startswith("Name=") and name is None:
                                name = line.split("=", 1)[1]
                            elif line.startswith("Exec=") and exec_cmd is None:
                                exec_cmd = line.split("=", 1)[1]
                            elif line == "NoDisplay=true":
                                no_display = True
            except Exception:
                continue

            if name and exec_cmd and not no_display:
                clean_exec = exec_cmd.split("%")[0].strip()
                apps.append((name, clean_exec))

    apps.sort(key=lambda x: x[0].lower())
    return apps


class SiteOSMenuWindow(Gtk.Window):
    def __init__(self):
        super().__init__(type=Gtk.WindowType.TOPLEVEL)
        self.set_title("Site OS Menu")
        self.set_decorated(False)
        self.set_skip_taskbar_hint(True)
        self.set_skip_pager_hint(True)
        # Using UTILITY hint ensures clicks and focus work properly without override-redirect issues
        self.set_type_hint(Gdk.WindowTypeHint.UTILITY)
        self.set_keep_above(True)
        self.set_can_focus(True)
        self.stick()

        self.get_style_context().add_class("menu-window")

        self.set_app_paintable(True)
        screen = self.get_screen()
        visual = screen.get_rgba_visual()
        if visual and screen.is_composited():
            self.set_visual(visual)

        self.active_category = None
        self._last_pos = None

        # Main horizontal container (left menu + right submenu)
        self.container = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=2)
        self.container.set_name("menu-container")
        self.add(self.container)

        # Left menu box
        self.left_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        self.left_box.set_name("menu")
        self.container.pack_start(self.left_box, False, False, 0)

        # Start title
        header_lbl = Gtk.Label(label="Start")
        header_lbl.get_style_context().add_class("menu-header")
        header_lbl.set_xalign(0.0)
        self.left_box.pack_start(header_lbl, False, False, 0)

        # Category buttons
        self.btn_programs = self.create_category_row("Programs", has_arrow=True)
        self.btn_programs.connect("clicked", lambda w: self.on_category_clicked("programs"))
        self.btn_programs.connect(
            "enter-notify-event", lambda w, e: self.on_category_hovered("programs")
        )
        self.left_box.pack_start(self.btn_programs, False, False, 0)

        self.btn_favorites = self.create_category_row("Favorites", has_arrow=True)
        self.btn_favorites.connect("clicked", lambda w: self.on_category_clicked("favorites"))
        self.btn_favorites.connect(
            "enter-notify-event", lambda w, e: self.on_category_hovered("favorites")
        )
        self.left_box.pack_start(self.btn_favorites, False, False, 0)

        self.btn_settings = self.create_category_row("Settings", has_arrow=False)
        self.btn_settings.connect("clicked", self.on_settings_clicked)
        self.btn_settings.connect("enter-notify-event", lambda w, e: self.hide_sub())
        self.left_box.pack_start(self.btn_settings, False, False, 0)

        self.btn_help = self.create_category_row("Help", has_arrow=False)
        self.btn_help.connect("clicked", self.on_help_clicked)
        self.btn_help.connect("enter-notify-event", lambda w, e: self.hide_sub())
        self.left_box.pack_start(self.btn_help, False, False, 0)

        # Fill spacer (matches .fill { height: 70px } in mockup)
        spacer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        spacer.set_size_request(-1, 70)
        self.left_box.pack_start(spacer, True, True, 0)

        # Footer (#foot)
        foot_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=0)
        foot_box.set_name("foot")

        username = get_current_user()
        user_lbl = Gtk.Label(label=username)
        user_lbl.get_style_context().add_class("user-label")
        user_lbl.set_xalign(0.0)
        foot_box.pack_start(user_lbl, True, True, 0)

        # Eject drive button (▲)
        btn_eject = Gtk.Button(label="▲")
        btn_eject.get_style_context().add_class("sq-button")
        btn_eject.set_tooltip_text("Eject Disc Drive (Открытие дисковода)")
        btn_eject.connect("clicked", self.on_eject_clicked)
        foot_box.pack_end(btn_eject, False, False, 0)

        # Power button (⏻)
        btn_power = Gtk.Button(label="⏻")
        btn_power.get_style_context().add_class("sq-button")
        btn_power.set_tooltip_text("Power / Log Out (Выключение)")
        btn_power.connect("clicked", self.on_power_clicked)
        foot_box.pack_end(btn_power, False, False, 4)

        self.left_box.pack_end(foot_box, False, False, 0)

        # Right submenu box
        self.sub_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=1)
        self.sub_box.set_name("sub")

        # Scroll container for right submenu
        self.sub_scroll = Gtk.ScrolledWindow()
        self.sub_scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        self.sub_scroll.set_min_content_height(260)
        self.sub_scroll.set_max_content_height(460)
        self.sub_scroll.set_propagate_natural_height(True)
        self.sub_scroll.add(self.sub_box)
        self.container.pack_start(self.sub_scroll, True, True, 0)

        # Submenu starts hidden
        self.sub_scroll.set_visible(False)

        # Events
        self.connect("key-press-event", self.on_key_press)
        self.connect("focus-out-event", self.on_focus_out)
        self.connect("destroy", self.cleanup_and_quit)
        self.connect("size-allocate", self.on_size_allocate)

    def create_category_row(self, title, has_arrow=False):
        btn = Gtk.Button()
        btn.get_style_context().add_class("menu-item")
        box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)

        dot = Gtk.Box()
        dot.get_style_context().add_class("menu-dot")
        box.pack_start(dot, False, False, 0)

        lbl = Gtk.Label(label=title)
        lbl.get_style_context().add_class("menu-item-text")
        lbl.set_xalign(0.0)
        box.pack_start(lbl, True, True, 0)

        if has_arrow:
            arrow = Gtk.Label(label="▸")
            arrow.get_style_context().add_class("menu-arrow")
            box.pack_end(arrow, False, False, 0)

        btn.add(box)
        return btn

    def create_sub_item(self, label_text, on_click_cmd):
        btn = Gtk.Button()
        btn.get_style_context().add_class("sub-item")
        lbl = Gtk.Label(label=label_text)
        lbl.get_style_context().add_class("sub-item-text")
        lbl.set_xalign(0.0)
        btn.add(lbl)
        btn.connect("clicked", lambda w: self.launch_and_close(on_click_cmd))
        return btn

    def on_category_hovered(self, cat):
        if self.active_category != cat:
            self.switch_category(cat)

    def on_category_clicked(self, cat):
        if self.sub_scroll.get_visible() and self.active_category == cat:
            self.hide_sub()
        else:
            self.switch_category(cat)

    def switch_category(self, cat):
        self.active_category = cat
        self.btn_programs.get_style_context().remove_class("active")
        self.btn_favorites.get_style_context().remove_class("active")

        if cat == "programs":
            self.btn_programs.get_style_context().add_class("active")
            self.populate_programs_sub()
            self.sub_scroll.set_visible(True)
            self.sub_box.show_all()
        elif cat == "favorites":
            self.btn_favorites.get_style_context().add_class("active")
            self.populate_favorites_sub()
            self.sub_scroll.set_visible(True)
            self.sub_box.show_all()

    def hide_sub(self):
        self.active_category = None
        self.btn_programs.get_style_context().remove_class("active")
        self.btn_favorites.get_style_context().remove_class("active")
        self.sub_scroll.set_visible(False)
        self.resize(1, 1)

    def populate_programs_sub(self):
        for child in self.sub_box.get_children():
            self.sub_box.remove(child)

        primary_apps = [
            ("Terminal", "xfce4-terminal"),
            ("File Explorer", "thunar"),
            ("System Monitor", "xfce4-taskmanager"),
            ("Text Editor", "sh -c 'xed || mousepad || xfce4-terminal -e nano'"),
            ("Web Browser", "sh -c 'firefox || chromium-browser || x-www-browser'"),
            ("Settings", "xfce4-settings-manager"),
            (
                "About Site OS",
                (
                    "zenity --info --title='About Site OS' --text='Site OS 1.0\\nLinux Mint XFCE"
                    " base\\nTheme: Site OS' 2>/dev/null || true"
                ),
            ),
        ]

        for name, cmd in primary_apps:
            self.sub_box.pack_start(self.create_sub_item(name, cmd), False, False, 0)

        # Other installed applications
        installed = get_installed_apps()
        if installed:
            sep = Gtk.Box()
            sep.get_style_context().add_class("sub-sep")
            self.sub_box.pack_start(sep, False, False, 2)

            for name, cmd in installed:
                if any(p[0].lower() == name.lower() for p in primary_apps):
                    continue
                self.sub_box.pack_start(self.create_sub_item(name, cmd), False, False, 0)

    def populate_favorites_sub(self):
        for child in self.sub_box.get_children():
            self.sub_box.remove(child)

        favs = [
            ("Site", "thunar ~/Desktop/Site"),
            ("Sessions", "thunar ~/Desktop/Sessions"),
            ("Personal", "thunar ~/Desktop/Personal"),
            ("Intake", "thunar ~/Desktop/Intake"),
            ("Desktop", "thunar ~/Desktop"),
            ("Home", "thunar ~"),
        ]

        for name, cmd in favs:
            self.sub_box.pack_start(self.create_sub_item(name, cmd), False, False, 0)

    def launch_and_close(self, cmd):
        self.cleanup_and_quit()
        subprocess.Popen(["sh", "-c", cmd], start_new_session=True)

    def on_settings_clicked(self, widget):
        self.launch_and_close("xfce4-settings-manager")

    def on_help_clicked(self, widget):
        msg = (
            "SITE OS QUICK HELP\\n\\n"
            "- Start menu: click categories to see applications\\n"
            "- ▲ button: eject / close optical disc drive\\n"
            "- ⏻ button: power off / log out\\n"
            "- Double-click folders to explore\\n"
            "- Round buttons: minimize / maximize / close"
        )
        self.launch_and_close(
            f"siteos-dialog --info --title='Help' --message='{msg}' 2>/dev/null || zenity --info"
            f" --title='Help' --text='{msg}' 2>/dev/null || true"
        )

    def on_eject_clicked(self, widget):
        self.cleanup_and_quit()
        subprocess.Popen(
            ["sh", "-c", "eject -T 2>/dev/null || eject 2>/dev/null || true"],
            start_new_session=True,
        )

    def on_power_clicked(self, widget):
        self.cleanup_and_quit()
        subprocess.Popen(["sh", "-c", "xfce4-session-logout || poweroff"], start_new_session=True)

    def on_key_press(self, widget, event):
        if event.keyval == Gdk.KEY_Escape:
            self.cleanup_and_quit()
            return True
        return False

    def on_focus_out(self, widget, event):
        GLib.timeout_add(150, self.check_focus)
        return False

    def check_focus(self):
        if not self.is_active():
            self.cleanup_and_quit()
        return False

    def on_size_allocate(self, widget, allocation):
        screen = Gdk.Screen.get_default()
        sw = screen.get_width() if screen else 1920
        sh = screen.get_height() if screen else 1080
        panel_height = 46
        gap = 8
        target_x = gap
        target_y = sh - panel_height - allocation.height - gap

        last_pos = getattr(self, "_last_pos", None)
        if last_pos != (target_x, target_y):
            self._last_pos = (target_x, target_y)
            self.move(max(0, target_x), max(0, target_y))

    def cleanup_and_quit(self, *args):
        try:
            if os.path.exists(PID_FILE):
                os.remove(PID_FILE)
        except Exception:
            pass
        Gtk.main_quit()


def main():
    css_provider = Gtk.CssProvider()
    css_provider.load_from_data(CSS_DATA)
    Gtk.StyleContext.add_provider_for_screen(
        Gdk.Screen.get_default(), css_provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
    )

    win = SiteOSMenuWindow()
    win.show_all()
    # Ensure submenu stays hidden on initial open
    win.sub_scroll.set_visible(False)
    win.present()
    Gtk.main()


if __name__ == "__main__":
    main()
