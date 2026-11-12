# genmon status line

`siteos-status.sh` is the source for the panel's genmon plugin. `install.sh --step xfce-config` copies it to `/usr/local/share/siteos/`.

Panel setup: add a genmon item with command `/usr/local/share/siteos/siteos-status.sh`, period 1 s. Requires the `xfce4-genmon-plugin` package (installed in the xfce-config step). **Not checked in VM.**
