-- What a harbour's Butikk sells. Safe to edit: id / name / price / desc / icon
-- and it appears in the grid. Purchases live in the save under state.owned[id];
-- an owned one-off is crossed out. `icon` is drawn by src/ui/icons.lua, and
-- assets/icons/<icon>.png replaces the placeholder with no code.
--   stack = true   re-buyable upgrade (Kanon: each one speeds up the battery)
--   ammo  = N      re-buyable crate of N cannonballs
--   food  = true   re-buyable provisions; crew and passengers eat them at sea
-- Kanonkuler stays LAST: it's the only crate that can be hidden (no cannon
-- aboard), and as the tail item its coming and going never shifts the others.

return {
    { id = "cannon",     name = "Kanon",      price = 100, desc = "Skyt på sjørøvere!", icon = "cannon", stack = true },
    { id = "brod",     name = "Brød",     price = 10,  desc = "Nybakt brød.",     icon = "bread",  food = true },
    { id = "saft",     name = "Saft",     price = 12,  desc = "Søt rød saft.",    icon = "juice",  food = true },
    { id = "sitroner", name = "Sitroner", price = 15,  desc = "Friske sitroner.", icon = "lemon",  food = true },
    { id = "epler",    name = "Epler",    price = 8,   desc = "Røde epler.",      icon = "apple",  food = true },
    { id = "ost",      name = "Ost",      price = 14,  desc = "Gul ost.",         icon = "cheese", food = true },
    { id = "kanonkuler", name = "Kanonkuler", price = 20,  desc = "En hel kasse med kuler!", icon = "kanonkuler", ammo = 25 },
}
