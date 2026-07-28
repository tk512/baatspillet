-- tests/pointer.lua
-- The geometry behind the "go THAT way" markers (src/ui/pointer.lua).
--
-- The invariant worth a test file: the treasure marker is a CHEST with a small
-- arrow on it, and a chest is not symmetric. Rotate it with the arrow and it
-- hangs upside-down every time the boat sails west -- and an upside-down chest
-- stops reading as a chest, which is the entire point of the marker. That bug
-- is invisible in half of all playtests, because half the time you happen to be
-- sailing east.
--
-- So: Pointer.layout returns the badge's anchor and the arrow's angle
-- SEPARATELY, and returns no rotation for the badge at all. These tests pin the
-- anchor as bearing-independent at every compass point.
--
-- Screen space: x grows right, y grows DOWN (so "south" on screen is +y).
--
-- Runs WITHOUT LÖVE, from the project root:
--     luajit tests/pointer.lua
-- (plain `lua` works too). Exit code 0 = all green.

package.path = "./?.lua;" .. package.path
local H = require("tests.harness")
H.installLove()

local Pointer = require("src.ui.pointer")
local check, near = H.check, H.near

local BX, BY = 400, 300         -- the boat, mid-screen
local LIFT, WOBBLE = 60, 4      -- marker floats this far above it, bobbing
local TOL = 1e-9

-- eight bearings around the boat, at a fixed distance
local D = 250
local BEARINGS = {
    { name = "east",       ang = 0 },
    { name = "south-east", ang = math.pi * 0.25 },
    { name = "south",      ang = math.pi * 0.5 },
    { name = "south-west", ang = math.pi * 0.75 },
    { name = "west",       ang = math.pi },
    { name = "north-west", ang = -math.pi * 0.75 },
    { name = "north",      ang = -math.pi * 0.5 },
    { name = "north-east", ang = -math.pi * 0.25 },
}

-- ── the arrow points at the target, at every bearing ─────────────────────────
for _, b in ipairs(BEARINGS) do
    local tx = BX + math.cos(b.ang) * D
    local ty = BY + math.sin(b.ang) * D
    local _, _, ang = Pointer.layout(BX, BY, tx, ty, LIFT, 0, 0, 0)
    -- compare as a direction, not a number: -pi and +pi are the same bearing
    near(math.cos(ang), math.cos(b.ang), 1e-9, "arrow points " .. b.name .. " (cos)")
    near(math.sin(ang), math.sin(b.ang), 1e-9, "arrow points " .. b.name .. " (sin)")
end

-- ── THE INVARIANT: the badge anchor does not care which way you're sailing ───
-- With no hop, the anchor sits directly above the boat whatever the bearing --
-- it never orbits, never swings, and (crucially) layout returns NO angle for
-- it. There is nothing a caller could rotate the chest by.
for _, b in ipairs(BEARINGS) do
    local tx = BX + math.cos(b.ang) * D
    local ty = BY + math.sin(b.ang) * D
    local ax, ay = Pointer.layout(BX, BY, tx, ty, LIFT, 0, WOBBLE, 30)
    near(ax, BX, TOL, "badge stays above the boat sailing " .. b.name .. " (x)")
    near(ay, BY - LIFT + WOBBLE, TOL, "badge stays above the boat sailing " .. b.name .. " (y)")
end

-- the badge anchor is identical east vs west -- the case that would have shown
-- an upside-down chest if the badge lived inside the rotation
local eAx, eAy = Pointer.layout(BX, BY, BX + D, BY, LIFT, 0, 0, 30)
local wAx, wAy = Pointer.layout(BX, BY, BX - D, BY, LIFT, 0, 0, 30)
near(eAx, wAx, TOL, "badge anchor: east == west (x)")
near(eAy, wAy, TOL, "badge anchor: east == west (y)")

-- ── the arrow orbits the anchor, along the bearing ───────────────────────────
for _, b in ipairs(BEARINGS) do
    local tx = BX + math.cos(b.ang) * D
    local ty = BY + math.sin(b.ang) * D
    local ax, ay, ang, qx, qy = Pointer.layout(BX, BY, tx, ty, LIFT, 0, 0, 30)
    local dx, dy = qx - ax, qy - ay
    near(math.sqrt(dx * dx + dy * dy), 30, 1e-9,
        "arrow sits exactly `orbit` from the anchor, " .. b.name)
    -- ...and on the target's side of it, not the far side
    near(dx, math.cos(ang) * 30, 1e-9, "arrow orbits toward the target, " .. b.name .. " (x)")
    near(dy, math.sin(ang) * 30, 1e-9, "arrow orbits toward the target, " .. b.name .. " (y)")
end

-- orbit 0 (the gold mission arrow): the arrow IS the marker, sitting on the anchor
local ax, ay, _, qx, qy = Pointer.layout(BX, BY, BX + D, BY + D, LIFT, 0, 0, 0)
near(qx, ax, TOL, "orbit 0: arrow sits on the anchor (x)")
near(qy, ay, TOL, "orbit 0: arrow sits on the anchor (y)")

-- ── the hop leans the whole marker TOWARD the target ─────────────────────────
-- The motion itself points ("this way! this way!"), so it must never lean away.
for _, b in ipairs(BEARINGS) do
    local tx = BX + math.cos(b.ang) * D
    local ty = BY + math.sin(b.ang) * D
    local hAx, hAy = Pointer.layout(BX, BY, tx, ty, LIFT, 12, 0, 0)
    local rAx, rAy = Pointer.layout(BX, BY, tx, ty, LIFT, 0, 0, 0)
    -- displacement caused by the hop, projected onto the bearing: must be +12
    local dx, dy = hAx - rAx, hAy - rAy
    near(dx * math.cos(b.ang) + dy * math.sin(b.ang), 12, 1e-9,
        "hop leans toward the target, " .. b.name)
end

-- a zero hop leaves the anchor exactly where it was (no drift from the maths)
local zAx, zAy = Pointer.layout(BX, BY, BX + D, BY - D, LIFT, 0, 0, 0)
near(zAx, BX, TOL, "no hop: no sideways drift")
near(zAy, BY - LIFT, TOL, "no hop: anchor is exactly LIFT above the boat")

-- ── degenerate: the target is exactly where the boat is ──────────────────────
-- (you're on top of the chest, the frame before it's grabbed) -- must not blow up
local ok = pcall(function()
    local x, y, a2 = Pointer.layout(BX, BY, BX, BY, LIFT, 8, 0, 30)
    check(x == x and y == y and a2 == a2, "target under the boat: no NaN")
end)
check(ok, "target under the boat: does not error")

H.report()
