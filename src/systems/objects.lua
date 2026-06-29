-- src/systems/objects.lua
-- The sprite-object layer: buildings, trees, rocks and other decorations that
-- sit on top of the ground tiles, single-tile or multi-tile (SimCity-2000
-- style), depth-sorted against the terrain and the boat.
--
-- An object is just data:
--   {
--     tx, ty,            -- top-left tile it occupies (1-based)
--     w = 1, h = 1,      -- footprint size in tiles (e.g. a 2x2 warehouse)
--     sprite = nil,      -- optional image path under assets/ (e.g. "ports/x.png")
--     draw = fn(obj, g), -- placeholder drawing, called with footprint geometry g
--     data = ...,        -- anything the owner wants to stash
--   }
--
-- A `sprite` PNG is blitted to cover the footprint; otherwise `draw(obj, g)`
-- paints the in-code placeholder.

local config = require("src.config")
local Assets = require("src.assets")
local Iso    = require("src.systems.iso")

local Objects = {}
Objects.__index = Objects

-- Fraction of the footprint width a sprite fills (>1.0 lets art overhang).
local SPRITE_FILL = 1.0

function Objects.new()
    return setmetatable({ list = {} }, Objects)
end

function Objects:add(obj)
    obj.w = obj.w or 1
    obj.h = obj.h or 1
    obj.z = obj.z or 0     -- ground height (units) the object stands on
    obj.depth = Iso.footprintDepth(obj.tx, obj.ty, obj.w, obj.h, config.TILE)
    self.list[#self.list + 1] = obj
    return obj
end

-- Drop every object matching `pred` (used to clear a yard for a big landmark).
function Objects:removeWhere(pred)
    local list = self.list
    for i = #list, 1, -1 do
        if pred(list[i]) then table.remove(list, i) end
    end
end

-- Append every object whose footprint touches the visible tile range to `out`
-- and return the new length. world.lua merges these with terrain tiles and the
-- boat into one sorted pass.
function Objects:collectVisible(i0, j0, i1, j1, out)
    local n = #out
    for _, obj in ipairs(self.list) do
        local ox0, oy0 = obj.tx, obj.ty
        local ox1, oy1 = obj.tx + obj.w - 1, obj.ty + obj.h - 1
        if ox1 >= i0 and ox0 <= i1 and oy1 >= j0 and oy0 <= j1 then
            n = n + 1
            out[n] = obj
        end
    end
    return n
end

-- Draw one object: PNG if present, otherwise its placeholder. Called with the
-- camera already attached (we draw in iso space).
function Objects.draw(obj)
    local g = Iso.footprint(obj.tx, obj.ty, obj.w, obj.h, config.TILE)
    g.z = obj.z or 0

    local img = obj.sprite and Assets.image(obj.sprite)
    if img then
        -- Iso tile sprites are bottom-aligned: anchor the image's bottom-center
        -- at the footprint's front (south) corner and scale its diamond to the
        -- footprint width. Per-sprite nudges via obj.spriteScale / offset.
        local sx, sy = Iso.project(g.gx1, g.gy1, g.z)
        local scale = (g.width * SPRITE_FILL * (obj.spriteScale or 1)) / img:getWidth()
        -- anchor at the sprite's real ground line so padding doesn't float it
        local oy = Assets.imageGroundY(obj.sprite) or img:getHeight()
        love.graphics.setColor(1, 1, 1)
        love.graphics.draw(img, sx + (obj.spriteOffX or 0), sy + (obj.spriteOffY or 0),
            0, scale, scale, img:getWidth() / 2, oy)
        return
    end

    if obj.draw then obj.draw(obj, g) end
end

-- Placeholder drawing helpers.

-- Flat diamond "lot" covering the footprint, at the object's ground height.
function Objects.drawLot(g, color)
    local z = g.z or 0
    local ax, ay = Iso.project(g.gx0, g.gy0, z)
    local bx, by = Iso.project(g.gx1, g.gy0, z)
    local cx, cy = Iso.project(g.gx1, g.gy1, z)
    local dx, dy = Iso.project(g.gx0, g.gy1, z)
    love.graphics.setColor(color)
    love.graphics.polygon("fill", ax, ay, bx, by, cx, cy, dx, dy)
end

-- A cobblestone harbour plaza filling the footprint: a grid of small stone
-- diamonds with deterministic light/dark variation and a darker rim, so the port
-- ground reads as paved ground rather than one flat coloured square.
function Objects.drawPavedLot(g, salt)
    local z = g.z or 0
    local N = 8
    local x0, y0, x1, y1 = g.gx0, g.gy0, g.gx1, g.gy1
    local dx, dy = (x1 - x0) / N, (y1 - y0) / N
    salt = salt or 0
    for a = 0, N - 1 do
        for b = 0, N - 1 do
            local n = math.sin((a + 1) * 12.9898 + (b + 1) * 78.233 + salt) * 43758.5453
            n = n - math.floor(n)                       -- 0..1 deterministic
            local f = 0.86 + n * 0.24                    -- per-stone shade
            local cx0, cy0 = x0 + a * dx, y0 + b * dy
            local cx1, cy1 = cx0 + dx, cy0 + dy
            local Ax, Ay = Iso.project(cx0, cy0, z)
            local Bx, By = Iso.project(cx1, cy0, z)
            local Cx, Cy = Iso.project(cx1, cy1, z)
            local Dx, Dy = Iso.project(cx0, cy1, z)
            love.graphics.setColor(0.58 * f, 0.55 * f, 0.50 * f)
            love.graphics.polygon("fill", Ax, Ay, Bx, By, Cx, Cy, Dx, Dy)
        end
    end
    -- darker stone rim around the plaza
    local ax, ay = Iso.project(x0, y0, z)
    local bx, by = Iso.project(x1, y0, z)
    local cx, cy = Iso.project(x1, y1, z)
    local ex, ey = Iso.project(x0, y1, z)
    love.graphics.setColor(0.34, 0.30, 0.25)
    love.graphics.setLineWidth(2)
    love.graphics.polygon("line", ax, ay, bx, by, cx, cy, ex, ey)
    love.graphics.setLineWidth(1)
    love.graphics.setColor(1, 1, 1)
end

-- An extruded iso box over a ground rect (cx,cy = center, hw/hd = half-extents
-- in ground units) from z0..z1. Three shaded faces for readable volume.
function Objects.box(cx, cy, hw, hd, z0, z1, col)
    local function shade(f) return { col[1] * f, col[2] * f, col[3] * f } end
    local x0, x1 = cx - hw, cx + hw
    local y0, y1 = cy - hd, cy + hd
    local Ax, Ay = Iso.project(x0, y0, z1)
    local Bx, By = Iso.project(x1, y0, z1)
    local Cx, Cy = Iso.project(x1, y1, z1)
    local Dx, Dy = Iso.project(x0, y1, z1)
    local B0x, B0y = Iso.project(x1, y0, z0)
    local C0x, C0y = Iso.project(x1, y1, z0)
    local D0x, D0y = Iso.project(x0, y1, z0)
    love.graphics.setColor(shade(0.80))
    love.graphics.polygon("fill", Bx, By, Cx, Cy, C0x, C0y, B0x, B0y) -- right
    love.graphics.setColor(shade(0.62))
    love.graphics.polygon("fill", Dx, Dy, Cx, Cy, C0x, C0y, D0x, D0y) -- left
    love.graphics.setColor(shade(1.00))
    love.graphics.polygon("fill", Ax, Ay, Bx, By, Cx, Cy, Dx, Dy)     -- top
end

-- A detailed building: shaded walls + rows of windows on the two viewer-facing
-- faces + a pitched gable roof.
local function lerp2(p, q, a) return { p[1] + (q[1] - p[1]) * a, p[2] + (q[2] - p[2]) * a } end

-- Window grid on a face given its 4 screen corners (t1,t2 top edge; b1 under
-- t1, b2 under t2).
local function faceWindows(t1, t2, b1, b2, cols, rows)
    love.graphics.setColor(0.20, 0.24, 0.30, 0.92)
    for ci = 1, cols do
        for ri = 1, rows do
            local u, v = ci / (cols + 1), ri / (rows + 1)
            local uh, vh = 0.34 / (cols + 1), 0.34 / (rows + 1)
            local function P(uu, vv)
                return lerp2(lerp2(t1, t2, uu), lerp2(b1, b2, uu), vv)
            end
            local a, b = P(u - uh, v - vh), P(u + uh, v - vh)
            local c, d = P(u + uh, v + vh), P(u - uh, v + vh)
            love.graphics.polygon("fill", a[1], a[2], b[1], b[2], c[1], c[2], d[1], d[2])
        end
    end
end

function Objects.building(cx, cy, hw, hd, z, wallH, roofH, wall, roof)
    local ztop = z + wallH
    local x0, x1, y0, y1 = cx - hw, cx + hw, cy - hd, cy + hd
    Objects.box(cx, cy, hw, hd, z, ztop, wall)

    -- windows on the east (x1) and south (y1) faces
    local function p(gx, gy, zz) local a, b = Iso.project(gx, gy, zz); return { a, b } end
    faceWindows(p(x1, y0, ztop), p(x1, y1, ztop), p(x1, y0, z), p(x1, y1, z), 3, 2)
    faceWindows(p(x0, y1, ztop), p(x1, y1, ztop), p(x0, y1, z), p(x1, y1, z), 3, 2)

    -- pitched gable roof (ridge runs along x, at y = cy)
    if roofH and roofH > 0 then
        local zr = ztop + roofH
        local function pj(gx, gy, zz) return Iso.project(gx, gy, zz) end
        local nwx, nwy = pj(x0, y0, ztop); local nex, ney = pj(x1, y0, ztop)
        local swx, swy = pj(x0, y1, ztop); local sex, sey = pj(x1, y1, ztop)
        local r0x, r0y = pj(x0, cy, zr);  local r1x, r1y = pj(x1, cy, zr)
        local function shade(f) love.graphics.setColor(roof[1]*f, roof[2]*f, roof[3]*f) end
        shade(1.10); love.graphics.polygon("fill", nwx, nwy, nex, ney, r1x, r1y, r0x, r0y) -- north slope
        shade(0.80); love.graphics.polygon("fill", swx, swy, sex, sey, r1x, r1y, r0x, r0y) -- south slope
        shade(0.66); love.graphics.polygon("fill", nwx, nwy, r0x, r0y, swx, swy)           -- west gable
        shade(0.66); love.graphics.polygon("fill", nex, ney, r1x, r1y, sex, sey)           -- east gable
    end
end

-- A dense forest tile: many overlapping trees so neighbouring forest tiles blend
-- into one woodland. `salt` makes the layout deterministic per tile; layouts
-- never change, so each is computed once and cached. All trees are the soft
-- code-drawn kind (no pixel-art sprites) -- they read better at a glance.
local forestCache = {}

function Objects.drawForest(g, salt)
    local c = config.colors
    local z = g.z or 0
    local trees = forestCache[salt]
    if not trees then
        local s = (salt or 1) % 100000
        local function rnd()
            s = (s * 1103515245 + 12345) % 2147483648
            return s / 2147483648
        end
        -- pick tree positions, then sort back-to-front so nearer trees overlap
        trees = {}
        for k = 1, config.FOREST_DENSITY do
            local gx = g.gx0 + rnd() * (g.gx1 - g.gx0)
            local gy = g.gy0 + rnd() * (g.gy1 - g.gy0)
            trees[k] = { gx, gy, 0.85 + rnd() * 0.5 }
        end
        table.sort(trees, function(a, b) return (a[1] + a[2]) < (b[1] + b[2]) end)
        forestCache[salt] = trees
    end

    for _, t in ipairs(trees) do
        local sx, sy = Iso.project(t[1], t[2], z)
        local sc = t[3]
        love.graphics.setColor(0, 0, 0, 0.10)
        love.graphics.ellipse("fill", sx, sy + 2, 9 * sc, 4 * sc)
        love.graphics.setColor(c.tree_trunk)
        love.graphics.rectangle("fill", sx - 2 * sc, sy - 12 * sc, 4 * sc, 12 * sc)
        love.graphics.setColor(c.tree_leaf)
        love.graphics.circle("fill", sx, sy - 18 * sc, 10 * sc)
        love.graphics.setColor(c.tree_leaf_hi)
        love.graphics.circle("fill", sx - 3 * sc, sy - 21 * sc, 6 * sc)
    end
end

-- A 1x1 rock cluster (also used as a decorative sea hazard marker).
function Objects.drawRock(g)
    local c = config.colors
    local sx, sy = Iso.project(g.cx, g.cy, g.z or 0)
    love.graphics.setColor(c.rock_dark)
    love.graphics.ellipse("fill", sx, sy - 2, 12, 7)
    love.graphics.setColor(c.rock_light)
    love.graphics.circle("fill", sx - 3, sy - 5, 7)
    love.graphics.circle("fill", sx + 5, sy - 3, 5)
end

-- A skerry: a small rocky outcrop sitting in open water, ringed by a gentle
-- pulsing foam wash at the waterline. `salt` varies the rock shape + foam phase
-- per skerry. No per-frame allocations (hot draw path).
function Objects.drawSkerry(g, salt)
    local c = config.colors
    local sx, sy = Iso.project(g.cx, g.cy, g.z or 0)
    salt = salt or 0
    local t = love.timer.getTime()
    local pulse = 0.5 + 0.5 * math.sin(t * 1.4 + salt)
    -- foam wash around the base
    love.graphics.setColor(1, 1, 1, 0.16 + 0.10 * pulse)
    love.graphics.ellipse("fill", sx, sy + 2, 22, 11)
    love.graphics.setColor(1, 1, 1, 0.32)
    love.graphics.ellipse("line", sx, sy + 2, 16 + pulse * 2, 8 + pulse)
    -- a little rock cluster, shape jittered by salt
    local j = (salt % 3) - 1
    love.graphics.setColor(c.rock_dark)
    love.graphics.ellipse("fill", sx, sy - 2, 11, 6)
    love.graphics.setColor(c.rock_light)
    love.graphics.circle("fill", sx - 3 + j, sy - 5, 6)
    love.graphics.circle("fill", sx + 4, sy - 3 - j, 4)
end

-- City landmark placeholders (swap for pixel art later). Each is anchored on its
-- 1-tile footprint center (g.cx, g.cy) at height g.z, mixing grounded iso boxes
-- with a few screen-space details (spires, awnings, cables).

local function shadow(sx, sy, rx)
    love.graphics.setColor(0, 0, 0, 0.14)
    love.graphics.ellipse("fill", sx, sy + 2, rx, rx * 0.5)
end

-- Church: a white nave + a tall steeple with a red spire and a cross.
function Objects.drawChurch(g)
    local cx, cy, z = g.cx, g.cy, g.z or 0
    local sx, sy = Iso.project(cx, cy, z)
    shadow(sx, sy, 22)
    Objects.box(cx + 7, cy, 11, 9, z, z + 20, { 0.92, 0.91, 0.86 })   -- nave
    -- a little round rose window on the nave's south face
    local wx, wy = Iso.project(cx + 7, cy + 9, z + 12)
    love.graphics.setColor(0.30, 0.40, 0.55); love.graphics.circle("fill", wx, wy, 3)
    Objects.box(cx - 11, cy, 6, 6, z, z + 38, { 0.88, 0.87, 0.82 })   -- steeple tower
    -- red spire (screen-space triangle on the tower top) + a cross
    local tx, ty = Iso.project(cx - 11, cy, z + 38)
    love.graphics.setColor(0.62, 0.30, 0.26)
    love.graphics.polygon("fill", tx - 9, ty, tx + 9, ty, tx, ty - 26)
    love.graphics.setColor(0.45, 0.22, 0.19)
    love.graphics.polygon("fill", tx + 9, ty, tx, ty, tx, ty - 26)     -- shaded side
    love.graphics.setColor(0.95, 0.92, 0.7)
    love.graphics.setLineWidth(2)
    love.graphics.line(tx, ty - 26, tx, ty - 36)                       -- cross post
    love.graphics.line(tx - 3, ty - 32, tx + 3, ty - 32)              -- cross arms
    love.graphics.setLineWidth(1)
end

-- Market square: a cluster of little striped-awning stalls.
function Objects.drawMarket(g)
    local cx, cy, z = g.cx, g.cy, g.z or 0
    local sx, sy = Iso.project(cx, cy, z)
    shadow(sx, sy, 22)
    local stalls = {
        { -10, -6, { 0.80, 0.32, 0.28 } }, { 9, -2, { 0.30, 0.52, 0.62 } },
        { -2, 8, { 0.82, 0.66, 0.30 } },
    }
    for _, s in ipairs(stalls) do
        local ox, oy = cx + s[1], cy + s[2]
        Objects.box(ox, oy, 6, 5, z, z + 9, { 0.78, 0.70, 0.55 })      -- stall counter/posts
        -- striped awning roof (screen-space, two colours)
        local ax, ay = Iso.project(ox, oy, z + 9)
        love.graphics.setColor(s[3])
        love.graphics.polygon("fill", ax - 9, ay - 1, ax + 9, ay - 1, ax + 6, ay - 7, ax - 6, ay - 7)
        love.graphics.setColor(0.95, 0.94, 0.9)
        love.graphics.polygon("fill", ax - 3, ay - 1, ax + 1, ay - 1, ax + 0.5, ay - 5, ax - 2.5, ay - 5)
    end
end

-- Harbour crane: a steel mast + jib with a hanging hook, beside stacked crates.
function Objects.drawCrane(g)
    local cx, cy, z = g.cx, g.cy, g.z or 0
    local sx, sy = Iso.project(cx, cy, z)
    shadow(sx, sy, 20)
    Objects.box(cx - 4, cy + 4, 6, 6, z, z + 8, { 0.34, 0.36, 0.40 })  -- crane base/cab
    local mx, my = Iso.project(cx - 4, cy + 4, z + 8)
    love.graphics.setColor(0.24, 0.26, 0.30)
    love.graphics.setLineWidth(4)
    love.graphics.line(mx, my, mx, my - 46)                            -- mast
    love.graphics.line(mx, my - 46, mx + 34, my - 38)                  -- jib
    love.graphics.setLineWidth(2)
    love.graphics.setColor(0.20, 0.21, 0.24)
    love.graphics.line(mx + 30, my - 39, mx + 30, my - 22)             -- cable
    love.graphics.setColor(0.5, 0.45, 0.2)
    love.graphics.rectangle("fill", mx + 27, my - 22, 6, 4)            -- hook block
    -- a couple of cargo crates
    Objects.box(cx + 9, cy - 6, 5, 5, z, z + 9, { 0.62, 0.46, 0.30 })
    Objects.box(cx + 8, cy - 5, 4, 4, z + 9, z + 16, { 0.70, 0.54, 0.36 })
end

-- Fish-drying racks: wooden A-frames with rows of little hanging fish.
function Objects.drawFishRacks(g)
    local cx, cy, z = g.cx, g.cy, g.z or 0
    local sx, sy = Iso.project(cx, cy, z)
    shadow(sx, sy, 20)
    for r = -1, 1, 2 do
        local ox = cx + r * 7
        local a1x, a1y = Iso.project(ox, cy - 8, z)
        local a2x, a2y = Iso.project(ox, cy + 8, z)
        local topx, topy = (a1x + a2x) / 2, math.min(a1y, a2y) - 22
        love.graphics.setColor(0.42, 0.30, 0.18)
        love.graphics.setLineWidth(3)
        love.graphics.line(a1x, a1y, topx, topy)                       -- A-frame legs
        love.graphics.line(a2x, a2y, topx, topy)
        love.graphics.setLineWidth(1)
    end
    -- horizontal beam + hanging fish between the two frames
    local lx, ly = Iso.project(cx - 7, cy, z + 20)
    local rx, ry = Iso.project(cx + 7, cy, z + 20)
    love.graphics.setColor(0.36, 0.26, 0.16)
    love.graphics.setLineWidth(3); love.graphics.line(lx, ly, rx, ry); love.graphics.setLineWidth(1)
    for k = 0, 4 do
        local fx = lx + (rx - lx) * (k / 4)
        local fy = ly + (ry - ly) * (k / 4) + 6
        love.graphics.setColor(0.66, 0.70, 0.74)
        love.graphics.ellipse("fill", fx, fy, 3, 5)
    end
end

-- Placeholder landmarks (used only if the matching PNG is missing). Kept simple;
-- the real art is the OpenGFX sprite blitted by Objects.draw.
function Objects.drawLighthouse(g)
    local sx, sy = Iso.project(g.cx, g.cy, g.z or 0)
    shadow(sx, sy, 12)
    love.graphics.setColor(0.92, 0.92, 0.94)                       -- white tapered tower
    love.graphics.polygon("fill", sx - 7, sy, sx + 7, sy, sx + 4, sy - 34, sx - 4, sy - 34)
    love.graphics.setColor(0.78, 0.18, 0.16)                       -- red bands
    love.graphics.rectangle("fill", sx - 6, sy - 11, 12, 5)
    love.graphics.rectangle("fill", sx - 5, sy - 24, 10, 5)
    love.graphics.setColor(0.20, 0.20, 0.24); love.graphics.rectangle("fill", sx - 5, sy - 44, 10, 10)  -- lamp room
    love.graphics.setColor(1, 0.92, 0.5); love.graphics.circle("fill", sx, sy - 39, 3)                  -- the light
end

function Objects.drawPark(g)
    local sx, sy = Iso.project(g.cx, g.cy, g.z or 0)
    love.graphics.setColor(0.30, 0.46, 0.24); love.graphics.ellipse("fill", sx, sy, 22, 11)  -- lawn
    shadow(sx, sy, 6)
    love.graphics.setColor(0.30, 0.20, 0.12); love.graphics.rectangle("fill", sx - 2, sy - 14, 4, 14)   -- trunk
    love.graphics.setColor(0.26, 0.40, 0.22); love.graphics.circle("fill", sx, sy - 20, 11)
    love.graphics.setColor(0.34, 0.48, 0.28); love.graphics.circle("fill", sx - 3, sy - 23, 6)
end

function Objects.drawFountain(g)
    local sx, sy = Iso.project(g.cx, g.cy, g.z or 0)
    shadow(sx, sy, 12)
    love.graphics.setColor(0.66, 0.66, 0.70); love.graphics.ellipse("fill", sx, sy, 14, 7)   -- stone basin
    love.graphics.setColor(0.40, 0.62, 0.80); love.graphics.ellipse("fill", sx, sy, 10, 5)   -- water
    love.graphics.setColor(0.72, 0.85, 0.95); love.graphics.rectangle("fill", sx - 1.5, sy - 12, 3, 12)  -- jet
end

-- A small isometric ship (volumetric hull + cabin), oriented by `angle`.
-- Reused for docked ships in harbors and ambient ships at sea. `scale` ~1.0.
local SHIP_HULL = { { 22, 0 }, { 8, -11 }, { -16, -11 }, { -20, 0 }, { -16, 11 }, { 8, 11 } }
function Objects.drawShip(gx, gy, angle, color, scale, z)
    scale = scale or 1
    z = z or 0
    local c = config.colors
    local hull = SHIP_HULL
    local function rot(px, py)
        local co, si = math.cos(angle), math.sin(angle)
        return gx + (px * co - py * si) * scale, gy + (px * si + py * co) * scale
    end
    local base, deck = {}, {}
    for _, p in ipairs(hull) do
        local wx, wy = rot(p[1], p[2])
        local bx, by = Iso.project(wx, wy, z)
        local dx, dy = Iso.project(wx, wy, z + 11 * scale)
        base[#base + 1] = { bx, by }
        deck[#deck + 1] = { dx, dy }
    end
    local sxc, syc = Iso.project(gx, gy, z)
    love.graphics.setColor(0, 0, 0, 0.14)
    love.graphics.ellipse("fill", sxc, syc + 3, 22 * scale, 11 * scale)

    love.graphics.setColor(color[1] * 0.7, color[2] * 0.7, color[3] * 0.7)
    local n = #base
    for k = 1, n do
        local a, b = k, (k % n) + 1
        love.graphics.polygon("fill", deck[a][1], deck[a][2], deck[b][1], deck[b][2],
            base[b][1], base[b][2], base[a][1], base[a][2])
    end
    local poly = {}
    for k = 1, n do poly[#poly + 1] = deck[k][1]; poly[#poly + 1] = deck[k][2] end
    love.graphics.setColor(color)
    love.graphics.polygon("fill", poly)
    -- cabin
    local cxs, cys = Iso.project(gx, gy, z + 11 * scale)
    love.graphics.setColor(c.boat_cabin)
    love.graphics.rectangle("fill", cxs - 6 * scale, cys - 12 * scale, 12 * scale, 12 * scale, 2, 2)
end

-- A fancy volumetric "3D" motor yacht: a sleek hull in the boat's accent colour, a
-- white two-tier superstructure with a window band, and a little flag. Rotates with
-- `angle` -- used spinning in the boat-select preview and when steered in the world.
local YACHT_HULL = { { 30, 0 }, { 16, -10 }, { -22, -10 }, { -30, 0 }, { -22, 10 }, { 16, 10 } }
function Objects.drawYacht(gx, gy, angle, color, scale, z)
    scale = scale or 1
    z = z or 0
    local co, si = math.cos(angle), math.sin(angle)
    local function rot(px, py) return gx + (px * co - py * si) * scale, gy + (px * si + py * co) * scale end

    -- soft shadow
    local sxc, syc = Iso.project(gx, gy, z)
    love.graphics.setColor(0, 0, 0, 0.18)
    love.graphics.ellipse("fill", sxc, syc + 3 * scale, 30 * scale, 14 * scale)

    -- hull (sides + deck)
    local hullH = 10 * scale
    local base, deck = {}, {}
    for _, p in ipairs(YACHT_HULL) do
        local wx, wy = rot(p[1], p[2])
        local bx, by = Iso.project(wx, wy, z)
        local dx, dy = Iso.project(wx, wy, z + hullH)
        base[#base + 1] = { bx, by }; deck[#deck + 1] = { dx, dy }
    end
    love.graphics.setColor(color[1] * 0.55, color[2] * 0.55, color[3] * 0.55)
    local n = #base
    for i = 1, n do
        local a, b = i, (i % n) + 1
        love.graphics.polygon("fill", deck[a][1], deck[a][2], deck[b][1], deck[b][2],
            base[b][1], base[b][2], base[a][1], base[a][2])
    end
    local poly = {}
    for i = 1, n do poly[#poly + 1] = deck[i][1]; poly[#poly + 1] = deck[i][2] end
    love.graphics.setColor(0.86, 0.82, 0.72)                 -- pale deck
    love.graphics.polygon("fill", poly)

    -- a rotated, projected box (superstructure tiers), with an optional window band
    local function tier(x0, y0, x1, y1, zb, zt, col, windows)
        local lo, hi = {}, {}
        for _, c in ipairs({ { x0, y0 }, { x1, y0 }, { x1, y1 }, { x0, y1 } }) do
            local wx, wy = rot(c[1], c[2])
            local lx, ly = Iso.project(wx, wy, zb)
            local hx, hy = Iso.project(wx, wy, zt)
            lo[#lo + 1] = { lx, ly }; hi[#hi + 1] = { hx, hy }
        end
        local m = #lo
        love.graphics.setColor(col[1] * 0.72, col[2] * 0.72, col[3] * 0.72)
        for i = 1, m do
            local a, b = i, (i % m) + 1
            love.graphics.polygon("fill", hi[a][1], hi[a][2], hi[b][1], hi[b][2],
                lo[b][1], lo[b][2], lo[a][1], lo[a][2])
            if windows then            -- dark window band around the middle of the walls
                love.graphics.setColor(0.18, 0.26, 0.34)
                local wy0 = 0.45
                love.graphics.polygon("fill",
                    hi[a][1] + (lo[a][1] - hi[a][1]) * 0.3, hi[a][2] + (lo[a][2] - hi[a][2]) * 0.3,
                    hi[b][1] + (lo[b][1] - hi[b][1]) * 0.3, hi[b][2] + (lo[b][2] - hi[b][2]) * 0.3,
                    hi[b][1] + (lo[b][1] - hi[b][1]) * 0.6, hi[b][2] + (lo[b][2] - hi[b][2]) * 0.6,
                    hi[a][1] + (lo[a][1] - hi[a][1]) * 0.6, hi[a][2] + (lo[a][2] - hi[a][2]) * 0.6)
                love.graphics.setColor(col[1] * 0.72, col[2] * 0.72, col[3] * 0.72)
            end
        end
        local rp = {}
        for i = 1, m do rp[#rp + 1] = hi[i][1]; rp[#rp + 1] = hi[i][2] end
        love.graphics.setColor(col); love.graphics.polygon("fill", rp)
    end
    local white = { 0.93, 0.94, 0.96 }
    tier(-14, -7, 12, 7, z + hullH, z + hullH + 11 * scale, white, true)         -- lower cabin
    tier(-6, -5, 8, 5, z + hullH + 11 * scale, z + hullH + 20 * scale, white, true)  -- bridge

    -- mast + colour flag
    local tx, ty = rot(2, 0)
    local mx, my = Iso.project(tx, ty, z + hullH + 20 * scale)
    love.graphics.setColor(0.30, 0.25, 0.20); love.graphics.setLineWidth(math.max(1, 2 * scale))
    love.graphics.line(mx, my, mx, my - 16 * scale)
    love.graphics.setColor(color)
    love.graphics.polygon("fill", mx, my - 16 * scale, mx + 12 * scale, my - 12 * scale, mx, my - 8 * scale)
    love.graphics.setLineWidth(1)
end

-- Rendered-frames boat: a real 3D model baked to N frames of a full turn (Blender,
-- iso camera) living in assets/boats/<name>/0.png .. (N-1).png. The count is auto-
-- detected; the frame is chosen by heading, so it "rotates" as you steer. Render
-- convention: all frames the same size, boat centred and sitting near the bottom,
-- frame 0 = bow pointing screen-right (east), turning clockwise. If a render starts
-- elsewhere or turns the other way, fix it in data with frameOffset / frameCW (no
-- re-render needed). See tools/render_boat_frames.md.
local boatFramesCache = {}
local function boatFrames(name)
    local c = boatFramesCache[name]
    if c == nil then
        c = {}
        local i = 0
        while true do
            local img = Assets.image("boats/" .. name .. "/" .. i .. ".png")
            if not img then break end
            c[#c + 1] = img
            i = i + 1
        end
        if #c == 0 then c = false end
        boatFramesCache[name] = c
    end
    return c or nil
end

function Objects.hasBoatFrames(name) return name ~= nil and boatFrames(name) ~= nil end

-- anchorFrac: vertical anchor as a fraction of frame height (1 = bottom, the
-- waterline, for sailing/thumbnails; ~0.5 = centred, for the big spinning preview).
function Objects.drawBoatFrames(name, gx, gy, angle, width, offset, cw, tint, anchorFrac)
    local frames = boatFrames(name)
    if not frames then return false end
    local N = #frames
    local vsx = (math.cos(angle) - math.sin(angle)) * Iso.SX     -- screen-space heading
    local vsy = (math.cos(angle) + math.sin(angle)) * Iso.SY
    local step = (2 * math.pi) / N
    local k = math.floor(math.atan2(vsy, vsx) / step + 0.5) % N
    if cw == false then k = (N - k) % N end
    local idx = (k + (offset or 0)) % N
    local img = frames[idx + 1]
    local s = (width or config.BOAT_SPRITE_WIDTH) / img:getWidth()
    local sx, sy = Iso.project(gx, gy, 0)
    love.graphics.setColor(tint or { 1, 1, 1 })
    love.graphics.draw(img, sx, sy, 0, s, s, img:getWidth() / 2, img:getHeight() * (anchorFrac or 1))
    return true
end

-- Sprite ambient ship: OpenGFX 8-view dimetric art under assets/ships/<name>/0..7.png,
-- the frame picked by heading. All 8 frames share one canvas + pivot (the extractor
-- bakes the source draw-offsets in), so we anchor every frame at the same
-- bottom-centre point -- the hull keeps its place as the boat turns. Returns false
-- if the art is absent so the caller can fall back to drawShip (placeholder-first).
-- gx,gy,angle are GROUND space; z is the bob height.
local shipFramesCache = {}
local function shipFrames(name)
    local c = shipFramesCache[name]
    if c == nil then
        local f0 = Assets.image("ships/" .. name .. "/0.png")
        if not f0 then shipFramesCache[name] = false; return nil end
        c = { f0 }
        for i = 1, 7 do c[i + 1] = Assets.image("ships/" .. name .. "/" .. i .. ".png") end
        shipFramesCache[name] = c
    end
    return c or nil
end

-- Frame index for a ground heading. Project the heading to screen velocity, take
-- its octant, and map to the OpenTTD direction-enum order baked on disk
-- (0=N,1=NE,2=E,3=SE,4=S,5=SW,6=W,7=NW). screen octant 0 is due-East, so the
-- enum frame is octant+2 (mod 8). If a play-test shows the bow points the wrong
-- way, this +2 is the single knob to turn.
local function headingFrame(angle)
    local vsx = (math.cos(angle) - math.sin(angle)) * Iso.SX
    local vsy = (math.cos(angle) + math.sin(angle)) * Iso.SY
    local k = math.floor(math.atan2(vsy, vsx) / (math.pi / 4) + 0.5) % 8
    return (k + 2) % 8
end

function Objects.drawShipSprite(name, gx, gy, angle, scale)
    local frames = shipFrames(name)
    if not frames then return false end
    scale = scale or 1
    local idx = headingFrame(angle)
    local img = frames[idx + 1]
    if not img then return false end

    -- Lie flat on the water: no bob, no shadow -- just the hull at the waterline.
    local w = config.AMBIENT_SHIP_WIDTH * scale
    local s = w / img:getWidth()
    local sx, sy = Iso.project(gx, gy, 0)
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(img, sx, sy, 0, s, s, img:getWidth() / 2, img:getHeight())
    return true
end

-- Photo billboard ambient ship (a stylized real-boat photo at assets/<imgPath>,
-- bow pointing right). Like the player boat, there's no rotation: it faces the way
-- it's travelling on screen and mirrors for the other direction, lying flat on the
-- water (no bob, no shadow). Returns false if the photo is missing.
function Objects.drawShipBillboard(imgPath, gx, gy, angle, scale)
    local img = Assets.image(imgPath)
    if not img then return false end
    if img:getFilter() ~= "nearest" then img:setFilter("nearest", "nearest") end
    local vsx = (math.cos(angle) - math.sin(angle)) * Iso.SX   -- screen-x travel
    local flip = (vsx < 0) and -1 or 1
    local w = config.AMBIENT_PHOTO_WIDTH * (scale or 1)
    local s = w / img:getWidth()
    local sx, sy = Iso.project(gx, gy, 0)
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(img, sx, sy, 0, s * flip, s, img:getWidth() / 2, img:getHeight())
    return true
end

return Objects
