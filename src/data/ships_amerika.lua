-- Ambient traffic for the Amerika map: the same international vessels as
-- ships.lua, with their routes pointed at Amerika's ports.

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
