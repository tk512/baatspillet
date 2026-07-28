-- tests/pirate.lua
-- How an attacking pirate holds its distance (Pirate.stationOffset).
--
-- Worth a test file because the failure is silent and gets blamed on the art. A
-- pirate that steers straight at you closes to zero, parks inside your hull and
-- clips through the sprite -- it looks like a drawing bug, not a steering one --
-- and a duel fought at zero range is unreadable to a five-year-old, who can no
-- longer tell which ship is which. It also stops the gunnery working, since the
-- shot leaves a long bow that by then is past you.
--
-- The rule is deliberately ONE continuous function of distance rather than a
-- close-in / hold / back-off state machine: a machine judders along its own
-- boundaries, which on screen is a galleon twitching in place.
--
-- Runs WITHOUT LÖVE, from the project root:
--     luajit tests/pirate.lua
-- (plain `lua` works too). Exit code 0 = all green.

package.path = "./?.lua;" .. package.path
local H = require("tests.harness")
H.installLove()

local Pirate = require("src.entities.pirate")
local config = require("src.config")
local check, near, eq = H.check, H.near, H.eq

local S = config.PIRATE.STANDOFF
local QUARTER, HALF = math.pi * 0.5, math.pi
local TOL = 1e-9

-- ── the three landmarks the whole behaviour rests on ─────────────────────────
for _, dir in ipairs({ 1, -1 }) do
    local tag = " (dir " .. dir .. ")"
    near(Pirate.stationOffset(S * 5, S, dir), 0, TOL,
        "far outside its station it steers straight at you" .. tag)
    near(Pirate.stationOffset(S * 2, S, dir), 0, TOL,
        "...and is already fully committed at twice the range" .. tag)
    near(Pirate.stationOffset(S, S, dir), dir * QUARTER, TOL,
        "ON station it steers across you -- it circles" .. tag)
    near(Pirate.stationOffset(0, S, dir), dir * HALF, TOL,
        "on top of you it steers away -- this is the anti-clipping case" .. tag)
end

-- ── continuous and monotonic: no judder, no reversal ─────────────────────────
local prev, prevD = nil, nil
for i = 0, 200 do
    local d = (i / 200) * S * 2.5
    local o = Pirate.stationOffset(d, S, 1)
    check(o == o, "offset is a number at d=" .. math.floor(d))
    check(o >= -TOL and o <= HALF + TOL,
        "offset stays within a half turn at d=" .. math.floor(d))
    if prev then
        -- closer in always means a bigger turn away: never the reverse
        check(o <= prev + 1e-9,
            "the turn only opens up as it gets closer (d=" .. math.floor(d) .. ")")
        -- and it moves smoothly, with no step at any boundary
        check(math.abs(o - prev) < 0.06,
            "no jump between neighbouring distances (d=" .. math.floor(d) .. ")")
    end
    prev, prevD = o, d
end

-- ── it must never end up steering INTO the boat when close ───────────────────
-- The bug this exists to prevent: anywhere inside the station the pirate must
-- have SOME outward component, or it drives on through the hull.
for i = 0, 40 do
    local d = (i / 40) * S * 0.95
    local o = Pirate.stationOffset(d, S, 1)
    check(o > QUARTER,
        "inside the station it turns past a quarter, i.e. outward (d=" .. math.floor(d) .. ")")
end
-- ...and outside it, some inward component, or it never closes to fight
for i = 1, 40 do
    local d = S + (i / 40) * S
    local o = Pirate.stationOffset(d, S, 1)
    check(o < QUARTER + 1e-9,
        "outside the station it turns inside a quarter, i.e. closes (d=" .. math.floor(d) .. ")")
end

-- ── the station sits clear of both hulls and inside the guns ─────────────────
-- 26 (pirate) + 20 (boat) is the point where the sprites literally overlap.
check(S > (26 + 20) * 3,
    "the station keeps a wide berth, not a hull's width (S=" .. S .. ")")
check(S < config.PIRATE.FIRE_RANGE,
    "...and is inside FIRE_RANGE, or it would circle forever without shooting")
-- flight time from station: long enough to see the ball and steer off it
local flight = S / config.PIRATE.BALL_SPEED
check(flight > 1.0, "a ball from station takes over a second -- dodge-able ("
    .. string.format("%.1fs", flight) .. ")")

-- ── degenerate inputs ────────────────────────────────────────────────────────
eq(Pirate.stationOffset(500, 0, 1), 0, "a zero station is simply no standoff")
eq(Pirate.stationOffset(500, nil, 1), 0, "a missing station doesn't crash the AI")
near(Pirate.stationOffset(-5, S, 1), HALF, TOL, "a negative distance clamps, no NaN")

H.report()
