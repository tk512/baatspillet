-- tests/icons.lua
-- The goods huddle (Icons.cluster / Icons.clusterWidth in src/ui/icons.lua).
--
-- Worth a test file for one reason: TWO things have to agree. HUD.drawMission
-- lays the mission banner out from `clusterWidth` and then draws the figures with
-- `cluster`. If those two disagree the huddle silently overlaps "Oppdrag" on one
-- side or the town name on the other, and only for some counts -- so it looks
-- fine with 1 fish and wrong with 4 passengers, which is exactly the kind of bug
-- that ships. Same failure the shelf's shared `sectionExtent` exists to prevent.
--
-- Runs WITHOUT LÖVE, from the project root:
--     luajit tests/icons.lua
-- (plain `lua` works too). Exit code 0 = all green.

package.path = "./?.lua;" .. package.path
local H = require("tests.harness")
H.installLove()

local Icons = require("src.ui.icons")
local check, near, eq = H.check, H.near, H.eq

local TOL = 1e-9
local S = 40                        -- one item's size
local CX, CY = 500, 300

-- Watch what cluster actually asks to be drawn.
local drawn
local realDraw = Icons.draw
Icons.draw = function(kind, x, y, s) drawn[#drawn + 1] = { kind = kind, x = x, y = y, s = s } end
local function run(list, n)
    drawn = {}
    Icons.cluster(list, n, CX, CY, S)
    return drawn
end

-- ── count: clamped, never zero, never a crowd ────────────────────────────────
eq(Icons.clusterCount(1), 1, "one is one")
eq(Icons.clusterCount(4), 4, "four is four")
eq(Icons.clusterCount(0), 1, "a zero count still draws one thing, not nothing")
eq(Icons.clusterCount(-3), 1, "a negative count cannot draw a negative crowd")
eq(Icons.clusterCount(nil), 1, "a missing count falls back to one")
eq(Icons.clusterCount(99), Icons.CLUSTER_MAX, "a huge count is capped at a countable group")
eq(Icons.clusterCount(2.7), 2, "a fractional count floors rather than drawing 2.7 people")

-- ── THE INVARIANT: clusterWidth is what cluster actually occupies ────────────
for n = 1, 6 do
    local d = run("fish", n)
    eq(#d, n, "cluster draws exactly n figures (n=" .. n .. ")")

    local lo, hi = math.huge, -math.huge
    for _, it in ipairs(d) do
        lo = math.min(lo, it.x - it.s / 2)
        hi = math.max(hi, it.x + it.s / 2)
    end
    near(hi - lo, Icons.clusterWidth(n, S), TOL,
        "clusterWidth matches the drawn extent (n=" .. n .. ")")
    -- ...and the huddle is CENTRED on the point it was given, so a caller that
    -- reserved clusterWidth around cx gets exactly what it reserved
    near((lo + hi) / 2, CX, TOL, "the huddle is centred on cx (n=" .. n .. ")")
end

-- one item is exactly one item wide -- no phantom padding in the common case
near(Icons.clusterWidth(1, S), S, TOL, "a single item occupies exactly its own size")

-- ── they OVERLAP: a group, not a row ─────────────────────────────────────────
-- The whole point of the huddle is that three passengers read as one errand.
-- If the step ever grows past 1 they stop touching and it's a row again.
check(Icons.CLUSTER_STEP < 1, "figures overlap rather than sitting side by side")
check(Icons.CLUSTER_STEP > 0, "...but they don't stack into a single blob")
local d3 = run("fish", 3)
for i = 2, 3 do
    check(d3[i] ~= nil, "figure " .. i .. " exists")
end
-- ── the FIRST one is in front: drawn last, so nothing paints over it ─────────
-- Drawn back-to-front. A chest or a face half-covered by the one behind it stops
-- reading as a chest or a face, which is the same reason the marker badge never
-- rotates (tests/pointer.lua).
local order = run("fish", 4)
near(order[#order].x, order[1].x - 3 * S * Icons.CLUSTER_STEP, TOL,
    "the LAST thing drawn is the front figure, at the head of the huddle")
for i = 2, #order do
    check(order[i].x < order[i - 1].x, "each one drawn is further forward (step " .. i .. ")")
    check(order[i].y > order[i - 1].y, "...and a touch lower, so the huddle has depth")
end

-- ── a per-item list gives a group of DIFFERENT people ────────────────────────
local FIGS = { "passenger1", "passenger2", "passenger3" }
local dl = run(FIGS, 3)
local seenKinds = {}
for _, it in ipairs(dl) do seenKinds[it.kind] = true end
for _, want in ipairs(FIGS) do
    check(seenKinds[want], "the huddle uses the real figure '" .. want .. "'")
end

-- a list shorter than the count repeats its first entry rather than drawing nil
local dshort = run({ "passenger1" }, 3)
eq(#dshort, 3, "a short list still draws the full count")
for _, it in ipairs(dshort) do
    eq(it.kind, "passenger1", "...falling back to the first figure")
end

-- a plain string is repeated, which is the cargo case
for _, it in ipairs(run("box", 3)) do eq(it.kind, "box", "a single kind repeats") end

Icons.draw = realDraw
H.report()
