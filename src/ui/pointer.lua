-- Screen-space "go that way" marker: an arrow that swings to the bearing, an
-- optional upright badge, and a pulsing ring on the target.

local Icons = require("src.ui.icons")

local Pointer = {}

-- The mission arrow's shape and colours. It lives HERE, not in world.lua, so the
-- help screen can show the child the exact arrow he follows at sea: a second
-- hand-drawn arrow on the page that drifted from this one would teach the wrong
-- symbol. Read, never written -- file scope, not per frame.
-- (Why the arrow carries no badge is in World:drawMissionPointer.)
Pointer.MISSION = {
    shape = {
         36,   0,   -- tip
         15, -20,   -- head top corner
         15,  -9,   -- step in to shaft
        -30, -14,   -- tail top
        -18,   0,   -- the swallowtail notch
        -30,  14,   -- tail bottom
         15,   9,   -- step out
         15,  20,   -- head bottom corner
    },
    fill  = { 0.99, 0.83, 0.22 },   -- bright gold
    line  = { 0.10, 0.08, 0.05 },   -- dark outline
    orbit = 0,                      -- the arrow IS the marker; nothing to orbit
    reach = 22,                     -- arrow half-height: what a caption clears
    ringThick = 4, ringShadow = 7, ringShadowA = 0.5, ringAlpha = 0.95,
}

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
--   badge, badgeSize   optional icon, drawn upright and CENTRED on the anchor
--   reach              how far the marker extends ABOVE the anchor, design px:
--                      what a caption hung over it has to clear. For a badged
--                      marker that is the badge's radius -- remembering that
--                      Icons.draw paints ART at 1.5x the size it is handed, so a
--                      reach taken from badgeSize alone puts the caption inside
--                      the badge. For a bare arrow it is the arrow's half-height.
--   ring*              see Pointer.ring
-- `scale` multiplies the design-px geometry; the caller picks Scale.overlay or
-- Scale.marker. Motion (hop/wobble) arrives already integrated -- pass phases,
-- never rates, or a changing rate jumps.
-- Returns the anchor, so a caller can hang a caption off the marker without
-- recomputing the layout.
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
    return ax, ay
end

-- Pins something to the screen edge in the direction of an off-screen target:
-- returns the clamped position, the bearing from screen centre, and whether the
-- target was off screen at all. Shared by the pirate indicator and the treasure
-- hint, which are the same idea pointed at opposite feelings.
function Pointer.edge(tx, ty, sw, sh, margin)
    local off = (tx < 0 or tx > sw or ty < 0 or ty > sh)
    local ang = math.atan2(ty - sh / 2, tx - sw / 2)
    return math.max(margin, math.min(sw - margin, tx)),
           math.max(margin, math.min(sh - margin, ty)), ang, off
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
