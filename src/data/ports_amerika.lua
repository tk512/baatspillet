-- The Amerika map's harbours; same schema as ports.lua, (x, y) approximate and
-- snapped to the nearest coast. Harbour masters are still unnamed -- names and
-- assets/ports/portraits/<id>.png drop in with no code changes.
--   landmarks  named installations (LANDMARKS in src/scenes/world.lua), placed
--              as a cluster just past the built-up edge

return {
    {
        id    = "los_angeles",
        name  = "Los Angeles",
        x     = 2700, y = 5600,        -- coast of the desert continent (SW)
        color = {0.95, 0.62, 0.20},    -- sunset orange
        size  = "metropolis",
        landmarks = { "airport" },
        produces = { mode = "passengers", label = "Passasjerer", icon = "passenger" },
    },
    {
        id    = "new_york",
        name  = "New York City",
        x     = 8500, y = 3100,        -- fjord mouth of the lush NE coast
        color = {0.95, 0.78, 0.22},    -- taxi yellow
        size  = "metropolis",
        -- own icon, NOT `chest`: that one is the treasure hunt's language
        landmarks = { "airport" },
        produces = { mode = "cargo", label = "Containere", icon = "container" },
    },
    {
        id    = "boston",
        name  = "Boston",
        x     = 9700, y = 1300,        -- the far NE lush coast
        color = {0.30, 0.55, 0.30},    -- green monster
        size  = "large",
        produces = { mode = "cargo", label = "Fisk", icon = "fish" },
    },
    {
        id    = "washington",
        name  = "Washington DC",
        x     = 9900, y = 5900,        -- mid-Atlantic green coast
        color = {0.90, 0.90, 0.95},    -- marble white
        size  = "large",
        produces = { mode = "passengers", label = "Passasjerer", icon = "passenger" },
    },
    {
        id    = "norfolk",
        name  = "Norfolk",
        x     = 11400, y = 5200,       -- harbour on the SE island
        color = {0.45, 0.55, 0.75},    -- navy blue
        size  = "medium",
        produces = { mode = "cargo", label = "Fisk", icon = "fish" },
    },
}
