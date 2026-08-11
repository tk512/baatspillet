-- Port definitions. (x, y) is a rough intent -- terrain snaps each port to the
-- nearest coast and flattens under it. Add a town by copying a block.
--
--   id        unique lowercase string (also the photo/voice/portrait filename)
--   name      shown in UI (Norwegian)
--   x, y      approximate location (snapped to a coast)
--   color     {r,g,b} accent for the roof + destination flag
--   size      city size: tiny / small / medium / large (see config.CITY_SIZES)
--   master    harbour master's name -> "Havnesjef <master>"; a LIST turns it
--             plural, "Havnesjefer ...". Portrait either way is
--             assets/ports/portraits/<id>.png. Omit for a plain "Havnesjef".
--   produces  what this town sends:
--               { mode = "passengers", label = "Passasjerer", icon = "passenger" }
--               { mode = "cargo",      label = "Fisk",        icon = "fish" }

return {
    {
        id    = "bergen",
        name  = "Bergen",
        master = "Farfar",
        x     = 3600, y = 3500,        -- SE coast of the big NW island
        color = {0.85, 0.30, 0.28},
        size  = "large",
        produces = { mode = "passengers", label = "Passasjerer", icon = "passenger" },
    },
    {
        id    = "oslo",
        name  = "Oslo",
        master = "Donald Duck",
        x     = 9000, y = 5400,        -- NW coast of the big SE island
        color = {0.35, 0.45, 0.78},
        size  = "large",
        produces = { mode = "passengers", label = "Passasjerer", icon = "passenger" },
    },
    {
        id    = "skiparviken",
        name  = "Skiparviken",
        master = { "S", "F" },   -- this harbour is run by two havnesjefer
        x     = 8700, y = 3400,        -- south coast of the NE island
        color = {0.30, 0.62, 0.66},
        size  = "medium",
        produces = { mode = "cargo", label = "Fisk", icon = "fish" },
    },
    {
        id    = "leroy",
        name  = "Lerøy",              -- famous for salmon → fish cargo
        master = "Farfar",
        x     = 3500, y = 5300,        -- NE coast of the SW island
        color = {0.55, 0.45, 0.75},
        size  = "medium",
        produces = { mode = "cargo", label = "Fisk", icon = "fish" },
    },
    {
        id    = "alversund",
        name  = "Alversund",
        master = "Samuel",
        x     = 6200, y = 3000,        -- south coast of the N-mid island
        color = {0.50, 0.62, 0.40},
        size  = "small",
        produces = { mode = "passengers", label = "Passasjerer", icon = "passenger" },
    },
    {
        id    = "hjellestad",
        name  = "Hjellestad",
        master = "Arne",
        x     = 7800, y = 5050,        -- south coast of the center island
        color = {0.90, 0.45, 0.62},
        size  = "small",
        produces = { mode = "passengers", label = "Passasjerer", icon = "passenger" },
    },
    {
        id    = "klokkarvik",
        name  = "Klokkarvik",
        master = "Farmor",
        x     = 5200, y = 5650,        -- the tiny island, S-mid
        color = {0.90, 0.62, 0.30},
        size  = "tiny",
        produces = { mode = "cargo", label = "Fisk", icon = "fish" },
    },
    {
        id    = "valhall",
        name  = "Valhall",
        master = "Torbjørn",
        x     = 5100, y = 4300,        -- big harbour on the central-sea island
        color = {0.95, 0.55, 0.20},
        size  = "large",
        produces = { mode = "passengers", label = "Passasjerer", icon = "passenger" },
    },
    -- Second town on BERGEN'S island, on the far NE shore ~2800 units from
    -- Bergen itself -- clear of it, since even a `large` town spreads ~1100 and
    -- the terrain flattening reaches ~450. Deliberately on an EXISTING island:
    -- adding to config.ISLANDS would renumber the island and treasure ids and
    -- break saves mid-hunt (see "Adding a town to a shipped map" in CLAUDE.md).
    {
        id    = "frekhaug",
        name  = "Frekhaug",
        master = "Sofie",
        x     = 4360, y = 840,         -- NE coast of the big NW island
        color = {0.40, 0.70, 0.45},    -- green: distinct from all eight others
        size  = "small",
        produces = { mode = "cargo", label = "Fisk", icon = "fish" },
    },
}

