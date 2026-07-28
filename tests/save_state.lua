-- tests/save_state.lua
-- Save/state tests for src/game.lua: the one part of the game where a silent bug
-- eats real progress (Finn-Erik's gold, treasures and boats). Covers the save
-- round-trip, old-save migration, corrupt-file recovery and the gold/food/ammo
-- book-keeping. Everything else in the game is feel, and feel is tested by
-- playing it.
--
-- Runs WITHOUT LÖVE, from the project root:
--     luajit tests/save_state.lua
-- (plain `lua` works too). Exit code 0 = all green.

package.path = "./?.lua;" .. package.path

-- The LÖVE stub and the assertion helpers are shared with the other test files
-- (tests/harness.lua); `files` is the stub's in-memory filesystem, which the
-- save tests seed and re-read.
local H = require("tests.harness")
local files = H.installLove()

local config = require("src.config")
local json   = require("src.json")
local Game   = require("src.game")
Game.data = { boats = require("src.data.boats") }

local check, eq = H.check, H.eq
-- Fresh in-memory "disk" (optionally pre-seeded with a save file) + reload.
local function reset(saved)
    for k in pairs(files) do files[k] = nil end
    if saved then files[Game.SAVE_FILE] = saved end
    Game:loadSave()
end

-- fresh defaults --------------------------------------------------------------
reset()
eq(Game.state.coins, 0, "fresh: no gold")
-- Asserted against boats.lua's FIRST entry rather than a hard-coded id: the
-- rule is "the first boat is the default", and the failure this catches is
-- someone reordering boats.lua without updating defaultState -- which would
-- silently start new players in a different boat.
local defaultBoat = Game.data.boats[1]
eq(Game.state.selectedBoat, defaultBoat.id, "fresh: the default boat is selected")
eq(Game.state.unlockedBoats[1], defaultBoat.id, "fresh: the default boat is unlocked")
check(not defaultBoat.premium,
    "the default boat must be FREE -- a new player would otherwise start in a boat "
    .. "they don't own (" .. defaultBoat.id .. ")")
eq(Game.state.ammo, 0, "fresh: no cannonballs")
eq(Game.state.cannons, 0, "fresh: no cannons")
eq(Game.state.premium, false, "fresh: no premium")
eq(#Game:mapState("norge").treasuresFound, 0, "fresh: no treasures found")

-- full round-trip -------------------------------------------------------------
reset()
Game.state.coins = 123
Game.state.boatNames = { cargo_ship = "Sjørøver'n" }  -- norwegian chars must survive JSON
Game.state.selectedBoat = "cargo_ship"
Game.state.food = { brod = 2, ost = 1 }
Game.state.ammo = 7
Game.state.cannons = 2
Game.state.owned = { cannon = true }
Game:mapState("norge").treasuresFound = { "chest1", "chest2" }
Game.state.premium = true
Game:save()
Game.state = nil
Game:loadSave()
eq(Game.state.coins, 123, "roundtrip: coins")
eq(Game.state.boatNames.cargo_ship, "Sjørøver'n", "roundtrip: boat name (norwegian chars)")
eq(Game.state.selectedBoat, "cargo_ship", "roundtrip: selected boat")
eq(Game.state.food.brod, 2, "roundtrip: food stock")
eq(Game.state.ammo, 7, "roundtrip: ammo")
eq(Game.state.cannons, 2, "roundtrip: cannons")
eq(Game.state.owned.cannon, true, "roundtrip: cannon owned")
eq(Game:mapState("norge").treasuresFound[2], "chest2", "roundtrip: treasures")
eq(Game.state.premium, true, "roundtrip: premium")
check(json.decode(files[Game.SAVE_FILE]) ~= nil, "roundtrip: save file is valid JSON")

-- migration: pre-boatNames saves had ONE boatName, owned by the selected boat --
reset()
files[Game.SAVE_FILE] = json.encode({
    coins = 5, selectedBoat = "cargo_ship", boatName = "Gamlebåten",
})
Game:loadSave()
eq(Game.state.boatNames.cargo_ship, "Gamlebåten",
    "migration: old single boatName lands on the selected boat")

-- crash safety: corrupt main save recovers from the .bak rotation ------------
reset()
Game.state.coins = 777
Game.state.premium = true
Game:save()                                   -- seeds _lastGood
Game.state.coins = 778
Game:save()                                   -- rotates good save into .bak
check(files[Game.SAVE_BAK] ~= nil, "bak: rotation wrote a backup")
files[Game.SAVE_FILE] = "{\"coins\": 77"       -- truncated mid-write by an app kill
Game:loadSave()
eq(Game.state.coins, 777, "bak: corrupt main falls back to last good save")
eq(Game.state.premium, true, "bak: entitlement survives the corruption")

-- corrupt main AND bak still degrades safely to defaults ----------------------
reset()
files[Game.SAVE_FILE] = "garbage"
files[Game.SAVE_BAK]  = "also garbage"
Game:loadSave()
eq(Game.state.coins, 0, "bak: both corrupt -> safe defaults, no crash")

-- "Spill igjen" must NEVER wipe the paid entitlement or identity --------------
reset()
Game.state.premium = true
Game.state.coins = 500
Game.state.unlockedBoats = { "starter_boat", "fishing_boat" }
Game.state.boatNames = { fishing_boat = "Tøffe" }
Game.state.selectedBoat = "fishing_boat"
Game.state.treasuresFound = { "chest1" }
Game:newGame()
eq(Game.state.premium, true, "newGame: KEEPS the paid premium pack")
eq(Game.state.boatNames.fishing_boat, "Tøffe", "newGame: keeps boat names")
eq(Game.state.selectedBoat, "fishing_boat", "newGame: keeps selected boat")
eq(Game.state.unlockedBoats[2], "fishing_boat", "newGame: keeps unlocked boats")
eq(Game.state.coins, 0, "newGame: progress (gold) IS reset")
eq(#Game:mapState("norge").treasuresFound, 0, "newGame: progress (treasures) IS reset")

-- per-map isolation: Norge's exploration must never leak into Amerika --------
reset()
Game:mapState("norge").treasuresFound = { "chest1" }
Game:mapState("norge").fog = "NORGEFOG"
eq(#Game:mapState("amerika").treasuresFound, 0, "maps: amerika starts unexplored")
eq(Game:mapState("amerika").fog, nil, "maps: amerika has no fog data")
Game:save(); Game.state = nil; Game:loadSave()
eq(Game:mapState("norge").fog, "NORGEFOG", "maps: norge fog survives roundtrip")
eq(#Game:mapState("amerika").treasuresFound, 0, "maps: isolation survives roundtrip")

-- migration: pre-maps saves put world progress at the top level (Norge's) ----
reset()
files[Game.SAVE_FILE] = json.encode({
    coins = 9, fog = "OLDFOG", treasuresFound = { "chest3" },
    discoveredIslands = { "bergen" },
})
Game:loadSave()
eq(Game:mapState("norge").fog, "OLDFOG", "migration: old fog lands under norge")
eq(Game:mapState("norge").treasuresFound[1], "chest3", "migration: old treasures land under norge")
eq(Game:mapState("norge").discoveredIslands[1], "bergen", "migration: old islands land under norge")


-- A map bucket that exists but is missing its lists. loadSave takes `data.maps`
-- wholesale, so an older build's save (or a hand-edited one) can hand us a
-- bucket with only some keys -- and World:load walks treasuresMapped with
-- ipairs() on the very first frame, which would crash on a nil rather than
-- degrade. Backfilled in Game:mapState.
reset(json.encode({ coins = 5, maps = { norge = { fog = "PARTIALFOG" } } }))
local partial = Game:mapState("norge")
eq(partial.fog, "PARTIALFOG", "partial bucket: what WAS saved survives")
eq(#partial.treasuresMapped, 0, "partial bucket: treasuresMapped backfilled, not nil")
eq(#partial.treasuresFound, 0, "partial bucket: treasuresFound backfilled, not nil")
eq(#partial.discoveredIslands, 0, "partial bucket: discoveredIslands backfilled, not nil")

-- partial save (old version / hand-edited): missing fields fall to defaults ----
reset('{"coins":42}')
eq(Game.state.coins, 42, "partial: kept coins")
eq(Game.state.selectedBoat, Game.data.boats[1].id, "partial: default boat")
eq(Game.state.ammo, 0, "partial: default ammo")

-- corrupt / empty file: never crash, start fresh --------------------------------
local ok = pcall(function() reset('not json {{{') end)
check(ok, "corrupt: loadSave survives garbage")
eq(Game.state.coins, 0, "corrupt: falls back to defaults")
ok = pcall(function() reset('') end)
check(ok, "corrupt: loadSave survives an empty file")
eq(Game.state.coins, 0, "empty file: defaults")

-- migration: pre-cannonball saves get a loaded cannon ---------------------------
reset('{"owned":{"cannon":true}}')
eq(Game.state.ammo, config.CANNON.START_AMMO, "migration: legacy cannon owner gets full ammo")
eq(Game.state.cannons, 1, "migration: legacy cannon counted once")
-- ...but explicit values (even zero) are respected, never overwritten
reset('{"owned":{"cannon":true},"ammo":0,"cannons":2}')
eq(Game.state.ammo, 0, "migration: explicit ammo 0 kept (locker stays empty)")
eq(Game.state.cannons, 2, "migration: explicit cannon count kept")

-- gold + shop ------------------------------------------------------------------
reset()
Game:addCoins(10)
eq(Game.state.coins, 10, "coins: addCoins")
eq(Game:buyUpgrade("cannon", 100), false, "shop: can't afford")
eq(Game.state.coins, 10, "shop: failed buy costs nothing")
eq(Game:owns("cannon"), false, "shop: failed buy owns nothing")
Game:addCoins(140)
eq(Game:buyUpgrade("cannon", 100), true, "shop: afforded buy succeeds")
eq(Game.state.coins, 50, "shop: gold deducted")
eq(Game:owns("cannon"), true, "shop: upgrade owned")
Game:loadSave()
eq(Game:owns("cannon"), true, "shop: purchase persisted to disk")

-- food -------------------------------------------------------------------------
reset()
Game:addCoins(100)
eq(Game:buyFood("brod", 10), true, "food: buy")
eq(Game:buyFood("brod", 10), true, "food: buy again stacks")
eq(Game:buyFood("saft", 10), true, "food: second kind")
eq(Game:foodCount("brod"), 2, "food: stock counted")
eq(Game:buyFood("ost", 999), false, "food: can't afford")
eq(Game:eatFood(), "brod", "food: eats the largest stock first")
eq(Game:foodCount("brod"), 1, "food: eaten unit deducted")
Game.state.food = { ost = 1 }
eq(Game:eatFood(), "ost", "food: last unit eaten")
eq(Game.state.food.ost, nil, "food: empty stock removed")
eq(Game:eatFood(), nil, "food: nothing aboard -> nil")

-- cannonballs --------------------------------------------------------------------
reset()
eq(Game:useAmmo(), false, "ammo: empty locker fires nothing")
Game:addAmmo(2)
eq(Game:useAmmo(), true, "ammo: shot spends a ball")
eq(Game:ammoCount(), 1, "ammo: count after shot")
Game:addCoins(50)
eq(Game:buyAmmo(20, 10), true, "ammo: buy a pack")
eq(Game:ammoCount(), 11, "ammo: pack added")
eq(Game.state.coins, 30, "ammo: pack paid for")

-- cannons + fire rate -------------------------------------------------------------
reset()
Game:addCoins(1000)
eq(Game:cannonRate(), 1, "cannon: no cannon, base rate")
Game:buyCannon(100)
eq(Game:cannonCount(), 1, "cannon: first bought")
eq(Game:owns("cannon"), true, "cannon: gating flag set")
eq(Game:cannonRate(), 1, "cannon: one cannon, base rate")
Game:buyCannon(100)
eq(Game:cannonRate(), 1 + config.CANNON.EXTRA_RATE, "cannon: second speeds the battery")
for _ = 1, 6 do Game:buyCannon(100) end
eq(Game:cannonRate(), config.CANNON.MAX_RATE, "cannon: rate capped at MAX_RATE")
-- in-memory legacy state (save already migrated on disk, belt & braces here)
Game.state.cannons = nil
eq(Game:cannonCount(), 1, "cannon: nil count falls back to owned.cannon")

-- premium + boats ------------------------------------------------------------------
reset()
eq(Game:ownsBoat("starter_boat"), true, "boats: free boat always owned")
local premiumBoat
for _, b in ipairs(Game.data.boats) do
    if b.premium then premiumBoat = b.id; break end
end
check(premiumBoat ~= nil, "boats: data has at least one premium boat")
eq(Game:ownsBoat(premiumBoat), false, "boats: premium locked before the pack")
Game:unlockPremium()
eq(Game:isPremium(), true, "premium: pack flag set")
eq(Game:ownsBoat(premiumBoat), true, "boats: the one pack unlocks premium boats")
Game:loadSave()
eq(Game:isPremium(), true, "premium: persisted")
eq(Game:getBoatDef("finnes_ikke").id, Game.data.boats[1].id,
    "boats: unknown id falls back to the first boat")

-- utf8: json \u decoding + latin-1 save repair ------------------------------------
eq(json.decode('{"n": "T\\u00f8ffe"}').n, "T\195\184ffe",
    "json: \\u00f8 decodes to UTF-8 bytes, not Latin-1")
eq(json.decode('{"n": "\\u0041"}').n, "A", "json: ascii \\u escape")
eq(Game.repairUtf8("Nasse N\195\184ff"), "Nasse N\195\184ff",
    "repairUtf8: valid UTF-8 untouched")
eq(Game.repairUtf8("T\248ffe"), "T\195\184ffe",
    "repairUtf8: Latin-1 bytes re-encoded to UTF-8")
eq(Game.repairUtf8(nil), nil, "repairUtf8: non-strings pass through")
-- a save written by the old decoder: corrupt name is repaired on load
reset('{"boatNames": {"fishing_boat": "T\248ffe"}}')
eq(Game.state.boatNames.fishing_boat, "T\195\184ffe",
    "loadSave: Latin-1 boat name repaired to UTF-8")

-- ---------------------------------------------------------------------------------
H.report()
