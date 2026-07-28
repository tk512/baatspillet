-- 2:1 isometric projection. Game logic stays in the flat (gx, gy) ground plane;
-- this is the only place that converts between that plane and the screen.
-- gz is height: bigger gz lifts a point up the screen.

local Iso = {}

Iso.SX = 0.5     -- horizontal squash
Iso.SY = 0.25    -- vertical squash
Iso.HEIGHT = 1.0 -- how strongly gz lifts

-- ground -> iso screen space, before the camera transform
function Iso.project(gx, gy, gz)
    gz = gz or 0
    local x = (gx - gy) * Iso.SX
    local y = (gx + gy) * Iso.SY - gz * Iso.HEIGHT
    return x, y
end

-- iso screen space -> ground, assuming gz = 0 (turns a click into a destination)
function Iso.unproject(x, y)
    local a = x / Iso.SX   -- gx - gy
    local b = y / Iso.SY   -- gx + gy
    local gx = (a + b) / 2
    local gy = (b - a) / 2
    return gx, gy
end

-- Painter's key: larger = nearer the viewer, so drawn later.
function Iso.depth(gx, gy)
    return gx + gy
end

-- Geometry for a sprite occupying a wxh tile block with top-left tile (tx, ty),
-- 1-based: the four ground corners, the centre, and the on-screen diamond width.
-- The result table is shared -- objects are drawn one at a time.
local _fp = {}
function Iso.footprint(tx, ty, w, h, T)
    local gx0, gx1 = (tx - 1) * T, (tx - 1 + w) * T
    local gy0, gy1 = (ty - 1) * T, (ty - 1 + h) * T
    local f = _fp
    f.gx0, f.gx1, f.gy0, f.gy1 = gx0, gx1, gy0, gy1
    f.cx, f.cy = (gx0 + gx1) / 2, (gy0 + gy1) / 2
    local rx = (gx1 - gy0) * Iso.SX
    local lx = (gx0 - gy1) * Iso.SX
    f.width = rx - lx
    return f
end

-- A footprint's front (south) corner, so it paints after what it stands on.
function Iso.footprintDepth(tx, ty, w, h, T)
    return Iso.depth((tx - 1 + w) * T, (ty - 1 + h) * T)
end

return Iso
