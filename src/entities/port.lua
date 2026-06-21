-- src/entities/port.lua
-- A harbour the boat visits to load / deliver cargo. It's a multi-tile object;
-- terrain snaps it to a coastline, flattens the ground under it, and tells it
-- which way the open sea is (seaDx, seaDy) so the dock faces the water.
-- Drop in assets/ports/<id>.png to replace the placeholder art.

local config  = require("src.config")
local Iso     = require("src.systems.iso")
local Objects = require("src.systems.objects")

local Port = {}
Port.__index = Port

Port.FOOTPRINT = 4  -- tiles per side (a small harbor town)

function Port.new(def)
    local self = setmetatable({}, Port)
    self.def   = def
    self.id    = def.id
    self.name  = def.name
    self.x     = def.x          -- intended location; terrain snaps it to coast
    self.y     = def.y
    self.color = def.color or {0.8, 0.6, 0.4}
    self.bob   = #def.id
    self.w, self.h = Port.FOOTPRINT, Port.FOOTPRINT
    self.tx, self.ty = 1, 1
    self.buildZ = 0
    self.seaDx, self.seaDy = 0, 1
    return self
end

-- Called by terrain after it snaps the port to a coast + flattens the site.
function Port:placeAt(tx, ty, cx, cy, buildZ, seaDx, seaDy)
    self.tx, self.ty = tx, ty
    self.x, self.y = cx, cy
    self.buildZ = buildZ
    self.seaDx, self.seaDy = seaDx, seaDy
end

function Port:update(dt) self.bob = self.bob + dt end

-- The spot the boat pulls up to: out in the water in front of the harbour
-- (the buildings sit on unreachable land). Pushed past the flattened footprint
-- so it lands on sailable water.
function Port:dockPoint()
    if self.dockX then return self.dockX, self.dockY end   -- set by terrain (shoreline water)
    local d = Port.FOOTPRINT * config.TILE * 0.5 + 40       -- fallback
    return self.x + self.seaDx * d, self.y + self.seaDy * d
end

-- Where the boat parks: sea-ward of the dock point, beside the pier. The boat
-- glides here before the docking screen opens.
function Port:berth()
    local dpx, dpy = self:dockPoint()
    return dpx + self.seaDx * 34, dpy + self.seaDy * 34
end

function Port:isBoatInRange(boat)
    local dpx, dpy = self:dockPoint()
    local dx, dy = boat.x - dpx, boat.y - dpy
    return (dx * dx + dy * dy) <= (config.PICKUP_RADIUS * config.PICKUP_RADIUS)
end

function Port:toObject()
    return {
        tx = self.tx, ty = self.ty, w = self.w, h = self.h, z = self.buildZ,
        sprite = "ports/" .. self.id .. ".png",
        data = self,
        draw = function(_, g) self:drawPlaceholder(g) end,
    }
end

-- The pier as a separate object so it depth-sorts with the boat (and so the
-- dock art can be swapped via assets/ports/dock.png). Sits at the dock-point tile.
function Port:toDockObject()
    local T = config.TILE
    local dpx, dpy = self:dockPoint()
    return {
        tx = math.floor(dpx / T) + 1, ty = math.floor(dpy / T) + 1, w = 1, h = 1, z = 0,
        sprite = "ports/dock.png",
        data = self,
        draw = function(_, g) self:drawDock() end,
    }
end

-- A little wooden jetty reaching from the shore out to the dock point.
function Port:drawDock()
    local c = config.colors
    local T = config.TILE
    local dpx, dpy = self:dockPoint()
    local sdx, sdy = self.seaDx, self.seaDy        -- toward the sea
    local px, py   = -sdy, sdx                      -- along the shore
    local len, hw, deckZ = T * 1.5, T * 0.16, 9    -- reach, half-width, deck height

    -- point at distance s along the sea axis (0 = dock point, negative = shoreward)
    -- and offset w across the shore axis, at height z.
    local function P(s, w, z)
        return Iso.project(dpx + sdx * s + px * w, dpy + sdy * s + py * w, z)
    end

    -- support posts
    for i = 0, 3 do
        local s = -len * (i / 3) - len * 0.02
        for _, w in ipairs({ -hw * 0.8, hw * 0.8 }) do
            Objects.box(dpx + sdx * s + px * w, dpy + sdy * s + py * w, 2, 2, 0, deckZ, c.dock_side)
        end
    end

    -- deck top
    local a1, a2 = P(0.1 * T, hw, deckZ)
    local b1, b2 = P(0.1 * T, -hw, deckZ)
    local d1, d2 = P(-len, -hw, deckZ)
    local e1, e2 = P(-len, hw, deckZ)
    love.graphics.setColor(c.dock_top)
    love.graphics.polygon("fill", a1, a2, b1, b2, d1, d2, e1, e2)

    -- plank seams across the deck
    love.graphics.setColor(c.dock_side[1], c.dock_side[2], c.dock_side[3], 0.7)
    for i = 0, 6 do
        local s = 0.1 * T - (0.1 * T + len) * (i / 6)
        local f1, f2 = P(s, hw, deckZ)
        local g1, g2 = P(s, -hw, deckZ)
        love.graphics.line(f1, f2, g1, g2)
    end
    love.graphics.setColor(1, 1, 1)
end

function Port:drawPlaceholder(g)
    local c   = config.colors
    local z   = g.z
    local sdx, sdy = self.seaDx, self.seaDy        -- toward the sea
    local px, py   = -sdy, sdx                      -- along the shore
    local salt = #self.id

    local function gxof(s, p) return g.cx + sdx * s + px * p end
    local function gyof(s, p) return g.cy + sdy * s + py * p end
    local function box(s, p, hw, hd, z0, z1, color)
        Objects.box(gxof(s, p), gyof(s, p), hw, hd, z0, z1, color)
    end
    local function building(s, p, hw, hd, wallH, roofH, wall, roof)
        Objects.building(gxof(s, p), gyof(s, p), hw, hd, z, wallH, roofH, wall, roof)
    end
    local bc = config.BUILDING_COLORS
    local function col(n) return bc[((salt + n) % #bc) + 1] end

    -- 1) cobblestone plaza + a darker quay/apron near the water
    Objects.drawPavedLot(g, salt)
    box(36, 0, 56, 30, z, z + 1.5, c.road)

    -- 2) main warehouse with windows + a pitched roof
    building(-44, -16, 34, 28, 40, 20, c.building_wall, self.color)

    -- 3) a cluster of varied town buildings (different sizes/heights/roofs)
    building(-58, 38,  16, 16, 22, 16, c.building_wall, col(1))   -- house
    building(-30, 56,  14, 14, 18, 14, c.building_wall, col(2))   -- house
    building(-78, 2,   18, 18, 54, 18, c.building_dk,   col(3))   -- tall office
    building(-20, -54, 20, 14, 26, 12, c.building_wall, col(4))   -- shed

    -- 4) two storage tanks
    box(2,  -52, 9, 9, z, z + 22, c.stone)
    box(22, -48, 9, 9, z, z + 22, c.stone)

    -- 5) a lighthouse near the seaward corner, with a blinking lamp
    box(46, -44, 8,   8,   z,      z + 56, c.building_wall)
    box(46, -44, 8.5, 8.5, z + 30, z + 38, {0.70, 0.30, 0.26})  -- red band
    local lsx, lsy = Iso.project(gxof(46, -44), gyof(46, -44), z + 64)
    love.graphics.setColor((math.sin(self.bob * 2.0) > 0) and {1.0, 0.92, 0.5} or {0.7, 0.6, 0.3})
    love.graphics.circle("fill", lsx, lsy, 5)

    -- 6) a crane near the quay
    self:drawCrane(gxof(18, 44), gyof(18, 44), z)

    -- 7) crates
    box(28, 12, 7, 7, z, z + 14, col(5))
    box(40, 24, 6, 6, z, z + 11, col(2))

    self:drawLabel(g)
    love.graphics.setColor(1, 1, 1)
end

function Port:drawCrane(gx, gy, z)
    local bx, by = Iso.project(gx, gy, z)
    local tx, ty = Iso.project(gx, gy, z + 64)
    love.graphics.setColor(0.85, 0.65, 0.2)
    love.graphics.setLineWidth(4)
    love.graphics.line(bx, by, tx, ty)                       -- mast
    love.graphics.setLineWidth(3)
    love.graphics.line(tx, ty, tx + 34, ty + 6)              -- jib arm
    love.graphics.setColor(0.2, 0.2, 0.22)
    love.graphics.setLineWidth(1)
    love.graphics.line(tx + 30, ty + 5, tx + 30, ty + 22)    -- cable
    love.graphics.rectangle("fill", tx + 26, ty + 22, 8, 6)  -- hook block
end

function Port:drawLabel(g)
    local font = love.graphics.getFont()
    local sx, sy = Iso.project(g.cx, g.cy, g.z + 96)
    local w = font:getWidth(self.name)
    local hh = font:getHeight()
    local c = config.colors
    love.graphics.setColor(c.panel[1], c.panel[2], c.panel[3], 0.82)
    love.graphics.rectangle("fill", sx - w / 2 - 6, sy - hh / 2 - 2, w + 12, hh + 4, 4, 4)
    love.graphics.setColor(c.text)
    love.graphics.print(self.name, sx - w / 2, sy - hh / 2)
end

return Port
