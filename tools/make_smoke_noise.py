#!/usr/bin/env python3
"""Bakes the tileable noise that smoke is drawn from: assets/fx/smoke_noise.png.

    python3 tools/make_smoke_noise.py

R: soft billows (low-frequency fBm), G: wispy ridges (turbulence that
thins into strands), B: fine grain. All three tile seamlessly, so the smoke
shaders can scroll and distort them freely. Needs numpy and Pillow.
"""
import os

import numpy as np
from PIL import Image

N = 256
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "fx", "smoke_noise.png")
rng = np.random.default_rng(77)


def band(lo, hi):
    """White noise filtered to a band of spatial frequencies (tiles exactly,
    since it is built in the Fourier domain)."""
    f = np.fft.fftfreq(N) * N
    r = np.sqrt(f[:, None] ** 2 + f[None, :] ** 2)
    mask = np.exp(-((np.log2(np.maximum(r, 1e-6)) - np.log2((lo + hi) / 2)) ** 2) / 0.5)
    mask[0, 0] = 0
    x = np.fft.ifft2(np.fft.fft2(rng.standard_normal((N, N))) * mask).real
    return x / np.abs(x).max()


def fbm(base, octaves, gain=0.5):
    x = np.zeros((N, N))
    amp = 1.0
    for o in range(octaves):
        f = base * 2 ** o
        x += band(f * 0.8, f * 1.25) * amp
        amp *= gain
    x -= x.min()
    return x / x.max()


def norm(x):
    x = x - x.min()
    return x / x.max()


billow = fbm(3, 5, 0.55)
# Ridged turbulence: 1 - |noise| makes thin bright strands.
wisp = np.zeros((N, N))
amp = 1.0
for o in range(4):
    f = 4 * 2 ** o
    wisp += (1.0 - np.abs(band(f * 0.8, f * 1.25))) ** 3 * amp
    amp *= 0.55
wisp = norm(wisp) ** 1.4
grain = fbm(16, 3, 0.6)

img = np.stack([billow, norm(wisp), grain], axis=-1)
os.makedirs(os.path.dirname(OUT), exist_ok=True)
Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8), "RGB").save(OUT, optimize=True)
print("wrote", OUT)
