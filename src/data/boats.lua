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
        cost     = 0,
        sprite   = "boat1.png",
        color    = {0.85, 0.30, 0.25},
    },
    {
        id       = "fishing_boat",
        name     = "Fiskebåten",       -- "The Fishing Boat"
        speed    = 175,
        accel    = 110,
        turn     = 2.0,
        capacity = 4,
        cost     = 60,
        sprite   = "boat2.png",
        color    = {0.30, 0.55, 0.85},
    },
    {
        id       = "cargo_ship",
        name     = "Lasteskipet",      -- "The Cargo Ship"
        speed    = 210,
        accel    = 70,
        turn     = 1.4,
        capacity = 8,
        cost     = 180,
        sprite   = "boat3.png",
        color    = {0.95, 0.70, 0.20},
    },
}
