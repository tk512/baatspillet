-- src/systems/iso.lua
-- 2:1 isometric projection (SimCity 2000 "diamond" look). All game logic stays
-- in a flat ground plane of (gx, gy); this is the only place that converts
-- between that plane and the screen.
--
--   ground (gx, gy, gz)  --project-->  iso screen (x, y)
--   iso (x, y)           --unproject-> ground (gx, gy)   (assumes gz = 0)
--
-- gz is height: a bigger gz lifts a point up the screen (land, buildings, deck).

local Iso = {}

-- Half-width / quarter-height factors give the classic 2:1 diamond.
Iso.SX = 0.5    -- horizontal squash
Iso.SY = 0.25   -- vertical squash
Iso.HEIGHT = 1.0 -- how strongly gz lifts things on screen

-- Ground -> iso screen space (before the camera transform is applied).
function Iso.project(gx, gy, gz)
    gz = gz or 0
    local x = (gx - gy) * Iso.SX
    local y = (gx + gy) * Iso.SY - gz * Iso.HEIGHT
    return x, y
end

-- Iso screen space -> ground (assuming the point sits on the water, gz = 0).
-- Used to turn a mouse click into a destination for the boat.
function Iso.unproject(x, y)
    -- From the two project() equations:
    --   x = (gx - gy) * SX      ->  gx - gy = x / SX
    --   y = (gx + gy) * SY      ->  gx + gy = y / SY
    local a = x / Iso.SX   -- gx - gy
    local b = y / Iso.SY   -- gx + gy
    local gx = (a + b) / 2
    local gy = (b - a) / 2
    return gx, gy
end

-- Painter's-algorithm depth key. Things with a LARGER value are nearer the
-- viewer (lower on screen) and must be drawn later so they overlap correctly.
function Iso.depth(gx, gy)
    return gx + gy
end

-- Multi-tile footprints for sprite objects. An object occupies a wxh block of
-- tiles whose top-left tile is (tx, ty) (1-based; tile i spans [(i-1)*T, i*T]).
-- footprint() returns the geometry a sprite needs: the four ground corners, the
-- ground center, and the on-screen diamond width.
-- The output table is shared and reused: objects are drawn and consumed one at a
-- time, so a single table avoids allocating one per draw.
local _fp = {}
function Iso.footprint(tx, ty, w, h, T)
    local gx0, gx1 = (tx - 1) * T, (tx - 1 + w) * T
    local gy0, gy1 = (ty - 1) * T, (ty - 1 + h) * T
    local f = _fp
    f.gx0, f.gx1, f.gy0, f.gy1 = gx0, gx1, gy0, gy1
    f.cx, f.cy = (gx0 + gx1) / 2, (gy0 + gy1) / 2     -- ground center
    -- diamond width on screen (before zoom) = T * (w + h) / 2
    local rx = (gx1 - gy0) * Iso.SX
    local lx = (gx0 - gy1) * Iso.SX
    f.width = rx - lx
    return f
end

-- Depth of a footprint = its front (south) corner, so it's painted after the
-- tiles it stands on and the tiles behind it.
function Iso.footprintDepth(tx, ty, w, h, T)
    return Iso.depth((tx - 1 + w) * T, (ty - 1 + h) * T)
end

return Iso
