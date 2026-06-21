-- src/data/shop.lua
-- Things you can buy in a harbour's Butikk by saving up gold from cargo runs.
-- Safe for non-coders to edit: add an item with id / name / price / desc / icon
-- and it appears in the store grid. Buying is permanent (stored in the save under
-- state.owned[id]); an owned item is crossed out in the store.
--
-- `icon` is drawn by src/ui/icons.lua. Drop assets/icons/<icon>.png to replace a
-- code placeholder with real artwork (Finn-Erik's drawings later) -- zero code.
--
-- The Kanon is the one functional upgrade (auto-fires at pirates), bought once.
-- The rest are FOOD (`food = true`): provisions you can buy again and again and
-- stock up on. The crew + passengers eat them on voyages (see World eating), so
-- the maths of saving up, buying, and using up stays front and centre.
return {
    { id = "cannon",   name = "Kanon",    price = 100, desc = "Skyt på sjørøvere!", icon = "cannon" },
    { id = "brod",     name = "Brød",     price = 10,  desc = "Nybakt brød.",     icon = "bread",  food = true },
    { id = "saft",     name = "Saft",     price = 12,  desc = "Søt rød saft.",    icon = "juice",  food = true },
    { id = "sitroner", name = "Sitroner", price = 15,  desc = "Friske sitroner.", icon = "lemon",  food = true },
    { id = "epler",    name = "Epler",    price = 8,   desc = "Røde epler.",      icon = "apple",  food = true },
    { id = "ost",      name = "Ost",      price = 14,  desc = "Gul ost.",         icon = "cheese", food = true },
}
