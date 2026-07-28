-- src/ui/pointer.lua
-- The one "go THAT way" marker: a screen-space arrow that hovers above the boat
-- and swings to point at a target, plus the pulsing ring drawn on the target
-- itself when it's on screen.
--
-- This existed twice in world.lua as forty near-identical lines each -- the gold
-- mission arrow and the orange treasure arrow -- differing only in colour, arrow
-- shape and where the animation phase came from. They are one thing in two
-- costumes, so the drawing lives here once and the costumes are `style` tables.
--
-- ── THE INVARIANT THIS MODULE EXISTS TO PROTECT ──────────────────────────────
-- A marker has a ROTATING part (the arrow, which must swing to the bearing) and
-- an optional UPRIGHT part (the `badge` -- a treasure chest). A chest is not
-- symmetric about its own axis: rotate it with the arrow and it hangs
-- upside-down every time the boat sails west, and an upside-down chest stops
-- reading as a chest instantly. So the badge is drawn OUTSIDE the rotation, and
-- the API has no way to express a rotated badge. Don't add one.
--
-- ── PHASES, NOT RATES ────────────────────────────────────────────────────────
-- Callers pass already-integrated motion values (hop, wobble, scale). NEVER
-- sin(love.timer.getTime() * rate) when the rate varies with something -- see
-- the note on World:updateHuntPhases for the jumping-and-skipping bug that
-- caused. A constant rate is fine; a changing one is not.

local Icons = require("src.ui.icons")

local Pointer = {}

-- Where the marker's pieces go.
--
-- PURE: no drawing, no state, and no allocation -- multiple returns rather than
-- a table, because this runs every frame for every live pointer and a table per
-- frame is exactly the steady GC pressure that shows up as sailing stutter.
--
-- Returns:
--   ax, ay   the anchor. The badge sits here, UPRIGHT, and it does not orbit --
--            only the boat's position and the vertical motion move it.
--   ang      the bearing to the target. ONLY the arrow may rotate by this.
--   qx, qy   the arrow's centre: the anchor pushed out by `orbit` along the
--            bearing, so the arrow rides on the badge's leading edge.
function Pointer.layout(bx, by, tx, ty, lift, hop, wobble, orbit)
    local ang = math.atan2(ty - by, tx - bx)
    local ca, sa = math.cos(ang), math.sin(ang)
    -- the whole marker hops a little TOWARD the target ("this way! this way!"),
    -- so the motion itself points even before you read the arrow
    local ax = bx + ca * hop
    local ay = by - lift + wobble + sa * hop
    return ax, ay, ang, ax + ca * orbit, ay + sa * orbit
end

-- `style` is a PERSISTENT table -- build it once at file scope, never per frame:
--   shape       polygon vertices for the arrow, pointing +x, in design px
--   fill, line  arrow fill and outline colours
--   orbit       how far the arrow sits from the anchor (design px; 0 = on it)
--   badge       optional icon name, drawn UPRIGHT at the anchor
--   badgeSize   badge size in design px (scaled by the same `scale`)
--   ring*       see Pointer.ring
--
-- `scale` multiplies the design-px geometry; the caller decides whether that
-- came from Scale.overlay or Scale.marker.
function Pointer.draw(style, bx, by, tx, ty, lift, hop, wobble, scale)
    local ax, ay, ang, qx, qy =
        Pointer.layout(bx, by, tx, ty, lift, hop, wobble, (style.orbit or 0) * scale)

    -- The arrow: the ONLY thing inside the rotation.
    local shape = style.shape
    love.graphics.push()
    love.graphics.translate(qx, qy)
    love.graphics.rotate(ang)
    love.graphics.scale(scale, scale)
    love.graphics.setColor(0, 0, 0, 0.28)                -- soft drop shadow
    love.graphics.push(); love.graphics.translate(2, 3)
    love.graphics.polygon("fill", shape); love.graphics.pop()
    love.graphics.setColor(style.fill)
    love.graphics.polygon("fill", shape)
    love.graphics.setColor(style.line)
    love.graphics.setLineWidth(4); love.graphics.polygon("line", shape)
    love.graphics.setLineWidth(1)
    love.graphics.pop()

    -- The badge: drawn after and OUTSIDE the transform, so it is upright at
    -- every bearing. This is the invariant in the header -- keep it here.
    if style.badge then
        Icons.draw(style.badge, ax, ay, style.badgeSize * scale)
    end
    love.graphics.setColor(1, 1, 1)
end

-- The pulsing ring drawn ON the target (callers check it's on screen first).
-- Colour is an argument, not a style field: the mission ring takes the
-- destination town's own colour, which changes per mission.
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
