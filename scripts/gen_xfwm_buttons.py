#!/usr/bin/env python3
"""Generate round xfwm4 buttons (minimize, close) as XPM. NOT CHECKED IN VM."""
import os

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO, "theme", "SiteOS", "xfwm4", "xpm")


def mark_min(x, y):
    return 4 <= x <= 9 and y in (6, 7)


def mark_close(x, y):
    on_diag = abs(x - y) <= 1 or abs(x + y - 13) <= 1
    return on_diag and 3 <= x <= 10


def button(name, fill, ring, mark):
    w = h = 14
    cx = cy = 6.5
    pal = {".": "None", "f": fill, "r": ring, "m": "#1E2228"}
    rows = []
    for y in range(h):
        row = []
        for x in range(w):
            d = ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5
            if d > 6.5:
                row.append(".")
            elif d > 5.2:
                row.append("r")
            elif mark(x, y):
                row.append("m")
            else:
                row.append("f")
        rows.append("".join(row))
    lines = ["/* XPM */", f"static char * {name}_xpm[] = {{", '"14 14 4 1",']
    for k, v in pal.items():
        lines.append(f'"{k} c {v}",')
    for r in rows:
        lines.append(f'"{r}",')
    lines[-1] = lines[-1].rstrip(",")
    lines.append("};")
    return "\n".join(lines) + "\n"


def main():
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, "minimize.xpm"), "w", encoding="utf-8") as f:
        f.write(button("minimize", "#8E9AA6", "#A9B6C4", mark_min))
    with open(os.path.join(OUT, "close.xpm"), "w", encoding="utf-8") as f:
        f.write(button("close", "#B5656B", "#A9B6C4", mark_close))
    print(f"[xpm] wrote {OUT}/minimize.xpm and close.xpm")


if __name__ == "__main__":
    main()
