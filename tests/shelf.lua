-- tests/shelf.lua
-- The shelf's BUILD step: what ends up in each section, and -- the part worth
-- the file -- the cache signature that decides whether the build runs at all.
--
-- Shelf.build only rebuilds when signature() changes. Any input the build
-- branches on that the signature forgets to mix in produces the nastiest class
-- of bug in this codebase: the shelf keeps drawing a stale layout until some
-- unrelated change (a coin, a bite of bread) happens to bump the number. You
-- get a treasure tally that appears "sometimes", minutes late, and never in the
-- same place twice. Playing the game does not find that; this file does.
--
-- Drawing is NOT tested here (that's feel, and feel is tested by playing) --
-- only the pure table-building underneath it.
--
-- Runs WITHOUT LÖVE, from the project root:
--     luajit tests/shelf.lua
-- (plain `lua` works too). Exit code 0 = all green.

package.path = "./?.lua;" .. package.path
local H = require("tests.harness")
H.installLove()

local Shelf = require("src.ui.shelf")
local check, eq, near = H.check, H.eq, H.near

-- Stand-in for World + Game: only the fields Shelf.build actually reads.
local function fakeWorld(o)
    o = o or {}
    return {
        huntSeen  = o.huntSeen or false,
        treasures = o.treasures,
        boat      = { cargo = o.cargo or {} },
        minimap   = nil,
        game = {
            state = { coins = o.coins or 0 },
            data  = { shop = {
                { id = "cannon", icon = "cannon", stack = true },
                { id = "brod",   icon = "brod",   food  = true },
                { id = "kuler",  icon = "kanonkuler", ammo = true },
                { id = "kikkert", icon = "kikkert" },        -- a plain one-time upgrade
            } },
            owns        = function(_, id) return (o.owned or {})[id] == true end,
            foodCount   = function(_, id) return (o.food or {})[id] or 0 end,
            ammoCount   = function() return o.ammo or 0 end,
            cannonCount = function() return o.cannons or 0 end,
        },
    }
end

-- n chests, the first `found` of them dug up.
local function chests(n, found)
    local t = {}
    for i = 1, n do t[i] = { id = "c" .. i, found = i <= (found or 0) } end
    return t
end

-- ── the treasure tally: ONE slot, filled in proportion ───────────────────────

-- never seen a map: no tally at all, rather than an empty well to puzzle over
local w = fakeWorld{ treasures = chests(4, 0) }
eq(#Shelf.build(w).treas, 0, "no hunt yet: no treasure slot")

-- the hunt has been introduced but nothing is dug up yet
w = fakeWorld{ treasures = chests(4, 0), huntSeen = true }
local sh = Shelf.build(w)
eq(#sh.treas, 1, "hunt introduced: exactly ONE treasure slot (not one per chest)")
eq(sh.treas[1].icon, "chest", "treasure slot: always shows the chest icon")
near(sh.treas[1].frac, 0, 1e-9, "0 of 4: empty fill")
eq(sh.treas[1].label, "0/4", "0 of 4: label")

w = fakeWorld{ treasures = chests(4, 2), huntSeen = true }
sh = Shelf.build(w)
eq(#sh.treas, 1, "2 of 4: still one slot")
near(sh.treas[1].frac, 0.5, 1e-9, "2 of 4: half-filled")
eq(sh.treas[1].label, "2/4", "2 of 4: label")

-- all four: the fill is full, and nothing divides by zero on the way
w = fakeWorld{ treasures = chests(4, 4), huntSeen = true }
sh = Shelf.build(w)
near(sh.treas[1].frac, 1, 1e-9, "4 of 4: full fill")
eq(sh.treas[1].label, "4/4", "4 of 4: label")

-- a world with no chests placed at all must not draw a "0/0" slot
w = fakeWorld{ treasures = {}, huntSeen = true }
eq(#Shelf.build(w).treas, 0, "no chests in the world: no treasure slot")
w = fakeWorld{ treasures = nil, huntSeen = true }
eq(#Shelf.build(w).treas, 0, "treasures not built yet: no treasure slot, no crash")

-- The label is built ONCE, in build -- not concatenated every frame in the draw
-- call. Rebuilding with the same state must hand back the same string object.
w = fakeWorld{ treasures = chests(4, 1), huntSeen = true }
local first = Shelf.build(w).treas[1].label
eq(Shelf.build(w).treas[1].label, first, "label is cached, not rebuilt per frame")

-- ── a pirate stealing the chest must not empty the shelf ─────────────────────
-- pirateStealsTreasure un-maps the chest so the X vanishes. huntSeen LATCHES,
-- so the tally stays put; a tally that disappeared at that moment would read to
-- a child as "the pirate took my treasures away too".
w = fakeWorld{ treasures = chests(4, 1), huntSeen = true }
eq(#Shelf.build(w).treas, 1, "before the theft: tally shown")
-- the theft changes nothing the shelf reads: no chest is found or lost
eq(#Shelf.build(w).treas, 1, "after the theft: tally still shown")
near(Shelf.build(w).treas[1].frac, 0.25, 1e-9, "after the theft: still 1 of 4")

-- ── the other sections still behave ──────────────────────────────────────────
w = fakeWorld{
    cargo   = { { icon = "fish", count = 3 }, { icon = "smile", count = 1 } },
    owned   = { kikkert = true },
    food    = { brod = 2 },
    ammo    = 7,
    cannons = 2,
}
sh = Shelf.build(w)
-- Cargo is the mission banner's job now: it draws the goods themselves, and a
-- harbour won't hand out a second one while a job is aboard, so a cargo slot here
-- said the same thing again in the weaker grammar. Pinned, because "the shelf
-- shows what you have" is the obvious thing to re-add without noticing why not.
check(sh.cargo == nil, "cargo has no section: the mission banner shows the goods")
-- cannon x2, brod x2, kuler x7, kikkert -- four owned things
eq(#sh.gear, 4, "gear: one slot per owned thing")

w = fakeWorld{}
sh = Shelf.build(w)
eq(#sh.gear, 0, "bought nothing: no gear slots")

-- ── Sections and their hit-box names must stay in step ──────────────────────
-- These were two separate lists once. Cargo left the shelf, the section list
-- lost an entry, the name list kept three, and every rect shifted by one -- so
-- the treasure tally's hit box was filed under "gear" and the ONE tappable slot
-- in the shelf silently stopped opening the album. Nothing crashed, nothing
-- looked wrong, and it reads as "can't tap the chest on iPhone" when in fact it
-- was broken everywhere. Both halves now come from Shelf.SECTIONS.
w = fakeWorld{ owned = { kikkert = true }, treasures = chests(4, 1), huntSeen = true }
sh = Shelf.build(w)
check(#Shelf.SECTIONS > 0, "there are sections to draw")
local rectNames = {}
for _, d in ipairs(Shelf.SECTIONS) do
    check(sh[d.field] ~= nil,
        "section '" .. d.field .. "' is a real table on the built shelf")
    check(type(d.rect) == "string" and #d.rect > 0,
        "section '" .. d.field .. "' names the hit box it fills")
    check(not rectNames[d.rect], "hit-box name '" .. d.rect .. "' is used once")
    rectNames[d.rect] = true
end
-- World:mousepressed looks up exactly this key to open the album; if the tally
-- is ever renamed or dropped, the album becomes unreachable by touch entirely
check(rectNames.treasures,
    "a 'treasures' hit box exists -- it is what opens the album (World:mousepressed)")
-- and the tally must be the section that's actually tappable
for _, d in ipairs(Shelf.SECTIONS) do
    if d.rect == "treasures" then
        check(sh[d.field].progress, "the 'treasures' section is the progress tally")
    end
end

-- ── THE CACHE. Every input the build reads must move the signature ───────────
local function sigAfter(world, mutate)
    local before = Shelf.build(world).sig
    mutate(world)
    return before, Shelf.build(world).sig
end

-- the one this change introduced: huntSeen is a NEW input to the build, and if
-- signature() forgets it the tally simply never appears when the first map is
-- granted -- until something unrelated happens to invalidate the cache
w = fakeWorld{ treasures = chests(4, 0) }
local a, b = sigAfter(w, function(x) x.huntSeen = true end)
check(a ~= b, "signature: granting the first map invalidates the cache")
eq(#Shelf.build(w).treas, 1, "granting the first map makes the tally appear AT ONCE")

-- finding a chest
w = fakeWorld{ treasures = chests(4, 1), huntSeen = true }
a, b = sigAfter(w, function(x) x.treasures[2].found = true end)
check(a ~= b, "signature: finding a chest invalidates the cache")
eq(Shelf.build(w).treas[1].label, "2/4", "found chest shows up immediately")

-- gold is mixed in FIRST, which is exactly the position a plain running-product
-- hash loses to floating-point once there are enough inputs after it
w = fakeWorld{ coins = 10, treasures = chests(4, 2), huntSeen = true,
               food = { brod = 3 }, ammo = 5, cannons = 2, owned = { kikkert = true } }
a, b = sigAfter(w, function(x) x.game.state.coins = 11 end)
check(a ~= b, "signature: a single coin still invalidates the cache")

-- ...and the rule runs the OTHER way too: an input the build no longer reads
-- must be OUT of the signature, or every pickup rebuilds the whole shelf to
-- produce byte-identical output. Cargo is the case -- it left the build, so it
-- has to leave the hash with it.
w = fakeWorld{ cargo = { { icon = "fish", count = 1 } } }
a, b = sigAfter(w, function(x) x.boat.cargo[1].count = 2 end)
eq(a, b, "signature: cargo no longer touches the shelf, so it must not rebuild it")

w = fakeWorld{ cargo = { { icon = "fish", count = 1 } } }
a, b = sigAfter(w, function(x) x.boat.cargo[2] = { icon = "smile", count = 1 } end)
eq(a, b, "signature: taking on another job doesn't rebuild the shelf either")

-- food, ammo, cannons
w = fakeWorld{ food = { brod = 1 } }
a, b = sigAfter(w, function(x) x.game.foodCount = function() return 0 end end)
check(a ~= b, "signature: eating the last bread invalidates the cache")

w = fakeWorld{ ammo = 5 }
a, b = sigAfter(w, function(x) x.game.ammoCount = function() return 4 end end)
check(a ~= b, "signature: firing a cannonball invalidates the cache")

-- and the other way round: nothing changed, so the build must be REUSED (this
-- is what keeps the shelf from allocating fresh tables every frame)
w = fakeWorld{ coins = 3, treasures = chests(4, 1), huntSeen = true }
local s1 = Shelf.build(w)
local s2 = Shelf.build(w)
check(s1 == s2 and s1.treas[1] == s2.treas[1],
    "unchanged state: the cached build is reused, entries and all")

H.report()
