#!/usr/bin/env python3
# Build every app icon from ONE master: assets/icon/icon-1024.png — a
# 1024×1024 FULL-BLEED square of finished art (Apple applies its own rounded
# mask on iOS, so the master must not have rounded corners of its own).
# Drop a new master in and re-run; nothing else in the repo needs touching.
#
#   python3 tools/make_icon.py [path/to/new-master.png]
#
# It writes:
#   engine/…/iOS AppIcon.appiconset    the 1024, RGB — Xcode derives every
#                                      iOS size from it at build time
#   engine/…/OS X AppIcon.appiconset   the 16…1024 ladder, in the macOS shape
#                                      (squircle inset in a transparent canvas)
#                                      — this is what ./bygg.sh setup bakes
#                                      into love.app, which `./bygg.sh dmg`
#                                      copies into Båtspillet.app and the .dmg
#   assets/icon/batlogo-rounded.png    the same macOS-shaped 1024, for marketing
#
# NO ALPHA on the iOS side: App Store Connect rejects an app icon that carries
# an alpha channel (ITMS-90717), even one that is fully opaque.
#
# The art is used as-is — no pixelating, no palette work. The master IS the
# icon. (assets/icon/batlogo-master.png + batlogo-ferry-1024.png are the older
# hand-made pixel ferry, kept in case it comes back; `git log` has the
# pixelate-from-master script that produced it.)
import os
import sys
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MASTER = os.path.join(ROOT, "assets/icon/icon-1024.png")
SRC = sys.argv[1] if len(sys.argv) > 1 else MASTER

# Apple's macOS icon grid: on a 1024 canvas the icon body is 824×824 centred,
# with a 185.4px corner radius. That margin is why a Dock full of icons lines
# up; a full-bleed square would sit oversized among its neighbours.
MAC_CANVAS, MAC_BODY, MAC_RADIUS = 1024, 824, 185.4
MAC_SIZES = (16, 32, 64, 128, 256, 512, 1024)

im = Image.open(SRC)
if im.size != (1024, 1024):
    raise SystemExit("master must be 1024×1024, got %dx%d — %s" % (*im.size, SRC))
rgba = im.convert("RGBA")
alpha = rgba.split()[3]
if alpha.getextrema()[0] < 255:
    print("!! master has transparent pixels — flattening over black "
          "(iOS icons must be fully opaque)")
flat = Image.new("RGB", im.size, (0, 0, 0))
flat.paste(rgba, mask=alpha)

if SRC != MASTER:                       # adopt a new master into the repo
    flat.save(MASTER)
    print("wrote", MASTER)

# ── iOS: the full-bleed square, RGB, single size ────────────────────────────
ios = os.path.join(ROOT, "engine/platform/xcode/Images.xcassets/iOS AppIcon.appiconset")
for f in os.listdir(ios):
    os.remove(os.path.join(ios, f))
flat.save(os.path.join(ios, "icon-1024.png"))
with open(os.path.join(ios, "Contents.json"), "w") as f:
    f.write('{\n  "images" : [\n    {\n      "filename" : "icon-1024.png",\n'
            '      "idiom" : "universal",\n      "platform" : "ios",\n'
            '      "size" : "1024x1024"\n    }\n  ],\n'
            '  "info" : {\n    "author" : "xcode",\n    "version" : 1\n  }\n}\n')
print("installed into", ios)


def squircle(size, radius, ss=4):
    """A rounded-rect alpha mask, drawn 4× and shrunk so the corners are smooth."""
    m = Image.new("L", (size * ss, size * ss), 0)
    ImageDraw.Draw(m).rounded_rectangle(
        (0, 0, size * ss - 1, size * ss - 1), radius=radius * ss, fill=255)
    return m.resize((size, size), Image.LANCZOS)


# ── macOS: the body inset in a transparent canvas, whole size ladder ────────
body = flat.resize((MAC_BODY, MAC_BODY), Image.LANCZOS).convert("RGBA")
body.putalpha(squircle(MAC_BODY, MAC_RADIUS))
mac = Image.new("RGBA", (MAC_CANVAS, MAC_CANVAS), (0, 0, 0, 0))
mac.paste(body, ((MAC_CANVAS - MAC_BODY) // 2,) * 2)

osx = os.path.join(ROOT, "engine/platform/xcode/Images.xcassets/OS X AppIcon.appiconset")
for s in MAC_SIZES:
    mac.resize((s, s), Image.LANCZOS).save(os.path.join(osx, "%d.png" % s))
print("installed into", osx, "(%s)" % ", ".join("%dpx" % s for s in MAC_SIZES))
# Contents.json there is the engine's own and already maps these filenames —
# leave it alone so the vendored diff stays to the seven PNGs.

out = os.path.join(ROOT, "assets/icon/batlogo-rounded.png")
mac.save(out)
print("wrote", out)
