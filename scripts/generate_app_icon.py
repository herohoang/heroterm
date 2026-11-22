"""Generate the HeroTerm macOS app icon set (dark terminal tile, green >_ prompt)."""
from PIL import Image, ImageDraw, ImageFont

S = 1024
INSET = 96            # transparent margin around the tile (macOS style)
RADIUS = 190
TOP = (17, 26, 46)    # gradient top  #111A2E
BOTTOM = (7, 11, 20)  # gradient bottom #070B14
GREEN = (61, 220, 132)
GREEN_DIM = (38, 160, 96)
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf"

# vertical gradient tile
tile = Image.new("RGBA", (S, S), (0, 0, 0, 0))
grad = Image.new("RGBA", (S, S))
gd = ImageDraw.Draw(grad)
for y in range(S):
    t = y / S
    gd.line([(0, y), (S, y)], fill=tuple(int(TOP[i] + (BOTTOM[i] - TOP[i]) * t) for i in range(3)) + (255,))
mask = Image.new("L", (S, S), 0)
md = ImageDraw.Draw(mask)
md.rounded_rectangle([INSET, INSET, S - INSET, S - INSET], radius=RADIUS, fill=255)
tile.paste(grad, (0, 0), mask)

d = ImageDraw.Draw(tile)
# subtle inner border
d.rounded_rectangle([INSET, INSET, S - INSET, S - INSET], radius=RADIUS, outline=(255, 255, 255, 28), width=3)

font = ImageFont.truetype(FONT, 430)
# draw ">" then "_" as a cursor block for a terminal feel
d.text((248, 268), ">", font=font, fill=GREEN)
# blinking-cursor block after the prompt
d.rounded_rectangle([560, 560, 800, 640], radius=18, fill=GREEN)
# small dim dot row (window controls nod) top-left inside tile
for i, col in enumerate([(255, 95, 86), (255, 189, 46), (39, 201, 63)]):
    cx = 190 + i * 64
    d.ellipse([cx, 176, cx + 34, 210], fill=col + (255,))

import os
out_dir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                       "macos/Runner/Assets.xcassets/AppIcon.appiconset")
for size in (16, 32, 64, 128, 256, 512, 1024):
    tile.resize((size, size), Image.LANCZOS).save(f"{out_dir}/app_icon_{size}.png")
tile.save("/tmp/heroterm_icon_preview.png")  # preview only
print("icons written")
