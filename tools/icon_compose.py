#!/usr/bin/env python3
"""Builds every Weed World icon from the rendered Keling portrait.

    python3 tools/icon_compose.py [art_source/keling_portrait.png]

The portrait comes from tools/render_icon_portrait.gd (transparent background).
Writes into res://branding/:
  icon.png                 1024 px rounded-square app icon (project + window icon)
  icon.ico                 Windows exe icon, 16-256 px
  android_main_192.png     legacy Android launcher icon
  android_fg_432.png       adaptive icon foreground (Keling)
  android_bg_432.png       adaptive icon background (glade glow)
  android_mono_432.png     themed (monochrome) icon
Needs Pillow and numpy.
"""
import math
import random
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "branding"
S = 2048  # supersampled working size


def lerp(a, b, t):
    return a + (b - a) * t


def hexc(h):
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], dtype=np.float32) / 255.0


def background(size: int, seed: int = 7) -> Image.Image:
    """Dusky glade: deep teal canopy fading into a warm golden clearing glow,
    with soft light shafts and floating firefly bokeh."""
    y, x = np.mgrid[0:size, 0:size].astype(np.float32) / size
    top, mid, low = hexc("#08221f"), hexc("#17482f"), hexc("#3f7a2c")
    t = y[..., None]
    col = np.where(t < 0.55, lerp(top, mid, t / 0.55), lerp(mid, low, (t - 0.55) / 0.45))
    # Golden clearing glow behind the Keling's head.
    d = np.sqrt((x - 0.5) ** 2 + ((y - 0.40) * 1.05) ** 2)[..., None]
    glow = np.clip(1.0 - d / 0.62, 0.0, 1.0) ** 2.2
    col = col + glow * (hexc("#ffd27a") - col) * 0.85
    core = np.clip(1.0 - d / 0.26, 0.0, 1.0) ** 2.0
    col = col + core * (hexc("#fff3c8") - col) * 0.55
    # Vignette.
    v = np.sqrt((x - 0.5) ** 2 + (y - 0.5) ** 2)[..., None]
    col *= 1.0 - np.clip((v - 0.38) / 0.45, 0.0, 1.0) ** 1.6 * 0.55
    img = Image.fromarray((np.clip(col, 0, 1) * 255).astype(np.uint8), "RGB").convert("RGBA")

    # Light shafts falling from the upper left.
    rays = Image.new("L", (size, size), 0)
    rd = ImageDraw.Draw(rays)
    rng = random.Random(seed)
    for i in range(6):
        a = math.radians(58 + i * 7.5 + rng.uniform(-2, 2))
        w = math.radians(rng.uniform(1.2, 2.6))
        ox, oy = -0.15 * size, -0.25 * size
        L = 2.2 * size
        pts = [(ox, oy), (ox + math.cos(a - w) * L, oy + math.sin(a - w) * L), (ox + math.cos(a + w) * L, oy + math.sin(a + w) * L)]
        rd.polygon(pts, fill=int(rng.uniform(26, 48)))
    rays = rays.filter(ImageFilter.GaussianBlur(size * 0.012))
    img = Image.composite(Image.new("RGBA", (size, size), (255, 236, 170, 255)), img, rays)

    # Firefly bokeh: big soft discs far away, small crisp sparks near.
    bokeh = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    bd = ImageDraw.Draw(bokeh)
    palette = [(255, 226, 120), (200, 255, 130), (255, 180, 220), (255, 250, 210)]
    for i in range(34):
        r = rng.uniform(0.006, 0.03) * size
        cx, cy = rng.uniform(0.02, 0.98) * size, rng.uniform(0.04, 0.9) * size
        if abs(cx / size - 0.5) < 0.2 and 0.3 < cy / size < 0.9:
            continue  # keep the face clean
        c = rng.choice(palette)
        bd.ellipse((cx - r, cy - r, cx + r, cy + r), fill=c + (int(rng.uniform(60, 150)),))
    bokeh = bokeh.filter(ImageFilter.GaussianBlur(size * 0.004))
    img.alpha_composite(bokeh)
    sparks = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    sd = ImageDraw.Draw(sparks)
    for i in range(16):
        r = rng.uniform(0.003, 0.007) * size
        cx, cy = rng.uniform(0.05, 0.95) * size, rng.uniform(0.05, 0.75) * size
        if abs(cx / size - 0.5) < 0.22 and cy / size > 0.25:
            continue
        sd.ellipse((cx - r, cy - r, cx + r, cy + r), fill=(255, 245, 190, 255))
    halo = sparks.filter(ImageFilter.GaussianBlur(size * 0.01))
    img.alpha_composite(halo)
    img.alpha_composite(halo)
    img.alpha_composite(sparks)
    return img


def keling_layer(portrait: Image.Image, size: int, scale: float, head_y: float, glow_on: bool = True) -> Image.Image:
    """The Keling with a warm backlit halo, placed so its face sits at head_y."""
    p = portrait.crop(portrait.getchannel("A").getbbox())
    w = int(size * scale)
    h = int(p.height * w / p.width)
    p = p.resize((w, h), Image.LANCZOS)
    # Work on an oversized canvas so the halo never clips and close-ups may
    # spill past the edges.
    pad = size
    layer = Image.new("RGBA", (size + 2 * pad, size + 2 * pad), (0, 0, 0, 0))
    # The face (eyes) sits ~58% down the cropped portrait.
    ox = (size - w) // 2 + pad
    oy = int(size * head_y - h * 0.58) + pad
    if glow_on:
        r = int(size * 0.05)
        glow_a = Image.new("L", (w + 2 * r, h + 2 * r), 0)
        glow_a.paste(p.getchannel("A"), (r, r))
        glow_a = glow_a.filter(ImageFilter.GaussianBlur(size * 0.018)).point(lambda a: int(a * 0.85))
        glow = Image.new("RGBA", glow_a.size, (255, 222, 140, 0))
        glow.putalpha(glow_a)
        layer.alpha_composite(glow, (ox - r, oy - r))
    layer.alpha_composite(p, (ox, oy))
    layer = layer.crop((pad, pad, pad + size, pad + size))
    return layer


def rounded(img: Image.Image, radius: float) -> Image.Image:
    size = img.width
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size - 1, size - 1), radius=int(size * radius), fill=255)
    out = img.copy()
    out.putalpha(ImageChops.multiply(out.getchannel("A"), mask))
    # A thin light rim gives the tile some depth on dark taskbars.
    rim = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(rim)
    d.rounded_rectangle((0, 0, size - 1, size - 1), radius=int(size * radius), outline=70, width=max(2, size // 160))
    rim = rim.filter(ImageFilter.GaussianBlur(size / 700))
    out.alpha_composite(Image.merge("RGBA", (rim.point(lambda _: 255),) * 3 + (ImageChops.multiply(rim, mask),)))
    return out


def main() -> None:
    src = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "art_source" / "keling_portrait.png"
    portrait = Image.open(src).convert("RGBA")
    OUT.mkdir(exist_ok=True)

    bg = background(S)
    # Full icon: the Keling bursts out of the bottom of the tile, crown up top.
    full = bg.copy()
    full.alpha_composite(keling_layer(portrait, S, 0.82, 0.63))
    icon = rounded(full, 0.22)
    icon.resize((1024, 1024), Image.LANCZOS).save(OUT / "icon.png", optimize=True)
    icon.resize((192, 192), Image.LANCZOS).save(OUT / "android_main_192.png", optimize=True)
    # Tiny sizes (taskbar, title bar, file lists) get a close-up of the face so
    # the Keling still reads at 16 px.
    close = bg.copy()
    close.alpha_composite(keling_layer(portrait, S, 1.45, 0.66, False))
    close = rounded(close, 0.22)
    frames = [(icon if s >= 64 else close).resize((s, s), Image.LANCZOS) for s in (256, 128, 64, 48, 32, 24, 16)]
    frames[0].save(OUT / "icon.ico", sizes=[f.size for f in frames], append_images=frames[1:])

    # Adaptive icon: only the middle 72 of 108 dp is ever visible, and the mask
    # can be a circle, so the face and crown live in the central two thirds.
    bg.resize((432, 432), Image.LANCZOS).convert("RGB").save(OUT / "android_bg_432.png", optimize=True)
    fg = keling_layer(portrait, S, 0.64, 0.58)
    fg.resize((432, 432), Image.LANCZOS).save(OUT / "android_fg_432.png", optimize=True)
    mono_a = keling_layer(portrait, S, 0.60, 0.58, False).getchannel("A").point(lambda a: 255 if a > 140 else 0)
    mono = Image.new("RGBA", (S, S), (255, 255, 255, 0))
    mono.putalpha(mono_a)
    mono.resize((432, 432), Image.LANCZOS).save(OUT / "android_mono_432.png", optimize=True)
    print("icons written to", OUT)


if __name__ == "__main__":
    main()
