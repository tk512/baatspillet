-- src/systems/terrain.lua
-- Procedural isometric tilemap: water / sand / grass / rock tiles with curvy
-- coastlines, plus a discrete-plateau heightfield for visual mountains. Tiles
-- draw a PNG from assets/tiles/<type>.png when present, else code art.

local config = require("src.config")
local Iso    = require("src.systems.iso")
local Assets = require("src.assets")
local Loader = require("src.systems.loader")

local Terrain = {}
Terrain.__index = Terrain

-- Deterministic value noise (stable per seed).
local function hashf(x, y, seed)
    local s = math.sin(x * 12.9898 + y * 78.233 + seed * 0.1357) * 43758.5453
    return s - math.floor(s)
end
local function smooth(t) return t * t * (3 - 2 * t) end
local function valueNoise(x, y, seed)
    local x0, y0 = math.floor(x), math.floor(y)
    local fx, fy = smooth(x - x0), smooth(y - y0)
    local a = hashf(x0, y0, seed);     local b = hashf(x0 + 1, y0, seed)
    local c = hashf(x0, y0 + 1, seed); local d = hashf(x0 + 1, y0 + 1, seed)
    return a + (b - a) * fx + (c - a) * fy + (a - b - c + d) * fx * fy
end
local function fbm(x, y, seed)
    local v, amp, freq, norm = 0, 1, 1, 0
    for _ = 1, 4 do
        v = v + valueNoise(x * freq, y * freq, seed) * amp
        norm = norm + amp; amp = amp * 0.5; freq = freq * 2
    end
    return v / norm
end

function Terrain.new(ports)
    local self = setmetatable({}, Terrain)
    local T = config.TILE
    self.nx = math.ceil(config.WORLD_WIDTH  / T)
    self.ny = math.ceil(config.WORLD_HEIGHT / T)
    self.time = 0
    self.props = {}
    self.islandCenters = {}

    self._ports = ports
    self:generateLand()          -- corner land/water flags (irregular coasts)
    self:snapPorts(ports)        -- place ports on the coast + mark their pads
    self:classifyTiles()         -- water / sand / grass / rock per tile
    self:buildShoreDist()        -- corner→waterline distances (the beach band)
    self:buildHeightfield()      -- per-tile elevation level
    self:scatterProps()
    self:buildCoastMesh()
    self:buildLandMesh()
    self:buildRoadMesh()         -- country roads between neighbouring houses

    for i, isl in ipairs(config.ISLANDS) do
        self.islandCenters[i] = { x = isl.x, y = isl.y, radius = isl.radius, id = "island" .. i }
    end
    return self
end

-- Corner grid: 1 = land, 0 = sea. Island masks set the broad shape; noise
-- perturbs the edge so coastlines are irregular rather than circular.
function Terrain:generateLand()
    local T = config.TILE
    local seed = config.WORLD_SEED
    self.corner = {}
    for ci = 1, self.nx + 1 do
        self.corner[ci] = {}
        local gx = (ci - 1) * T
        Loader.tick()
        for cj = 1, self.ny + 1 do
            local gy = (cj - 1) * T
            local mask = 0
            for _, isl in ipairs(config.ISLANDS) do
                local dx, dy = gx - isl.x, gy - isl.y
                local d = math.sqrt(dx * dx + dy * dy) / isl.radius
                if d < 1 then mask = math.max(mask, smooth(1 - d)) end
            end
            local edge = (fbm(gx / config.COAST_SCALE, gy / config.COAST_SCALE, seed) - 0.5) * 2
            self.corner[ci][cj] = (mask + edge * config.COAST_NOISE > config.LAND_THRESH) and 1 or 0
        end
    end
end

local function cornersAllZero(self, i, j)
    return self.corner[i][j] == 0 and self.corner[i + 1][j] == 0
       and self.corner[i + 1][j + 1] == 0 and self.corner[i][j + 1] == 0
end

-- Place each port on the nearest coastal land tile + record the build pad.
function Terrain:snapPorts(ports)
    local T = config.TILE
    self.buildMask = {}
    local function isLand(i, j) return not cornersAllZero(self, i, j) end
    local function isWaterT(i, j) return cornersAllZero(self, i, j) end

    for _, port in ipairs(ports) do
        local startI = math.max(2, math.min(self.nx - 5, math.floor(port.x / T)))
        local startJ = math.max(2, math.min(self.ny - 5, math.floor(port.y / T)))
        local best, bestD
        for r = 0, 60 do   -- wide search: islands are large, ports start inland
            for di = -r, r do
                for dj = -r, r do
                    if math.abs(di) == r or math.abs(dj) == r then
                        local i, j = startI + di, startJ + dj
                        if i >= 2 and j >= 2 and i <= self.nx - 4 and j <= self.ny - 4 and isLand(i, j) then
                            if isWaterT(i + 1, j) or isWaterT(i - 1, j)
                               or isWaterT(i, j + 1) or isWaterT(i, j - 1) then
                                local d = di * di + dj * dj
                                if not bestD or d < bestD then bestD, best = d, { i, j } end
                            end
                        end
                    end
                end
            end
            if best then break end
        end
        best = best or { startI, startJ }

        local w, h = port.w, port.h
        local i0 = math.min(math.max(1, best[1] - 1), self.nx - w)
        local j0 = math.min(math.max(1, best[2] - 1), self.ny - h)

        -- force the footprint to solid land + flag it (flat, no props)
        for ci = i0, i0 + w do for cj = j0, j0 + h do self.corner[ci][cj] = 1 end end
        for i = i0, i0 + w - 1 do
            self.buildMask[i] = self.buildMask[i] or {}
            for j = j0, j0 + h - 1 do self.buildMask[i][j] = true end
        end

        local cx = (i0 - 1 + w / 2) * T
        local cy = (j0 - 1 + h / 2) * T
        local function waterAt(gx, gy)
            local ti = math.max(1, math.min(self.nx, math.floor(gx / T) + 1))
            local tj = math.max(1, math.min(self.ny, math.floor(gy / T) + 1))
            return cornersAllZero(self, ti, tj)
        end
        local sdx, sdy = 0, 0
        for _, dir in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
            if waterAt(cx + dir[1] * T * (w + 1), cy + dir[2] * T * (h + 1)) then
                sdx, sdy = sdx + dir[1], sdy + dir[2]
            end
        end
        if sdx == 0 and sdy == 0 then sdy = 1 end
        local mag = math.sqrt(sdx * sdx + sdy * sdy)
        local ux, uy = sdx / mag, sdy / mag
        port:placeAt(i0, j0, cx, cy, 0, ux, uy)  -- buildZ = 0 (flat)

        -- Dock point: step out from the harbour centre along the sea direction
        -- to the FIRST water tile (then a touch further), so the boat has a real
        -- spot in the water to pull up to. Stored on the port for isBoatInRange.
        local dockX, dockY = cx + ux * T, cy + uy * T
        for s = 1, 40 do
            local gx, gy = cx + ux * T * 0.5 * s, cy + uy * T * 0.5 * s
            if waterAt(gx, gy) then
                dockX, dockY = gx + ux * T * 0.6, gy + uy * T * 0.6
                break
            end
        end
        port.dockX, port.dockY = dockX, dockY
    end
end

-- Combined island-mask value at a world point (1 at a centre, 0 past the
-- radius). The shape that carved the islands, reused to raise elevation toward
-- each island's middle.
-- Which island "owns" this spot: the one contributing most mask here, or nil
-- over open water and unclaimed land. Everything that varies per island (biome,
-- and whether it's a remote wilderness) reads from this one lookup.
function Terrain:islandAt(gx, gy)
    local best, owner = 0, nil
    for _, isl in ipairs(config.ISLANDS) do
        local dx, dy = gx - isl.x, gy - isl.y
        local d = math.sqrt(dx * dx + dy * dy) / isl.radius
        if d < 1 and (1 - d) > best then
            best, owner = 1 - d, isl
        end
    end
    return owner
end

-- Biome of the owning island; unclaimed ground is "green" (the Norge baseline).
function Terrain:biomeAt(gx, gy)
    local isl = self:islandAt(gx, gy)
    return (isl and isl.biome) or "green"
end

-- A REMOTE island (maps.lua `remote = true`) grows no countryside houses, so it
-- stays wilderness: forest, rock and coast, with no scattered farms and — since
-- the country roads link neighbouring houses — no roads either. Sailing past one
-- should feel like nobody lives there.
function Terrain:isRemoteAt(gx, gy)
    local isl = self:islandAt(gx, gy)
    return isl ~= nil and isl.remote == true
end

function Terrain:islandMask(gx, gy)
    local m = 0
    for _, isl in ipairs(config.ISLANDS) do
        local dx, dy = gx - isl.x, gy - isl.y
        local d = math.sqrt(dx * dx + dy * dy) / isl.radius
        if d < 1 then
            local s = smooth(1 - d)
            if s > m then m = s end
        end
    end
    return m
end

-- Discrete-plateau terrain. Each full-land tile gets an integer level from a
-- smooth field (large contiguous plateaus). A corner's height is the average of
-- its touching tile levels x STEP, so plateau interiors stay flat and only
-- boundary tiles ramp up one level: no bumps, no walls.
-- tile.level = plateau level; cz[ci][cj] = corner height; tile.z = avg height.
function Terrain:buildHeightfield()
    local T = config.TILE
    local M = config.MOUNTAINS
    local seed = config.WORLD_SEED

    for i = 1, self.nx do
        Loader.tick()
        for j = 1, self.ny do
            local tile = self.tiles[i][j]
            tile.level = 0
            if (not tile.water) and tile.land >= 4 and not tile.build then
                local cx, cy = (i - 0.5) * T, (j - 0.5) * T
                local mask = self:islandMask(cx, cy)
                local shape = (mask - config.LAND_THRESH) / (1 - config.LAND_THRESH) -- 0 coast .. 1 centre
                if shape < 0 then shape = 0 end
                local n = fbm(cx / M.NOISE_SCALE, cy / M.NOISE_SCALE, seed + 300)
                -- shape tapers to 0 at the coast; noise terraces the interior
                local h = shape * (0.5 + 0.85 * n)
                if h > 1 then h = 1 end
                tile.level = math.floor(h * M.MAX_LEVEL + 0.001)
            end
        end
    end

    -- flatten the tiles in a disc around each town (level 0)
    for _, port in ipairs(self._ports or {}) do
        local R = M.FLATTEN_R
        for di = -R, R do
            for dj = -R, R do
                if di * di + dj * dj <= R * R then
                    local row = self.tiles[port.tx + di]
                    local tl = row and row[port.ty + dj]
                    if tl then tl.level = 0 end
                end
            end
        end
    end

    -- corner height = average of the (up to 4) touching tile levels x STEP
    local function tlvl(i, j)
        local row = self.tiles[i]; local t = row and row[j]
        return (t and t.level) or 0
    end
    -- A corner touching the flat beach strip (coastal tile), open water or the
    -- map edge is PINNED to sea level. The beach/water tiles are drawn flat at
    -- z=0 (coastMesh / water base), so a lifted shared corner would hoist the
    -- land mesh's edge off them and expose the blue clear color underneath as
    -- long triangular gaps. Pinning makes the land always rise from BEHIND the
    -- beach, and the two meshes meet exactly.
    local function flatTile(i, j)
        local row = self.tiles[i]; local t = row and row[j]
        return (not t) or t.water or t.land < 4
    end
    self.cz = {}
    for ci = 1, self.nx + 1 do
        self.cz[ci] = {}
        Loader.tick()
        for cj = 1, self.ny + 1 do
            if flatTile(ci - 1, cj - 1) or flatTile(ci, cj - 1)
                or flatTile(ci - 1, cj) or flatTile(ci, cj) then
                self.cz[ci][cj] = 0
            else
                local s = tlvl(ci - 1, cj - 1) + tlvl(ci, cj - 1) + tlvl(ci - 1, cj) + tlvl(ci, cj)
                self.cz[ci][cj] = (s * 0.25) * M.STEP
            end
        end
    end

    -- per-tile average height (props / fog)
    for i = 1, self.nx do
        for j = 1, self.ny do
            self.tiles[i][j].z =
                (self.cz[i][j] + self.cz[i + 1][j] + self.cz[i + 1][j + 1] + self.cz[i][j + 1]) * 0.25
        end
    end
end

-- Height (world-units) of a grid corner / a tile's average (0 out of range).
function Terrain:cornerZ(ci, cj)
    local row = self.cz and self.cz[ci]
    return (row and row[cj]) or 0
end
function Terrain:tileZ(i, j)
    local row = self.tiles[i]
    local t = row and row[j]
    return (t and t.z) or 0
end

-- Classify each tile from its corner land flags + a land-cover noise.
function Terrain:classifyTiles()
    local T = config.TILE
    local seed = config.WORLD_SEED
    self.tiles = {}
    for i = 1, self.nx do
        self.tiles[i] = {}
        Loader.tick()
        for j = 1, self.ny do
            local land = self.corner[i][j] + self.corner[i + 1][j]
                       + self.corner[i + 1][j + 1] + self.corner[i][j + 1]
            local build = self.buildMask and self.buildMask[i] and self.buildMask[i][j]
            local tile = { land = land, build = build or false }

            if land == 0 then
                tile.type, tile.water = "water", true
            elseif land < 4 then
                tile.type, tile.water = "sand", false   -- coastline (curvy beach)
            else
                local cx, cy = (i - 0.5) * T, (j - 0.5) * T
                local cover = fbm(cx / config.COVER_SCALE, cy / config.COVER_SCALE, seed + 11)
                tile.type, tile.water = (cover > config.ROCK_THRESH) and "rock" or "grass", false
            end
            if tile.build then tile.type, tile.water = "grass", false end
            tile.biome = self:biomeAt((i - 0.5) * T, (j - 0.5) * T)
            tile.tint = 1 + (((i * 17 + j * 29) % 5) - 2) * 0.02
            self.tiles[i][j] = tile
        end
    end
    for i = 1, self.nx do
        for j = 1, self.ny do
            local t = self.tiles[i][j]
            if t.water then t.shallow = self:hasLandNeighbor(i, j) end
        end
    end
end

-- Chamfer distance (in corner steps, capped at 3) from every grid corner to the
-- nearest sea corner: the "how far inland am I" field that drives the dithered
-- sand→grass band (isBeach). Two forward/backward sweeps are exact here because
-- the cap is tiny.
function Terrain:buildShoreDist()
    local sd = {}
    for ci = 1, self.nx + 1 do
        sd[ci] = {}
        for cj = 1, self.ny + 1 do
            sd[ci][cj] = (self.corner[ci][cj] == 0) and 0 or 9
        end
    end
    local function relax(ci, cj, di, dj, cost)
        local row = sd[ci + di]
        local v = row and row[cj + dj]
        if v and v + cost < sd[ci][cj] then sd[ci][cj] = v + cost end
    end
    for _ = 1, 2 do
        for ci = 1, self.nx + 1 do
            Loader.tick()
            for cj = 1, self.ny + 1 do
                relax(ci, cj, -1, 0, 1);    relax(ci, cj, 0, -1, 1)
                relax(ci, cj, -1, -1, 1.4); relax(ci, cj, 1, -1, 1.4)
                if sd[ci][cj] > 3 then sd[ci][cj] = 3 end
            end
        end
        for ci = self.nx + 1, 1, -1 do
            Loader.tick()
            for cj = self.ny + 1, 1, -1 do
                relax(ci, cj, 1, 0, 1);    relax(ci, cj, 0, 1, 1)
                relax(ci, cj, 1, 1, 1.4);  relax(ci, cj, -1, 1, 1.4)
                if sd[ci][cj] > 3 then sd[ci][cj] = 3 end
            end
        end
    end
    self.shoreD = sd
end

-- Bilinear corner height at a world point (the land mesh's smooth surface).
function Terrain:heightAt(gx, gy)
    local T = config.TILE
    local ci, cj = gx / T + 1, gy / T + 1
    local i0 = math.max(1, math.min(self.nx, math.floor(ci)))
    local j0 = math.max(1, math.min(self.ny, math.floor(cj)))
    local fx, fy = ci - i0, cj - j0
    local a, b = self.cz[i0][j0], self.cz[i0 + 1][j0]
    local c, d = self.cz[i0][j0 + 1], self.cz[i0 + 1][j0 + 1]
    local top = a + (b - a) * fx
    local bot = c + (d - c) * fx
    return top + (bot - top) * fy
end

-- Bilinear shore distance at a world point (0 right at the waterline).
function Terrain:shoreDistAt(gx, gy)
    local T = config.TILE
    local ci, cj = gx / T + 1, gy / T + 1
    local i0 = math.max(1, math.min(self.nx, math.floor(ci)))
    local j0 = math.max(1, math.min(self.ny, math.floor(cj)))
    local fx, fy = ci - i0, cj - j0
    local a, b = self.shoreD[i0][j0], self.shoreD[i0 + 1][j0]
    local c, d = self.shoreD[i0][j0 + 1], self.shoreD[i0 + 1][j0 + 1]
    local top = a + (b - a) * fx
    local bot = c + (d - c) * fx
    return top + (bot - top) * fy
end

-- Is the ground at (gx,gy) beach sand (true) or grass (false)? Solid sand near
-- the waterline, solid grass inland, and a speckled per-pixel dither in the
-- band between (config.BEACH), so the sand→grass edge frays naturally instead
-- of tracing the tile diamonds. Used by BOTH ground meshes at bake time.
function Terrain:isBeach(gx, gy)
    local B = config.BEACH
    local s = self:shoreDistAt(gx, gy)
        + (fbm(gx / 55, gy / 55, config.WORLD_SEED + 40) - 0.5) * B.WOBBLE
    if s < B.INNER then return true end
    if s >= B.OUTER then return false end
    return hashf(gx * 0.37, gy * 0.37, config.WORLD_SEED + 77)
        < (B.OUTER - s) / (B.OUTER - B.INNER)
end

function Terrain:hasLandNeighbor(i, j)
    for di = -1, 1 do for dj = -1, 1 do
        local n = self.tiles[i + di] and self.tiles[i + di][j + dj]
        if n and not n.water then return true end
    end end
    return false
end

function Terrain:scatterProps()
    local T = config.TILE
    local seed = config.WORLD_SEED
    for i = 1, self.nx do
        Loader.tick()
        for j = 1, self.ny do
            local t = self.tiles[i][j]
            if not t.water and not t.build then
                local cx, cy = (i - 0.5) * T, (j - 0.5) * T
                if t.type == "grass" then
                    local bio = config.BIOMES[t.biome or "green"] or config.BIOMES.green
                    local f = fbm(cx / config.FOREST_SCALE, cy / config.FOREST_SCALE, seed + 200)
                    if f > config.FOREST_THRESH + (bio.forest or 0) then
                        self.props[#self.props + 1] = { tx = i, ty = j, kind = "forest", z = 0,
                            salt = i * 131 + j * 977, biome = t.biome }
                    elseif bio.scrub and f > config.FOREST_THRESH + bio.scrub then
                        -- desert: cactus and low bushes where woods can't grow
                        self.props[#self.props + 1] = { tx = i, ty = j, kind = "scrub", z = 0,
                            salt = i * 131 + j * 977, biome = t.biome }
                    elseif (i * 31 + j * 7) % 13 == 0 and not self:isRemoteAt(cx, cy) then
                        self.props[#self.props + 1] = { tx = i, ty = j, kind = "house", z = 0 }
                    end
                end
            end
        end
    end
end

function Terrain:tileIndexAt(gx, gy)
    local T = config.TILE
    local i = math.max(1, math.min(self.nx, math.floor(gx / T) + 1))
    local j = math.max(1, math.min(self.ny, math.floor(gy / T) + 1))
    return i, j
end
function Terrain:isWater(gx, gy)
    local i, j = self:tileIndexAt(gx, gy)
    return self.tiles[i][j].water
end
function Terrain:update(dt) self.time = self.time + dt end

function Terrain:visibleRange(minGx, minGy, maxGx, maxGy)
    local T = config.TILE
    local i0 = math.max(1, math.floor(minGx / T) - 2)
    local j0 = math.max(1, math.floor(minGy / T) - 2)
    local i1 = math.min(self.nx, math.ceil(maxGx / T) + 2)
    local j1 = math.min(self.ny, math.ceil(maxGy / T) + 3)
    return i0, j0, i1, j1
end

-- Ground texture atlas: hand-drawn iso tile art (assets/tiles/gress/) baked
-- once into a mipmapped atlas. The land mesh UV-maps each flat tile's top
-- diamond onto a deterministic variant, so the whole ground still draws as
-- ONE textured mesh. Rocky, snowy and beach subcells sample the solid-white
-- cell instead (vertex colour alone), keeping today's cliffs/snow/dithered
-- beach. Missing art -> nil, and the mesh stays untextured (placeholder-first).
-- The art is NEUTRALIZED at build: each tile is normalized so its average
-- colour becomes even grey, and the land mesh's vertex colours (the game's
-- own palette + biome + snow + rock + shade pipeline) re-tint it — the art
-- is a pure detail layer, so it can never clash with the game's colours and
-- the dithered transitions to plain ground stay subtle. NORM sets the grey
-- level; the mesh multiplies vertex colours by 1/NORM to compensate.
local ATLAS_NORM = 0.8
local gressAtlas   -- nil = untried, false = art absent (cached across F6 regens)
local function groundAtlas()
    if gressAtlas ~= nil then return gressAtlas or nil end
    local names = {
        grass = { "grass1", "grass2", "grass3", "grass4", "grass5",
                  "grass6", "grass7", "grass8", "grass9", "grass10" },
        dirt  = { "dirt1", "dirt2", "dirt3", "dirt4" },
    }
    local CW, CH = 128, 64
    local list = {}
    for set, ns in pairs(names) do
        for _, n in ipairs(ns) do
            local ok, id = pcall(love.image.newImageData, "assets/tiles/gress/" .. n .. ".png")
            if ok and id then list[#list + 1] = { set = set, id = id } end
        end
    end
    if #list == 0 then gressAtlas = false; return nil end

    local cols = 4
    local rows = math.ceil((#list + 1) / cols)
    local AW, AH = cols * CW, rows * CH
    local cv = love.graphics.newCanvas(AW, AH)
    local prev = love.graphics.getCanvas()
    love.graphics.push("all")
    love.graphics.setCanvas(cv)
    love.graphics.origin()
    love.graphics.clear(0, 0, 0, 0)
    love.graphics.setColor(1, 1, 1)
    local out = { grass = {}, dirt = {} }
    local pad = 2                     -- inset against mipmap bleed between cells
    for k, e in ipairs(list) do
        local col = (k - 1) % cols
        local row = math.floor((k - 1) / cols)
        -- Only the block's TOP SURFACE goes into the atlas — the art also
        -- paints the block's soil thickness below it, which we never render.
        -- Measure the face's real quadrilateral: the outermost opaque columns
        -- are the side corners (their first opaque pixel = corner height),
        -- the centre columns give the top corner, and the bottom corner —
        -- hidden against the soil — follows by symmetry. Cropping that exact
        -- band keeps every soil pixel out of the atlas.
        local id = e.id
        local w, h = id:getDimensions()
        -- neutralize: average opaque colour -> ATLAS_NORM grey (per channel,
        -- so the art's own hue goes away and vertex colour brings the game's)
        local sr, sg, sb, n = 0, 0, 0, 0
        for y = 0, h - 1, 2 do
            for x = 0, w - 1, 2 do
                local r, g, b, a = id:getPixel(x, y)
                if a > 0.1 then sr, sg, sb, n = sr + r, sg + g, sb + b, n + 1
                end
            end
        end
        if n > 0 then
            local kr = ATLAS_NORM / math.max(0.05, sr / n)
            local kg = ATLAS_NORM / math.max(0.05, sg / n)
            local kb = ATLAS_NORM / math.max(0.05, sb / n)
            id:mapPixel(function(_, _, r, g, b, a)
                return math.min(1, r * kr), math.min(1, g * kg),
                    math.min(1, b * kb), a
            end)
        end
        local function firstOpaque(x)
            for y = 0, h - 1 do
                local _, _, _, a = id:getPixel(x, y)
                if a > 0.05 then return y end
            end
            return nil
        end
        local xL, yL, xR, yR
        for x = 0, w - 1 do
            yL = firstOpaque(x)
            if yL then xL = x; break end
        end
        for x = w - 1, 0, -1 do
            yR = firstOpaque(x)
            if yR then xR = x; break end
        end
        local yT = math.huge
        for x = math.floor(w / 2) - 2, math.floor(w / 2) + 2 do
            local y = firstOpaque(x)
            if y and y < yT then yT = y end
        end
        yT = yT + math.floor(w * 0.02)   -- grass tufts poke above the face; split the difference
        local mid = (yL + yR) / 2
        local yB = math.min(h - 1, mid + (mid - yT))
        local cw2 = xR - xL + 1
        local ch2 = math.max(1, math.floor(yB - yT + 1))
        local img = love.graphics.newImage(id)
        local q = love.graphics.newQuad(xL, yT, cw2, ch2, w, h)
        love.graphics.draw(img, q, col * CW, row * CH, 0, CW / cw2, CH / ch2)
        out[e.set][#out[e.set] + 1] = {
            (col * CW + pad) / AW, (row * CH + pad) / AH,
            (CW - 2 * pad) / AW, (CH - 2 * pad) / AH,
        }
    end
    local wk = #list                  -- the solid-white cell
    local wcol, wrow = wk % cols, math.floor(wk / cols)
    love.graphics.rectangle("fill", wcol * CW, wrow * CH, CW, CH)
    love.graphics.pop()
    love.graphics.setCanvas(prev)

    local id = love.graphics.readbackTexture and love.graphics.readbackTexture(cv)
        or cv:newImageData()
    local img = love.graphics.newImage(id, { mipmaps = true })
    img:setFilter("linear", "linear")
    img:setMipmapFilter("linear")
    id:release()
    cv:release()
    gressAtlas = { img = img, grass = out.grass, dirt = out.dirt,
        whiteX = (wcol * CW + CW / 2) / AW, whiteY = (wrow * CH + CH / 2) / AH }
    return gressAtlas
end

-- Draw a tile PNG (flat, centred, fit to TILE). Returns false if not present.
function Terrain:drawSprite(ttype, i, j)
    local img = Assets.image("tiles/" .. ttype .. ".png")
    if not img then return false end
    local T = config.TILE
    local sx, sy = Iso.project((i - 0.5) * T, (j - 0.5) * T, 0)
    local scale = T / img:getWidth()
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(img, sx, sy, 0, scale, scale, img:getWidth() / 2, img:getHeight() / 2)
    return true
end

function Terrain:drawTile(i, j)
    local tile = self.tiles[i][j]
    if tile.water then
        if not self:drawSprite("water", i, j) then self:drawWater(i, j, tile) end
    elseif tile.land < 4 then
        -- coastal: only the animated water base. The jagged land edge is baked
        -- into self.coastMesh. Full-land tiles are baked into self.landMesh.
        if not self:drawSprite("water", i, j) then self:drawWater(i, j, tile) end
    end
end

-- Bake the jagged, pixelized shoreline into one static mesh. Each coastal tile
-- is split into COAST_PIXELS^2 sub-cells; land/wet-sand/foam cells become little
-- iso-diamond quads. Land vs water per sub-cell = bilinear of the 4 tile corners
-- + world-space noise, so the coast frays irregularly and joins seamlessly
-- tile-to-tile.
function Terrain:buildCoastMesh()
    local T = config.TILE
    local N = config.COAST_PIXELS
    local sub = T / N
    local jag = config.COAST_JAGGED
    local seed = config.WORLD_SEED
    local foam = config.colors.foam
    local v = {}

    local function quad(gx, gy, r, g, b, a)
        local x1, y1 = Iso.project(gx, gy, 0)
        local x2, y2 = Iso.project(gx + sub, gy, 0)
        local x3, y3 = Iso.project(gx + sub, gy + sub, 0)
        local x4, y4 = Iso.project(gx, gy + sub, 0)
        v[#v + 1] = { x1, y1, 0, 0, r, g, b, a }
        v[#v + 1] = { x2, y2, 0, 0, r, g, b, a }
        v[#v + 1] = { x3, y3, 0, 0, r, g, b, a }
        v[#v + 1] = { x1, y1, 0, 0, r, g, b, a }
        v[#v + 1] = { x3, y3, 0, 0, r, g, b, a }
        v[#v + 1] = { x4, y4, 0, 0, r, g, b, a }
    end

    for i = 1, self.nx do
        Loader.tick()
        for j = 1, self.ny do
            local tile = self.tiles[i][j]
            if (not tile.water) and tile.land < 4 then
                local x0, y0 = (i - 1) * T, (j - 1) * T
                local lu = self.corner[i][j]
                local ru = self.corner[i + 1][j]
                local rd = self.corner[i + 1][j + 1]
                local ld = self.corner[i][j + 1]
                local fac = config.colors[tile.type] or config.colors.sand
                local bio = config.BIOMES[tile.biome or "green"] or config.BIOMES.green
                if bio.sand and tile.type == "sand" then
                    -- biome shoreline (frosted in snow, pale gold in desert)
                    fac = { top = bio.sand,
                            lip = { bio.sand[1] * 0.80, bio.sand[2] * 0.80, bio.sand[3] * 0.86 },
                            dot = bio.sand }
                end
                for a = 0, N - 1 do
                    for b = 0, N - 1 do
                        local u, vv = (a + 0.5) / N, (b + 0.5) / N
                        local top = lu + (ru - lu) * u
                        local bot = ld + (rd - ld) * u
                        local base = top + (bot - top) * vv
                        local gx, gy = x0 + (a + 0.5) * sub, y0 + (b + 0.5) * sub
                        -- Fray the coast only AT the waterline: the noise fades
                        -- out where the corners say "solidly land", so it can't
                        -- punch holes through the beach to the blue water base
                        -- behind the wet lip (no blue speckles inland).
                        local damp = 1 - math.min(1, math.max(0, (base - 0.55) / 0.25))
                        local val = base + (fbm(gx / 90, gy / 90, seed) - 0.5) * jag * damp
                        if val > 0.5 then
                            if val < 0.58 then                  -- wet sand at the edge
                                quad(x0 + a * sub, y0 + b * sub, fac.lip[1], fac.lip[2], fac.lip[3], 1)
                            else
                                local tint = 0.9 + 0.2 * fbm(gx / 35, gy / 35, seed + 7)
                                local dry = fac.top
                                -- dry ground above the wet lip: grass creeps into
                                -- the beach strip through the dithered band
                                -- (isBeach), so the sand→grass edge never traces
                                -- the tile diamonds. 0.96 ≈ flat-land lighting in
                                -- buildLandMesh, so the greens match across meshes.
                                if tile.type == "sand" and not self:isBeach(gx, gy) then
                                    dry = config.colors.grass.top
                                    tint = tint * 0.96
                                end
                                quad(x0 + a * sub, y0 + b * sub,
                                    dry[1] * tint, dry[2] * tint, dry[3] * tint, 1)
                            end
                        elseif val > 0.43 then                  -- foam/surf off the beach
                            local aF = (val - 0.43) / 0.07
                            quad(x0 + a * sub, y0 + b * sub, foam[1], foam[2], foam[3], 0.55 * aF)
                        end
                    end
                end
            end
        end
    end

    if #v > 0 then
        self.coastMesh = love.graphics.newMesh(v, "triangles", "static")
    end
end

-- Bake all full-land tiles into one static mesh at sub-tile pixel resolution.
-- Each tile is split into SUBPIX^2 cells, corner heights bilinearly interpolated
-- for a smooth surface, each cell coloured from its height + fine noise (grass ->
-- snow by height, rock on slopes). Shade + rockiness come from a per-cell
-- gradient of the smoothed height field (sampled across tile borders, noisy
-- threshold), so slopes fringe and dither instead of flipping per tile.
-- Emitted back-to-front (by i+j) so the mesh self-occludes.
function Terrain:buildLandMesh()
    local T = config.TILE
    local M = config.MOUNTAINS
    local seed = config.WORLD_SEED
    local N = M.SUBPIX or 6
    local v = {}
    local Lx, Ly, Lz = -0.45, -0.45, 0.77
    local grass = config.colors.grass.top
    local rock  = config.colors.rock.top
    local snow  = { 0.93, 0.95, 0.98 }
    local snowStart = (M.SNOW_LEVEL - 2) * M.STEP
    local snowFull  = M.SNOW_LEVEL * M.STEP

    -- granular material colour: ground->snow by height, with FINE per-pixel
    -- noise. Ground colour + snowline come from the tile's biome palette.
    local function material(z, gx, gy, gC, sSt, sFu)
        local n = fbm(gx / 21, gy / 21, seed + 900)       -- fine = pixel-scale grain
        local sa = (z - sSt) / math.max(1, sFu - sSt)
        if sa < 0 then sa = 0 elseif sa > 1 then sa = 1 end
        local f = 0.84 + 0.26 * n
        return (gC[1] + (snow[1] - gC[1]) * sa) * f,
               (gC[2] + (snow[2] - gC[2]) * sa) * f,
               (gC[3] + (snow[3] - gC[3]) * sa) * f
    end

    local function emit(gx, gy, z, r, g, b, tu, tv)
        local px, py = Iso.project(gx, gy, z)
        v[#v + 1] = { px, py, tu or 0, tv or 0, r, g, b, 1 }
    end

    -- Ground art: flat grass subcells UV into the atlas; everything else
    -- (rock, snow, beach, no art) samples its solid-white cell.
    local atlas = groundAtlas()
    local wx, wy = 0, 0
    if atlas then wx, wy = atlas.whiteX, atlas.whiteY end

    local order = {}
    for i = 1, self.nx do
        for j = 1, self.ny do
            local tile = self.tiles[i][j]
            if (not tile.water) and tile.land >= 4 then order[#order + 1] = { i, j } end
        end
    end
    table.sort(order, function(a, b) return (a[1] + a[2]) < (b[1] + b[2]) end)

    local sandTop = config.colors.sand.top
    local beachReach = config.BEACH.OUTER + config.BEACH.WOBBLE * 0.5
    local SD = T * 0.6   -- gradient sampling radius: crosses tile borders, so
                         -- slope (rock tint) and shade fringe smoothly instead
                         -- of switching per tile ("square" brown patches)

    for _, ij in ipairs(order) do
        Loader.tick()
        local i, j = ij[1], ij[2]
        local x0 = (i - 1) * T
        local y0 = (j - 1) * T
        -- Low, un-built tiles near the waterline can carry the beach's dithered
        -- sand edge (isBeach below); everything further inland skips the test.
        local tile = self.tiles[i][j]
        local sdMin = math.min(self.shoreD[i][j], self.shoreD[i + 1][j],
                               self.shoreD[i][j + 1], self.shoreD[i + 1][j + 1])
        -- (the per-subcell `cz < 5` gate below keeps the sand near sea level,
        -- so the band can climb the very FOOT of a shoreside ramp and stop)
        local beachable = not tile.build and sdMin < beachReach
        -- the tile's biome picks the palette for everything below
        local bio = config.BIOMES[tile.biome or "green"] or config.BIOMES.green
        local grassC = bio.grass or grass
        local rockC  = bio.rock or rock
        local sandC  = bio.sand or sandTop
        -- this tile's ground art variant (deterministic); desert uses the dirt
        -- set, snow stays plain (frozen ground reads better untextured)
        local cell
        if atlas and not tile.build then
            local set = (tile.biome == "desert") and atlas.dirt
                or (tile.biome ~= "snow") and atlas.grass or nil
            if set and #set > 0 then
                cell = set[1 + (i * 131 + j * 977) % #set]
            end
        end
        local sSt, sFu = snowStart, snowFull
        if bio.snowAt then
            sSt, sFu = (bio.snowAt - 2) * M.STEP, bio.snowAt * M.STEP
        elseif bio.snowless then
            sSt, sFu = 1e9, 1e9 + 1
        end
        local zA, zB = self.cz[i][j], self.cz[i + 1][j]      -- corners: A(0,0) B(1,0)
        local zC, zD = self.cz[i + 1][j + 1], self.cz[i][j + 1] --          C(1,1) D(0,1)
        local function H(u, w) return (zA + (zB - zA) * u) + ((zD + (zC - zD) * u) - (zA + (zB - zA) * u)) * w end

        for a = 0, N - 1 do
            for b = 0, N - 1 do
                local u0, u1 = a / N, (a + 1) / N
                local w0, w1 = b / N, (b + 1) / N
                local gx0, gx1 = x0 + u0 * T, x0 + u1 * T
                local gy0, gy1 = y0 + w0 * T, y0 + w1 * T
                local h00, h10 = H(u0, w0), H(u1, w0)
                local h11, h01 = H(u1, w1), H(u0, w1)
                local cz = H((u0 + u1) / 2, (w0 + w1) / 2)
                local cgx, cgy = (gx0 + gx1) / 2, (gy0 + gy1) / 2

                -- Per-PIXEL shade + rockiness from the smoothed height field
                -- (central differences over SD, sampled across tile borders):
                -- brown creeps around ramp edges organically, with a noisy
                -- threshold so the grass/sand→rock line dithers, never a
                -- clean tile-diamond switch. Flat ground can't rock up from
                -- the noise alone (slope 0 stays below the cut).
                local gdx = (self:heightAt(cgx + SD, cgy) - self:heightAt(cgx - SD, cgy)) / (2 * SD)
                local gdy = (self:heightAt(cgx, cgy + SD) - self:heightAt(cgx, cgy - SD)) / (2 * SD)
                local nl = math.sqrt(gdx * gdx + gdy * gdy + 1)
                local d = (-gdx * Lx - gdy * Ly + Lz) / nl; if d < 0 then d = 0 end
                local sh = 0.50 + 0.60 * d
                local slope = math.sqrt(gdx * gdx + gdy * gdy) / nl
                local rk = (slope + (fbm(cgx / 33, cgy / 33, seed + 500) - 0.5) * 0.10 - 0.05) / 0.18
                if rk < 0 then rk = 0 elseif rk > 1 then rk = 1 end

                local mr, mg, mb
                local sa = (cz - sSt) / math.max(1, sFu - sSt)
                local beach = beachable and cz < 5 and self:isBeach(cgx, cgy)
                if beach then
                    -- the beach reaches into this tile: sand, same grain noise
                    local n = fbm(cgx / 21, cgy / 21, seed + 900)
                    local f = 0.84 + 0.26 * n
                    mr, mg, mb = sandC[1] * f, sandC[2] * f, sandC[3] * f
                else
                    mr, mg, mb = material(cz, cgx, cgy, grassC, sSt, sFu)
                end
                mr = (mr + (rockC[1] - mr) * rk) * sh
                mg = (mg + (rockC[2] - mg) * rk) * sh
                mb = (mb + (rockC[3] - mb) * rk) * sh
                -- Flat open ground samples the (neutralized) art, re-tinted by
                -- these very colours — rocky/snowy/beach subcells stay on the
                -- white cell, and since both share one colour pipeline the
                -- rk/sa dither line between them is texture-only, not colour.
                local tex = cell and not beach and rk < 0.5 and sa < 0.35
                if not tex then
                    emit(gx0, gy0, h00, mr, mg, mb, wx, wy)
                    emit(gx1, gy0, h10, mr, mg, mb, wx, wy)
                    emit(gx1, gy1, h11, mr, mg, mb, wx, wy)
                    emit(gx0, gy0, h00, mr, mg, mb, wx, wy)
                    emit(gx1, gy1, h11, mr, mg, mb, wx, wy)
                    emit(gx0, gy1, h01, mr, mg, mb, wx, wy)
                else
                    -- compensate the atlas normalization (art mean = NORM grey)
                    local gain = 1 / ATLAS_NORM
                    mr = math.min(1, mr * gain)
                    mg = math.min(1, mg * gain)
                    mb = math.min(1, mb * gain)
                    -- the tile's (u,w) square maps onto the art diamond:
                    -- atlas x follows u-w, atlas y follows u+w
                    local ax, ay, aw, ah = cell[1], cell[2], cell[3], cell[4]
                    local u00x, u00y = ax + (u0 - w0 + 1) * 0.5 * aw, ay + (u0 + w0) * 0.5 * ah
                    local u10x, u10y = ax + (u1 - w0 + 1) * 0.5 * aw, ay + (u1 + w0) * 0.5 * ah
                    local u11x, u11y = ax + (u1 - w1 + 1) * 0.5 * aw, ay + (u1 + w1) * 0.5 * ah
                    local u01x, u01y = ax + (u0 - w1 + 1) * 0.5 * aw, ay + (u0 + w1) * 0.5 * ah
                    emit(gx0, gy0, h00, mr, mg, mb, u00x, u00y)
                    emit(gx1, gy0, h10, mr, mg, mb, u10x, u10y)
                    emit(gx1, gy1, h11, mr, mg, mb, u11x, u11y)
                    emit(gx0, gy0, h00, mr, mg, mb, u00x, u00y)
                    emit(gx1, gy1, h11, mr, mg, mb, u11x, u11y)
                    emit(gx0, gy1, h01, mr, mg, mb, u01x, u01y)
                end
            end
        end
    end
    if #v > 0 then
        self.landMesh = love.graphics.newMesh(v, "triangles", "static")
        if atlas then self.landMesh:setTexture(atlas.img) end
    end
end

-- Bake thin dirt "country roads" between neighbouring countryside houses into
-- one static mesh. Each drawn house links to its nearest drawn neighbour
-- (within ROADS.MAX_LINK); the path meanders a little (ends pinned on the
-- houses), drapes over the height field, and is dropped entirely if it would
-- cross water, a port pad or climb past the treeline. Purely decorative --
-- nothing drives on them (yet).
function Terrain:buildRoadMesh()
    local T = config.TILE
    local R = config.ROADS
    local seed = config.WORLD_SEED
    local dirt = config.colors.dirt
    local M = config.MOUNTAINS

    -- The same filter world.lua applies before drawing a house prop (solid
    -- land, below the treeline, off the pads), so every road really ends at a
    -- visible house.
    local function landAt(i, j)
        local row = self.tiles[i]; local t = row and row[j]
        return t and not t.water
    end
    local function houseDrawn(tx, ty)
        local t = self.tiles[tx] and self.tiles[tx][ty]
        if not t or t.water or t.build then return false end
        if (t.level or 0) >= M.TREELINE_LEVEL then return false end
        if self.buildMask[tx] and self.buildMask[tx][ty] then return false end
        return landAt(tx + 1, ty) and landAt(tx - 1, ty)
           and landAt(tx, ty + 1) and landAt(tx, ty - 1)
    end

    local houses = {}
    for _, p in ipairs(self.props) do
        if p.kind == "house" and houseDrawn(p.tx, p.ty) then
            houses[#houses + 1] = { x = (p.tx - 0.5) * T, y = (p.ty - 0.5) * T }
        end
    end
    if #houses < 2 then return end

    -- nearest neighbour per house, deduped: at most one path per pair
    local edges, seen = {}, {}
    for i = 1, #houses do
        Loader.tick()
        local best, bestD2
        for j = 1, #houses do
            if j ~= i then
                local dx = houses[j].x - houses[i].x
                local dy = houses[j].y - houses[i].y
                local d2 = dx * dx + dy * dy
                if not bestD2 or d2 < bestD2 then best, bestD2 = j, d2 end
            end
        end
        if best and bestD2 < R.MAX_LINK * R.MAX_LINK then
            local a, b = math.min(i, best), math.max(i, best)
            if not seen[a * 100000 + b] then
                seen[a * 100000 + b] = true
                edges[#edges + 1] = { houses[a], houses[b] }
            end
        end
    end

    -- Route one path: the straight line plus a noise meander (pinned at both
    -- ends), sampled every few units. Any bad sample (water, pad, too high)
    -- drops the whole path -- better no road than a road into the sea.
    local function route(A, B)
        local dx, dy = B.x - A.x, B.y - A.y
        local len = math.sqrt(dx * dx + dy * dy)
        if len < 30 then return end
        local px, py = -dy / len, dx / len
        local n = math.ceil(len / 9)
        local pts = {}
        for k = 0, n do
            local t = k / n
            local gx, gy = A.x + dx * t, A.y + dy * t
            local w = (fbm(gx / 70, gy / 70, seed + 600) - 0.5) * 2
                    * R.WOBBLE * math.sin(t * math.pi)
            gx, gy = gx + px * w, gy + py * w
            local ti, tj = self:tileIndexAt(gx, gy)
            local tile = self.tiles[ti][tj]
            if tile.water then return end
            if (tile.level or 0) >= M.TREELINE_LEVEL then return end
            if self.buildMask[ti] and self.buildMask[ti][tj] then return end
            pts[#pts + 1] = { gx, gy }
        end
        return pts
    end

    -- Two layers baked into one mesh: soft translucent "trodden verge" quads
    -- first, the pale track fill after (mesh triangles draw in order). The
    -- verge is dark earth at ~30% alpha, so it blends the track into the
    -- grass like worn ground -- not a hard black outline.
    local rim, fill = {}, {}
    local edgeC = config.colors.dirt_edge
    local function emit(arr, gx, gy, r, g, b, al)
        -- lifted a hair above the ground so it never z-fights the land mesh
        local sx, sy = Iso.project(gx, gy, self:heightAt(gx, gy) + 0.5)
        arr[#arr + 1] = { sx, sy, 0, 0, r, g, b, al }
    end
    local function strip(arr, ax, ay, bx, by, qx, qy, hw, r, g, b, al)
        emit(arr, ax + qx * hw, ay + qy * hw, r, g, b, al)
        emit(arr, ax - qx * hw, ay - qy * hw, r, g, b, al)
        emit(arr, bx - qx * hw, by - qy * hw, r, g, b, al)
        emit(arr, ax + qx * hw, ay + qy * hw, r, g, b, al)
        emit(arr, bx - qx * hw, by - qy * hw, r, g, b, al)
        emit(arr, bx + qx * hw, by + qy * hw, r, g, b, al)
    end

    -- One worn track along `pts` (shared by house paths and the ring roads).
    -- Long legs are chopped into ~14-unit chunks so width and tint wander and
    -- the occasional grassy break stays small: a track worn by feet and carts,
    -- not a painted line.
    local function emitPath(pts)
        for k = 1, #pts - 1 do
            local ax, ay = pts[k][1], pts[k][2]
            local bx, by = pts[k + 1][1], pts[k + 1][2]
            local ddx, ddy = bx - ax, by - ay
            local dl = math.sqrt(ddx * ddx + ddy * ddy)
            if dl > 1e-3 then
                local qx, qy = -ddy / dl, ddx / dl
                local nsub = math.ceil(dl / 14)
                for sgi = 0, nsub - 1 do
                    local x1, y1 = ax + ddx * (sgi / nsub), ay + ddy * (sgi / nsub)
                    local x2, y2 = ax + ddx * ((sgi + 1) / nsub), ay + ddy * ((sgi + 1) / nsub)
                    if hashf(x1 * 2.1, y1 * 2.1, seed + 640) <= 0.94 then  -- worn grassy breaks
                        local hw = R.WIDTH * (0.4 + 0.3 * hashf(x1, y1, seed + 610))
                        local f = 0.92 + 0.16 * hashf(x1 * 0.7, y1 * 0.7, seed + 620)
                        local rw = hw + 1.5 + 2.5 * hashf(x1 * 1.3, y1 * 1.3, seed + 630)
                        strip(rim, x1, y1, x2, y2, qx, qy, rw,
                            edgeC[1], edgeC[2], edgeC[3], 0.30 * f)
                        strip(fill, x1, y1, x2, y2, qx, qy, hw,
                            dirt[1] * f, dirt[2] * f, dirt[3] * f, 1)
                    end
                end
            end
        end
    end

    for _, e in ipairs(edges) do
        Loader.tick()
        local pts = route(e[1], e[2])
        if pts and #pts > 1 then emitPath(pts) end
    end

    -- A coast road around each island, just behind the beach. For every
    -- bearing from the island's centre we march inward to the OUTERMOST point
    -- comfortably past the sand (shoreDist >= RING_IN) -- so the road follows
    -- the real coastline shape, not a circle -- then smooth the radius so it
    -- flows. Stretches that would cross water, pads or high ground are simply
    -- left out: a ring with natural breaks beats a road forced through a fjord.
    for _, isl in ipairs(config.ISLANDS) do
        local nS = math.max(48, math.floor(isl.radius * math.pi * 2 / 70))
        local rad = {}
        for k = 0, nS - 1 do
            Loader.tick()
            local a = k / nS * math.pi * 2
            local ca, sa = math.cos(a), math.sin(a)
            for t = isl.radius * 1.25, isl.radius * 0.2, -14 do
                local gx, gy = isl.x + ca * t, isl.y + sa * t
                if gx > 0 and gy > 0 and gx < config.WORLD_WIDTH and gy < config.WORLD_HEIGHT
                    and self:shoreDistAt(gx, gy) >= R.RING_IN then
                    rad[k] = t
                    break
                end
            end
        end
        for _ = 1, 2 do    -- smooth: the road flows instead of stair-stepping
            local out = {}
            for k = 0, nS - 1 do
                local a, b, c = rad[(k - 1) % nS], rad[k], rad[(k + 1) % nS]
                out[k] = (a and b and c) and (a + 2 * b + c) * 0.25 or rad[k]
            end
            rad = out
        end
        local arc = {}
        local function flush()
            if #arc >= 5 then emitPath(arc) end
            arc = {}
        end
        for k = 0, nS do                    -- ..nS: a fully-valid ring closes
            local kk = k % nS
            local ok, gx, gy = false, nil, nil
            if rad[kk] then
                local a = kk / nS * math.pi * 2
                gx = isl.x + math.cos(a) * rad[kk]
                gy = isl.y + math.sin(a) * rad[kk]
                local ti, tj = self:tileIndexAt(gx, gy)
                local tile = self.tiles[ti][tj]
                ok = (not tile.water) and (tile.level or 0) < M.TREELINE_LEVEL
                    and not (self.buildMask[ti] and self.buildMask[ti][tj])
            end
            if ok then arc[#arc + 1] = { gx, gy } else flush() end
        end
        flush()
    end

    if #rim > 0 then
        for k = 1, #fill do rim[#rim + 1] = fill[k] end
        self.roadMesh = love.graphics.newMesh(rim, "triangles", "static")
    end
end

local function diamond(i, j)
    local T = config.TILE
    local x0, x1 = (i - 1) * T, i * T
    local y0, y1 = (j - 1) * T, j * T
    local ax, ay = Iso.project(x0, y0, 0)
    local bx, by = Iso.project(x1, y0, 0)
    local cx, cy = Iso.project(x1, y1, 0)
    local dx, dy = Iso.project(x0, y1, 0)
    return ax, ay, bx, by, cx, cy, dx, dy, x0, y0, x1, y1
end

function Terrain:drawWater(i, j, tile)
    local c = config.colors
    local ax, ay, bx, by, cx, cy, dx, dy, x0, y0 = diamond(i, j)
    love.graphics.setColor(tile.shallow and c.water_top or c.water_deep)
    love.graphics.polygon("fill", ax, ay, bx, by, cx, cy, dx, dy)
    local s = math.sin(self.time * 1.2 + (x0 + y0) * 0.010)
    if s > 0.65 then
        local mx, my = (ax + cx) / 2, (ay + cy) / 2
        love.graphics.setColor(c.wave[1], c.wave[2], c.wave[3], 0.07 * (s - 0.65))
        love.graphics.polygon("fill", mx, my - 5, mx + 12, my, mx, my + 5, mx - 12, my)
    end
end

return Terrain
