-- src/ui/mapreveal.lua
-- The "you got a treasure map!" moment: a big celebratory full-screen card that
-- pops right after a harbourmaster hands you a map, so a young player clearly
-- gets it -- WOHO! -- "Finn skatten!" ("Find the treasure!"). A modal owned by
-- the world scene (freezes the world, like the docking screen); a click or a key
-- dismisses it and the hunt is on.
--
-- Placeholder-first: it draws a hand-drawn parchment map in code; drop a picture
-- at assets/ui/treasuremap.png and that's shown instead, zero code changes. Voice
-- is added later (Finn-Erik's recording); for now a synth jingle plays on open.

local config = require("src.config")
local Assets = require("src.assets")
local Retro  = require("src.ui.retro")

local WOOD = Retro.WOOD

local MapReveal = {}
MapReveal.__index = MapReveal

function MapReveal.new(world, treasure)
    return setmetatable({ world = world, treasure = treasure, t = 0 }, MapReveal)
end

function MapReveal:update(dt) self.t = self.t + dt end

-- A tiny delay before it accepts input, so an in-flight click doesn't skip it.
function MapReveal:mousepressed(_, _, button)
    if button == 1 and self.t > 0.35 then self.world:closeMapReveal() end
end

function MapReveal:keypressed(key)
    if self.t > 0.35 and (key == "return" or key == "space" or key == "escape" or key == "b") then
        self.world:closeMapReveal()
    end
end

-- Hand-drawn parchment: tan sheet, an island blob, a dashed route to a big red
-- pulsing X, and a little compass rose. Stands in until a picture is supplied.
local function drawParchment(x, y, w, h, t)
    love.graphics.setColor(0.87, 0.79, 0.58)                      -- sheet
    love.graphics.rectangle("fill", x, y, w, h, 6, 6)
    love.graphics.setColor(0.73, 0.63, 0.43)                      -- worn inner border
    love.graphics.setLineWidth(3); love.graphics.rectangle("line", x + 5, y + 5, w - 10, h - 10, 4, 4)
    love.graphics.setLineWidth(1)

    local x0, y0 = x + w * 0.30, y + h * 0.40                      -- island
    love.graphics.setColor(0.56, 0.62, 0.40)
    love.graphics.ellipse("fill", x0, y0, w * 0.15, h * 0.17)
    love.graphics.setColor(0.70, 0.62, 0.40)
    love.graphics.ellipse("fill", x0, y0, w * 0.15, h * 0.17, 5)  -- (rough outline)

    local x1, y1 = x + w * 0.70, y + h * 0.66                      -- dashed route to X
    love.graphics.setColor(0.45, 0.30, 0.18)
    love.graphics.setLineWidth(3)
    local steps = 14
    for i = 0, steps - 1, 2 do
        local a, b = i / steps, (i + 1) / steps
        love.graphics.line(x0 + (x1 - x0) * a, y0 + (y1 - y0) * a,
                           x0 + (x1 - x0) * b, y0 + (y1 - y0) * b)
    end
    love.graphics.setLineWidth(1)

    local p = 1 + 0.14 * math.sin(t * 6)                          -- big pulsing red X
    local r = w * 0.05 * p
    love.graphics.setColor(0.82, 0.18, 0.14)
    love.graphics.setLineWidth(6)
    love.graphics.line(x1 - r, y1 - r, x1 + r, y1 + r)
    love.graphics.line(x1 - r, y1 + r, x1 + r, y1 - r)
    love.graphics.setLineWidth(1)

    local cxx, cyy, cr = x + w * 0.85, y + h * 0.20, w * 0.055     -- compass rose
    love.graphics.setColor(0.42, 0.31, 0.20)
    love.graphics.circle("line", cxx, cyy, cr)
    love.graphics.polygon("fill", cxx, cyy - cr, cxx - cr * 0.32, cyy, cxx + cr * 0.32, cyy)
end

function MapReveal:draw()
    local sw, sh = love.graphics.getDimensions()
    local fonts  = self.world.game.fonts
    local t      = self.t

    love.graphics.setColor(0, 0, 0, 0.6)                          -- dim the frozen world
    love.graphics.rectangle("fill", 0, 0, sw, sh)

    local bt = math.max(3, math.floor(fonts.small:getHeight() * 0.22))
    local pw = math.min(sw * 0.74, 720)
    local ph = math.min(sh * 0.78, 540)
    local px, py = (sw - pw) / 2, (sh - ph) / 2
    local ix, iy, iw, ih = Retro.plaque(px, py, pw, ph, bt)

    local titleH, subH, hintH = fonts.title:getHeight(), fonts.big:getHeight(), fonts.small:getHeight()

    -- bouncing title
    local hop = math.abs(math.sin(t * 4)) * 8
    love.graphics.setFont(fonts.title)
    local title = "Skattekart!"
    local tw = fonts.title:getWidth(title)
    love.graphics.setColor(0, 0, 0, 0.4); love.graphics.print(title, ix + (iw - tw) / 2 + 2, iy + 8 - hop + 2)
    love.graphics.setColor(WOOD.accent);  love.graphics.print(title, ix + (iw - tw) / 2, iy + 8 - hop)

    -- the map (PNG if present, else the drawn parchment), centred in the middle band
    local mapTop = iy + 12 + titleH
    local mapH   = (iy + ih) - mapTop - (subH + 10 + hintH + 14)
    local mapW   = math.min(iw * 0.82, mapH * 1.4)
    local mapX   = ix + (iw - mapW) / 2
    local img    = Assets.image("ui/treasuremap.png")
    if img then
        local s = math.min(mapW / img:getWidth(), mapH / img:getHeight())
        love.graphics.setColor(1, 1, 1)
        love.graphics.draw(img, ix + iw / 2, mapTop + mapH / 2, 0, s, s, img:getWidth() / 2, img:getHeight() / 2)
    else
        drawParchment(mapX, mapTop, mapW, mapH, t)
    end

    -- subtitle: the call to action
    love.graphics.setFont(fonts.big)
    local sub = "Finn skatten!"
    local pulse = 0.8 + 0.2 * math.sin(t * 6)
    love.graphics.setColor(config.colors.gold[1], config.colors.gold[2], config.colors.gold[3], pulse)
    love.graphics.print(sub, ix + (iw - fonts.big:getWidth(sub)) / 2, iy + ih - subH - hintH - 16)

    -- tap-to-continue hint (after a short beat)
    if t > 0.6 then
        love.graphics.setFont(fonts.small)
        local hint = "Klikk for å seile"
        love.graphics.setColor(WOOD.text[1], WOOD.text[2], WOOD.text[3], 0.55 + 0.35 * math.sin(t * 3))
        love.graphics.print(hint, ix + (iw - fonts.small:getWidth(hint)) / 2, iy + ih - hintH - 8)
    end

    -- a few sparkles popping around the card for the WOHO factor (deterministic)
    for k = 1, 7 do
        local sp = (t * 1.3 + k * 0.5) % 1
        local rr = 1 - sp
        local sx = px + pw * (0.12 + 0.76 * ((k * 0.37) % 1))
        local sy = py + ph * (0.10 + 0.80 * ((k * 0.53) % 1))
        love.graphics.setColor(1, 0.95, 0.6, rr)
        local s = 3 + 5 * rr
        love.graphics.polygon("fill", sx, sy - s, sx + s * 0.3, sy - s * 0.3,
            sx + s, sy, sx + s * 0.3, sy + s * 0.3, sx, sy + s,
            sx - s * 0.3, sy + s * 0.3, sx - s, sy, sx - s * 0.3, sy - s * 0.3)
    end
    love.graphics.setColor(1, 1, 1)
end

return MapReveal
