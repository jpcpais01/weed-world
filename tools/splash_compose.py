#!/usr/bin/env python3
"""Turns the rendered key art into the boot splash / loading screen picture.

    python3 tools/splash_compose.py [art_source/key_art.png]

The key art comes from tools/render_key_art.gd. Adds a soft vignette, a
darker band at the bottom for the loading text, and the game's title in
Fredoka, then writes branding/splash.png. The loading screen shows the same
file with the same "cover" fit, so boot splash and loading screen line up.
Needs Pillow and numpy.
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
FONT = ROOT / "ui" / "fonts" / "Fredoka.ttf"
TITLE = "Weed World"
TAGLINE = "a cozy forest for Kelings and friends"
# Title centre, as a fraction of the picture. Kept inside the middle 16:9
# area so phones (20:9) and PCs (16:9) both show all of it.
TITLE_AT = (0.5, 0.135)


def font(px: int, weight: int) -> ImageFont.FreeTypeFont:
    f = ImageFont.truetype(str(FONT), px)
    try:
        f.set_variation_by_axes([weight, 100])
    except (OSError, ValueError):
        pass
    return f


def grade(img: Image.Image) -> Image.Image:
    a = np.asarray(img.convert("RGB")).astype(np.float32) / 255.0
    h, w = a.shape[:2]
    y, x = np.mgrid[0:h, 0:w].astype(np.float32)
    y /= h
    x /= w
    # Vignette, plus a deep green band at the bottom so the loading text pops.
    v = np.sqrt(((x - 0.5) * 1.25) ** 2 + (y - 0.48) ** 2)
    shade = 1.0 - np.clip((v - 0.35) / 0.5, 0, 1) ** 1.5 * 0.45
    band = np.clip((y - 0.62) / 0.38, 0, 1) ** 1.4
    a = a * shade[..., None]
    a = a * (1 - band[..., None] * 0.62) + np.array([0.02, 0.07, 0.04]) * band[..., None] * 0.62
    # Lift the top a touch for the title.
    top = np.clip((0.32 - y) / 0.32, 0, 1) ** 2
    a = a * (1 - top[..., None] * 0.18)
    return Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8), "RGB").convert("RGBA")


def title(img: Image.Image) -> Image.Image:
    w, h = img.size
    big = font(int(h * 0.15), 650)
    small = font(int(h * 0.036), 500)
    cx, cy = TITLE_AT[0] * w, TITLE_AT[1] * h

    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.text((cx, cy), TITLE, font=big, anchor="mm", fill=(255, 255, 255, 255))
    alpha = layer.getchannel("A")

    # Deep forest shadow + warm glow behind the letters.
    shadow = alpha.filter(ImageFilter.GaussianBlur(h * 0.012))
    out = img.copy()
    out.alpha_composite(Image.merge("RGBA", [Image.new("L", img.size, v) for v in (10, 32, 18)] + [shadow.point(lambda p: int(p * 0.9))]), (0, int(h * 0.006)))
    glow = alpha.filter(ImageFilter.GaussianBlur(h * 0.03))
    out.alpha_composite(Image.merge("RGBA", [Image.new("L", img.size, v) for v in (255, 214, 120)] + [glow.point(lambda p: int(p * 0.55))]))

    # Letters: a fat dark-green outline, then a cream-to-lime gradient fill.
    outline = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(outline).text((cx, cy), TITLE, font=big, anchor="mm", fill=(20, 58, 28, 255), stroke_width=int(h * 0.009), stroke_fill=(20, 58, 28, 255))
    out.alpha_composite(outline)
    ys = np.linspace(0, 1, h, dtype=np.float32)[:, None]
    t = np.clip((ys - (cy / h - 0.07)) / 0.14, 0, 1)
    top_c, bot_c = np.array([255, 250, 222]), np.array([190, 236, 110])
    grad = (top_c * (1 - t[..., None]) + bot_c * t[..., None]).repeat(w, axis=1).astype(np.uint8)
    fill = Image.fromarray(grad, "RGB").convert("RGBA")
    fill.putalpha(alpha)
    out.alpha_composite(fill)

    tag = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ty = cy + h * 0.105
    ImageDraw.Draw(tag).text((cx, ty), TAGLINE, font=small, anchor="mm", fill=(255, 246, 214, 235), stroke_width=int(h * 0.004), stroke_fill=(16, 44, 22, 200))
    out.alpha_composite(tag)
    return out


def main() -> None:
    src = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "art_source" / "key_art.png"
    art = Image.open(src)
    out = title(grade(art))
    (ROOT / "branding").mkdir(exist_ok=True)
    out.convert("RGB").save(ROOT / "branding" / "splash.png", optimize=True)
    print("splash written:", out.size)


if __name__ == "__main__":
    main()
