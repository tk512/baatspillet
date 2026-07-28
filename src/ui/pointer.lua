-- Screen-space "go that way" marker: an arrow that swings to the bearing, an
-- optional upright badge, and a pulsing ring on the target.

local Icons = require("src.ui.icons")

local Pointer = {}

-- Returns anchor ax,ay (where the badge sits), bearing ang, and the arrow
-- centre qx,qy (anchor pushed out along the bearing by `orbit`).
-- Pure and allocation-free -- runs per frame per live pointer.
function Pointer.layout(bx, by, tx, ty, lift, hop, wobble, orbit)
    local ang = math.atan2(ty - by, tx - bx)
    local ca, sa = math.cos(ang), math.sin(ang)
    local ax = bx + ca * hop            -- hops toward the target, so the motion points too
    local ay = by - lift + wobble + sa * hop
    return ax, ay, ang, ax + ca * orbit, ay + sa * orbit
end

-- `style` is persistent, built once at file scope:
--   shape, fill, line  arrow polygon (points +x, design px) and its colours
--   orbit              arrow distance from the anchor (0 = on it)
--   badge, badgeSize   optional icon, drawn upright at the anchor
--   ring*              see Pointer.ring
-- `scale` multiplies the design-px geometry; the caller picks Scale.overlay or
-- Scale.marker. Motion (hop/wobble) arrives already integrated -- pass phases,
-- never rates, or a changing rate jumps.
function Pointer.draw(style, bx, by, tx, ty, lift, hop, wobble, scale)
    local ax, ay, ang, qx, qy =
        Pointer.layout(bx, by, tx, ty, lift, hop, wobble, (style.orbit or 0) * scale)

    local shape = style.shape           -- the arrow is all that rotates
    love.graphics.push()
    love.graphics.translate(qx, qy)
    love.graphics.rotate(ang)
    love.graphics.scale(scale, scale)
    love.graphics.setColor(0, 0, 0, 0.28)
    love.graphics.push(); love.graphics.translate(2, 3)
    love.graphics.polygon("fill", shape); love.graphics.pop()
    love.graphics.setColor(style.fill)
    love.graphics.polygon("fill", shape)
    love.graphics.setColor(style.line)
    love.graphics.setLineWidth(4); love.graphics.polygon("line", shape)
    love.graphics.setLineWidth(1)
    love.graphics.pop()

    -- outside the transform on purpose: a rotated chest stops reading as a chest
    if style.badge then
        Icons.draw(style.badge, ax, ay, style.badgeSize * scale)
    end
    love.graphics.setColor(1, 1, 1)
end

-- Drawn on the target (callers check it's on screen). Colour is an argument,
-- not a style field: the mission ring takes the destination town's colour.
function Pointer.ring(style, tx, ty, r, col)
    love.graphics.setColor(0, 0, 0, style.ringShadowA or 0.45)
    love.graphics.setLineWidth(style.ringShadow or 6)
    love.graphics.circle("line", tx, ty, r)
    love.graphics.setColor(col[1], col[2], col[3], style.ringAlpha or 1)
    love.graphics.setLineWidth(style.ringThick or 3)
    love.graphics.circle("line", tx, ty, r)
    love.graphics.setLineWidth(1)
    love.graphics.setColor(1, 1, 1)
end

return Pointer
