#!/usr/bin/env python3
"""Builds the app's images from the source icon, which is never edited.

Usage: python3 -I design/ui/assets/build.py   (needs Pillow)
Writes icon/AppIcon.png: 1024 x 1024, transparent, the artwork in the 824 x 824 macOS icon
body (100 pt margin each side) with continuous corners, no shadow. design-system.md §6 App icon.
"""
import math
from pathlib import Path

from PIL import Image, ImageDraw

HERE = Path(__file__).parent
SOURCE = HERE / "icon" / "Raccoon App Icon.png"
CANVAS, BODY = 1024, 824
# A superellipse of this exponent has the continuous corners of the macOS icon shape; on an
# 824 body its corners read like a 185 pt radius.
EXPONENT = 5
SUPERSAMPLE = 4


def squircle_mask(size):
    big = size * SUPERSAMPLE
    half = big / 2
    points = []
    for step in range(1440):
        t = 2 * math.pi * step / 1440
        c, s = math.cos(t), math.sin(t)
        points.append((half + half * math.copysign(abs(c) ** (2 / EXPONENT), c),
                       half + half * math.copysign(abs(s) ** (2 / EXPONENT), s)))
    mask = Image.new("L", (big, big), 0)
    ImageDraw.Draw(mask).polygon(points, fill=255)
    return mask.resize((size, size), Image.LANCZOS)


def app_icon(source):
    art = source.convert("RGB").resize((BODY, BODY), Image.LANCZOS)
    icon = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    margin = (CANVAS - BODY) // 2
    icon.paste(art, (margin, margin), squircle_mask(BODY))
    return icon


# The empty state's mark (design-system.md §6 Empty state). Luminance below DARK is the navy
# background and the mask patches, eyes and nose (27-43 in the source): clear. At LIGHT and above
# it is the white fur (231): opaque. The gray crown (155) lands about half way.
DARK, LIGHT = 60, 232
MARK_PX = 320  # 160 pt @2x


def face_mark(source):
    lum = source.convert("L")
    alpha = lum.point(lambda v: max(0, min(255, round((v - DARK) * 255 / (LIGHT - DARK)))))
    left, top, right, bottom = alpha.getbbox()
    side = max(right - left, bottom - top)
    cx, cy = (left + right) // 2, (top + bottom) // 2
    box = (cx - side // 2, cy - side // 2, cx - side // 2 + side, cy - side // 2 + side)
    alpha = alpha.crop(box).resize((MARK_PX, MARK_PX), Image.LANCZOS)
    mark = Image.new("RGBA", (MARK_PX, MARK_PX), (0, 0, 0, 0))
    mark.putalpha(alpha)
    return mark


def main():
    source = Image.open(SOURCE)
    assert source.size[0] == source.size[1], "the source icon must be square"
    icon = app_icon(source)
    icon.save(HERE / "icon" / "AppIcon.png", optimize=True)
    # The corners and the margin are clear; the body's center is the artwork, opaque.
    assert icon.getpixel((0, 0))[3] == 0 and icon.getpixel((99, 512))[3] == 0
    assert icon.getpixel((512, 512))[3] == 255 and icon.getpixel((101, 512))[3] == 255
    print("wrote icon/AppIcon.png")

    mark = face_mark(source)
    (HERE / "empty").mkdir(exist_ok=True)
    mark.save(HERE / "empty" / "RaccoonFace@2x.png", optimize=True)
    # A template: black everywhere, the shape only in alpha; the corners are clear.
    assert mark.getpixel((0, 0))[3] == 0 and all(mark.getpixel((x, y))[:3] == (0, 0, 0) for x, y in [(160, 160), (100, 250)])
    print("wrote empty/RaccoonFace@2x.png")


main()
