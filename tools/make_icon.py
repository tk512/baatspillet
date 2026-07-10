#!/usr/bin/env python3
# Generate the Båtspillet app icon (1024x1024, opaque — App Store requires no
# alpha) from the Sundferjen photo: sunny sky, sea with wave glints, the ferry
# front and center. Output: assets/icon/icon-1024.png, and it is installed into
# the vendored engine's iOS appiconset as a single-size icon (Xcode 14+ derives
# every size from the 1024 automatically).
#
#   python3 tools/make_icon.py
import os
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
S = 1024
img = Image.new("RGB", (S, S))
d = ImageDraw.Draw(img)

# sky: light azure -> pale near the horizon
horizon = int(S * 0.42)
for y in range(horizon):
    t = y / horizon
    d.line([(0, y), (S, y)], fill=(
        int(0x5e + (0xc9 - 0x5e) * t),
        int(0x9d + (0xe4 - 0x9d) * t),
        int(0xd8 + (0xf2 - 0xd8) * t)))

# sea: teal -> deep blue
for y in range(horizon, S):
    t = (y - horizon) / (S - horizon)
    d.line([(0, y), (S, y)], fill=(
        int(0x4f - 0x22 * t),
        int(0x7d - 0x2e * t),
        int(0x99 - 0x1f * t)))

# sun with a soft glow, upper right
glow = Image.new("RGB", (S, S), (0, 0, 0))
gd = ImageDraw.Draw(glow)
gd.ellipse([S * 0.66, S * 0.02, S * 1.02, S * 0.38], fill=(90, 70, 20))
glow = glow.filter(ImageFilter.GaussianBlur(60))
img = Image.blend(img, Image.blend(img, glow, 0.0), 0.0)  # keep img; use paste below
from PIL import ImageChops
img = ImageChops.add(img, glow)
d = ImageDraw.Draw(img)
d.ellipse([S * 0.72, S * 0.08, S * 0.96, S * 0.32], fill=(0xff, 0xe9, 0x8f))
d.ellipse([S * 0.76, S * 0.12, S * 0.92, S * 0.28], fill=(0xff, 0xf4, 0xc0))

# wave glints on the sea
import random
random.seed(7)
for i in range(46):
    y = random.randint(horizon + 30, S - 40)
    x = random.randint(20, S - 120)
    w = random.randint(40, 130)
    a = 0.5 + 0.5 * random.random()
    c = (int(0x8a * a + 0x4f * (1 - a)), int(0xb5 * a + 0x7d * (1 - a)), int(0xc9 * a + 0x99 * (1 - a)))
    d.rounded_rectangle([x, y, x + w, y + 10], radius=5, fill=c)

# the ferry, big and proud, sitting on the horizon-ish line
boat = Image.open(os.path.join(ROOT, "assets/boats/boat1.png")).convert("RGBA")
bw = int(S * 0.92)
bh = int(boat.height * bw / boat.width)
boat = boat.resize((bw, bh), Image.LANCZOS)
bx, by = (S - bw) // 2, int(S * 0.56) - bh // 2

# soft shadow/reflection under the hull
sh = Image.new("RGBA", (S, S), (0, 0, 0, 0))
sd = ImageDraw.Draw(sh)
sd.ellipse([bx + bw * 0.06, by + bh * 0.82, bx + bw * 0.94, by + bh * 1.12], fill=(10, 30, 45, 130))
sh = sh.filter(ImageFilter.GaussianBlur(18))
img.paste(sh, (0, 0), sh)
img.paste(boat, (bx, by), boat)

# sink the hull INTO the sea: repaint water over its bottom slice, then a
# continuous foam waterline where steel meets water
d = ImageDraw.Draw(img)
wl = by + int(bh * 0.80)
for y in range(wl, min(S, by + bh + 20)):
    t = (y - horizon) / (S - horizon)
    d.line([(0, y), (S, y)], fill=(
        int(0x4f - 0x22 * t), int(0x7d - 0x2e * t), int(0x99 - 0x1f * t)))
d.rounded_rectangle([bx - 30, wl - 10, bx + bw + 30, wl + 12], radius=11,
                    fill=(0xea, 0xf4, 0xf8))
d.rounded_rectangle([bx + bw * 0.15, wl + 16, bx + bw * 0.5, wl + 30], radius=7,
                    fill=(0xbf, 0xd9, 0xe4))

out = os.path.join(ROOT, "assets/icon")
os.makedirs(out, exist_ok=True)
master = os.path.join(out, "icon-1024.png")
img.save(master)
print("wrote", master)

# install into the vendored engine's iOS appiconset (single-size, Xcode 14+)
iconset = os.path.join(ROOT, "engine/platform/xcode/Images.xcassets/iOS AppIcon.appiconset")
for f in os.listdir(iconset):
    os.remove(os.path.join(iconset, f))
img.save(os.path.join(iconset, "icon-1024.png"))
with open(os.path.join(iconset, "Contents.json"), "w") as f:
    f.write('{\n  "images" : [\n    {\n      "filename" : "icon-1024.png",\n'
            '      "idiom" : "universal",\n      "platform" : "ios",\n'
            '      "size" : "1024x1024"\n    }\n  ],\n'
            '  "info" : {\n    "author" : "xcode",\n    "version" : 1\n  }\n}\n')
print("installed into", iconset)
