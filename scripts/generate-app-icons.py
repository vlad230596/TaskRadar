#!/usr/bin/env python3
"""Draws every app icon TaskRadar ships, from one geometry definition.

Why a script and not a folder of exported PNGs: the same mark has to exist in
about twenty sizes across three platforms (a 16 px favicon, a 432 px Android
adaptive foreground, a seven-image .ico), and each of them is a separate file
that a design tool exports separately. Kept by hand they drift — one size gets
the new colour, the rest keep the old one, and nobody notices because nobody
looks at a 24 px notification icon on purpose. Here the geometry lives once, at
the top of this file, and every target is derived from it.

The mark: a radar sweep. Two rings, a 60° sector opening up-and-right from the
centre, one amber blip on the inner ring — the current task among the quiet
ones. Dark indigo tile, `#1B2050`.

Run it after changing anything above the OUTPUTS section:

    python -m pip install pillow
    python scripts/generate-app-icons.py

It overwrites its outputs in place and prints each one. Nothing else in the
build calls it: icons change a few times in a project's life, and a generated
binary in the tree is easier to review in a diff than a build step nobody runs.

Drawing is done with Pillow rather than by rasterising the SVG, because that
would add a renderer (cairo/resvg/a headless browser) to the toolchain for one
shape made of two circles, a pie slice and two dots. The SVG masters under
design/icon/ are written from the same constants for the same reason the PNGs
are: so they cannot disagree with what ships.
"""

from pathlib import Path

from PIL import Image, ImageDraw

REPO = Path(__file__).resolve().parent.parent
APP = REPO / "app"
RES = APP / "android" / "app" / "src" / "main" / "res"

# ---------------------------------------------------------------- geometry --
#
# Everything is described on a 512x512 grid and scaled to the target size, so
# the numbers below match the SVG masters and the design canvas one to one.

GRID = 512
TILE_RADIUS = 116  # 22.7% — the iOS/Android "squircle" corner, near enough

BG = "#1B2050"  # tile
SECTOR = "#4A56BE"  # the sweep
RINGS = "#9AA5F7"  # rings and centre dot
BLIP = "#F0A33C"  # the one live mark

SECTOR_R = 208
# Pillow's angles: 0° is 3 o'clock and they grow clockwise, so 270→330 is the
# 60° wedge from straight up towards the upper right.
SECTOR_FROM, SECTOR_TO = 270, 330

RING_OUTER_R, RING_INNER_R, RING_W = 200, 116, 22
CENTRE_R = 16
BLIP_XY, BLIP_R = (338, 174), 28

# The monochrome silhouette is NOT the colour mark with its colours removed: it
# drops the sector (which would merge with the rings into a blob once every
# shape is the same colour) and thickens what is left, because it is shown at
# 24 dp in a status bar and tinted by the system.
MONO_OUTER_R, MONO_INNER_R, MONO_W = 192, 108, 30
MONO_CENTRE_R = 20
MONO_BLIP_XY, MONO_BLIP_R = (332, 180), 34

# How much of the 512 grid the drawing actually covers, corner to corner. Used
# to express sizes as "the art fills N% of this canvas" instead of as a scale
# factor nobody can picture.
ART_EXTENT = (RING_OUTER_R + RING_W / 2) * 2 / GRID  # 0.824
MONO_EXTENT = (MONO_OUTER_R + MONO_W / 2) * 2 / GRID  # 0.809

# Android's adaptive-icon safe zone is the central 72 dp of 108 dp: anything
# outside it can be cropped by a launcher's mask. Web maskable icons ask for the
# same idea with a 80%-diameter circle; 0.70 leaves room for the corner cuts.
ADAPTIVE_FILL = 0.66
MASKABLE_FILL = 0.70
# A status-bar icon is drawn inside a 22 dp square of its 24 dp canvas.
NOTIFICATION_FILL = 0.90

SS = 4  # supersampling factor: draw big, resize down, get antialiasing for free


def _draw(px, fill_fraction, extent, painter):
    """Paints on a transparent px*px canvas with the art scaled to fill_fraction."""
    canvas = Image.new("RGBA", (px, px), (0, 0, 0, 0))
    draw = ImageDraw.Draw(canvas)
    scale = px / GRID * (fill_fraction / extent)

    def box(cx, cy, r):
        return [
            px / 2 + (cx - r - GRID / 2) * scale,
            px / 2 + (cy - r - GRID / 2) * scale,
            px / 2 + (cx + r - GRID / 2) * scale,
            px / 2 + (cy + r - GRID / 2) * scale,
        ]

    painter(draw, box, scale)
    return canvas


def _paint_colour(draw, box, scale):
    draw.pieslice(box(256, 256, SECTOR_R), SECTOR_FROM, SECTOR_TO, fill=SECTOR)
    width = max(1, round(RING_W * scale))
    draw.ellipse(box(256, 256, RING_OUTER_R), outline=RINGS, width=width)
    draw.ellipse(box(256, 256, RING_INNER_R), outline=RINGS, width=width)
    draw.ellipse(box(256, 256, CENTRE_R), fill=RINGS)
    draw.ellipse(box(*BLIP_XY, BLIP_R), fill=BLIP)


def _paint_mono(colour):
    def painter(draw, box, scale):
        width = max(1, round(MONO_W * scale))
        draw.ellipse(box(256, 256, MONO_OUTER_R), outline=colour, width=width)
        draw.ellipse(box(256, 256, MONO_INNER_R), outline=colour, width=width)
        draw.ellipse(box(256, 256, MONO_CENTRE_R), fill=colour)
        draw.ellipse(box(*MONO_BLIP_XY, MONO_BLIP_R), fill=colour)

    return painter


def tile(size, rounded=True, fill_fraction=ART_EXTENT):
    """The full icon: art on its own tile."""
    px = size * SS
    art = _draw(px, fill_fraction, ART_EXTENT, _paint_colour)

    plate = Image.new("RGBA", (px, px), (0, 0, 0, 0))
    plate_draw = ImageDraw.Draw(plate)
    if rounded:
        plate_draw.rounded_rectangle(
            [0, 0, px - 1, px - 1], radius=TILE_RADIUS * px / GRID, fill=BG
        )
    else:
        # Maskable and adaptive backgrounds are full-bleed: the launcher, not
        # the icon, decides the shape.
        plate_draw.rectangle([0, 0, px - 1, px - 1], fill=BG)

    plate.alpha_composite(art)
    return plate.resize((size, size), Image.LANCZOS)


def foreground(size, fill_fraction=ADAPTIVE_FILL):
    """The art alone, transparent around it (Android adaptive foreground)."""
    px = size * SS
    return _draw(px, fill_fraction, ART_EXTENT, _paint_colour).resize(
        (size, size), Image.LANCZOS
    )


def monochrome(size, fill_fraction, colour="#FFFFFF"):
    """The silhouette, transparent around it (themed icons, status bar)."""
    px = size * SS
    return _draw(px, fill_fraction, MONO_EXTENT, _paint_mono(colour)).resize(
        (size, size), Image.LANCZOS
    )


# ----------------------------------------------------------------- masters --


def svg_colour():
    return f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {GRID} {GRID}" width="{GRID}" height="{GRID}" role="img" aria-label="TaskRadar">
  <rect width="{GRID}" height="{GRID}" rx="{TILE_RADIUS}" fill="{BG}"/>
  <path d="M256 256 L256 48 A{SECTOR_R} {SECTOR_R} 0 0 1 436.1 152 Z" fill="{SECTOR}"/>
  <g fill="none" stroke="{RINGS}" stroke-width="{RING_W}">
    <circle cx="256" cy="256" r="{RING_OUTER_R}"/>
    <circle cx="256" cy="256" r="{RING_INNER_R}"/>
  </g>
  <circle cx="256" cy="256" r="{CENTRE_R}" fill="{RINGS}"/>
  <circle cx="{BLIP_XY[0]}" cy="{BLIP_XY[1]}" r="{BLIP_R}" fill="{BLIP}"/>
</svg>
"""


def svg_mono():
    return f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {GRID} {GRID}" width="{GRID}" height="{GRID}" role="img" aria-label="TaskRadar">
  <g fill="none" stroke="currentColor" stroke-width="{MONO_W}">
    <circle cx="256" cy="256" r="{MONO_OUTER_R}"/>
    <circle cx="256" cy="256" r="{MONO_INNER_R}"/>
  </g>
  <circle cx="256" cy="256" r="{MONO_CENTRE_R}" fill="currentColor"/>
  <circle cx="{MONO_BLIP_XY[0]}" cy="{MONO_BLIP_XY[1]}" r="{MONO_BLIP_R}" fill="currentColor"/>
</svg>
"""


# ------------------------------------------------------------------ output --

# density -> multiplier against the mdpi baseline
DENSITIES = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}

# Windows wants one file holding every size the shell might ask for: 16 px in
# the title bar, 256 px in the "extra large icons" view of Explorer.
ICO_SIZES = [16, 24, 32, 48, 64, 128, 256]


def write(path, image):
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path)
    print(f"  {path.relative_to(REPO)}  {image.size[0]}px")


def main():
    print("web")
    # Kept at 32: a 16 px favicon renders the two rings as one grey smudge, and
    # every browser downsamples 32 for the places that still want 16.
    write(APP / "web" / "favicon.png", tile(32))
    for size in (192, 512):
        write(APP / "web" / "icons" / f"Icon-{size}.png", tile(size))
        write(
            APP / "web" / "icons" / f"Icon-maskable-{size}.png",
            tile(size, rounded=False, fill_fraction=MASKABLE_FILL),
        )
    # iOS rounds the home-screen icon itself and fills anything transparent with
    # black, so the one it reads is square-cornered rather than the rounded tile
    # the other targets use. 180 is what current iPhones and iPads ask for.
    write(APP / "web" / "icons" / "Icon-apple-180.png", tile(180, rounded=False))

    print("android")
    for density, factor in DENSITIES.items():
        write(RES / f"mipmap-{density}" / "ic_launcher.png", tile(round(48 * factor)))
        write(
            RES / f"mipmap-{density}" / "ic_launcher_foreground.png",
            foreground(round(108 * factor)),
        )
        write(
            RES / f"mipmap-{density}" / "ic_launcher_monochrome.png",
            monochrome(round(108 * factor), ADAPTIVE_FILL),
        )
        write(
            RES / f"drawable-{density}" / "ic_notification.png",
            monochrome(round(24 * factor), NOTIFICATION_FILL),
        )

    print("windows")
    frames = [tile(size) for size in ICO_SIZES]
    ico = APP / "windows" / "runner" / "resources" / "app_icon.ico"
    frames[-1].save(
        ico,
        format="ICO",
        sizes=[(size, size) for size in ICO_SIZES],
        append_images=frames[:-1],
    )
    print(f"  {ico.relative_to(REPO)}  {', '.join(str(s) for s in ICO_SIZES)}px")

    print("masters")
    for name, text in (
        ("taskradar-icon.svg", svg_colour()),
        ("taskradar-icon-monochrome.svg", svg_mono()),
    ):
        path = REPO / "design" / "icon" / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
        print(f"  {path.relative_to(REPO)}")


if __name__ == "__main__":
    main()
