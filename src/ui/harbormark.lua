-- src/ui/harbormark.lua
-- A little "harbour" badge: two tall gabled Bryggen-style houses side by side,
-- tinted to a town's accent colour. It replaces the plain colour square that
-- used to stand in for a town (HUD mission banner, dock-screen title + offer),
-- so each harbour reads as a place -- not just a coloured block -- while keeping
-- the town's colour as the recognisable cue for a non-reader.
--
-- Inspired by Bergen's Bryggen wharf: narrow wooden houses with steep pointed
-- gables, one in the town colour and one pale (like the red + cream pair there).
-- Drawn to fill the box (x, y, w, h); pure code art, crisp at any size.
--
-- Placeholder-first: if assets/ui/harbormark.png exists (a pixelised Bryggen
-- photo) it's used as the emblem instead -- the town colour still shows in the
-- name text beside it. Drop the PNG in and it swaps with zero code changes.

local Assets = require("src.assets")

local HarborMark = {}

local OUTLINE = { 0.12, 0.10, 0.08, 0.85 }

-- Shade a colour: f < 1 darkens toward black, f > 1 lightens toward white.
local function shade(c, f)
    if f <= 1 then return c[1] * f, c[2] * f, c[3] * f end
    local k = f - 1
    return c[1] + (1 - c[1]) * k, c[2] + (1 - c[2]) * k, c[3] + (1 - c[3]) * k
end

-- One gabled house filling (bx, by, bw, bh): triangular roof + body, optional
-- window dots when there's room, and a dark outline so it pops on any panel.
local function house(bx, by, bw, bh, br, bg, bb, rr, rg, rb)
    local roofH = bh * 0.44
    local bodyY = by + roofH
    local bodyH = bh - roofH
    local peakX = bx + bw / 2

    love.graphics.setColor(rr, rg, rb)                                  -- roof
    love.graphics.polygon("fill", peakX, by, bx, bodyY, bx + bw, bodyY)
    love.graphics.setColor(br, bg, bb)                                  -- body
    love.graphics.rectangle("fill", bx, bodyY, bw, bodyH)

    if bw >= 12 then                                                    -- windows
        local ww, wh = bw * 0.22, bodyH * 0.18
        love.graphics.setColor(OUTLINE[1], OUTLINE[2], OUTLINE[3], 0.5)
        love.graphics.rectangle("fill", bx + bw * 0.22, bodyY + bodyH * 0.24, ww, wh)
        love.graphics.rectangle("fill", bx + bw * 0.56, bodyY + bodyH * 0.24, ww, wh)
        love.graphics.rectangle("fill", bx + bw * 0.22, bodyY + bodyH * 0.56, ww, wh)
        love.graphics.rectangle("fill", bx + bw * 0.56, bodyY + bodyH * 0.56, ww, wh)
    end

    love.graphics.setColor(OUTLINE)
    love.graphics.setLineWidth(math.max(1, bw * 0.09))
    love.graphics.polygon("line", peakX, by, bx, bodyY, bx + bw, bodyY)
    love.graphics.rectangle("line", bx, bodyY, bw, bodyH)
    love.graphics.setLineWidth(1)
end

function HarborMark.draw(x, y, w, h, color)
    -- Pixelised photo emblem, if present: contained (aspect-preserved) + centred.
    local img = Assets.image("ui/harbormark.png")
    if img then
        local s = math.min(w / img:getWidth(), h / img:getHeight())
        local dw, dh = img:getWidth() * s, img:getHeight() * s
        love.graphics.setColor(1, 1, 1)
        love.graphics.draw(img, x + (w - dw) / 2, y + (h - dh) / 2, 0, s, s)
        return
    end

    color = color or { 0.8, 0.6, 0.4 }
    local gap = w * 0.08
    local bw  = (w - gap) / 2
    local lift = h * 0.10               -- left house a touch shorter (gabled skyline)

    local rr, rg, rb = shade(color, 0.5)            -- dark roof in the town's hue
    local pr, pg, pb = shade(color, 1.55)           -- pale "cream" body for the right house
    house(x, y + lift, bw, h - lift, color[1], color[2], color[3], rr, rg, rb)  -- left: town colour
    house(x + bw + gap, y, bw, h, pr, pg, pb, rr, rg, rb)                       -- right: cream

    love.graphics.setColor(1, 1, 1)
end

return HarborMark
