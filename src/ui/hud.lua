-- src/ui/hud.lua
-- Heads-up display drawn in screen space: coins, boat + cargo, the active
-- mission, and short-lived toast messages. Laid out from measured text widths
-- so labels never collide whatever the font size or town-name length.

local config = require("src.config")
local Retro  = require("src.ui.retro")

local HUD = {}
local WOOD = Retro.WOOD

-- Wooden plaque (raised outer bevel + sunken inner well). Returns the inner
-- content rect (x, y, w, h).
local function plaque(x, y, w, h, t)
    Retro.bevel(x, y, w, h, WOOD.face, WOOD.hi, WOOD.lo, t, true)
    Retro.bevel(x + t, y + t, w - 2 * t, h - 2 * t, WOOD.deep, WOOD.hi, WOOD.lo,
        math.max(1, math.floor(t * 0.6)), false)
    return x + t * 2, y + t * 2, w - t * 4, h - t * 4
end

local function coin(x, y, r)
    local c = config.colors
    love.graphics.setColor(0.62, 0.46, 0.08)
    love.graphics.circle("fill", x, y, r + 1)
    love.graphics.setColor(c.gold)
    love.graphics.circle("fill", x, y, r)
    love.graphics.setColor(1, 1, 1, 0.55)
    love.graphics.circle("fill", x - r * 0.3, y - r * 0.3, r * 0.28)
end

-- A small icon (passenger / fish / generic) centred at (x,y), size s.
local function missionIcon(kind, x, y, s)
    if kind == "passenger" then
        love.graphics.setColor(0.95, 0.80, 0.55)
        love.graphics.rectangle("fill", x - s * 0.22, y - s * 0.5, s * 0.44, s * 0.4)
        love.graphics.setColor(0.30, 0.45, 0.70)
        love.graphics.rectangle("fill", x - s * 0.38, y - s * 0.08, s * 0.76, s * 0.5)
    elseif kind == "fish" then
        love.graphics.setColor(0.55, 0.68, 0.82)
        love.graphics.rectangle("fill", x - s * 0.42, y - s * 0.2, s * 0.66, s * 0.4)
        love.graphics.polygon("fill", x + s * 0.24, y, x + s * 0.46, y - s * 0.26, x + s * 0.46, y + s * 0.26)
        love.graphics.setColor(0.12, 0.14, 0.18)
        love.graphics.rectangle("fill", x - s * 0.28, y - s * 0.06, s * 0.1, s * 0.1)
    else
        love.graphics.setColor(0.60, 0.45, 0.28)
        love.graphics.rectangle("fill", x - s * 0.36, y - s * 0.36, s * 0.72, s * 0.72)
    end
end

-- world exposes: game (coins + fonts), boat, cargoSystem, nearPort, toast.
function HUD.draw(world)
    local c     = config.colors
    local fonts = world.game.fonts
    local sw    = love.graphics.getWidth()
    local sh    = love.graphics.getHeight()
    local smH   = fonts.small:getHeight()
    local nmH   = fonts.normal:getHeight()
    local t     = math.max(2, math.floor(smH * 0.20))   -- bevel thickness (scaled)

    -- Top-left: gold + boat + cargo plaque
    local pad  = math.max(6, math.floor(smH * 0.55))
    local gap  = math.floor(smH * 0.32)
    local cr   = nmH * 0.42                               -- coin radius
    local goldStr  = tostring(world.game.state.coins) .. " gull"
    local boatStr  = "Båt: " .. world.boat.def.name
    local cargoStr = "Last: " .. world.boat:cargoCount() .. " / " .. world.boat.capacity

    local row1W = cr * 2 + gap + fonts.normal:getWidth(goldStr)
    local contentW = math.max(row1W, fonts.small:getWidth(boatStr), fonts.small:getWidth(cargoStr))
    local pw = contentW + (pad + t * 2) * 2
    local ph = (pad + t * 2) * 2 + nmH + gap + smH + gap + smH
    local ix, iy = plaque(16, 16, pw, ph, t)

    -- row 1: coin + gold count
    coin(ix + pad + cr, iy + pad + nmH * 0.5, cr)
    love.graphics.setFont(fonts.normal)
    love.graphics.setColor(c.gold)
    love.graphics.print(goldStr, ix + pad + cr * 2 + gap, iy + pad)
    -- rows 2 & 3: boat + cargo
    love.graphics.setFont(fonts.small)
    love.graphics.setColor(WOOD.text)
    local ry = iy + pad + nmH + gap
    love.graphics.print(boatStr, ix + pad, ry)
    love.graphics.print(cargoStr, ix + pad, ry + smH + gap)

    -- Top-centre: current mission banner
    if world.boat.cargo[1] then
        HUD.drawMission(world, sw, c, fonts, smH, nmH, t)
    end

    -- Bottom-left: controls hint
    love.graphics.setFont(fonts.small)
    local hint = "Klikk = seil dit   •   Mus mot kanten = flytt kart   •   C = midtstill   •   ESC = meny"
    love.graphics.setColor(0, 0, 0, 0.45)
    love.graphics.print(hint, 17, sh - 25)
    love.graphics.setColor(c.text[1], c.text[2], c.text[3], 0.85)
    love.graphics.print(hint, 16, sh - 26)

    if world.toast and world.toast.timer > 0 then
        HUD.drawToast(world, sw, sh, c, fonts)
    end

    love.graphics.setColor(1, 1, 1)
end

-- Top-centre banner: "Oppdrag <icon>×N → ▮ <BY>", destination in its town colour.
function HUD.drawMission(world, sw, c, fonts, smH, nmH, t)
    local m = world.boat.cargo[1]
    local pad  = math.max(8, math.floor(smH * 0.7))
    local gap  = math.floor(nmH * 0.55)
    local s    = nmH * 0.9                                 -- icon size
    local flag = nmH * 0.8                                 -- flag swatch
    local dest = m.toName
    local countStr = "×" .. m.count

    local wLabel = fonts.normal:getWidth("Oppdrag")
    local wCount = fonts.normal:getWidth(countStr)
    local wArrow = fonts.normal:getWidth("→")
    local wDest  = fonts.normal:getWidth(dest)
    local content = wLabel + gap + s + gap * 0.4 + wCount + gap + wArrow + gap
                    + flag + gap * 0.5 + wDest

    local ph = nmH + (pad + t * 2)
    local pw = content + (pad + t * 2) * 2
    local px = math.floor(sw / 2 - pw / 2)
    local ix, iy, _, ih = plaque(px, 14, pw, ph, t)
    local cy = iy + ih / 2                                  -- vertical mid-line
    local function ty(fontH) return cy - fontH / 2 end

    local cx = ix + pad
    love.graphics.setFont(fonts.normal)

    -- label
    love.graphics.setColor(WOOD.accent)
    love.graphics.print("Oppdrag", cx, ty(nmH)); cx = cx + wLabel + gap

    -- icon ×N
    missionIcon(m.icon, cx + s / 2, cy, s); cx = cx + s + gap * 0.4
    love.graphics.setColor(WOOD.text)
    love.graphics.print(countStr, cx, ty(nmH)); cx = cx + wCount + gap

    -- arrow
    love.graphics.print("→", cx, ty(nmH)); cx = cx + wArrow + gap

    -- destination flag + name in town colour
    love.graphics.setColor(m.color or WOOD.text)
    love.graphics.rectangle("fill", cx, cy - flag / 2, flag, flag); cx = cx + flag + gap * 0.5
    love.graphics.print(dest, cx, ty(nmH))

    love.graphics.setColor(1, 1, 1)
end

function HUD.drawToast(world, sw, sh, c, fonts)
    local t = world.toast
    local alpha = math.min(1, t.timer)  -- fade out in the last second
    love.graphics.setFont(fonts.big)
    local w = fonts.big:getWidth(t.text)
    local x = sw / 2 - w / 2
    local y = sh * 0.30 - t.rise  -- floats upward as it fades

    love.graphics.setColor(0, 0, 0, 0.4 * alpha)
    love.graphics.print(t.text, x + 2, y + 2)
    love.graphics.setColor(c.gold[1], c.gold[2], c.gold[3], alpha)
    love.graphics.print(t.text, x, y)
end

return HUD
