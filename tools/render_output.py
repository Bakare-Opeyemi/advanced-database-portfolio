"""Render a captured terminal output file as a terminal-style PNG "screenshot".

The text is the real output saved from psql / mongosh / Python; this script only draws it.
Usage: python3 tools/render_output.py input.txt output.png "Title" [first_line] [last_line]
"""
import sys
from PIL import Image, ImageDraw, ImageFont

src, dst, title = sys.argv[1], sys.argv[2], sys.argv[3]
lines = open(src, encoding="utf-8").read().expandtabs(4).splitlines()
if len(sys.argv) > 5:
    lines = lines[int(sys.argv[4]) - 1:int(sys.argv[5])]
lines = [l[:150] for l in lines] or [""]

FONT_PATHS = ["/System/Library/Fonts/Menlo.ttc", "/System/Library/Fonts/Monaco.ttf"]
font = None
for fp in FONT_PATHS:
    try:
        font = ImageFont.truetype(fp, 15)
        break
    except OSError:
        pass
font = font or ImageFont.load_default()
title_font = font

line_h = 20
char_w = font.getlength("M")
width = int(max(len(l) for l in lines) * char_w) + 40
width = max(width, 700)
bar = 34
height = bar + 16 + line_h * len(lines) + 16

img = Image.new("RGB", (width, height), "#1e1e1e")
d = ImageDraw.Draw(img)
d.rectangle([0, 0, width, bar], fill="#323233")
for i, c in enumerate(["#ff5f56", "#ffbd2e", "#27c93f"]):
    d.ellipse([12 + i * 20, 11, 24 + i * 20, 23], fill=c)
d.text((80, 9), title, fill="#d4d4d4", font=title_font)

y = bar + 16
for l in lines:
    color = "#d4d4d4"
    s = l.strip()
    if "ERROR" in l or "error" in s[:12]:
        color = "#f48771"
    elif s.startswith(("===", "---", "STEP", "[S1]", "[S2]")):
        color = "#4ec9b0"
    elif s.startswith(("PASS", "OK", "COMMIT", "Execution Time", "RESULT")):
        color = "#b5cea8"
    d.text((20, y), l, fill=color, font=font)
    y += line_h
img.save(dst)
print("saved", dst, img.size)
