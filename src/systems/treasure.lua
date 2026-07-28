-- src/systems/treasure.lua
-- Places the treasure chests for the hunt: one on a "sandbank" in open water just
-- off each of the biggest islands (clean water the boat can sail right up to).
-- Placement is deterministic from the world seed -- the same map always hides the
-- chests in the same spots -- so the save only needs to remember which were found.
--
-- A treasure is a plain table: { id, x, y, good, found }.
--   good = the collectible it yields (an Icons kind, e.g. "shell")

local config = require("src.config")

local Treasure = {}

-- Is a map due on this delivery? PURE, and it lives here rather than inside
-- World because this cadence is the whole rhythm of the game -- the delivery
-- loop is the spine and hunts are the punctuation -- and it is the one part of
-- the hunt that can be wrong for weeks without anything looking broken. It just
-- quietly feels relentless. That has happened twice now (see config.TREASURE),
-- so it sits somewhere a headless test can reach it (tests/treasure.lua).
--
--   everHad   has the player ever had a map? The FIRST one is guaranteed, so
--             the hunt always gets introduced -- a pre-reader can't be told the
--             mechanic exists, he has to be handed it.
--   sinceMap  deliveries of NORMAL trading since the last map. Deliveries made
--             during a hunt deliberately don't count: the breather is a break
--             FROM ordinary trading, so it has to be measured in it
--             (World:openDock).
--   roll      a 0..1 random number, passed in rather than drawn here.
function Treasure.mapDue(everHad, sinceMap, cooldown, roll, chance)
    if not everHad then return true end
    -- A guaranteed breather first: without it a fair coin will hand you a
    -- second hunt immediately after the first often enough to feel like the
    -- game is nothing but treasure hunts.
    if sinceMap < cooldown then return false end
    return roll < chance
end

-- The COUNT biggest islands, in island order (stable -> stable collectible map).
local function pickIslands(n)
    local idx = {}
    for i = 1, #config.ISLANDS do idx[i] = i end
    table.sort(idx, function(a, b) return config.ISLANDS[a].radius > config.ISLANDS[b].radius end)
    local picks = {}
    for i = 1, math.min(n, #idx) do picks[i] = idx[i] end
    table.sort(picks)
    return picks
end

-- An OPEN-water spot just off `isl`: the first tile (stepping out from the coast
-- at a seeded angle) that has water on all sides, so the boat -- which sails in
-- straight lines, no pathfinding -- can pull right up to it without grinding the
-- shore. The sandbank is only a visual; placing it in clean water is what keeps
-- the approach smooth. Returns world x, y (tile centre) or nil.
local function sandbankNear(terrain, isl, salt)
    local T = config.TILE
    local ci = math.floor(isl.x / T) + 1
    local cj = math.floor(isl.y / T) + 1
    local r0 = math.max(2, math.floor(isl.radius / T))    -- roughly the coast
    local start = salt * 2.3999632                        -- golden-angle spread per chest

    local function openWater(i, j)                         -- water all around (reachable)
        for di = -1, 1 do
            for dj = -1, 1 do
                local row = terrain.tiles[i + di]
                local t = row and row[j + dj]
                if not (t and t.water) then return false end
            end
        end
        return true
    end

    for r = r0 + 1, r0 + 16 do
        local steps = math.max(12, r * 6)
        for s = 0, steps - 1 do
            local ang = start + (s / steps) * math.pi * 2
            local i = ci + math.floor(math.cos(ang) * r + 0.5)
            local j = cj + math.floor(math.sin(ang) * r + 0.5)
            if i >= 2 and j >= 2 and i < terrain.nx and j < terrain.ny and openWater(i, j) then
                return (i - 0.5) * T, (j - 0.5) * T
            end
        end
    end
    return nil
end

-- Build the chest list. `foundSet[id] = true` for chests already dug up.
function Treasure.build(terrain, foundSet)
    foundSet = foundSet or {}
    local goods = config.TREASURE_GOODS
    local list = {}
    for k, islIdx in ipairs(pickIslands(config.TREASURE.COUNT)) do
        local x, y = sandbankNear(terrain, config.ISLANDS[islIdx], k)
        if x then
            local id = "treasure" .. islIdx
            list[#list + 1] = {
                id    = id,
                x     = x,
                y     = y,
                good  = goods[((k - 1) % #goods) + 1],
                found = foundSet[id] == true,
            }
        end
    end
    return list
end

return Treasure
