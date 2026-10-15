#!/usr/bin/env python3
"""imgcheck.py shot.(png|ppm) [--ref ref.png] [--min-fg PCT=1.0] [--min-colors N=16] [--bg #rrggbb]
Reads any PIL format incl. PPM P6. Reports size, % non-background pixels, distinct colors, and (with --ref) mean abs diff + SSIM.
Background = --bg, else the most common color. Exit 0 = scene non-empty, 1 = looks empty/blank,
2 = usage/IO error. With --ref, also fails (1) if SSIM < --min-ssim (default: not enforced)."""
import sys, argparse
import numpy as np
from PIL import Image

def load(p): return np.asarray(Image.open(p).convert("RGB"))

def ssim_np(a, b):  # global-window grayscale SSIM fallback (no scikit-image)
    a = a.mean(2); b = b.mean(2); C1, C2 = 6.5025, 58.5225
    ma, mb = a.mean(), b.mean(); va, vb = a.var(), b.var(); cov = ((a-ma)*(b-mb)).mean()
    return ((2*ma*mb+C1)*(2*cov+C2))/((ma*ma+mb*mb+C1)*(va+vb+C2))

ap = argparse.ArgumentParser()
ap.add_argument("png"); ap.add_argument("--ref"); ap.add_argument("--bg")
ap.add_argument("--min-fg", type=float, default=1.0); ap.add_argument("--min-colors", type=int, default=16)
ap.add_argument("--min-ssim", type=float)
a = ap.parse_args()
try: im = load(a.png)
except Exception as e: print("ERROR", e); sys.exit(2)
h, w, _ = im.shape
flat = im.reshape(-1, 3)
packed = (flat[:,0].astype(np.uint32) << 16) | (flat[:,1].astype(np.uint32) << 8) | flat[:,2]
vals, cnt = np.unique(packed, return_counts=True)
bg = int(a.bg.lstrip("#"), 16) if a.bg else int(vals[cnt.argmax()])
fg = 100.0 * (packed != bg).mean()
print(f"size: {w}x{h}\nbackground: #{bg:06x}\nnon_background_pct: {fg:.2f}\ndistinct_colors: {len(vals)}")
ok = fg >= a.min_fg and len(vals) >= a.min_colors
if a.ref:
    r = load(a.ref)
    if r.shape != im.shape: print(f"ref size mismatch {r.shape[1]}x{r.shape[0]}"); sys.exit(1)
    mad = np.abs(im.astype(float) - r.astype(float)).mean()
    try:
        from skimage.metrics import structural_similarity as ss
        s = ss(im, r, channel_axis=2); how = "skimage"
    except Exception:
        s = ssim_np(im, r); how = "numpy-global"
    print(f"mean_abs_diff: {mad:.3f}\nssim: {s:.4f} ({how})")
    if a.min_ssim is not None and s < a.min_ssim: ok = False
print("RESULT:", "NON-EMPTY" if ok else "EMPTY/FAIL"); sys.exit(0 if ok else 1)
