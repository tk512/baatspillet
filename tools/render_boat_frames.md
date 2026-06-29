# Rendering a 3D boat model into game frames

The game is 2D, so a real 3D model is baked into flat frames from the iso angle and
dropped in as sprites (the same trick OpenGFX/OpenTTD use). Steer the boat in-game
and it shows the frame nearest your heading, so it looks like it turns. The boat
also spins these frames in the "Velg båten din" screen.

End result: `assets/boats/<name>/0.png 1.png ... (N-1).png`, then set `frames = "<name>"`
in `src/data/boats.lua` (the yacht is already set to `frames = "yacht"`).

## 1. Get a model
glTF (.glb/.gltf), FBX, or OBJ all import into Blender. Stylized low-poly reads
best for kids. Sources: Kenney and Quaternius (free, CC0), Synty POLYGON packs,
Sketchfab Store, CGTrader, TurboSquid. For a paid app get a royalty-free /
"use in games" license and note it in CREDITS.md.

## 2. Blender scene
1. Import the model. Move it to the world origin (0,0,0). Rotate it so the **bow
   points along +X** and **up is +Z**. Scale it to a sensible size.
2. Camera: add a camera, set it to **Orthographic** (Camera data > Lens >
   Orthographic), and set its **Rotation: X = 60°, Y = 0°, Z = 45°**. That is the
   exact 2:1 game-isometric this project uses. Frame the boat with the Ortho Scale
   slider (leave a little margin).
3. Lighting: a Sun lamp plus a bit of world/ambient light so the textures read.
4. Transparent background: Render Properties > Film > **Transparent** (on).
5. Output: Output Properties > Format **PNG**, Color **RGBA**. Resolution square,
   e.g. **512 x 512** (the game scales it down to ~140px, so 256-512 is plenty).
6. Framing: keep the boat centred left-to-right and sitting **near the bottom** of
   the frame (the game anchors the frame's bottom-centre at the waterline). Same
   framing for every frame.

## 3. Render the turn (N frames)
Pick N = 16 (steers fine) or 32 (smoother). Rotate the **model** (not the camera)
around Z by 360/N each frame. Easiest is this script: Scripting tab > New > paste,
set the object name and output path, Run.

```python
import bpy, math, os

OBJ = "Boat"        # name of your model object (or an Empty parenting it)
N   = 32            # number of frames
OUT = "/Users/tk/proj/båtspillet/assets/boats/yacht"   # assets/boats/<name>

obj = bpy.data.objects[OBJ]
os.makedirs(OUT, exist_ok=True)
sc = bpy.context.scene
sc.render.film_transparent = True
sc.render.image_settings.file_format = 'PNG'
sc.render.image_settings.color_mode = 'RGBA'
base = obj.rotation_euler[2]
for i in range(N):
    obj.rotation_euler[2] = base + math.radians(360.0 * i / N)
    sc.render.filepath = os.path.join(OUT, f"{i}.png")
    bpy.ops.render.render(write_still=True)
print("done")
```

## 4. Hook it up
- The count is auto-detected (it reads 0.png, 1.png, ... until one is missing).
- The yacht already has `frames = "yacht"`. For a new boat, add `frames = "<name>"`
  to its entry in `src/data/boats.lua`.
- Run the game. If the bow points the wrong way for your heading, tweak in data,
  no re-render needed:
  - `frameOffset = <int>` rotates which frame maps to which heading (try 1, 2, ...).
  - `frameCW = false` flips the spin direction if it turns the wrong way.
- If the boat sits too high/low on the water, adjust the framing in Blender (step
  2.6) so the hull is nearer the bottom of the frame.

Until frames exist, the boat falls back to its placeholder (the yacht uses the
code-drawn volumetric boat), so the game always runs.
