#!/usr/bin/env python3
"""Site OS wallpaper generator (dark topographic map).

Gaussian-filtered fBm height field, tanh plateaus/slopes, 7 contour levels,
constant ~2-3 px line width, colours bg #44566A / line #B4CADE, light vignette.

Usage (from repo root):
    python scripts/gen_wallpaper.py --out theme/wallpaper/site-os-topo.png
    python scripts/gen_wallpaper.py --out x.png --size 1920x1080 --seed 7

NOT CHECKED IN VM. Requires: numpy, scipy, pillow.
"""
import argparse
import os

import numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter

BG = np.array([0x44, 0x56, 0x6A], dtype=np.float64)
LC = np.array([0xB4, 0xCA, 0xDE], dtype=np.float64)
LINE_ALPHA = 0.60
LEVELS = 7
VIGNETTE = 0.06


def fbm(w, h, rng, sigmas=(150, 65, 28), weights=(1.0, 0.45, 0.10)):
    field = np.zeros((h, w))
    for s, wt in zip(sigmas, weights):
        n = gaussian_filter(rng.standard_normal((h, w)), s, mode="wrap")
        field += wt * n / n.std()
    return field


def normalize(a):
    return (a - a.min()) / (a.max() - a.min() + 1e-12)


def render(w, h, seed):
    rng = np.random.default_rng(seed)
    height = normalize(fbm(w, h, rng))
    height = normalize(np.tanh(2.6 * (height - 0.5)))

    v = height * LEVELS
    gy, gx = np.gradient(v)
    dist_px = np.abs(v - np.round(v)) / (np.hypot(gx, gy) + 1e-6)
    line = np.clip(1.5 - dist_px, 0, 1)

    alpha = LINE_ALPHA * line[..., None]
    img = BG * (1 - alpha) + LC * alpha

    yy, xx = np.mgrid[0:h, 0:w]
    r = np.hypot((xx - w / 2) / (w / 2), (yy - h / 2) / (h / 2))
    img *= (1 - VIGNETTE * np.clip(r, 0, 1.2) ** 2)[..., None]

    return Image.fromarray(img.clip(0, 255).astype(np.uint8), "RGB")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--size", default="1920x1080")
    ap.add_argument("--seed", type=int, default=7)
    args = ap.parse_args()

    w, h = (int(x) for x in args.size.lower().split("x"))
    out = os.path.abspath(args.out)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    render(w, h, args.seed).save(out, format="PNG", optimize=True)
    print(f"[wallpaper] wrote {out} ({w}x{h}, seed={args.seed})")


if __name__ == "__main__":
    main()
