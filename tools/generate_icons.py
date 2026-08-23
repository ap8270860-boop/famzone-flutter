#!/usr/bin/env python3
"""
Build every launcher icon SFamily needs from the 1142px brand tile.

The master is a rounded-square tile that carries its own gradient, which is
exactly wrong for Android 8+: adaptive icons are two full-bleed layers that
the launcher masks into whatever shape the phone uses (circle on Pixel,
squircle on Samsung, teardrop on some OEM skins). Handing it a pre-rounded
tile gets you a rounded square floating inside a circle, with grey corners.

So the tile is split into two layers:

  background  a full-bleed gradient, bilinear-interpolated from the tile's
              four corner colours, so it matches the master and there is
              never a transparent corner for the mask to expose
  foreground  the tile artwork scaled to 80% of the 108dp canvas

Scaling matters. The 108dp canvas only ever shows its middle 72dp, and only
the middle 66dp is guaranteed. The glyph fills ~78% of the tile, so at 80%
scale it lands at ~67dp — inside the safe circle, while the tile itself
(86dp) still covers the visible window edge to edge, whatever mask is used.

Run from the repository root, after replacing assets/logo/sfamily_mark_1024.png:

    python tools/generate_icons.py
    flutter clean && flutter run

Requires Pillow and numpy:  pip install pillow numpy
"""

from PIL import Image, ImageDraw
import numpy as np
import os

SRC = 'assets/logo/sfamily_mark_1024.png'
OUT = '.'

# Corner colours sampled from the master, inside its rounded corners.
TL, TR = (1, 155, 228), (33, 205, 124)
BL, BR = (1, 38, 96), (3, 75, 69)

# Legacy launcher icon: 48dp base.
LEGACY = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}
# Adaptive layers: 108dp canvas.
ADAPTIVE = {'mdpi': 108, 'hdpi': 162, 'xhdpi': 216, 'xxhdpi': 324, 'xxxhdpi': 432}

# How much of the adaptive canvas the tile occupies.
TILE_SCALE = 0.80

IOS = [
    ('Icon-App-20x20@1x.png', 20), ('Icon-App-20x20@2x.png', 40),
    ('Icon-App-20x20@3x.png', 60), ('Icon-App-29x29@1x.png', 29),
    ('Icon-App-29x29@2x.png', 58), ('Icon-App-29x29@3x.png', 87),
    ('Icon-App-40x40@1x.png', 40), ('Icon-App-40x40@2x.png', 80),
    ('Icon-App-40x40@3x.png', 120), ('Icon-App-60x60@2x.png', 120),
    ('Icon-App-60x60@3x.png', 180), ('Icon-App-76x76@1x.png', 76),
    ('Icon-App-76x76@2x.png', 152), ('Icon-App-83.5x83.5@2x.png', 167),
    ('Icon-App-1024x1024@1x.png', 1024),
]


def gradient(size):
    """The tile's gradient, bilinear from the four corner colours."""
    u = np.linspace(0, 1, size)[None, :, None]   # left -> right
    v = np.linspace(0, 1, size)[:, None, None]   # top -> bottom
    tl, tr = np.array(TL, float), np.array(TR, float)
    bl, br = np.array(BL, float), np.array(BR, float)
    top = tl * (1 - u) + tr * u
    bot = bl * (1 - u) + br * u
    out = top * (1 - v) + bot * v
    rgb = np.repeat(np.repeat(out, 1, 0), 1, 1).astype(np.uint8)
    rgb = np.broadcast_to(rgb, (size, size, 3)).copy()
    return Image.fromarray(rgb, 'RGB')


def full_bleed(master):
    """The tile with its rounded corners filled by the gradient."""
    n = master.size[0]
    base = gradient(n).convert('RGBA')
    base.alpha_composite(master)
    return base


def circle(img):
    """Circular crop — for ic_launcher_round on Android 7.1 launchers."""
    n = img.size[0]
    # 4x supersample the mask so the edge is smooth rather than stair-stepped.
    mask = Image.new('L', (n * 4, n * 4), 0)
    ImageDraw.Draw(mask).ellipse((0, 0, n * 4 - 1, n * 4 - 1), fill=255)
    mask = mask.resize((n, n), Image.LANCZOS)
    out = img.convert('RGBA').copy()
    out.putalpha(mask)
    return out


def save(img, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path, 'PNG', optimize=True)


def resize(img, n):
    return img.resize((n, n), Image.LANCZOS)


master = Image.open(SRC).convert('RGBA')
bleed = full_bleed(master)
print(f'master {master.size[0]}px -> full-bleed {bleed.size[0]}px')

# --- Android -------------------------------------------------------------

for dpi, n in LEGACY.items():
    d = f'{OUT}/android/app/src/main/res/mipmap-{dpi}'
    save(resize(master, n), f'{d}/ic_launcher.png')
    save(resize(circle(bleed), n), f'{d}/ic_launcher_round.png')

for dpi, n in ADAPTIVE.items():
    d = f'{OUT}/android/app/src/main/res/mipmap-{dpi}'

    save(gradient(n), f'{d}/ic_launcher_background.png')

    # Foreground: the tile, centred, at 80% of the canvas.
    #
    # The *full-bleed* tile, not the master — its rounded corners would
    # otherwise sit inside the mask and expose the background layer as a
    # dark crescent at each corner. A solid square at this size contains
    # every standard mask, so the join never shows.
    fg = Image.new('RGBA', (n, n), (0, 0, 0, 0))
    t = int(round(n * TILE_SCALE))
    off = (n - t) // 2
    fg.alpha_composite(resize(bleed, t), (off, off))
    save(fg, f'{d}/ic_launcher_foreground.png')

ADAPTIVE_XML = '''<?xml version="1.0" encoding="utf-8"?>
<!--
  Android 8+ launcher icon.

  Two full-bleed layers the launcher masks into the phone's own shape, so the
  icon looks native on a Pixel circle and a Samsung squircle alike. Generated
  from assets/logo/sfamily_mark_1024.png — regenerate rather than hand-editing.
-->
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@mipmap/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
</adaptive-icon>
'''

save_dir = f'{OUT}/android/app/src/main/res/mipmap-anydpi-v26'
os.makedirs(save_dir, exist_ok=True)
for name in ('ic_launcher.xml', 'ic_launcher_round.xml'):
    with open(f'{save_dir}/{name}', 'w', encoding='utf-8') as f:
        f.write(ADAPTIVE_XML)

# --- iOS -----------------------------------------------------------------
#
# iOS icons must be fully opaque — the App Store rejects any alpha channel,
# and the system rounds the corners itself, so the square full-bleed tile is
# what's wanted here rather than the pre-rounded master.

for name, n in IOS:
    save(resize(bleed, n).convert('RGB'), f'{OUT}/ios/Runner/Assets.xcassets/AppIcon.appiconset/{name}')

# --- Store listing -------------------------------------------------------

save(resize(bleed, 512).convert('RGB'), f'{OUT}/assets/store/play-store-icon-512.png')

# --- Report --------------------------------------------------------------

print('Icons written. Run from the repo root:')
print('  python tools/generate_icons.py && flutter clean && flutter run')
