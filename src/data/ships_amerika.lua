-- src/data/ships_amerika.lua
-- Ambient sea traffic for the Amerika map. Reuses the existing ship photos
-- (they're international vessels — they sail everywhere), with routes pointed
-- at Amerika's ports. The Norwegian submarine visits on exercise, of course.

return {
    { photo = "aidaluna", name = "Aidaluna", country = "Tyskland", type = "Passasjerskip", cruise = true, visits = { "new_york", "boston" } },
    { photo = "beffen", name = "Beffen", country = "Norge", type = "Ferje", scale = 0.55, cruise = true, home = "new_york" },
    { photo = "italeni", name = "Italeni", country = "Sør-Afrika", type = "Arbeidsskip", cruise = true },
    { photo = "msc_santhya", name = "MSC Santhya", country = "Panama", type = "Containerskip", scale = 1.15, cruise = true, visits = { "los_angeles", "norfolk" } },
    { photo = "vasiliy_golovnin", name = "Vasiliy Golovnin", country = "Sør-Afrika", type = "Isbryter", cruise = true },
    { photo = "hurtigruten_nordlys", name = "MS Nordlys", country = "Norge", type = "Hurtigruteskip", cruise = true, visits = { "boston", "washington" } },
    { photo = "rem_inspektor", name = "Rem Inspektør", country = "Norge", type = "Arbeidsskip", cruise = true, home = "norfolk" },
    { photo = "norsk_ubat", name = "Norsk ubåt", country = "Norge", type = "Ubåt", cruise = true, submarine = true },
}
