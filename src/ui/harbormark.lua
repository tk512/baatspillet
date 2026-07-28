-- A town badge: two gabled Bryggen-style houses, tinted to the town's accent
-- colour, so a harbour reads as a place instead of a coloured square. Fills the
-- box (x, y, w, h). Placeholder-first -- assets/ui/harbormark.png replaces it.

local Assets = require("src.assets")

local HarborMark = {}

local OUTLINE = { 0.12, 0.10, 0.08, 0.85 }

-- f < 1 darkens toward black, f > 1 lightens toward white
local function shade(c, f)
    if f <= 1 then return c[1] * f, c[2] * f, c[3] * f end
    local k = f - 1
    return c[1] + (1 - c[1]) * k, c[2] + (1 - c[2]) * k, c[3] + (1 - c[3]) * k
end

-- one gabled house filling (bx, by, bw, bh), windows only when there's room
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
    local img = Assets.image("ui/harbormark.png")
    if img then                                     -- contained + centred
        local s = math.min(w / img:getWidth(), h / img:getHeight())
        local dw, dh = img:getWidth() * s, img:getHeight() * s
        love.graphics.setColor(1, 1, 1)
        love.graphics.draw(img, x + (w - dw) / 2, y + (h - dh) / 2, 0, s, s)
        return
    end

    color = color or { 0.8, 0.6, 0.4 }
    local gap = w * 0.08
    local bw  = (w - gap) / 2
    local lift = h * 0.10               -- left house shorter, for a gabled skyline

    local rr, rg, rb = shade(color, 0.5)            -- dark roof in the town's hue
    local pr, pg, pb = shade(color, 1.55)           -- pale body for the right house
    house(x, y + lift, bw, h - lift, color[1], color[2], color[3], rr, rg, rb)
    house(x + bw + gap, y, bw, h, pr, pg, pb, rr, rg, rb)

    love.graphics.setColor(1, 1, 1)
end

return HarborMark
