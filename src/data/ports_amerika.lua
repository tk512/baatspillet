-- src/data/ports_amerika.lua
-- The Amerika map's harbours. Same schema as ports.lua: (x, y) is approximate
-- (snapped to the nearest coast + flattened). Harbour masters are deliberately
-- unnamed placeholders for now — real names + photos drop into
-- assets/ports/portraits/<id>.png later with zero code changes.

return {
    {
        id    = "los_angeles",
        name  = "Los Angeles",
        x     = 2700, y = 5600,        -- coast of the desert continent (SW)
        color = {0.95, 0.62, 0.20},    -- sunset orange
        size  = "metropolis",
        produces = { mode = "passengers", label = "Passasjerer", icon = "passenger" },
    },
    {
        id    = "new_york",
        name  = "New York City",
        x     = 8500, y = 3100,        -- fjord mouth of the lush NE coast
        color = {0.95, 0.78, 0.22},    -- taxi yellow
        size  = "metropolis",
        produces = { mode = "cargo", label = "Containere", icon = "chest" },
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
