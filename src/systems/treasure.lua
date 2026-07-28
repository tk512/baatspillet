-- Places the hunt's chests: one per big island, on a sandbank in open water.
-- Seeded from the world seed, so the save only stores which were found.
-- A treasure is { id, x, y, good, found }; `good` is an Icons kind.

local config = require("src.config")

local Treasure = {}

-- Is a map due on this delivery? Pure, and tested (tests/treasure.lua) --
-- the cadence is tuned in config.TREASURE and explained in CLAUDE.md.
--   everHad   the first map is guaranteed
--   sinceMap  normal deliveries since the last map; deliveries made DURING a
--             hunt don't count (World:openDock)
--   roll      0..1, drawn by the caller
function Treasure.mapDue(everHad, sinceMap, cooldown, roll, chance)
    if not everHad then return true end
    if sinceMap < cooldown then return false end
    return roll < chance
end

-- the COUNT biggest islands, in island order (stable -> stable collectibles)
local function pickIslands(n)
    local idx = {}
    for i = 1, #config.ISLANDS do idx[i] = i end
    table.sort(idx, function(a, b) return config.ISLANDS[a].radius > config.ISLANDS[b].radius end)
    local picks = {}
    for i = 1, math.min(n, #idx) do picks[i] = idx[i] end
    table.sort(picks)
    return picks
end

-- First tile off `isl` with water on all sides, stepping out from the coast at
-- a seeded angle. The boat has no pathfinding, so open water is what lets it
-- pull straight up. Returns world x, y (tile centre) or nil.
local function sandbankNear(terrain, isl, salt)
    local T = config.TILE
    local ci = math.floor(isl.x / T) + 1
    local cj = math.floor(isl.y / T) + 1
    local r0 = math.max(2, math.floor(isl.radius / T))    -- roughly the coast
    local start = salt * 2.3999632                        -- golden angle, spreads the chests

    local function openWater(i, j)
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

-- `foundSet[id] = true` for chests already dug up.
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
