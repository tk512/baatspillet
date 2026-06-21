-- src/ui/hud.lua
-- Heads-up display drawn in screen space: coins, boat + cargo, the active
-- mission, and short-lived toast messages. Laid out from measured text widths
-- so labels never collide whatever the font size or town-name length.

local config = require("src.config")
local Retro  = require("src.ui.retro")
local Icons  = require("src.ui.icons")

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

    -- Bought goods (the "inventory") shown under the boat/cargo rows as a row of
    -- symbols only -- no text -- so a non-reader recognises them at a glance (and
    -- so Finn-Erik's drawings can replace them later via assets/icons/<icon>.png).
    local owned = {}
    for _, it in ipairs(world.game.data.shop) do
        if it.food then
            local n = world.game:foodCount(it.id)
            if n > 0 then owned[#owned + 1] = { it = it, count = n } end
        elseif world.game:owns(it.id) then
            owned[#owned + 1] = { it = it }
        end
    end
    local invIcon = nmH * 0.9                             -- inventory icon size
    local invGap  = math.floor(invIcon * 0.35)
    local invPer  = 5                                     -- icons per row before wrapping
    local invRows = (#owned > 0) and math.ceil(#owned / invPer) or 0
    local invCols = math.min(#owned, invPer)
    local invW = (#owned > 0) and (invCols * invIcon + (invCols - 1) * invGap) or 0
    if #owned > 0 then invW = math.max(invW, fonts.small:getWidth("Kjøpt:")) end

    local row1W = cr * 2 + gap + fonts.normal:getWidth(goldStr)
    local contentW = math.max(row1W, fonts.small:getWidth(boatStr), fonts.small:getWidth(cargoStr), invW)
    local pw = contentW + (pad + t * 2) * 2
    local ph = (pad + t * 2) * 2 + nmH + gap + smH + gap + smH
    if #owned > 0 then ph = ph + gap + smH + gap + invRows * (invIcon + invGap) end
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

    -- inventory: "Kjøpt:" header then a wrapped row of symbols only
    if #owned > 0 then
        local oy = ry + (smH + gap) * 2
        love.graphics.setFont(fonts.small)
        love.graphics.setColor(WOOD.accent)
        love.graphics.print("Kjøpt:", ix + pad, oy)
        local startY = oy + smH + gap
        for k, e in ipairs(owned) do
            local col, row = (k - 1) % invPer, math.floor((k - 1) / invPer)
            local cxk = ix + pad + col * (invIcon + invGap) + invIcon * 0.5
            local cyk = startY + row * (invIcon + invGap) + invIcon * 0.5
            Icons.draw(e.it.icon, cxk, cyk, invIcon)
            if e.count and e.count > 1 then        -- food stock: "xN" badge
                love.graphics.setFont(fonts.small)
                local lbl = "x" .. e.count
                love.graphics.setColor(0, 0, 0, 0.55)
                love.graphics.print(lbl, cxk + invIcon * 0.5 - fonts.small:getWidth(lbl) + 1, cyk + invIcon * 0.3 + 1)
                love.graphics.setColor(WOOD.text)
                love.graphics.print(lbl, cxk + invIcon * 0.5 - fonts.small:getWidth(lbl), cyk + invIcon * 0.3)
            end
        end
    end

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
    Icons.draw(m.icon, cx + s / 2, cy, s); cx = cx + s + gap * 0.4
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
