-- The Amerika map's harbours; same schema as ports.lua, (x, y) approximate and
-- snapped to the nearest coast.
--   landmarks  named installations (LANDMARKS in src/scenes/world.lua), placed
--              as a cluster just past the built-up edge
--
-- Every harbour master is named now. They are for whoever is holding the iPad --
-- a Norwegian five-year-old knows none of them -- so each is picked for the
-- city he actually belongs to. Portraits are still the default face until
-- assets/ports/portraits/<id>.png exists; see tools/make_portrait.py.

return {
    {
        id    = "los_angeles",
        name  = "Los Angeles",
        master = "Jay Leno",           -- the Tonight Show and that garage: LA's own
        x     = 2700, y = 5600,        -- coast of the desert continent (SW)
        color = {0.95, 0.62, 0.20},    -- sunset orange
        size  = "metropolis",
        landmarks = { "airport" },
        produces = { mode = "passengers", label = "Passasjerer", icon = "passenger" },
    },
    {
        id    = "new_york",
        name  = "New York City",
        -- Steamboat Willie premiered in New York, 1928 -- a mouse at a boat's
        -- wheel, which is the whole game, so he berths here rather than in LA
        master = "Walt Disney",
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
        master = "Benjamin Franklin",  -- born in Boston, 1706
        x     = 9700, y = 1300,        -- the far NE lush coast
        color = {0.30, 0.55, 0.30},    -- green monster
        size  = "large",
        produces = { mode = "cargo", label = "Fisk", icon = "fish" },
    },
    {
        id    = "starbase",
        name  = "Starbase, TX",        -- was Washington DC; renamed so Musk is
        master = "Elon Musk",          -- somewhere he actually belongs
        landmarks = { "oljeterminal" },  -- flare stack, plant, tanks: it's Texas
        x     = 9900, y = 5900,        -- mid-Atlantic green coast
        color = {0.68, 0.74, 0.82},    -- stainless steel
        size  = "large",
        produces = { mode = "passengers", label = "Passasjerer", icon = "passenger" },
    },
    {
        id    = "miami",
        name  = "Miami",
        master = { "Vlad", "Niki" },
        x     = 11400, y = 5200,       -- harbour on the SE island
        color = {0.98, 0.45, 0.62},    -- flamingo pink
        size  = "medium",              -- the SE island is the small one: 55 houses would spill
        produces = { mode = "passengers", label = "Passasjerer", icon = "passenger" },
    },
}
