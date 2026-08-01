-- tests/treasure.lua
-- The treasure-map CADENCE: how often a harbourmaster hands over a map.
--
-- Worth its own file because this number is the whole rhythm of the game -- the
-- delivery loop is the spine and hunts are the punctuation -- and because it is
-- the one part of the treasure hunt that can be wrong for weeks without anything
-- looking broken. It just quietly feels relentless. That has now happened twice:
-- once with no floor at all, and once with a floor that deliveries made DURING a
-- hunt were silently eating (World:openDock).
--
-- Only Treasure.mapDue is exercised: the method that calls it needs a whole
-- World, and the rule is the part that matters. It lives in src/systems/treasure
-- rather than in world.lua precisely so this file can reach the REAL function --
-- world.lua pulls in src/ui/minimap.lua, which needs `utf8` and won't load
-- headlessly, and a test asserting against its own copy of a rule is worse than
-- no test at all.
--
-- Runs WITHOUT LÖVE, from the project root:
--     luajit tests/treasure.lua
-- (plain `lua` works too). Exit code 0 = all green.

package.path = "./?.lua;" .. package.path
local H = require("tests.harness")
H.installLove()

local config   = require("src.config")
local Treasure = require("src.systems.treasure")
local check, near = H.check, H.near

local mapDue = Treasure.mapDue      -- the shipping rule, not a copy of it
local T = config.TREASURE

-- ── the first map is guaranteed ──────────────────────────────────────────────
-- The hunt has to be INTRODUCED: a pre-reader can't be told the mechanic exists,
-- so the first delivery always hands one over whatever the dice say.
check(mapDue(false, 0, 99, 0.99, 0.0), "first map is guaranteed, whatever the roll")
check(mapDue(false, 0, T.MAP_COOLDOWN, 1.0, T.MAP_CHANCE),
    "first map ignores the cooldown too")

-- ── the floor is hard ────────────────────────────────────────────────────────
for since = 0, T.MAP_COOLDOWN - 1 do
    check(not mapDue(true, since, T.MAP_COOLDOWN, 0.0, T.MAP_CHANCE),
        ("blocked at %d deliveries -- even on a winning roll"):format(since))
end
check(mapDue(true, T.MAP_COOLDOWN, T.MAP_COOLDOWN, 0.0, T.MAP_CHANCE),
    "allowed the moment the floor is reached, on a winning roll")
check(not mapDue(true, T.MAP_COOLDOWN, T.MAP_COOLDOWN, 0.999, T.MAP_CHANCE),
    "...but still only a chance -- a losing roll waits")

-- roll is compared strictly, so chance 0 never fires and chance 1 always does
check(not mapDue(true, 99, 0, 0.0, 0.0), "chance 0 never hands over a map")
check(mapDue(true, 99, 0, 0.999, 1.0), "chance 1 always does")

-- ── the gap, measured ────────────────────────────────────────────────────────
-- Deliveries of normal trading between hunts. Asserted against the closed form
-- rather than a hard-coded 4.2, so tuning MAP_CHANCE/MAP_COOLDOWN doesn't fail
-- the test -- but a LOGIC regression (the floor being skipped, or eaten by
-- hunt-time deliveries again) still does.
math.randomseed(20260728)
local function measureGap(chance, cooldown)
    local RUNS, total = 40000, 0
    for _ = 1, RUNS do
        local since, n = 0, 0             -- 0 = a map was just granted
        repeat
            n = n + 1
            since = since + 1
        until mapDue(true, since, cooldown, math.random(), chance)
        total = total + n
    end
    return total / RUNS
end

local function predicted(chance, cooldown) return cooldown - 1 + 1 / chance end

for _, c in ipairs({ { 0.45, 3 }, { 0.45, 2 }, { 0.30, 4 }, { 1.00, 1 } }) do
    local chance, cooldown = c[1], c[2]
    near(measureGap(chance, cooldown), predicted(chance, cooldown), 0.05,
        ("gap for chance %.2f / floor %d"):format(chance, cooldown))
end

-- and the SHIPPING numbers land where the config comment says
local gap = measureGap(T.MAP_CHANCE, T.MAP_COOLDOWN)
near(gap, predicted(T.MAP_CHANCE, T.MAP_COOLDOWN), 0.05, "shipping cadence matches its formula")

-- A sanity band, deliberately wide: this is the assertion that makes someone
-- look up when they retune. Too tight and the treasure loop is relentless; too
-- loose and the four chests are so far apart the finale never arrives.
check(gap >= 3.5 and gap <= 6.0,
    ("shipping gap is %.2f deliveries between hunts -- inside the 3.5..6.0 band")
    :format(gap))
check(T.COUNT * gap <= 30,
    ("the whole 4-chest arc is %.0f deliveries -- the finale stays reachable")
    :format(T.COUNT * gap))

-- ── chest identity survives an update ────────────────────────────────────────
-- A saved game stores treasures by ID, and the ID is "treasure" .. the island's
-- INDEX in config.ISLANDS (Treasure.build). Two ways a content change silently
-- breaks a child's half-finished hunt, neither of which errors or logs:
--
--   1. Inserting an island anywhere but the END renumbers every island after it,
--      so treasuresFound/Mapped -- and discoveredIslands, keyed "island"..i --
--      start naming different places than they were written for.
--   2. Adding an island BIGGER than the smallest currently-picked one displaces
--      it: pickIslands takes the COUNT biggest, so a found chest's id stops
--      existing. The tally drops (3/4 back to 2/4), and because `good` is handed
--      out by PICK ORDER, the album's stickers reshuffle underneath him.
--
-- Adding a TOWN is always safe -- nothing in the save mentions ports -- so this
-- guards the islands, which is the part that looks equally innocent in a diff.
local picks = {}
do
    local idx = {}
    for i = 1, #config.ISLANDS do idx[i] = i end
    table.sort(idx, function(a, b) return config.ISLANDS[a].radius > config.ISLANDS[b].radius end)
    for i = 1, math.min(T.COUNT, #idx) do picks[i] = idx[i] end
    table.sort(picks)
end

-- The shipping Norge map. Change this list ONLY together with a save migration.
local EXPECTED = { 1, 3, 5, 7 }
check(#picks == #EXPECTED, ("%d chest islands, as configured"):format(#EXPECTED))
for i, want in ipairs(EXPECTED) do
    check(picks[i] == want,
        ("chest %d sits on island %d (id \"treasure%d\") -- unchanged since release")
        :format(i, want, want))
end

-- The margin that keeps it that way: a new island must stay UNDER the smallest
-- picked radius, or it takes that island's chest. Ties are a coin flip, because
-- table.sort is unstable on equal keys -- so equal is not safe either.
local smallestPicked = math.huge
for _, i in ipairs(picks) do
    smallestPicked = math.min(smallestPicked, config.ISLANDS[i].radius)
end
check(smallestPicked == 1820,
    ("a new Norge island must have radius < %d to leave the hunt alone")
    :format(smallestPicked))

local biggestUnpicked = 0
for i = 1, #config.ISLANDS do
    local picked = false
    for _, p in ipairs(picks) do if p == i then picked = true end end
    if not picked then
        biggestUnpicked = math.max(biggestUnpicked, config.ISLANDS[i].radius)
    end
end
check(biggestUnpicked < smallestPicked,
    ("no tie at the cut: biggest unpicked %d < smallest picked %d, so the "):format(
        biggestUnpicked, smallestPicked)
    .. "pick set can't flip on a re-sort")

H.report()
