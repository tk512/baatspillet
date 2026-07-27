-- src/ui/minimap.lua
-- A Civilization-style world map in the top-right corner: a small top-down view
-- of the whole ocean, revealed only where you've sailed. It shares the fog grid
-- with the fog-of-war (so "explored" means the same thing on the map as in the
-- world) and bakes the revealed terrain into one texture, repainting only the
-- cells that newly light up -- no per-frame terrain scan, no per-frame allocs.
--
-- The map is drawn in the SAME isometric projection as the world, so it comes
-- out as a diamond rather than a rectangle. That is deliberate and worth
-- keeping: when the map was a straight top-down scaling (x = gx, y = gy) it
-- disagreed with the view by a 45-degree rotation, so a child who looked at the
-- map, decided the chest was "up and to the left", and then sailed that way on
-- screen went somewhere else entirely. Up on this map is now up in the world.
--
-- Everything therefore goes through Iso.project, exactly like the world does --
-- the texture (drawn rotated + squashed), the port pips, the treasure X's, the
-- boat and the camera viewport.

local config = require("src.config")
local utf8  = require("utf8")
local Iso   = require("src.systems.iso")
local Scale = require("src.ui.scale")
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

-- Push a closed polygon outward by `m`, the way a mitred picture frame goes
-- round a painting: every EDGE moves along its own normal and neighbouring
-- edges are re-intersected. At a sharp corner that intersection lands well
-- beyond the original vertex -- which is exactly the long point a real frame
-- has where two mitred lengths meet, and what the map's east/west corners were
-- missing when the frame was a stroked path (a stroke can only flat-cut or
-- spike there). Offsetting the VERTICES instead does not work at all: see the
-- note in draw().
local function offsetPolygon(pts, m)
    local n = #pts / 2
    local cx, cy = 0, 0
    for k = 1, #pts, 2 do cx = cx + pts[k]; cy = cy + pts[k + 1] end
    cx, cy = cx / n, cy / n

    local px, py, dx, dy = {}, {}, {}, {}
    for i = 1, n do
        local j = (i % n) + 1
        local ax, ay = pts[i * 2 - 1], pts[i * 2]
        local bx, by = pts[j * 2 - 1], pts[j * 2]
        local ex, ey = bx - ax, by - ay
        local len = math.sqrt(ex * ex + ey * ey)
        ex, ey = ex / len, ey / len
        local nx, ny = -ey, ex                       -- one of the two normals...
        local mx, my = (ax + bx) * 0.5, (ay + by) * 0.5
        if (mx + nx - cx) ^ 2 + (my + ny - cy) ^ 2 < (mx - cx) ^ 2 + (my - cy) ^ 2 then
            nx, ny = -nx, -ny                        -- ...the one pointing outward
        end
        px[i], py[i] = ax + nx * m, ay + ny * m
        dx[i], dy[i] = ex, ey
    end

    local out = {}
    for i = 1, n do
        local a = ((i - 2) % n) + 1                  -- the edge arriving at vertex i
        local cross = dx[a] * dy[i] - dy[a] * dx[i]
        if math.abs(cross) < 1e-9 then               -- parallel: no miter to find
            out[i * 2 - 1], out[i * 2] = px[i], py[i]
        else
            local tx, ty = px[i] - px[a], py[i] - py[a]
            local tt = (tx * dy[i] - ty * dx[i]) / cross
            out[i * 2 - 1] = px[a] + dx[a] * tt
            out[i * 2] = py[a] + dy[a] * tt
        end
    end
    return out
end

-- The map diamond's four corners: the world's four corners, projected. Not
-- symmetric -- a 12000x8000 world puts the top vertex 40% across and the bottom
-- at 60%. Given in a box iw x ih with its origin at (0, 0).
local function diamond(iw, ih, worldW, worldH)
    local fx = worldH / (worldW + worldH)
    local fy = worldH / (worldW + worldH)
    return { iw * fx, 0,                 -- top    = world (0, 0)
             iw, ih * (1 - fy),          -- right  = world (W, 0)
             iw * (1 - fx), ih,          -- bottom = world (W, H)
             0, ih * fy }                -- left   = world (0, H)
end

-- Where the map plaque sits, as PURE geometry (no drawing). The HUD reads this
-- to keep the shelf clear of the map, and re-deriving the sizing rule over
-- there would guarantee the two drift apart the first time either is tweaked.
-- Also hands back the frame polygons so draw() can't disagree with the space
-- reserved for them -- a mitred corner reaches further out than the band width,
-- so the padding has to come from the actual geometry, not a guess.
function Minimap:layout()
    local sw = love.graphics.getWidth()
    local t  = math.max(2, math.floor(self.world.game.fonts.small:getHeight() * 0.20))
    -- A touch bigger than the old rectangular map: the diamond is 2:1 so it's
    -- shorter than the 3:2 rectangle was, and the width buys back legibility
    -- without costing the height we just saved.
    local iw = Scale.phone and math.floor(math.max(160, math.min(215, sw * 0.17)))
        or math.floor(math.max(200, math.min(300, sw * 0.21)))
    -- The iso diamond's aspect is SX:SY (2:1), NOT the world's w:h -- projecting
    -- a rectangle 45 degrees always yields a 2:1 diamond however long the world
    -- is. Handily that's shorter than the old 3:2, which buys back height on a
    -- phone.
    local ih = math.floor(iw * Iso.SY / Iso.SX)
    local band = math.max(2, t * 1.3)                  -- wooden surround, per side

    local inner = diamond(iw, ih, self.worldW, self.worldH)
    local outer = offsetPolygon(inner, band)
    local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
    for k = 1, #outer, 2 do
        minX = math.min(minX, outer[k]);     maxX = math.max(maxX, outer[k])
        minY = math.min(minY, outer[k + 1]); maxY = math.max(maxY, outer[k + 1])
    end
    local padL, padT = math.ceil(-minX) + 1, math.ceil(-minY) + 1
    local outerW = math.ceil(maxX) + padL + 1
    local outerH = math.ceil(maxY) + padT + 1

    -- 8px from the screen edge, not 16: the frame reads as part of the border.
    return sw - 8 - outerW, 8, outerW, outerH, iw, ih, t, band, padL, padT,
           inner, outer
end

function Minimap:draw()
    local world = self.world
    local fonts = world.game.fonts
    local c     = config.colors
    local sw    = love.graphics.getWidth()

    -- Frame: a wooden DIAMOND that follows the map, not a rectangle with the
    -- map sitting inside it leaving four empty corners.
    local ox, oy, outerW, outerH, iw, ih, t, band, padL, padT, dInner, dOuter
        = self:layout()
    local ix, iy = ox + padL, oy + padT

    -- Iso space for the whole world is a diamond spanning
    --   x: -worldH*SX .. worldW*SX      y: 0 .. (worldW+worldH)*SY
    -- so shift x by worldH*SX to start at zero, then scale that box into the well.
    local SX, SY = Iso.SX, Iso.SY
    local dw, dh = (self.worldW + self.worldH) * SX, (self.worldW + self.worldH) * SY
    local kx, ky = iw / dw, ih / dh
    local x0 = self.worldH * SX

    local function toScreen(gx, gy)
        return ix + ((gx - gy) * SX + x0) * kx, iy + ((gx + gy) * SY) * ky
    end

    -- Frame polygons come from layout() (so the reserved space and the drawing
    -- can't disagree); shift them from box-local into screen coords.
    local inner, outer = {}, {}
    for k = 1, 8, 2 do
        inner[k], inner[k + 1] = ix + dInner[k], iy + dInner[k + 1]
        outer[k], outer[k + 1] = ix + dOuter[k], iy + dOuter[k + 1]
    end

    -- Wooden surround: a filled MITRED ring (offsetPolygon above). Two earlier
    -- attempts were wrong in instructive ways -- pushing the four vertices
    -- diagonally left the shallow top/bottom edges with no frame at all, and a
    -- thick stroke had to flat-cut the sharp east/west corners, where a real
    -- mitred frame comes to a point.
    local W = Retro.WOOD
    love.graphics.setColor(0, 0, 0, 0.5)
    love.graphics.setLineWidth(2)
    love.graphics.polygon("line", outer)               -- silhouette
    love.graphics.setLineWidth(1)
    love.graphics.setColor(W.face)
    love.graphics.polygon("fill", outer)               -- the plank
    love.graphics.setColor(W.deep)                     -- the well behind the map
    love.graphics.polygon("fill", inner)

    -- The explored map itself, rotated into the diamond. LÖVE composes
    -- transforms outermost-first, so scale-then-rotate here means the texture is
    -- ROTATED first and squashed after -- which is exactly Iso.project written
    -- as a matrix: [SX,-SX; SY,SY] = diag(SX*root2, SY*root2) * rotate(45).
    -- (draw()'s own angle/scale arguments can't express this: they scale first.)
    local cell, SQ2 = self.fog.cell, math.sqrt(2)
    love.graphics.setColor(1, 1, 1)
    love.graphics.push()
    love.graphics.translate(ix + x0 * kx, iy)
    love.graphics.scale(kx, ky)
    love.graphics.scale(cell * SX * SQ2, cell * SY * SQ2)
    love.graphics.rotate(math.pi / 4)
    love.graphics.draw(self.tex, 0, 0)
    love.graphics.pop()

    -- Overlays stay inside the map well even when something sits at the edge.
    love.graphics.setScissor(ix, iy, iw, ih)

    -- Camera viewport: project the four SCREEN corners back to the ground and
    -- forward again through the map's projection. On an iso map that traces the
    -- true view (an upright rectangle), rather than the over-large bounding
    -- diamond that groundBounds() would give.
    local vw, vh = love.graphics.getWidth(), love.graphics.getHeight()
    local quad = {}
    for _, cr in ipairs({ { 0, 0 }, { vw, 0 }, { vw, vh }, { 0, vh } }) do
        local gx, gy = world.camera:screenToWorld(cr[1], cr[2])
        local px, py = toScreen(gx, gy)
        quad[#quad + 1] = px
        quad[#quad + 1] = py
    end
    love.graphics.setColor(1, 1, 1, 0.55)
    love.graphics.setLineWidth(1)
    love.graphics.polygon("line", quad)

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

    -- Bevel the wooden diamond, drawn last so it sits over the map's edge: the
    -- two upper faces catch the light, the two lower ones fall into shadow --
    -- the same raised-plank language Retro.plaque uses on the square panels.
    local function edge(a, b, col, wdt)
        love.graphics.setColor(col)
        love.graphics.setLineWidth(wdt)
        love.graphics.line(inner[a], inner[a + 1], inner[b], inner[b + 1])
    end
    local lw = math.max(1.5, t * 0.9)
    edge(7, 1, W.hi, lw)      -- left  -> top   (lit)
    edge(1, 3, W.hi, lw)      -- top   -> right (lit)
    edge(3, 5, W.lo, lw)      -- right -> bottom (shadow)
    edge(5, 7, W.lo, lw)      -- bottom -> left  (shadow)
    love.graphics.setLineWidth(1)

    -- "Båtspillet!" in the intro's rainbow letters, big and proud: starts at
    -- the map's left edge and dips into the map itself (fonts.normal is
    -- Scale.ui-driven, so it sizes itself correctly on iPhone/iPad too).
    do
        local f = fonts.big   -- big and proud; a little overflow is charm
        love.graphics.setFont(f)
        local label = "Båtspillet"
        local lx = ox + t * 2 + 4                    -- left-aligned on the plaque
        local base = 16 + t * 2 + f:getHeight() * 0.45   -- low enough that the top never clips (dipping into the map is fine)
        local tt = love.timer.getTime()
        local i = 0
        for _, code in utf8.codes(label) do
            i = i + 1
            local ch = utf8.char(code)
            local cw = f:getWidth(ch)
            local hue = 3.0 + i * 0.7 + tt * 0.6     -- the menu title's palette, becalmed
            local r = 0.6 + 0.4 * math.sin(hue)
            local g = 0.6 + 0.4 * math.sin(hue + 2.1)
            local b = 0.6 + 0.4 * math.sin(hue + 4.2)
            local bob = math.sin(tt * 2 + i * 0.5) * 1.2
            love.graphics.setColor(0, 0, 0, 0.65)    -- strong shadow: legible over the map
            love.graphics.print(ch, lx + 2, base + bob + 2, 0, 1, 1, 0, f:getHeight())
            love.graphics.setColor(r, g, b)
            love.graphics.print(ch, lx, base + bob, 0, 1, 1, 0, f:getHeight())
            lx = lx + cw
        end
    end

    love.graphics.setColor(1, 1, 1)
end

return Minimap
