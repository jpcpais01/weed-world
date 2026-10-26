#!/usr/bin/env python3
"""Makes the store art that ships next to WeedWorld.exe in every Windows zip:

    python3 tools/store_art_compose.py

- store/weed_world_banner.png (3840x1240, Steam library hero size): the gang
  on the meadow path with the title over the treetops.
- store/weed_world_cover.png (1200x1800, Steam library capsule 2x): the gang
  huddled up, title in the sky, tagline on the path.
- store/weed_world_logo.png: the game icon (branding/icon.png).

The renders come from tools/render_key_art.gd (needs a real renderer):
    xvfb-run godot --path . --rendering-driver vulkan --resolution 3840x1240 -s res://tools/render_key_art.gd -- art_source/banner_art.png --fov=58 --back=0.6 --look-lift=0.55
    xvfb-run godot --path . --rendering-driver vulkan --resolution 1200x1800 -s res://tools/render_key_art.gd -- art_source/cover_art.png --fov=56 --back=1.2 --lift=0.1 --look-lift=0.9 --squeeze=0.55
Needs Pillow and numpy.
"""
import shutil
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

from splash_compose import ROOT, font, title

OUT = ROOT / "store"


def grade(img: Image.Image, title_y: float, foot: float) -> Image.Image:
    """Soft vignette, a gentle darkening behind the title so it reads, and a
    warm lift through the middle where the gang stands."""
    a = np.asarray(img.convert("RGB")).astype(np.float32) / 255.0
    h, w = a.shape[:2]
    y, x = np.mgrid[0:h, 0:w].astype(np.float32)
    y /= h
    x /= w
    aspect = w / h
    v = np.sqrt(((x - 0.5) * min(aspect, 1.6)) ** 2 + (y - 0.52) ** 2)
    shade = 1.0 - np.clip((v - 0.4) / 0.6, 0, 1) ** 1.6 * 0.5
    a = a * shade[..., None]
    halo = np.exp(-(((y - title_y) / 0.16) ** 2)) * np.exp(-(((x - 0.5) * aspect / 0.9) ** 2))
    a = a * (1 - halo[..., None] * 0.22)
    if foot > 0:
        band = np.clip((y - (1 - foot)) / foot, 0, 1) ** 1.3
        a = a * (1 - band[..., None] * 0.6) + np.array([0.02, 0.07, 0.04]) * band[..., None] * 0.6
    warm = np.exp(-(((y - 0.6) / 0.25) ** 2))[..., None] * np.array([0.035, 0.02, -0.01])
    a = a + warm
    return Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8), "RGB").convert("RGBA")


def tagline_low(img: Image.Image, text: str, y: float, px: int) -> Image.Image:
    w, h = img.size
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(layer).text((w / 2, y * h), text, font=font(px, 560), anchor="mm",
            fill=(255, 246, 214, 245), stroke_width=max(2, px // 9), stroke_fill=(16, 44, 22, 220))
    out = img.copy()
    out.alpha_composite(layer)
    return out


def main() -> None:
    OUT.mkdir(exist_ok=True)
    art = ROOT / "art_source"

    banner = Image.open(art / "banner_art.png")
    b = grade(banner, 0.17, 0.0)
    b = title(b, at=(0.5, 0.17), unit=banner.height * 1.15)
    b.convert("RGB").save(OUT / "weed_world_banner.png", optimize=True)

    cover = Image.open(art / "cover_art.png")
    c = grade(cover, 0.12, 0.22)
    # Title across the sky; the tagline sits on the path below the gang.
    c = title(c, at=(0.5, 0.115), unit=cover.width * 1.05, tagline="")
    c = tagline_low(c, "a cozy forest for Kelings and friends", 0.93, int(cover.width * 0.047))
    c.convert("RGB").save(OUT / "weed_world_cover.png", optimize=True)

    shutil.copyfile(ROOT / "branding" / "icon.png", OUT / "weed_world_logo.png")
    print("store art written:", banner.size, cover.size)


if __name__ == "__main__":
    main()
