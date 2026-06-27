#!/usr/bin/env python3
# Draw a cute cartoon salmon for fish ("Fisk") missions -> assets/icons/fish.png.
# The icon system (src/ui/icons.lua) auto-uses this over the code-drawn fish.
# Re-run to tweak; Finn-Erik can later replace it with his own drawing.

import os
from PIL import Image, ImageDraw

DEST = os.path.join(os.path.dirname(__file__), "..", "assets", "icons", "fish.png")
S = 4                      # supersample for smooth edges
W, H = 120, 72

f = Image.new("RGBA", (W * S, H * S), (0, 0, 0, 0))
d = ImageDraw.Draw(f)
cx, cy = W * S * 0.52, H * S * 0.5
bw, bh = W * S * 0.40, H * S * 0.26

d.polygon([(cx - bw * 0.9, cy), (cx - bw * 1.5, cy - bh * 0.9), (cx - bw * 1.5, cy + bh * 0.9)],
          fill=(214, 104, 72, 255))                                   # tail
d.ellipse([cx - bw, cy - bh, cx + bw, cy + bh], fill=(232, 124, 86, 255))             # body
d.ellipse([cx - bw * 0.7, cy + bh * 0.1, cx + bw * 0.8, cy + bh * 1.05], fill=(245, 170, 140, 255))  # belly
d.ellipse([cx - bw * 0.8, cy - bh * 1.05, cx + bw * 0.85, cy + bh * 0.1], fill=(196, 92, 64, 255))   # back
d.ellipse([cx - bw * 0.85, cy - bh * 0.6, cx + bw * 0.9, cy + bh * 0.6], fill=(232, 124, 86, 255))   # blend
d.polygon([(cx - bw * 0.1, cy - bh * 0.95), (cx + bw * 0.5, cy - bh * 1.5), (cx + bw * 0.45, cy - bh * 0.8)],
          fill=(210, 98, 68, 255))                                    # dorsal fin
d.polygon([(cx + bw * 0.05, cy + bh * 0.3), (cx + bw * 0.35, cy + bh * 1.1), (cx + bw * 0.5, cy + bh * 0.35)],
          fill=(210, 98, 68, 255))                                    # pectoral fin
d.arc([cx + bw * 0.2, cy - bh * 0.7, cx + bw * 1.1, cy + bh * 0.7], 110, 250,
      fill=(196, 92, 64, 255), width=int(3 * S))                      # gill
ex, ey = cx + bw * 0.62, cy - bh * 0.2
d.ellipse([ex - 7 * S, ey - 7 * S, ex + 7 * S, ey + 7 * S], fill=(255, 255, 255, 255))
d.ellipse([ex - 3.5 * S, ey - 3.5 * S, ex + 3.5 * S, ey + 3.5 * S], fill=(30, 30, 40, 255))

f = f.resize((W, H), Image.LANCZOS)
os.makedirs(os.path.dirname(DEST), exist_ok=True)
f.save(DEST)
print("wrote", os.path.normpath(DEST), f.size)
