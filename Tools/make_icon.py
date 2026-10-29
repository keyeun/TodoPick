"""Turns Resources/icon-source.webp into Resources/AppIcon.png on Apple's macOS icon grid
(824px rounded square + soft shadow on a 1024px transparent canvas).
Usage: python3 Tools/make_icon.py [inset]"""
import sys
from PIL import Image, ImageDraw, ImageFilter

SRC, OUT = "Resources/icon-source.webp", "Resources/AppIcon.png"
inset = int(sys.argv[1]) if len(sys.argv) > 1 else 55

src = Image.open(SRC).convert("RGB")
# The artwork's rounded square spans x 95..1159 in the source; crop inside it so no white rim remains.
l, t, r = 95, 93, 1159
side = (r - l) - 2 * inset
art = src.crop((l + inset, t + inset, l + inset + side, t + inset + side))

S, ART = 1024, 824
art = art.resize((ART, ART), Image.LANCZOS)
k = 4  # supersample the mask for smooth corners
mask = Image.new("L", (ART * k, ART * k), 0)
ImageDraw.Draw(mask).rounded_rectangle((0, 0, ART * k - 1, ART * k - 1), radius=int(ART * 0.225 * k), fill=255)
mask = mask.resize((ART, ART), Image.LANCZOS)

canvas = Image.new("RGBA", (S, S), (0, 0, 0, 0))
off = (S - ART) // 2
shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
shadow_mask = Image.new("L", (S, S), 0)
shadow_mask.paste(mask, (off, off + 10))
shadow.putalpha(shadow_mask.point(lambda v: int(v * 0.30)))
canvas = Image.alpha_composite(canvas, shadow.filter(ImageFilter.GaussianBlur(14)))
tile = art.convert("RGBA")
tile.putalpha(mask)
canvas.alpha_composite(tile, (off, off))
canvas.save(OUT)
print("✅ Wrote", OUT)
