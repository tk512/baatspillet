-- tests/announce.lua
-- The curves behind the marker flourish (src/ui/announce.lua).
--
-- Worth a test file because the whole point of the announce is a window in which
-- a five-year-old looks up and sees WHICH town (or that there's a chest). If the
-- badge is already most of the way back to normal size by the time he does, the
-- flourish still "works" on every frame counter and does nothing at all for the
-- player -- a failure that is invisible in code review and hard to spot by eye,
-- because something did flash. So the hold is pinned numerically.
--
-- The other reason: mission and treasure drive their badge, their whole-marker
-- growth and their caption from ONE countdown through these functions. If the
-- curve is not a pure function of the phase they drift apart, and a caption
-- outliving its badge is exactly the kind of thing nobody files a bug about.
--
-- Runs WITHOUT LÖVE, from the project root:
--     luajit tests/announce.lua
-- (plain `lua` works too). Exit code 0 = all green.

package.path = "./?.lua;" .. package.path
local H = require("tests.harness")
H.installLove()

local A = require("src.ui.announce")
local config = require("src.config")
local check, near, eq = H.check, H.near, H.eq

local DUR = 3.2

-- ── phase: 1 the instant it fires, 0 when it's over ──────────────────────────
near(A.phase(DUR, DUR), 1, 1e-9, "phase is 1 at the moment it fires")
near(A.phase(DUR / 2, DUR), 0.5, 1e-9, "phase is 0.5 halfway")
eq(A.phase(0, DUR), 0, "phase is 0 when the timer runs out")
eq(A.phase(-1, DUR), 0, "phase is 0 once the timer goes negative")
eq(A.phase(nil, DUR), 0, "phase is 0 when no announce is running")
eq(A.phase(DUR, 0), 0, "phase is 0 for a zero-length announce (no divide by zero)")
near(A.phase(DUR * 2, DUR), 1, 1e-9, "phase clamps at 1, never overshoots")

-- phase falls monotonically as the countdown runs down
local prev = math.huge
for i = 0, 32 do
    local p = A.phase(DUR * (1 - i / 32), DUR)
    check(p <= prev + 1e-12, "phase never rises as the timer drains (step " .. i .. ")")
    prev = p
end

-- ── pop: springs in, overshoots, then HOLDS at full size ─────────────────────
local SPAN, OVER = config.MARKER_ANNOUNCE.POP, config.MARKER_ANNOUNCE.OVER
near(A.pop(1, SPAN, OVER), 0, 1e-9, "pop starts at nothing")
near(A.pop(1 - SPAN, SPAN, OVER), 1, 1e-9, "pop is exactly full size when it lands")
eq(A.pop(0, SPAN, OVER), 1, "pop holds at full size once the entrance is done")
eq(A.pop(-1, SPAN, OVER), 1, "a spent phase is simply full size, not a crash")

-- THE POINT OF THE FILE: the entrance is a BUMP, not a polite ease. If this
-- stops overshooting, the flourish still runs on every frame counter and stops
-- doing the one thing it exists for -- pulling a child's eye off the sea.
local peak = 0
for i = 0, 200 do
    local p = 1 - (i / 200) * SPAN
    peak = math.max(peak, A.pop(p, SPAN, OVER))
end
check(peak > 1.05, "pop overshoots past full size on the way in (got " .. peak .. ")")
check(peak < 1.6, "...but not so far it reads as a glitch (got " .. peak .. ")")

-- it must never go negative: a negative scale mirrors the text
for i = 0, 200 do
    local p = 1 - (i / 200)
    check(A.pop(p, SPAN, OVER) >= 0, "pop never flips the caption (step " .. i .. ")")
end

-- the entrance is over well before the fade begins, so the line is never both
-- arriving and leaving at once
check(1 - SPAN > config.MARKER_ANNOUNCE.FADE,
    "the entrance finishes before the fade starts")

-- ── alpha: solid while it's readable, fading only at the end ─────────────────
local FADE = 0.38
eq(A.alpha(0, FADE), 0, "alpha is 0 once the phase is spent")
near(A.alpha(1, FADE), 1, 1e-9, "alpha is full at the start")
near(A.alpha(FADE, FADE), 1, 1e-9, "alpha is still full at the fade point")
near(A.alpha(FADE / 2, FADE), 0.5, 1e-9, "alpha is half, halfway through the fade")
near(A.alpha(0.5, 0), 1, 1e-9, "a zero fade means no fade at all")

-- the caption must not outlive the flourish: alpha hits 0 no later than phase 0
near(A.alpha(1e-9, FADE), 0, 1e-6, "alpha is spent as the phase reaches 0")

-- ── pulse: small, centred on 1, and never inverts ────────────────────────────
local amt = config.MARKER_ANNOUNCE.PULSE
for i = 0, 40 do
    local v = A.pulse(i * 0.13, amt)
    check(v >= 1 - amt - 1e-9 and v <= 1 + amt + 1e-9,
        "pulse stays within +/- amt of 1 (step " .. i .. ")")
    check(v > 0, "pulse never flips the badge inside out (step " .. i .. ")")
end

-- ── fit: the caption can never run off the sides ─────────────────────────────
near(A.fit(1, 400, 800), 1, 1e-9, "a line that fits is left alone")
near(A.fit(1.1, 400, 800), 1.1, 1e-9, "...including at the entrance's overshoot")
near(A.fit(2, 400, 800), 2, 1e-9, "exactly filling the width is still a fit")
near(A.fit(3, 400, 800), 2, 1e-9, "an oversized line is shrunk to exactly fit")
near(A.fit(1, 900, 800) * 900, 800, 1e-9, "the shrunk line ends up exactly max width")
eq(A.fit(1, 0, 800), 1, "a zero-width string is not a divide by zero")
eq(A.fit(1, 400, 0), 1, "a zero-width screen is left alone rather than collapsing")

-- ── the config the two markers actually share ────────────────────────────────
local M = config.MARKER_ANNOUNCE
check(M.TIME >= 2 and M.TIME <= 4,
    "the line is up for 2-3s: long enough to be seen, short enough not to nag")
check(M.POP > 0 and M.POP < 1, "the entrance takes a fraction of the phase")
check(M.FADE > 0 and M.FADE < 1, "the caption fades inside the flourish, not after")
check(M.PULSE > 0 and M.PULSE < 0.25, "the breathing is a hint of movement, not a wobble")
check(config.MISSION_MARKER.TEXT ~= config.TREASURE_MODE.TEXT,
    "the two announces say different things")
check(#config.TREASURE_MODE.TEXT > 0 and #config.MISSION_MARKER.TEXT > 0,
    "both announces have something to say")
check(config.TREASURE_MODE.HINT_SIZE > 0 and config.TREASURE_MODE.HINT_MARGIN > 0,
    "the treasure edge hint has a size and a margin")
-- the hint's centre must sit far enough in that the chest isn't half off screen
check(config.TREASURE_MODE.HINT_MARGIN >= config.TREASURE_MODE.HINT_SIZE / 2,
    "the edge hint is pinned far enough in to be drawn whole")

H.report()
