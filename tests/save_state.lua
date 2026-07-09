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

-- Minimal LÖVE stub: an in-memory filesystem is all the save/state functions
-- touch. Fonts, scenes and audio are never called from here.
local files = {}
love = {
    filesystem = {
        getInfo = function(p) return files[p] ~= nil and { type = "file" } or nil end,
        read    = function(p) return files[p] end,
        write   = function(p, s) files[p] = s; return true end,
    },
}

local config = require("src.config")
local json   = require("src.json")
local Game   = require("src.game")
Game.data = { boats = require("src.data.boats") }

-- tiny harness ---------------------------------------------------------------
local passed, failed = 0, 0
local function check(cond, msg)
    if cond then passed = passed + 1
    else failed = failed + 1; print("FAIL: " .. msg) end
end
local function eq(got, want, msg)
    check(got == want, string.format("%s (got %s, want %s)",
        msg, tostring(got), tostring(want)))
end
-- Fresh in-memory "disk" (optionally pre-seeded with a save file) + reload.
local function reset(saved)
    for k in pairs(files) do files[k] = nil end
    if saved then files[Game.SAVE_FILE] = saved end
    Game:loadSave()
end

-- fresh defaults --------------------------------------------------------------
reset()
eq(Game.state.coins, 0, "fresh: no gold")
eq(Game.state.selectedBoat, "starter_boat", "fresh: starter boat selected")
eq(Game.state.unlockedBoats[1], "starter_boat", "fresh: starter boat unlocked")
eq(Game.state.ammo, 0, "fresh: no cannonballs")
eq(Game.state.cannons, 0, "fresh: no cannons")
eq(Game.state.premium, false, "fresh: no premium")
eq(#Game.state.treasuresFound, 0, "fresh: no treasures found")

-- full round-trip -------------------------------------------------------------
reset()
Game.state.coins = 123
Game.state.boatName = "Sjørøver'n"          -- norwegian chars must survive JSON
Game.state.selectedBoat = "cargo_ship"
Game.state.food = { brod = 2, ost = 1 }
Game.state.ammo = 7
Game.state.cannons = 2
Game.state.owned = { cannon = true }
Game.state.treasuresFound = { "chest1", "chest2" }
Game.state.premium = true
Game:save()
Game.state = nil
Game:loadSave()
eq(Game.state.coins, 123, "roundtrip: coins")
eq(Game.state.boatName, "Sjørøver'n", "roundtrip: boat name (norwegian chars)")
eq(Game.state.selectedBoat, "cargo_ship", "roundtrip: selected boat")
eq(Game.state.food.brod, 2, "roundtrip: food stock")
eq(Game.state.ammo, 7, "roundtrip: ammo")
eq(Game.state.cannons, 2, "roundtrip: cannons")
eq(Game.state.owned.cannon, true, "roundtrip: cannon owned")
eq(Game.state.treasuresFound[2], "chest2", "roundtrip: treasures")
eq(Game.state.premium, true, "roundtrip: premium")
check(json.decode(files[Game.SAVE_FILE]) ~= nil, "roundtrip: save file is valid JSON")

-- partial save (old version / hand-edited): missing fields fall to defaults ----
reset('{"coins":42}')
eq(Game.state.coins, 42, "partial: kept coins")
eq(Game.state.selectedBoat, "starter_boat", "partial: default boat")
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

-- ---------------------------------------------------------------------------------
print(string.format("%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
