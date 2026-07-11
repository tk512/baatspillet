-- src/data/ports_amerika.lua
-- The Amerika map's harbours. Same schema as ports.lua: (x, y) is approximate
-- (snapped to the nearest coast + flattened). Harbour masters are deliberately
-- unnamed placeholders for now — real names + photos drop into
-- assets/ports/portraits/<id>.png later with zero code changes.

return {
    {
        id    = "los_angeles",
        name  = "Los Angeles",
        x     = 3000, y = 5600,        -- coast of the big desert island (SW)
        color = {0.95, 0.62, 0.20},    -- sunset orange
        size  = "metropolis",
        produces = { mode = "passengers", label = "Passasjerer", icon = "passenger" },
    },
    {
        id    = "new_york",
        name  = "New York City",
        x     = 8600, y = 2900,        -- south coast of the big lush NE island
        color = {0.95, 0.78, 0.22},    -- taxi yellow
        size  = "metropolis",
        produces = { mode = "cargo", label = "Containere", icon = "chest" },
    },
    {
        id    = "boston",
        name  = "Boston",
        x     = 10100, y = 1900,       -- the far NE lush island
        color = {0.30, 0.55, 0.30},    -- green monster
        size  = "large",
        produces = { mode = "cargo", label = "Fisk", icon = "fish" },
    },
    {
        id    = "washington",
        name  = "Washington DC",
        x     = 9000, y = 5200,        -- mid-Atlantic green island
        color = {0.90, 0.90, 0.95},    -- marble white
        size  = "large",
        produces = { mode = "passengers", label = "Passasjerer", icon = "passenger" },
    },
    {
        id    = "norfolk",
        name  = "Norfolk",
        x     = 10500, y = 6500,       -- small harbour island in the SE
        color = {0.45, 0.55, 0.75},    -- navy blue
        size  = "medium",
        produces = { mode = "cargo", label = "Fisk", icon = "fish" },
    },
}
