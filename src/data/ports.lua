-- Port definitions. (x, y) is the intended spot; the terrain engine snaps each
-- port to the nearest coast and flattens under it, so just place them roughly
-- next to an island. Add a town by copying a block.
--
-- Fields:
--   id        unique lowercase string (also the photo/voice/portrait filename)
--   name      shown in UI (Norwegian)
--   x, y      approximate location (snapped to a coast)
--   color     {r,g,b} accent for the roof + destination flag
--   size      city size: tiny / small / medium / large (see config.CITY_SIZES)
--   master    optional harbour master's name, shown as "Havnesjef <master>";
--             matches assets/ports/portraits/<id>.png. Omit for plain "Havnesjef".
--   produces  what this town sends:
--               { mode = "passengers", label = "Passasjerer", icon = "passenger" }
--               { mode = "cargo",      label = "Fisk",        icon = "fish" }

return {
    {
        id    = "bergen",
        name  = "Bergen",
        master = "Arne",
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
        id    = "floro",
        name  = "Florø",
        master = "Håkon",
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
        id    = "florida",
        name  = "Florida",
        master = "Vlad Niki",
        x     = 5100, y = 4300,        -- big harbour on the central-sea island
        color = {0.95, 0.55, 0.20},
        size  = "large",
        produces = { mode = "passengers", label = "Passasjerer", icon = "passenger" },
    },
}

