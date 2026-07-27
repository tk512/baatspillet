-- tests/cannon.lua
-- The player-aimed cannon shot (Boat:tapFire). Tapping the pirate is the only
-- trigger in the whole game, and unlike everything else the player does it
-- SPENDS something real -- a cannonball -- so every gate around it has to hold:
-- own a cannon, be in range, have a ball left, respect the cooldown. A bug here
-- either empties the locker in a second or makes the tap feel dead.
--
-- It's all arithmetic on the boat -- no drawing, no LÖVE.
--
-- Runs WITHOUT LÖVE, from the project root:
--     luajit tests/cannon.lua
-- (plain `lua` works too). Exit code 0 = all green.

package.path = "./?.lua;" .. package.path
local H = require("tests.harness")
H.installLove()

local config = require("src.config")
local Boat   = require("src.entities.boat")
local Game   = require("src.game")
local shop   = require("src.data.shop")
local check, eq = H.check, H.eq
local C = config.CANNON

math.randomseed(20260725)   -- the spread tests sample randomness; keep runs repeatable

-- Stand-in for Game. It BORROWS the real ammo and cannon-rate methods rather
-- than reimplementing them, so these tests exercise the shipping arithmetic
-- and can't quietly drift from it; only `owns` is faked.
local function fakeGame(ammo, hasCannon, cannons)
    return {
        state       = { ammo = ammo, cannons = cannons or 1 },
        owns        = function(_, id) return hasCannon and id == "cannon" end,
        cannonCount = Game.cannonCount,
        cannonRate  = Game.cannonRate,
        useAmmo     = Game.useAmmo,
        ammoCount   = Game.ammoCount,
    }
end

-- Only the fields tapFire and fireCannon actually touch.
local function fakeBoat()
    return setmetatable({ x = 0, y = 0, balls = {}, cannonT = 0, tapT = 0 }, Boat)
end

-- A pirate `d` ground-units due east, so the true bearing to it is always 0.
local function pirateAt(d) return { x = d, y = 0, radius = 26 } end

local IN  = C.FIRE_RANGE * 0.5    -- comfortably in range
local OUT = C.FIRE_RANGE + 50     -- just out of it

-- no cannon aboard ------------------------------------------------------------
local b, g = fakeBoat(), fakeGame(10, false)
eq(b:tapFire(pirateAt(IN), g), nil, "no cannon: tap does nothing")
eq(#b.balls, 0, "no cannon: no ball fired")
eq(g.state.ammo, 10, "no cannon: no ammo spent")
eq(b.tapFire and b:tapFire(pirateAt(IN), nil), nil, "no game object: tap does nothing")

-- out of range ----------------------------------------------------------------
b, g = fakeBoat(), fakeGame(10, true)
eq(b:tapFire(pirateAt(OUT), g), "far", "out of range: reports far")
eq(#b.balls, 0, "out of range: no ball fired")
eq(g.state.ammo, 10, "out of range: no ammo spent (it would be thrown away)")
eq(b.tapT, 0, "out of range: no cooldown started, so the next tap still works")

-- a good shot -----------------------------------------------------------------
b, g = fakeBoat(), fakeGame(3, true)
eq(b:tapFire(pirateAt(IN), g), "fired", "in range with ammo: fires")
eq(#b.balls, 1, "fired: exactly one ball in flight")
eq(g.state.ammo, 2, "fired: exactly one cannonball spent")
eq(b.tapT, C.TAP_INTERVAL, "fired: tap cooldown started")
check(b.cannonT >= C.TAP_INTERVAL,
    "fired: the automatic battery is pushed back so it can't double-fire")

-- cooldown --------------------------------------------------------------------
eq(b:tapFire(pirateAt(IN), g), "wait", "tapping again at once: waits")
eq(#b.balls, 1, "cooling down: no second ball")
eq(g.state.ammo, 2, "cooling down: no ammo spent")
b.tapT = 0                                   -- pretend the interval elapsed
eq(b:tapFire(pirateAt(IN), g), "fired", "after the cooldown: fires again")
eq(g.state.ammo, 1, "after the cooldown: one more ball spent")

-- empty locker ----------------------------------------------------------------
b, g = fakeBoat(), fakeGame(1, true)
eq(b:tapFire(pirateAt(IN), g), "fired", "last ball: fires")
b.tapT = 0
eq(b:tapFire(pirateAt(IN), g), "empty", "locker empty: reports empty")
eq(#b.balls, 1, "locker empty: no phantom ball")
eq(g.state.ammo, 0, "locker empty: cannot go negative")

-- extra cannons speed the TRIGGER, not just the autopilot ---------------------
local one, many = fakeGame(10, true, 1), fakeGame(10, true, 4)
eq(one:cannonRate(), 1, "one cannon: the base rate")
check(many:cannonRate() > one:cannonRate(), "four cannons: a faster battery")

b = fakeBoat(); b:tapFire(pirateAt(IN), one)
local tapOne = b.tapT
b = fakeBoat(); b:tapFire(pirateAt(IN), many)
local tapMany = b.tapT
eq(tapOne, C.TAP_INTERVAL, "one cannon: the plain tap interval")
H.near(tapMany, C.TAP_INTERVAL / many:cannonRate(), 1e-9,
    "extra cannons divide the tap interval by the battery rate")
check(tapMany < tapOne,
    "buying more cannons makes TAPPING faster, not only the automatic battery")

-- the locker is deep enough for a hammered trigger -----------------------------
-- These guard the design intent behind "mayhem": a fast trigger is only fun if
-- the locker outlasts a burst. If someone retunes START_AMMO or the crate back
-- down to automatic-battery sizes, these fail and say why.
local crate
for _, it in ipairs(shop) do if it.id == "kanonkuler" then crate = it end end
check(crate and (crate.ammo or 0) > 0, "shop: the Kanonkuler crate grants balls")
check(C.START_AMMO * C.TAP_INTERVAL > 15,
    string.format("a fresh cannon survives >15s of non-stop tapping (%.1fs)",
        C.START_AMMO * C.TAP_INTERVAL))
check(crate.ammo * C.TAP_INTERVAL > 8,
    string.format("a bought crate outlasts a burst (%.1fs)", crate.ammo * C.TAP_INTERVAL))

-- aim: a shot you pointed yourself is tighter than the automatic battery's -----
-- Invariants rather than exact angles, so tuning TAP_SPREAD never breaks these.
local function maxAimError(spread)
    local worst = 0
    for _ = 1, 500 do
        local bb = fakeBoat()
        bb:fireCannon(pirateAt(IN), IN, spread)
        local ball = bb.balls[1]
        worst = math.max(worst, math.abs(math.atan2(ball.vy, ball.vx)))
    end
    return worst
end

local tapWorst  = maxAimError(C.TAP_SPREAD)
local autoWorst = maxAimError(nil)           -- nil = the battery's wild SPREAD
check(tapWorst <= C.TAP_SPREAD + 1e-9,
    string.format("aimed shot never strays past TAP_SPREAD (worst %.4f)", tapWorst))
check(autoWorst <= C.SPREAD + 1e-9,
    string.format("auto shot never strays past SPREAD (worst %.4f)", autoWorst))
check(tapWorst < autoWorst,
    "aiming is genuinely rewarded: a tapped shot is tighter than an automatic one")
check(C.TAP_SPREAD < C.SPREAD,
    "config: TAP_SPREAD is tighter than the automatic SPREAD")

-- the ball itself -------------------------------------------------------------
b, g = fakeBoat(), fakeGame(1, true)
b:tapFire(pirateAt(IN), g)
local ball = b.balls[1]
H.near(ball.plan, IN / C.BALL_SPEED, 1e-6, "ball: flight time matches the distance")
H.near(math.sqrt(ball.vx ^ 2 + ball.vy ^ 2), C.BALL_SPEED, 1e-6,
    "ball: leaves the muzzle at BALL_SPEED")
eq(ball.life, 0, "ball: starts with no time on it")

H.report()
