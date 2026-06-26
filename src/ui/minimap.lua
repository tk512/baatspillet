-- src/ui/minimap.lua
-- A Civilization-style world map in the top-right corner: a small top-down view
-- of the whole ocean, revealed only where you've sailed. It shares the fog grid
-- with the fog-of-war (so "explored" means the same thing on the map as in the
-- world) and bakes the revealed terrain into one texture, repainting only the
-- cells that newly light up -- no per-frame terrain scan, no per-frame allocs.
--
-- The world's gameplay plane is flat (gx, gy); only the 3D view is isometric. So
-- this map is a straight top-down scaling of that plane: x = gx, y = gy. Ports,
-- the boat and the camera viewport are drawn over the texture each frame.

local config = require("src.config")
local Retro  = require("src.ui.retro")

local Minimap = {}
Minimap.__index = Minimap

-- "Unknown" (not-yet-explored) cells: a dark slate, a touch lighter than the
-- in-world fog so the map reads as parchment-dark rather than dead black.
local UNK = { 0.07, 0.09, 0.13 }

function Minimap.new(world)
    local self = setmetatable({}, Minimap)
    self.world   = world
    self.fog     = world.fog
    self.terrain = world.terrain
    self.w, self.h = self.fog.w, self.fog.h
    -- Ground extent the texture spans (the fog grid is ceil()'d, so it can be a
    -- hair wider than WORLD_*; use the grid extent so overlays line up exactly).
    self.worldW = self.w * self.fog.cell
    self.worldH = self.h * self.fog.cell

    self.img = love.image.newImageData(self.w, self.h)
    self.img:mapPixel(function() return UNK[1], UNK[2], UNK[3], 1 end)  -- start all unknown
    self.painted = {}                          -- painted[cx][cy] = already drawn
    for cx = 0, self.w - 1 do self.painted[cx] = {} end

    self.tex = love.graphics.newImage(self.img)
    self.tex:setFilter("nearest", "nearest")   -- crisp pixel cells (retro look)

    self:refresh()                             -- paint whatever the save revealed
    return self
end

-- Colour for the fog cell (cx, cy) from the terrain under its centre: blue for
-- sea (lighter in the shallows), land by cover type, paling toward snow as the
-- elevation level climbs so mountains stand out the way they do in the world.
function Minimap:terrainColor(cx, cy)
    local cell = self.fog.cell
    local i, j = self.terrain:tileIndexAt((cx + 0.5) * cell, (cy + 0.5) * cell)
    local t = self.terrain.tiles[i][j]
    if t.water then
        if t.shallow then return 0.40, 0.56, 0.64 end
        return 0.20, 0.35, 0.47
    end
    local base = config.colors[t.type] and config.colors[t.type].top or config.colors.grass.top
    local r, g, b = base[1], base[2], base[3]
    local f = (t.level or 0) / config.MOUNTAINS.MAX_LEVEL   -- 0 lowland .. 1 peak
    if f > 0 then
        r = r + (0.92 - r) * f
        g = g + (0.93 - g) * f
        b = b + (0.95 - b) * f
    end
    return r, g, b
end

-- Paint any cell that has become revealed since the last call, and re-upload the
-- texture only if something actually changed. Called when the fog reveals a new
-- cell (rare relative to the frame rate), so the per-cell work stays tiny.
function Minimap:refresh()
    local fog = self.fog
    local changed = false
    for cx = 0, self.w - 1 do
        local col, painted = fog.grid[cx], self.painted[cx]
        for cy = 0, self.h - 1 do
            if col[cy] and not painted[cy] then
                local r, g, b = self:terrainColor(cx, cy)
                self.img:setPixel(cx, cy, r, g, b, 1)
                painted[cy] = true
                changed = true
            end
        end
    end
    if changed then self.tex:replacePixels(self.img) end
    return changed
end

function Minimap:draw()
    local world = self.world
    local fonts = world.game.fonts
    local c     = config.colors
    local sw    = love.graphics.getWidth()

    -- Frame: a wooden plaque sized to the world's aspect ratio, top-right.
    local t  = math.max(2, math.floor(fonts.small:getHeight() * 0.20))
    local iw = math.floor(math.max(170, math.min(260, sw * 0.18)))
    local ih = math.floor(iw * self.h / self.w)
    local outerW, outerH = iw + t * 4, ih + t * 4
    local ox = sw - 16 - outerW
    local ix, iy = Retro.plaque(ox, 16, outerW, outerH, t)

    -- The explored map itself.
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(self.tex, ix, iy, 0, iw / self.w, ih / self.h)

    -- Overlays stay inside the map well even when something sits at the edge.
    love.graphics.setScissor(ix, iy, iw, ih)
    local function toScreen(gx, gy)
        return ix + (gx / self.worldW) * iw, iy + (gy / self.worldH) * ih
    end

    -- Camera viewport: a thin "you are looking here" rectangle (Civ-style). The
    -- iso view is a diamond in ground space; groundBounds() gives its bbox, which
    -- reads fine as an approximate frame.
    local minGx, minGy, maxGx, maxGy = world.camera:groundBounds()
    local vx1, vy1 = toScreen(math.max(0, minGx), math.max(0, minGy))
    local vx2, vy2 = toScreen(math.min(self.worldW, maxGx), math.min(self.worldH, maxGy))
    love.graphics.setColor(1, 1, 1, 0.55)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", vx1, vy1, vx2 - vx1, vy2 - vy1)

    -- Ports we've discovered: a town-coloured pip with a dark surround.
    for _, port in ipairs(world.ports) do
        if self.fog:pointRevealed(port.x, port.y) then
            local mx, my = toScreen(port.x, port.y)
            local pc = port.color
            love.graphics.setColor(0, 0, 0, 0.7)
            love.graphics.rectangle("fill", mx - 3, my - 3, 6, 6)
            love.graphics.setColor(pc[1], pc[2], pc[3])
            love.graphics.rectangle("fill", mx - 2, my - 2, 4, 4)
        end
    end

    -- Mission target: a pulsing ring on the destination town, echoing the big
    -- in-world arrow so a non-reader can see "go there" on the map too.
    local m = world.boat.cargo[1]
    if m then
        local port = world:portById(m.toId)
        if port and self.fog:pointRevealed(port.x, port.y) then
            local mx, my = toScreen(port.x, port.y)
            local pr = 6 + math.sin(love.timer.getTime() * 4) * 2
            love.graphics.setColor(m.color[1], m.color[2], m.color[3], 0.95)
            love.graphics.setLineWidth(2)
            love.graphics.circle("line", mx, my, pr)
            love.graphics.setLineWidth(1)
        end
    end

    -- Treasure chests: a pulsing white X for mapped, un-found chests (where the
    -- gold arrow leads); a small gold pip for ones already collected.
    if world.treasures then
        local t = love.timer.getTime()
        for _, tr in ipairs(world.treasures) do
            local mx, my = toScreen(tr.x, tr.y)
            if tr.found then
                love.graphics.setColor(c.gold)
                love.graphics.circle("fill", mx, my, 2.5)
            elseif world.mapped and world.mapped[tr.id] then
                local r = 4 + math.sin(t * 5) * 1.2
                love.graphics.setColor(0, 0, 0, 0.7)
                love.graphics.setLineWidth(3)
                love.graphics.line(mx - r, my - r, mx + r, my + r)
                love.graphics.line(mx - r, my + r, mx + r, my - r)
                love.graphics.setColor(1, 1, 1)
                love.graphics.setLineWidth(1.5)
                love.graphics.line(mx - r, my - r, mx + r, my + r)
                love.graphics.line(mx - r, my + r, mx + r, my - r)
                love.graphics.setLineWidth(1)
            end
        end
    end

    -- The boat: a bright dot with a pulsing gold ring so it's easy to spot.
    local bx, by = toScreen(world.boat.x, world.boat.y)
    local ring = 5 + math.sin(love.timer.getTime() * 4) * 1.5
    love.graphics.setColor(c.gold[1], c.gold[2], c.gold[3], 0.9)
    love.graphics.setLineWidth(2)
    love.graphics.circle("line", bx, by, ring)
    love.graphics.setLineWidth(1)
    love.graphics.setColor(0, 0, 0, 0.85)
    love.graphics.circle("fill", bx, by, 4)
    love.graphics.setColor(1, 1, 1)
    love.graphics.circle("fill", bx, by, 2.5)

    love.graphics.setScissor()
    love.graphics.setColor(1, 1, 1)
end

return Minimap
