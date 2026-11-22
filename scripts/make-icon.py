#!/usr/bin/env python3
"""Draws Sprout's app icon layers: a dot-matrix seedling over a seed bed.

Writes the Icon Composer bundle Resources/Sprout.icon (SVG layers + icon.json) and, with
--preview PATH, a flat PNG to look at. Edit PATTERN to change the drawing:
  '#' lit dot, 'o' International Orange (new growth: data arriving), '.' unlit dot.
"""
import json, os, sys

PATTERN = """
.............
.##.......#o.
####.....####
#####...#####
.#####.#####.
...###.###...
.....###.....
......#......
......#......
......#......
......#......
.###########.
.............
"""
SIZE = 1024          # Icon Composer canvas, points
PITCH = 54           # distance between dot centres
DOT = 40             # dot diameter
UNLIT = 0.10         # opacity of an unlit dot, like the app's LED panel
SIGNAL = "#FF4F00"   # International Orange (Palette's Signal)

rows = [r for r in PATTERN.strip().splitlines()]
n = len(rows[0])
assert all(len(r) == n for r in rows), "every row needs the same width"
origin_x = (SIZE - PITCH * (n - 1)) / 2
origin_y = (SIZE - PITCH * (len(rows) - 1)) / 2


def dots(kinds):
    for y, row in enumerate(rows):
        for x, c in enumerate(row):
            if c in kinds:
                yield origin_x + x * PITCH, origin_y + y * PITCH


def svg(kinds, fill, opacity=1.0):
    circles = "".join(f'<circle cx="{cx:.1f}" cy="{cy:.1f}" r="{DOT/2}"/>' for cx, cy in dots(kinds))
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{SIZE}" height="{SIZE}" viewBox="0 0 {SIZE} {SIZE}">'
            f'<g fill="{fill}" fill-opacity="{opacity}">{circles}</g></svg>\n')


root = os.path.join(os.path.dirname(__file__), "..", "Resources", "Sprout.icon")
os.makedirs(os.path.join(root, "Assets"), exist_ok=True)
layers = [("unlit", ".", "#FFFFFF", UNLIT), ("lit", "#", "#FFFFFF", 1.0), ("signal", "o", SIGNAL, 1.0)]
for name, kinds, fill, opacity in layers:
    with open(os.path.join(root, "Assets", f"{name}.svg"), "w") as f:
        f.write(svg(kinds, fill, opacity))

icon = {
    # The app's ground: black in every appearance, so the panel reads as the app.
    "fill": {"solid": "srgb:0.00000,0.00000,0.00000,1.00000"},
    "groups": [
        # Topmost first. Only the lit and orange dots catch the glass highlight.
        {"layers": [{"image-name": "signal.svg", "name": "signal", "glass": True},
                    {"image-name": "lit.svg", "name": "lit", "glass": True}],
         "shadow": {"kind": "neutral", "opacity": 0.5},
         "translucency": {"enabled": False, "value": 0}},
        {"layers": [{"image-name": "unlit.svg", "name": "unlit", "glass": False}],
         "shadow": {"kind": "none", "opacity": 0},
         "translucency": {"enabled": False, "value": 0}},
    ],
    "supported-platforms": {"squares": ["macOS"]},
}
with open(os.path.join(root, "icon.json"), "w") as f:
    json.dump(icon, f, indent=2)
    f.write("\n")

if "--preview" in sys.argv:
    from PIL import Image, ImageDraw
    path = sys.argv[sys.argv.index("--preview") + 1]
    scale = 1
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    mask = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, SIZE - 1, SIZE - 1], radius=int(SIZE * 0.225), fill=255)
    bg = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 255))
    img.paste(bg, (0, 0), mask)
    d = ImageDraw.Draw(img)
    colours = {".": (255, 255, 255, int(255 * UNLIT)), "#": (255, 255, 255, 255), "o": (255, 79, 0, 255)}
    overlay = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    od = ImageDraw.Draw(overlay)
    for kind, colour in colours.items():
        for cx, cy in dots(kind):
            od.ellipse([cx - DOT / 2, cy - DOT / 2, cx + DOT / 2, cy + DOT / 2], fill=colour)
    img = Image.alpha_composite(img, overlay)
    img.save(path)
    print("preview:", path)
