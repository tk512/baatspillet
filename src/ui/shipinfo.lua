-- src/ui/shipinfo.lua
-- A little MarineTraffic-style popup card for a tapped ambient ship: a photo
-- thumbnail, the ship's name, type, country (with a small drawn flag) and speed.
-- Anchored above the ship on screen, clamped to stay on-screen.

local Assets = require("src.assets")
local Retro  = require("src.ui.retro")

local ShipInfo = {}

-- Flags come from the shared module (image-first, painted fallback).
local Flags = require("src.ui.flags")
local function flag(country, x, y, w, h) Flags.draw(country, x, y, w, h) end

-- ship: { x,y, scale, moving, speed, look = { photo=..., def = {name,country,type} } }
-- sx, sy: the ship's position on screen (the card points down at it).
function ShipInfo.draw(ship, sx, sy, fonts)
    local def = ship.look and ship.look.def or {}
    local name = def.name or "Skip"
    local typ  = def.type or ""
    local country = def.country or ""
    local speedText = (ship.moving and ship.speed > 1 and not ship.waitT)
        and (math.floor(ship.speed * 0.5 + 0.5) .. " knop") or "Ligger stille"

    local sw, sh = love.graphics.getWidth(), love.graphics.getHeight()
    local k = sh / 800
    local pad, gap = 14 * k, 6 * k
    local nameF, rowF = fonts.normal, fonts.small
    local nh, rh = nameF:getHeight(), rowF:getHeight()
    local flagW = rh * 1.5

    -- Measure content, then size the card to it so nothing ever overflows.
    local rows = { { typ } }
    if country ~= "" then rows[#rows + 1] = { country, flagW + 6 * k } end
    rows[#rows + 1] = { speedText }
    local textW = nameF:getWidth(name)
    for _, r in ipairs(rows) do
        textW = math.max(textW, (r[2] or 0) + rowF:getWidth(r[1]))
    end
    local contentH = nh + #rows * (rh + gap)
    local thumb = ship.look and ship.look.img and Assets.image(ship.look.img)
    local tw = thumb and contentH * 1.5 or 0

    local t = math.max(4, math.floor(6 * k))
    local W = tw + (thumb and pad or 0) + textW + 2 * pad + 4 * t
    local H = contentH + 2 * pad + 4 * t
    local x = math.max(8, math.min(sw - W - 8, sx - W / 2))
    local y = math.max(8, math.min(sh - H - 8, sy - H - 22 * k))

    -- little pointer down toward the ship
    love.graphics.setColor(0.20, 0.14, 0.08)
    love.graphics.polygon("fill", x + W / 2 - 11 * k, y + H - 2, x + W / 2 + 11 * k, y + H - 2,
        x + W / 2, y + H + 16 * k)

    local ix, iy, iw, ih = Retro.plaque(x, y, W, H, t)

    local textX = ix + pad
    if thumb then
        local ts = tw / thumb:getWidth()
        love.graphics.setColor(1, 1, 1)
        love.graphics.draw(thumb, ix + pad, iy + ih / 2, 0, ts, ts, 0, thumb:getHeight() / 2)
        textX = ix + pad + tw + pad
    end

    local cy = iy + pad
    love.graphics.setFont(nameF)
    love.graphics.setColor(0.98, 0.96, 0.88)
    love.graphics.print(name, textX, cy)
    cy = cy + nh + gap

    love.graphics.setFont(rowF)
    love.graphics.setColor(0.86, 0.84, 0.78)
    love.graphics.print(typ, textX, cy)
    cy = cy + rh + gap

    if country ~= "" then
        flag(country, textX, cy + 1, flagW, rh - 2)
        love.graphics.setColor(0.86, 0.84, 0.78)
        love.graphics.print(country, textX + flagW + 6 * k, cy)
        cy = cy + rh + gap
    end

    love.graphics.setColor(0.74, 0.90, 1.0)
    love.graphics.print(speedText, textX, cy)
    love.graphics.setColor(1, 1, 1)
end

return ShipInfo
