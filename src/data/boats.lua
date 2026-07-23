-- Boat definitions. Add a boat by copying a block; no code changes needed.
--
-- Fields:
--   id        unique string, used in save data and unlock logic
--   name      shown in UI
--   speed     top speed, pixels/second
--   accel     how fast it reaches top speed (higher = snappier)
--   turn      turning speed, radians/second (lower = gentler for kids)
--   capacity  cargo units it can carry
--   cost      gold to unlock (0 = available from the start)
--   sprite    optional PNG in assets/boats/ (else placeholder art)
--   color     {r,g,b} hull color for the placeholder

return {
    {
        id       = "starter_boat",
        name     = "Sundferjen",       -- the little sound-ferry
        speed    = 140,
        accel    = 90,
        turn     = 1.8,
        capacity = 2,
        sprite   = "boat1.png",
        artist   = "Finn-Erik",        -- his boat: hangs a small credit sign in the chooser
        color    = {0.85, 0.30, 0.25},
    },
    {
        id       = "nasse_noff",
        name     = "Nasse Nøff",       -- stubby little tug-ferry, free boat #2
        speed    = 155,
        accel    = 95,
        turn     = 1.7,
        capacity = 3,
        -- Live 3D textured model (assets/models/nasse_noff.obj + .png — the
        -- png is recoloured happy Piglet-pink from the asset's dark green);
        -- the old 8-view turnsheet below stays as the fallback.
        model3d  = "nasse_noff",
        modelYaw = 0,
        -- 8-view turnsheet frames (raw/bat-turnsheet.png via tools/make_turnsheet.py)
        frames   = "nasse_noff",
        spriteWidth = 118,             -- gameplay-only size (preview scales itself)
        color    = {0.16, 0.22, 0.32}, -- navy hull for the placeholder fallback
    },
    {
        id       = "fishing_boat",
        name     = "Tøffe",       -- the little tug (live 3D)
        speed    = 175,
        accel    = 110,
        turn     = 2.0,
        capacity = 4,
        premium  = true,               -- unlocked by the one premium pack (config.PREMIUM)
        -- Live 3D voxel tug (assets/models/toffe.obj + .mtl); the old photo
        -- sprite stays as the fallback if the model can't load.
        model3d  = "toffe",
        modelYaw = 0,
        spriteWidth = 105,
        sprite   = "boat2.png",
        color    = {0.30, 0.55, 0.85},
    },
    {
        id       = "yacht",
        name     = "Vannvittig",    -- a fancy "3D" volumetric boat (premium)
        speed    = 205,
        accel    = 105,
        turn     = 1.9,
        capacity = 5,
        premium  = true,
        -- Live 3D textured model (assets/models/vannvittig.obj + .png — same
        -- hull as Nasse Nøff, its own paint job). Fallbacks below: baked
        -- frames if they ever exist, else the code-drawn volumetric boat.
        model3d  = "vannvittig",
        modelYaw = 0,
        spriteWidth = 110,
        frames     = "yacht",
        frameOffset = 0,
        frameCW    = true,
        model      = "yacht",
        color      = {0.20, 0.45, 0.80},
    },
    {
        id       = "vikingskipet",
        name     = "Vikingskipet",     -- dragon-headed longship (premium)
        speed    = 190,
        accel    = 100,
        turn     = 1.7,
        capacity = 6,
        premium  = true,
        -- Live 3D: assets/models/vikingskipet.obj rendered in real 3D each
        -- frame (src/systems/model3d.lua) — rotates smoothly as you steer.
        -- modelYaw (degrees) turns the model so the bow leads; tweak it here
        -- if a model's bow points the wrong way, no re-export needed.
        model3d  = "vikingskipet",
        modelYaw = 90,
        spriteWidth = 115,             -- long low ship; keep it modest on screen
        color    = {0.45, 0.30, 0.18}, -- wooden hull for the placeholder fallback
    },
}
