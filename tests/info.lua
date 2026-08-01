-- tests/info.lua
-- The help page's geometry (Info.layout in src/scenes/info.lua).
--
-- Worth a test file for one reason: the page has a fixed number of rows and no
-- scrolling, so on a short screen the last row is simply GONE -- and it is gone
-- on the phone he plays on, while looking perfect on the iPad it was written on.
-- That is the exact failure Announce.fit exists for, one screen bigger, and it
-- is silent: nothing errors, nothing logs, the page just stops early. So the
-- invariant is pinned here at every shape the game ships in.
--
-- Also checked: the panel never slides under the Tilbake key or the heading
-- (which is what "shrink the rows, not the margins" has to mean), and the icon
-- column stays inside its row -- the same draw-and-layout-must-agree contract
-- tests/icons.lua and tests/shelf.lua exist to hold.
--
-- Runs WITHOUT LÖVE, from the project root:
--     luajit tests/info.lua
-- (plain `lua` works too). Exit code 0 = all green.

package.path = "./?.lua;" .. package.path
local H = require("tests.harness")
H.installLove()

local Info  = require("src.scenes.info")
local Icons = require("src.ui.icons")
local check, eq = H.check, H.eq

-- Every shape the game actually runs at, plus two deliberately cruel ones.
-- The heading is fonts.big at that k (Game:buildFonts: 40).
local SCREENS = {
    { name = "desktop 1280x800",  w = 1280, h = 800,  k = 1.0 },
    { name = "iPad 1366x1024",    w = 1366, h = 1024, k = 1.28 },
    { name = "iPad 1080x810",     w = 1080, h = 810,  k = 1.01 },
    { name = "iPhone 874x402",    w = 874,  h = 402,  k = 0.804 },   -- phone: k * UI_BOOST
    { name = "iPhone 932x430",    w = 932,  h = 430,  k = 0.86 },
    { name = "tiny 640x360",      w = 640,  h = 360,  k = 0.45 },
    { name = "portrait 768x1024", w = 768,  h = 1024, k = 1.28 },
}

local N = 6                       -- the page's row count (ROWS in info.lua)

local function titleH(k) return 40 * k end

for _, s in ipairs(SCREENS) do
    local tH = titleH(s.k)
    local L = Info.layout(s.w, s.h, s.k, N, tH)
    local P = L.panel

    -- ── nothing falls off the bottom ─────────────────────────────────────────
    check(P.y + P.h <= L.bottom, s.name .. ": panel clears the bottom margin")
    check(L.bottom <= s.h, s.name .. ": the bottom margin is on screen")
    local last = L.rows[N]
    check(last.y + last.h <= P.y + P.h + 1e-9, s.name .. ": the last row is inside the panel")
    check(last.y + last.h <= s.h, s.name .. ": the last row is on screen at all")

    -- ── nor off the top, under the heading or the Tilbake key ────────────────
    check(P.y >= L.titleY + tH, s.name .. ": panel starts below the heading")
    check(P.y >= L.back.y + L.back.h, s.name .. ": panel starts below the Tilbake key")
    check(L.rows[1].y >= P.y, s.name .. ": the first row is inside the panel")

    -- ── horizontally inside the window ───────────────────────────────────────
    check(P.x >= 0 and P.x + P.w <= s.w, s.name .. ": panel fits the width")
    check(L.back.x + L.back.w <= s.w, s.name .. ": the Tilbake key fits the width")

    -- ── the rows tile the panel exactly, no gaps and no overlap ──────────────
    for i = 2, N do
        H.near(L.rows[i].y, L.rows[i - 1].y + L.rowH, 1e-9,
            s.name .. ": row " .. i .. " sits directly under row " .. (i - 1))
    end
    check(L.rowH > 0, s.name .. ": rows have height")

    -- ── the symbol column leaves the sentence somewhere to go ────────────────
    check(L.iconW < L.rows[1].w * 0.5,
        s.name .. ": the icon column is under half the row, so text has room")
    check(L.iconW <= L.rowH * 1.0, s.name .. ": the icon column stays inside its row")
end

-- ── shrink-to-fit, not overflow ──────────────────────────────────────────────
-- The rule the whole page rests on: rows take what is left, and what is left
-- getting smaller makes the ROWS smaller -- never pushes them past the edge.
do
    local tall = Info.layout(1280, 800, 1, N, 40)
    local short = Info.layout(1280, 420, 1, N, 40)
    check(short.rowH < tall.rowH, "a shorter screen shrinks the rows")
    check(tall.rowH <= Info.ROW_H, "a tall screen never grows a row past ROW_H")
    eq(tall.rowH, Info.ROW_H, "with room to spare a row is exactly ROW_H")
    check(short.panel.y + short.panel.h <= short.bottom,
        "even squeezed, the panel clears the bottom margin")
end

-- Absurdly short: it must still return usable, on-screen geometry rather than
-- negative heights. Nobody plays at 240px, but a resize passes through them.
do
    local L = Info.layout(1280, 240, 1, N, 40)
    check(L.rowH > 0, "a 240px window still yields positive rows")
    check(L.panel.h > 0, "a 240px window still yields a positive panel")
end

-- ── the huddle fits the column it is drawn in ────────────────────────────────
-- Info:drawRow solves `s` from Icons.clusterWidth so three passengers land
-- inside the symbol column. If that solve and clusterWidth ever disagree the
-- huddle creeps under the sentence -- for SOME counts only, which is the bug
-- tests/icons.lua was written for. Same arithmetic, checked here at the sizes
-- the page uses.
do
    local PAINT = 1.5                        -- Icons.draw paints art at 1.5x
    for _, s in ipairs(SCREENS) do
        local L = Info.layout(s.w, s.h, s.k, N, titleH(s.k))
        local avail = L.iconW * 0.84
        for n = 1, 4 do
            local size = avail / (Icons.clusterWidth(n, 1) + (PAINT - 1))
            -- true extent = the huddle's own width + the art's overhang each side
            local extent = Icons.clusterWidth(n, size) + size * (PAINT - 1)
            H.near(extent, avail, 1e-9,
                s.name .. ": a huddle of " .. n .. " exactly fills the symbol column")
            check(extent <= L.iconW, s.name .. ": a huddle of " .. n .. " stays in its column")
        end
    end
end

H.report()
