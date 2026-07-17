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
        -- 8-view turnsheet frames (raw/bat-turnsheet.png via tools/make_turnsheet.py)
        frames   = "nasse_noff",
        spriteWidth = 118,             -- gameplay-only size (preview scales itself)
        color    = {0.16, 0.22, 0.32}, -- navy hull for the placeholder fallback
    },
    {
        id       = "fishing_boat",
        name     = "Tøffe",       -- "The Fishing Boat"
        speed    = 175,
        accel    = 110,
        turn     = 2.0,
        capacity = 4,
        premium  = true,               -- unlocked by the one premium pack (config.PREMIUM)
        sprite   = "boat2.png",
        color    = {0.30, 0.55, 0.85},
    },
    {
        id       = "cargo_ship",
        name     = "Balder",      -- "The Cargo Ship"
        speed    = 210,
        accel    = 70,
        turn     = 1.4,
        capacity = 8,
        premium  = true,
        sprite   = "boat3.png",
        color    = {0.95, 0.70, 0.20},
    },
    {
        id       = "yacht",
        name     = "Vannvittig",    -- a fancy "3D" volumetric boat (premium)
        speed    = 205,
        accel    = 105,
        turn     = 1.9,
        capacity = 5,
        premium  = true,
        -- A real 3D model rendered to frames at assets/boats/yacht/0..N.png is used
        -- when present (see tools/render_boat_frames.md); until then it falls back to
        -- the code-drawn volumetric boat (model="yacht"). frameOffset/frameCW tune the
        -- render's starting angle / spin direction without re-rendering.
        frames     = "yacht",
        frameOffset = 0,
        frameCW    = true,
        model      = "yacht",
        color      = {0.20, 0.45, 0.80},
    },
}
