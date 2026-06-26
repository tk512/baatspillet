-- src/ui/retro.lua
-- Shared chunky-bevel drawing for the title, HUD and dock screens.

local Retro = {}

-- Warm-wood palette, shared with portscreen's cosy theme.
Retro.WOOD = {
    face   = {0.40, 0.29, 0.19},
    hi     = {0.62, 0.46, 0.30},
    lo     = {0.20, 0.14, 0.09},
    accent = {0.95, 0.80, 0.36},
    text   = {0.96, 0.91, 0.76},
    deep   = {0.28, 0.18, 0.11},   -- recessed wood
}

-- Filled rect with a 3D edge: light top/left + dark bottom/right when raised,
-- swapped for a sunken groove. `t` is edge thickness; raised defaults true.
function Retro.bevel(x, y, w, h, face, hi, lo, t, raised)
    if raised == nil then raised = true end
    love.graphics.setColor(face)
    love.graphics.rectangle("fill", x, y, w, h)
    local a, b = hi, lo
    if not raised then a, b = lo, hi end
    love.graphics.setColor(a)
    love.graphics.rectangle("fill", x, y, w, t)
    love.graphics.rectangle("fill", x, y, t, h)
    love.graphics.setColor(b)
    love.graphics.rectangle("fill", x, y + h - t, w, t)
    love.graphics.rectangle("fill", x + w - t, y, t, h)
end

-- Wooden plaque (raised outer bevel + sunken inner well). Returns the inner
-- content rect (x, y, w, h). Shared by the HUD plaques and the minimap frame.
function Retro.plaque(x, y, w, h, t)
    local W = Retro.WOOD
    Retro.bevel(x, y, w, h, W.face, W.hi, W.lo, t, true)
    Retro.bevel(x + t, y + t, w - 2 * t, h - 2 * t, W.deep, W.hi, W.lo,
        math.max(1, math.floor(t * 0.6)), false)
    return x + t * 2, y + t * 2, w - t * 4, h - t * 4
end

return Retro
