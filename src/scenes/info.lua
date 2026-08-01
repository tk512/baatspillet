-- "Sånn spiller du": the help page behind the title screen's questionmark disc.
--
-- This is the ONE screen in the game aimed past the child. Everywhere else state
-- is carried by shape, colour and voice (CLAUDE.md, "Pre-reader UX") because the
-- player cannot read; a how-to-play page is by nature words, and the words are
-- for whichever grown-up is holding the iPad. So the rule is bent here, not
-- broken: every line is ANCHORED to the symbol it explains, drawn at the size
-- and in the colours the child already meets at sea -- the real gold arrow
-- (Pointer.MISSION), the real chest, the real coin. He can browse the pictures
-- and recognise where each one lives; the grown-up gets the sentence.
--
-- The page is a single column that SHRINKS to fit rather than scrolls: an
-- iPhone is 402pt tall and a scrollbar is one more thing to discover. See
-- Info.layout, which is pure and pinned by tests/info.lua -- a row pushed off
-- the bottom is invisible on the iPad this was written on and obvious on the
-- phone he plays it on, which is the same failure Announce.fit exists for.

local config   = require("src.config")
local Assets   = require("src.assets")
local Retro    = require("src.ui.retro")
local Icons    = require("src.ui.icons")
local Scale    = require("src.ui.scale")
local Scene    = require("src.ui.pixelscene")
local Pointer  = require("src.ui.pointer")
local Announce = require("src.ui.announce")

local W = Retro.WOOD
local Info = {}

-- The chooser sky, one island each side so the middle stays quiet behind the
-- page (same reasoning as the map screen's).
local BACKDROP = {
    horizon = 0.24,
    islands = { { x = 0.05, w = 0.075, h = 0.085 }, { x = 0.96, w = 0.085, h = 0.105 } },
    sun     = { x = 0.90, y = 0.09, r = 0.05 },
    clouds  = { { w = 0.055, yf = 0.08, speed = 6 }, { w = 0.04, yf = 0.045, speed = 4 } },
}

-- The page, in the order the game is actually played: take a job, follow the
-- arrow, get paid, spend it -- then the two things that interrupt that loop.
-- `arrow` rows draw the mission marker instead of an icon; `n` makes a huddle
-- (Icons.cluster), so "folk og last" is a GROUP going one place, not one person.
local ROWS = {
    { icon = "passenger1", n = 3,
      text = "Legg til kai i en havn der havnesjefen gir deg folk og last" },
    { arrow = true,
      text = "Den gule pilen viser vei til byen du skal til" },
    { icon = "coin",
      text = "Lever lasten så kan du få gull" },
    { icon = "bread",
      text = "Kjøp blant annet mat og kanon i butikken i havna" },
    { icon = "chest",
      text = "Av og til får du et skattekart. Da peker pilen mot kisten" },
    { icon = "cannon",
      text = "Møter du en sjørøver? Trykk på ham så skyter du!" },
}

local TITLE = "Sånn spiller du"

-- Design px, scaled by k. Named because tests/info.lua reads them.
Info.ROW_H  = 74
Info.PAD    = 16
Info.BACK_W = 130
Info.BACK_H = 52

-- Pure geometry: screen size + the measured heading height in, every rect out.
-- No LÖVE calls, so a test can check the whole page fits on a phone.
-- `n` is the row count. The rows take whatever is left between the heading and
-- the bottom margin, and rowH shrinks to fill it -- never the other way round,
-- which is how a row ends up under the bottom edge.
function Info.layout(sw, sh, k, n, titleH)
    local pad  = Info.PAD * k
    local back = { x = 20 * k, y = 20 * k, w = Info.BACK_W * k, h = Info.BACK_H * k }

    local titleY = back.y
    -- Below BOTH the heading and the Tilbake key: on a narrow window the key is
    -- as tall as the heading, and the panel must clear whichever wins.
    local top    = math.max(titleY + titleH, back.y + back.h) + pad

    local bottom = sh - pad
    local avail  = math.max(0, bottom - top)

    local plaqueT = math.max(3, math.floor(sh / 190))
    local inset   = plaqueT * 2                          -- what Retro.plaque eats
    local rowH    = math.min(Info.ROW_H * k, math.max(1, (avail - inset * 2) / n))
    local ph      = rowH * n + inset * 2
    local pw      = math.min(sw * 0.92, 980 * k)
    local px      = math.floor((sw - pw) / 2)
    local py      = math.floor(top + math.max(0, (avail - ph) / 2))

    local rows = {}
    for i = 1, n do
        rows[i] = { x = px + inset, y = py + inset + (i - 1) * rowH, w = pw - inset * 2, h = rowH }
    end
    return {
        k = k, pad = pad, back = back, rows = rows, rowH = rowH, plaqueT = plaqueT,
        panel = { x = px, y = py, w = pw, h = ph },
        titleY = titleY, bottom = bottom,
        -- The symbol's own column. Draw and layout share the one number, so the
        -- pictures can never creep under the sentences.
        iconW = rowH * 0.95,
    }
end

function Info:load(game)
    self.game = game
    self.t = 0
    -- Optional: a spoken "Sånn spiller du" for the player who can't read the
    -- page. Missing file = silence, like every other named clip. ASCII name, å
    -- to a, the way sjorover_rommer.ogg spells ø.
    Assets.playNamedVoice("sann_spiller_du")
end

function Info:update(dt) self.t = self.t + dt end

-- The heading is measured here and passed in, so Info.layout stays pure.
function Info:layoutNow()
    local sw, sh = love.graphics.getDimensions()
    return Info.layout(sw, sh, Scale.ui(1), #ROWS, self.game.fonts.big:getHeight()), sw, sh
end

-- Centred line with the game's soft drop shadow.
local function centred(font, text, cx, y, col, shadow)
    love.graphics.setFont(font)
    local w = font:getWidth(text)
    love.graphics.setColor(0.13, 0.11, 0.09, 0.5)
    love.graphics.print(text, cx - w / 2 + shadow, y + shadow)
    love.graphics.setColor(col)
    love.graphics.print(text, cx - w / 2, y)
end

-- The mission arrow's polygon spans tip (36) to tail (-30) in design px.
local ARROW_W = 66

-- One row: the symbol in its own column, then the sentence, then a hairline rule
-- under everything but the last -- the shelf's grammar (a thin rule, no headers).
--
-- Every symbol is sized to the SAME column width. That is fussier than it looks:
-- Icons.draw paints art at 1.5x the size it is handed, and a huddle is wider
-- again by Icons.clusterWidth, so a single "s" for all three would put the
-- passengers half under the text while the coin floated in space.
function Info:drawRow(row, r, i, last, iconW)
    local cx    = r.x + iconW / 2
    local cy    = r.y + r.h / 2
    local avail = iconW * 0.84                   -- breathing room inside the column
    local PAINT = 1.5                            -- Icons.draw's art overscale

    if row.arrow then
        -- the real mission marker (Pointer.MISSION), pointing right the way it
        -- does at sea, with the same gentle bob so it reads as the thing that moves
        local wob = math.sin(self.t * 2.2 + i) * r.h * 0.04
        Pointer.draw(Pointer.MISSION, cx - 1, cy + wob, cx, cy + wob, 0, 0, 0, avail / ARROW_W)
    elseif row.icon == "coin" then
        Icons.coin(cx, cy, avail * 0.42)             -- coins have their own drawer
    elseif row.n then
        -- solve clusterWidth(n, s) + the art overhang = avail
        local s = avail / (Icons.clusterWidth(row.n, 1) + (PAINT - 1))
        Icons.cluster({ "passenger1", "passenger2", "passenger3", "passenger4" },
            row.n, cx, cy, s)
    else
        Icons.draw(row.icon, cx, cy, avail / PAINT)
    end

    local f = self.game.fonts.normal
    local tx = r.x + iconW + r.h * 0.10
    local tw = r.x + r.w - tx
    love.graphics.setFont(f)
    -- Same trick as the treasure caption: shrink rather than clip. A sentence
    -- that runs off the plank is unreadable exactly where the screen is smallest.
    local sc = Announce.fit(1, f:getWidth(row.text), tw)
    love.graphics.setColor(0, 0, 0, 0.35)
    love.graphics.print(row.text, tx + 1, cy - f:getHeight() * sc / 2 + 2, 0, sc, sc)
    love.graphics.setColor(W.text)
    love.graphics.print(row.text, tx, cy - f:getHeight() * sc / 2, 0, sc, sc)

    if not last then
        love.graphics.setColor(W.lo[1], W.lo[2], W.lo[3], 0.55)
        love.graphics.rectangle("fill", r.x + r.w * 0.03, r.y + r.h - 1, r.w * 0.94,
            math.max(1, r.h * 0.02))
    end
end

function Info:draw()
    local L, sw, sh = self:layoutNow()
    local fonts = self.game.fonts

    love.graphics.clear(config.colors.water_deep)
    Scene.drawBackdrop(self, sw, sh, BACKDROP, self.t)

    local shadow = math.max(2, 3 * L.k)
    centred(fonts.big, TITLE, sw / 2, L.titleY, W.text, shadow)

    local P = L.panel
    Retro.plaque(P.x, P.y, P.w, P.h, L.plaqueT)
    for i, r in ipairs(L.rows) do
        self:drawRow(ROWS[i], r, i, i == #L.rows, L.iconW)
    end

    -- Tilbake, in the corner the boat and map choosers put it
    Retro.button("info.back", L.back, "Tilbake", fonts.small)
    love.graphics.setColor(1, 1, 1)
end

function Info:back()
    Assets.playSfx("leave", 0.20)
    -- The title screen replays the whole welcome on load; coming BACK from a
    -- page the player opened himself is not an arrival, so it stays quiet.
    self.game.menuQuiet = true
    self.game:setScene("menu")
end

function Info:mousepressed(x, y, button)
    if button ~= 1 then return end
    local L = self:layoutNow()
    Retro.press("info.back", L.back, x, y)
end

function Info:mousereleased(x, y, button)
    if button ~= 1 then return end
    local L = self:layoutNow()
    if Retro.released("info.back", x, y) then self:back() end
end

function Info:keypressed(key)
    if key == "return" or key == "space" or key == "kpenter" then self:back() end
end

-- ESC belongs to this page, not to love.event.quit -- see Game:keypressed.
function Info:onEscape() self:back() end

return Info
