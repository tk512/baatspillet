-- The playable ocean scene: islands, ports, the boat, the cargo economy, the
-- camera and the HUD. Movement and collision are in the flat ground plane; only
-- drawing knows the iso projection, and objects and boat are depth-sorted so
-- the boat slips behind or in front of raised land.

local config       = require("src.config")
local Scale        = require("src.ui.scale")
local Profiler     = require("src.systems.profiler")
local Retro        = require("src.ui.retro")
local Assets       = require("src.assets")
local Iso          = require("src.systems.iso")
local Camera       = require("src.systems.camera")
local Terrain      = require("src.systems.terrain")
local Objects      = require("src.systems.objects")
local CargoSystem  = require("src.systems.cargo")
local Fleet        = require("src.systems.fleet")
local Fog          = require("src.systems.fog")
local Treasure     = require("src.systems.treasure")
local Loader       = require("src.systems.loader")
local Boat         = require("src.entities.boat")
local Port         = require("src.entities.port")
local Pirate       = require("src.entities.pirate")
local Shark        = require("src.entities.shark")
local Dolphins     = require("src.entities.dolphins")
local HUD          = require("src.ui.hud")
local Minimap      = require("src.ui.minimap")
local Album        = require("src.ui.album")
local MapReveal    = require("src.ui.mapreveal")
local WinScreen    = require("src.ui.winscreen")
local PortScreen   = require("src.ui.portscreen")
local Icons        = require("src.ui.icons")
local Pointer      = require("src.ui.pointer")
local ShipInfo     = require("src.ui.shipinfo")
local PauseMenu    = require("src.ui.pausemenu")

local World = {}

-- Chosen deterministically from the tile coords, so a map always looks the same
-- and F6 reproduces it.
local HOUSE_SPRITES = {
    "props/houses/house_1.png", "props/houses/house_2.png", "props/houses/house_3.png",
    "props/houses/house_4.png", "props/houses/house_5.png", "props/houses/house_6.png",
    "props/houses/house_7.png", "props/houses/house_8.png", "props/houses/house_9.png",
}
local function houseSprite(i, j)
    return HOUSE_SPRITES[(i * 7 + j * 13) % #HOUSE_SPRITES + 1]
end

-- Countryside houses: the brick house is weighted to be the common sight, with
-- a few cottages for variety. Deterministic per tile.
local COUNTRY_HOUSES = {
    "props/house.png", "props/house.png", "props/house.png", "props/house.png",
    "props/houses/house_1.png", "props/houses/house_2.png", "props/houses/house_7.png",
    "props/houses/house_8.png", "props/houses/house_9.png",
}

-- Farm districts. Countryside buildings land one tile in thirteen, so a lone
-- farm building would just read as an odd house. Hashing a COARSE 4x4 cell
-- instead makes every building inside one draw from the farm set, so a farm
-- arrives as a CLUSTER -- farmhouse, barn, silo, pig pen. The country roads
-- link neighbouring buildings, so farms get their tracks for free.
local FARM_SPRITES = {
    "props/farm/farmhouse.png", "props/farm/barn.png",
    "props/farm/silo.png", "props/farm/pigs.png",
}
local FARM_CELL   = 4    -- tiles per side of a farm district
local FARM_ODDS   = 5    -- one coarse cell in this many is farmland

-- Landmarks a town can be given in its ports file. Each is a CLUSTER on
-- consecutive tiles just past the built-up edge, so it reads as one
-- installation rather than three odd buildings.
local LANDMARKS = {
    airport = {
        "props/airport/tower.png",
        "props/airport/terminal.png",
        "props/airport/hangar.png",
    },
}

local function countryHouseSprite(i, j)
    local ci, cj = math.floor(i / FARM_CELL), math.floor(j / FARM_CELL)
    if (ci * 31 + cj * 17) % FARM_ODDS == 0 then
        return FARM_SPRITES[(i * 7 + j * 13) % #FARM_SPRITES + 1]
    end
    return COUNTRY_HOUSES[(i * 7 + j * 13) % #COUNTRY_HOUSES + 1]
end

-- Downtown blocks, chosen PER MAP: Norge gets modest Scandinavian ones, Amerika
-- real high-rises. Never collapse these into one list -- glass towers in a fjord
-- are wrong. Unknown maps fall back to `norge`.
local BLOCK_SETS = {
    norge = {
        "props/blocks/block_1.png", "props/blocks/block_2.png",
        "props/blocks/block_3.png", "props/blocks/block_4.png",
    },
    amerika = {},   -- filled below: us_1..21
}
for n = 1, 21 do
    BLOCK_SETS.amerika[n] = ("props/blocks/us_%d.png"):format(n)
end

local function blockSprite(i, j, set)
    local s = BLOCK_SETS[set] or BLOCK_SETS.norge
    return s[(i * 5 + j * 11) % #s + 1]
end

-- Tap box for firing at the pirate. Generous on purpose: a child aiming at a
-- moving ship needs slack, and a too-big box only means a tap beside the pirate
-- shoots instead of sailing -- which, that close, is what you meant.
local PIRATE_TAP_W = 60 * (config.PIRATE.LENGTH or 2.6)
local PIRATE_TAP_H = 95

function World:load(game)
    self.game    = game
    self.ms      = game:mapState()          -- THIS world's progress bucket
    self.camera  = Camera.new()
    if game.phone then self.camera.zoom = config.PHONE.CAMERA_ZOOM end
    self.panning = false
    self.toast   = { text = "", timer = 0, rise = 0 }

    -- created first, so terrain can snap them to coasts
    self.ports = {}
    for _, def in ipairs(game.data.ports) do
        self.ports[#self.ports + 1] = Port.new(def)
    end

    -- Build the procedurally heightmapped iso world (and place the ports).
    self.terrain = Terrain.new(self.ports)

    -- the boat chosen on the start screen, else the last unlocked
    local unlocked = game.state.unlockedBoats
    local boatDef  = game:getBoatDef(game.state.selectedBoat or unlocked[#unlocked])
    local sx, sy   = self:findStartWater(config.WORLD_WIDTH / 2, config.WORLD_HEIGHT / 2)
    self.boat = Boat.new(boatDef, sx, sy)
    self.boat.touchCoast = game.touchCamera   -- taps glide through their point
    self.boat.displayName = game:boatDisplayName(boatDef.id)      -- player's name for it

    -- Sprite-object layer: ports (3x3), props (1x1), ambient ships.
    self.objects = Objects.new()
    for _, port in ipairs(self.ports) do
        self.objects:add(port:toObject())
        self.objects:add(port:toDockObject())   -- the pier, as its own object
    end
    for _, p in ipairs(self.terrain.props) do
        Loader.tick()
        local ptile = self.terrain.tiles[p.tx][p.ty]
        local pz = ptile.z or 0                       -- sit the prop on the terrain height
        if (p.kind == "forest" or p.kind == "house" or p.kind == "scrub")
            and (ptile.level or 0) >= config.MOUNTAINS.TREELINE_LEVEL then
            -- above the treeline: bare rock/snow, no forests or houses
        elseif p.kind == "forest" then
            self.objects:add({
                tx = p.tx, ty = p.ty, z = pz, kind = "forest",
                draw = function(_, g) Objects.drawForest(g, p.salt, p.biome) end,
            })
        elseif p.kind == "scrub" then          -- desert: cactus + low bushes
            self.objects:add({
                tx = p.tx, ty = p.ty, z = pz, kind = "scrub",
                draw = function(_, g) Objects.drawScrub(g, p.salt) end,
            })
        elseif p.kind == "house" and self:solidLand(p.tx, p.ty) then
            self.objects:add({
                tx = p.tx, ty = p.ty, z = pz, kind = "house",
                sprite = countryHouseSprite(p.tx, p.ty),
                draw = function(_, g)  -- fallback if the PNG is missing
                    Objects.building(g.cx, g.cy, 16, 16, g.z, 22, 14,
                        config.colors.building_wall, config.colors.building_dk)
                end,
            })
        end
    end
    -- buildings around each port, sized by the town; blocks follow the map
    self.blockSet = game.state.selectedMap or "norge"
    for _, port in ipairs(self.ports) do
        self:scatterCity(port)
    end
    self:spawnLighthouses()    -- a lighthouse on the seaward coast of each town
    self:spawnPowerPlant()     -- the (in)famous Klokkarvik power plant

    -- the scene reads fleet.ships / fleet.obstacles for drawing and collision
    self.shipPopup = nil        -- MarineTraffic-style info card, when a ship is tapped
    self.fleet = Fleet.new{
        terrain = self.terrain, ports = self.ports, objects = self.objects,
        boat = self.boat, data = game.data.ships,
        -- the submarine's surfacing bubbles ride the world's splash bursts
        splash = function(x, y) self.splashes[#self.splashes + 1] = { x = x, y = y, t = 0 } end,
    }
    self.fleet:populate()

    self.cargoSystem = CargoSystem.new(self.ports)

    -- restore the explored area, then light up where the boat already is
    self.fog = Fog.new(self.ms.fog)
    self.fog:revealAround(self.boat.x, self.boat.y, config.FOG_REVEAL)
    self._fogSaveT = 0

    -- built last, so terrain, ports and fog all exist
    self.minimap = Minimap.new(self)

    -- sailing right around an island pops its interior too; this pass covers
    -- islands already circled in an older save
    self._islandFilled = {}
    self._islandCheckT = 0
    self:checkIslandFill()

    -- placement is seeded; the save only remembers found/mapped
    local foundSet = {}
    for _, id in ipairs(self.ms.treasuresFound) do foundSet[id] = true end
    self.treasures = Treasure.build(self.terrain, foundSet)
    self.mapped = {}
    for _, id in ipairs(self.ms.treasuresMapped) do self.mapped[id] = true end
    -- Gates the shelf's tally, so it isn't an empty well on a save that never
    -- saw a map. It LATCHES: a pirate stealing a chest un-maps it, and a tally
    -- vanishing at that moment reads as "my treasures were taken too".
    self.huntSeen = #self.ms.treasuresMapped > 0 or #self.ms.treasuresFound > 0
    self.album       = nil    -- the album overlay, when open
    self.mapReveal   = nil    -- the "Finn skatten!" reveal card, when up
    self.winScreen   = nil    -- the grand all-found finale, when up
    self.pause       = nil    -- the pause/menu overlay, when up
    self.racer       = nil    -- a pirate racing you to the active chest, when one's out
    self.treasureFX  = {}      -- chest-open coin bursts
    -- only on a freshly granted map: never on load, never mid-hunt
    self.pendingMapReveal = nil

    self.camera:snapTo(self.boat.x, self.boat.y)
    self.nearPort = nil
    self.dock = nil          -- the docking screen overlay, when open
    self.dockSuppress = nil  -- port id we just left a dock for (don't re-pop)

    self:buildClouds()

    -- No pirate yet; the first can appear after a grace period (see updatePirate).
    self.pirate = nil
    self.pirateCooldown = config.PIRATE.SPAWN_GRACE
    Assets.stopChase()

    self:spawnShark()        -- one friendly shark roams the sea from the start
    self.sharkSeen = false   -- so we greet it only the first time it bumps you
    self.dolphins = Dolphins.new()   -- a pod that joins when you sail fast

    self.splashes = {}       -- short-lived water bursts (e.g. a zapped pirate)
    self.coinPops = {}       -- gold tumbling out of a pirate that's been driven off
    self.eaten = {}          -- falling-food "Nam nam nam" bites
    self.sailDist = 0        -- distance sailed toward the next bite
    self.puffs = {}          -- horn smoke puffs rising off the funnel
    self.fireworks = {}      -- mini delivery fireworks over the town
    self.pendingFireworks = nil   -- port to celebrate once the dock closes

    -- Brand-new captain (never docked, no gold): one-time "Finn en havn!"
    if not game.state.hintFindPort and game.state.coins == 0 then
        self.findPortHint = 8
        game.state.hintFindPort = true
        game:save()
        Assets.playNamedVoice("finn_en_havn")   -- optional clip
    end

    collectgarbage("collect")

    if self:allTreasuresFound() then
        -- A completed save would dead-end: no maps left to hand out and no
        -- finale to re-fire. Show it, so "Spill igjen" starts a fresh hunt.
        self:openWinScreen()
    end
end

-- every treasure dug up: the game is won
function World:allTreasuresFound()
    if #self.treasures == 0 then return false end
    for _, tr in ipairs(self.treasures) do
        if not tr.found then return false end
    end
    return true
end

-- Houses around a port's pad, count and spread from its `size`. Dry non-pad
-- tiles only, nearest-first, so they cluster around the harbour.
function World:scatterCity(port)
    local spec = config.CITY_SIZES[port.def.size or "small"] or config.CITY_SIZES.small
    local ti, tj, R = port.tx, port.ty, spec.spread
    local cands = {}
    for di = -R, R do
        for dj = -R, R do
            local i, j = ti + di, tj + dj
            -- solid land only, so town buildings never hang off the shoreline
            if self:solidLand(i, j) then
                cands[#cands + 1] = { i = i, j = j, d = di * di + dj * dj }
            end
        end
    end
    table.sort(cands, function(a, b) return a.d < b.d end)

    -- which landmarks a town gets depends on its size and what it produces
    local size = port.def.size or "small"
    local metro = (size == "metropolis")
    local big  = metro or (size == "medium" or size == "large")
    local fishing = port.def.produces and port.def.produces.mode == "cargo"
    local marks = {}
    if size ~= "tiny" then marks[#marks + 1] = { sprite = "props/church.png", fn = Objects.drawChurch } end
    if size ~= "tiny" then marks[#marks + 1] = { sprite = "props/park.png", fn = Objects.drawPark } end
    if big then marks[#marks + 1] = { sprite = "props/market.png", fn = Objects.drawMarket } end
    if big then marks[#marks + 1] = { sprite = "props/crane.png",  fn = Objects.drawCrane } end
    if big then marks[#marks + 1] = { sprite = "props/fountain.png", fn = Objects.drawFountain } end
    if fishing then marks[#marks + 1] = { sprite = "props/fishracks.png", fn = Objects.drawFishRacks } end

    -- Place landmarks on nearby tiles (spaced a tile apart so they don't merge),
    -- then fill the rest of the town with houses.
    local taken = {}
    for li, m in ipairs(marks) do
        local idx = 1 + (li - 1) * 2
        if idx <= #cands then
            taken[idx] = true
            local c = cands[idx]
            local fn = m.fn
            self.objects:add({
                tx = c.i, ty = c.j, z = self.terrain:tileZ(c.i, c.j), sprite = m.sprite,
                draw = function(_, g) fn(g) end,
            })
        end
    end
    -- Candidates are nearest-first, so starting past `spec.houses` puts these
    -- just outside the built-up area, where an airport belongs.
    if port.def.landmarks then
        local slot = math.min(#cands, spec.houses + 4)
        for _, id in ipairs(port.def.landmarks) do
            for _, sprite in ipairs(LANDMARKS[id] or {}) do
                while slot < #cands and taken[slot] do slot = slot + 1 end
                if slot >= #cands then break end
                taken[slot] = true
                local c = cands[slot]
                self.objects:add({
                    tx = c.i, ty = c.j, z = self.terrain:tileZ(c.i, c.j), sprite = sprite,
                    draw = function(_, g)      -- fallback if the PNG is missing
                        Objects.building(g.cx, g.cy, 16, 16, g.z, 30, 16,
                            config.colors.building_wall, config.colors.building_dk)
                    end,
                })
                slot = slot + 1
            end
        end
    end

    -- big towns: a dense core of blocks ringed by cottages further out
    -- metropolis: over half the town is downtown high-rise blocks
    local blockCore = metro and math.floor(spec.houses * 0.55)
        or (big and math.floor(spec.houses * 0.4) or 0)
    local placed = 0
    for k = 1, #cands do
        if not taken[k] and placed < spec.houses then
            placed = placed + 1
            local c = cands[k]
            local sprite = (placed <= blockCore)
                and blockSprite(c.i, c.j, self.blockSet) or houseSprite(c.i, c.j)
            self.objects:add({
                tx = c.i, ty = c.j, z = self.terrain:tileZ(c.i, c.j), sprite = sprite,
                draw = function(_, g)
                    Objects.building(g.cx, g.cy, 16, 16, g.z, 22, 14,
                        config.colors.building_wall, config.colors.building_dk)
                end,
            })
        end
    end
end

-- land touching water on at least one side
function World:tileIsCoast(i, j)
    local T = config.TILE
    local function water(a, b) return self.terrain:isWater((a - 0.5) * T, (b - 0.5) * T) end
    if water(i, j) then return false end
    return water(i + 1, j) or water(i - 1, j) or water(i, j + 1) or water(i, j - 1)
end

-- One per town, on the most-seaward coastal tile near the harbour, so it stands
-- at the fjord mouth greeting boats.
function World:spawnLighthouses()
    local R = 9
    for _, port in ipairs(self.ports) do
        local best, bestScore
        for di = -R, R do
            for dj = -R, R do
                local i, j = port.tx + di, port.ty + dj
                if self:landTileFree(i, j) and self:tileIsCoast(i, j) then
                    -- more land neighbours = more solidly attached, so the
                    -- lighthouse and its hut sit on land, not a thin spit
                    local landN = 0
                    if self:isLandTile(i + 1, j) then landN = landN + 1 end
                    if self:isLandTile(i - 1, j) then landN = landN + 1 end
                    if self:isLandTile(i, j + 1) then landN = landN + 1 end
                    if self:isLandTile(i, j - 1) then landN = landN + 1 end
                    -- solidness first, then prefer seaward
                    local score = landN * 100 + (di * port.seaDx + dj * port.seaDy)
                    if not bestScore or score > bestScore then
                        best, bestScore = { i, j }, score
                    end
                end
            end
        end
        if best then
            self.objects:add({
                tx = best[1], ty = best[2], z = self.terrain:tileZ(best[1], best[2]),
                sprite = "props/lighthouse.png",
                draw = function(_, g) Objects.drawLighthouse(g) end,
            })
        end
    end
end

-- in bounds, dry, not a harbour pad
function World:landTileFree(i, j)
    if i < 1 or j < 1 or i > self.terrain.nx or j > self.terrain.ny then return false end
    if self.terrain.buildMask[i] and self.terrain.buildMask[i][j] then return false end
    local T = config.TILE
    return not self.terrain:isWater((i - 0.5) * T, (j - 0.5) * T)
end

-- any land, pads included
function World:isLandTile(i, j)
    if i < 1 or j < 1 or i > self.terrain.nx or j > self.terrain.ny then return false end
    local T = config.TILE
    return not self.terrain:isWater((i - 0.5) * T, (j - 0.5) * T)
end

-- buildable AND its four neighbours are land, so a building never hangs over
-- the water at the shoreline
function World:solidLand(i, j)
    return self:landTileFree(i, j)
        and self:isLandTile(i + 1, j) and self:isLandTile(i - 1, j)
        and self:isLandTile(i, j + 1) and self:isLandTile(i, j - 1)
end

-- The power plant at Klokkarvik: a 2x2 patch of dry land, preferring somewhere
-- inland from the harbour.
function World:spawnPowerPlant()
    if not Assets.image("props/powerplant.png") then return end
    local port = self:portById("klokkarvik")
    if not port then return end
    -- most land in its 3x3 neighbourhood wins, so the plant sits well inside
    -- the island; ties break toward the port
    local R, best, bestScore = 9, nil, nil
    for di = -R, R do
        for dj = -R, R do
            local i, j = port.tx + di, port.ty + dj
            if self:landTileFree(i, j) then
                local land = 0
                for ni = -1, 1 do
                    for nj = -1, 1 do
                        if self:landTileFree(i + ni, j + nj) then land = land + 1 end
                    end
                end
                local score = land * 100 - (di * di + dj * dj)
                if not bestScore or score > bestScore then best, bestScore = { i, j }, score end
            end
        end
    end
    if best then
        local i0, j0 = best[1], best[2]
        -- clear nearby trees and houses so nothing hides it
        self.objects:removeWhere(function(o)
            return (o.kind == "forest" or o.kind == "house")
                and o.tx >= i0 - 2 and o.tx <= i0 + 2 and o.ty >= j0 - 2 and o.ty <= j0 + 2
        end)
        -- small footprint, so it tucks onto the little island
        self.objects:add({
            tx = i0, ty = j0, w = 1, h = 1, z = self.terrain:tileZ(i0, j0),
            sprite = "props/powerplant.png", spriteScale = 1.2, kind = "powerplant",
            draw = function(_, g) Objects.drawLot(g, { 0.5, 0.5, 0.52 }) end,
        })
    end
end

-- Spirals out for a start tile. The first pass insists on OPEN water, clear in
-- all 8 directions, so the boat can't wake up wedged in a crevice between two
-- islands; the second takes any water.
function World:findStartWater(gx, gy)
    local T = config.TILE
    local DIRS = { {1,0},{-1,0},{0,1},{0,-1},{0.7,0.7},{0.7,-0.7},{-0.7,0.7},{-0.7,-0.7} }
    local function openWater(x, y, clearance)
        if not (x > 0 and y > 0 and x < config.WORLD_WIDTH and y < config.WORLD_HEIGHT)
           or not self.terrain:isWater(x, y) then return false end
        for _, d in ipairs(DIRS) do
            if not self.terrain:isWater(x + d[1] * clearance, y + d[2] * clearance) then
                return false
            end
        end
        return true
    end
    for _, clearance in ipairs({ T * 4, 0 }) do
        for r = 0, 60 do
            for a = 0, math.max(1, r * 6) do
                local ang = (a / math.max(1, r * 6)) * math.pi * 2
                local x = gx + math.cos(ang) * r * T
                local y = gy + math.sin(ang) * r * T
                if clearance > 0 and openWater(x, y, clearance) then
                    return x, y
                elseif clearance == 0 and x > 0 and y > 0 and x < config.WORLD_WIDTH
                       and y < config.WORLD_HEIGHT and self.terrain:isWater(x, y) then
                    return x, y
                end
            end
        end
    end
    return gx, gy
end

-- screen shake, a "doooink!" and a toast, on a cooldown so grinding along a
-- skerry doesn't spam it
function World:hitSkerry()
    if self._skerryCd > 0 then return end
    self._skerryCd = 1.2
    self.camera:addShake(14)
    Assets.playSfx("doink", 0.9)
    self:showToast("Du traff et skjær!")
end

-- within `r` of any town; the implementation lives in fleet.lua
function World:nearAnyPort(x, y, r, except)
    return Fleet.nearAnyPort(self.ports, x, y, r, except)
end

-- clouds gather over tall island summits and skip the flat little ones
function World:buildClouds()
    local T = config.TILE
    self.clouds = {}
    for _, isl in ipairs(self.terrain.islandCenters) do
        local ti = math.floor(isl.x / T) + 1
        local tj = math.floor(isl.y / T) + 1
        local peakZ, pcx, pcy = 0, isl.x, isl.y
        for di = -8, 8 do
            for dj = -8, 8 do
                local z = self.terrain:tileZ(ti + di, tj + dj)
                if z > peakZ then peakZ, pcx, pcy = z, (ti + di - 0.5) * T, (tj + dj - 0.5) * T end
            end
        end
        if peakZ >= 90 then                       -- only over genuinely tall peaks
            for k = 1, 2 do
                local cx = pcx + (k - 1.5) * 150
                local cy = pcy + (k - 1.5) * 70
                if not self:nearAnyPort(cx, cy, 500) then   -- keep clouds off the towns
                    self.clouds[#self.clouds + 1] = {
                        x = cx, y = cy,
                        z = peakZ + 130 + k * 28,           -- float high above the summit
                        scale = 22 + k * 7,
                        phase = isl.x * 0.01 + k * 1.7, range = 55 + k * 15,
                    }
                end
            end
        end
    end
end

-- rows of chunky blocks; a cloud is a few overlapping puffs, lifted over peaks
local function pixelPuff(cx, cy, r, blk, a)
    local r2 = r * r
    for by = -r, r, blk do
        local span = math.floor(math.sqrt(math.max(0, r2 - by * by)) / blk) * blk
        if span > 0 then
            love.graphics.setColor(0.97, 0.98, 1.0, a)
            love.graphics.rectangle("fill", cx - span, cy + by, span * 2, blk)
        end
    end
end

function World:drawClouds()
    if not config.SHOW_CLOUDS then return end
    if not self.clouds then return end
    local t = love.timer.getTime()
    local blk = 2                                  -- lightly pixelated, not chunky
    for _, c in ipairs(self.clouds) do
        local gx = c.x + math.sin(t * 0.04 + c.phase) * c.range
        local sx, sy = Iso.project(gx, c.y, c.z)
        local s = c.scale
        pixelPuff(sx, sy, s, blk, 0.9)
        pixelPuff(sx - s * 0.75, sy + s * 0.20, s * 0.6, blk, 0.9)
        pixelPuff(sx + s * 0.78, sy + s * 0.22, s * 0.66, blk, 0.9)
        pixelPuff(sx + s * 0.18, sy - s * 0.34, s * 0.55, blk, 0.9)
    end
    love.graphics.setColor(1, 1, 1)
end

function World:update(dt)
    -- Clamp dt spikes: movement is pos += speed*dt with point-sampled
    -- collision, so one huge step tunnels through a skerry and snaps back.
    dt = math.min(dt, 1 / 30)

    -- a release can be swallowed by a modal or a focus loss; don't stay stuck
    if self.panning and (self.dock or self.album or self.mapReveal or self.winScreen or self.pause
        or not love.window.hasFocus()) then
        self.panning = false
    end

    -- any modal freezes the world
    if self.pause then self.pause:update(dt); return end
    if self.winScreen then self.winScreen:update(dt); self:updateWinAudio(dt); return end
    if self.mapReveal then self.mapReveal:update(dt); return end
    if self.album then self.album:update(dt); return end
    if self.dock then self.dock:update(dt); return end

    -- deferred so the card follows the harbourmaster instead of stacking on it
    if self.pendingMapReveal then
        local t = self.pendingMapReveal
        self.pendingMapReveal = nil
        self:openMapReveal(t)
        return
    end

    -- the town sends you off with fireworks
    if self.pendingFireworks then
        self:startFireworks(self.pendingFireworks)
        self.pendingFireworks = nil
    end

    self.terrain:update(dt)
    self.boat:update(dt)
    self.boat:blockLand(self.terrain)   -- keep the boat on the water
    self.fleet:update(dt)

    -- Ships are solid, but docking wins: collision is skipped while latching,
    -- so a vessel near the harbour can't block the approach.
    self._skerryCd = math.max(0, (self._skerryCd or 0) - dt)
    if not self.latching and not self.nearPort then
        for _, s in ipairs(self.fleet.obstacles) do    -- skerries: clonk + shake on a real hit
            if self.boat:collideCircle(s.x, s.y, s.r) then self:hitSkerry() end
        end
        for _, s in ipairs(self.fleet.ships) do        -- ambient ships
            if not (s.dive and s.dive > 0.05) then     -- a submerged sub isn't solid
                self.boat:collideCircle(s.x, s.y, s.r)
            end
        end
    end

    for _, port in ipairs(self.ports) do port:update(dt) end

    -- flushed rarely: serializing the whole grid every frame is costly
    if self.fog:revealAround(self.boat.x, self.boat.y, config.FOG_REVEAL) then
        self._fogDirty = true
        self.minimap:refresh()          -- paint the newly-revealed cells onto the map
    end
    self._fogSaveT = self._fogSaveT + dt
    if self._fogDirty and self._fogSaveT > 8 then
        self.ms.fog = self.fog:serialize()
        self.game:save(); self._fogDirty = false; self._fogSaveT = 0
    end

    self:checkIslandDiscovery()

    -- every few seconds: has any island been fully circled?
    self._islandCheckT = self._islandCheckT + dt
    if self._islandCheckT > 4 then
        self._islandCheckT = 0
        self:checkIslandFill()
    end

    self.nearPort = nil
    for _, port in ipairs(self.ports) do
        if port:isBoatInRange(self.boat) then self.nearPort = port; break end
    end

    -- once close, the boat is pulled into the berth and the screen opens only
    -- when parked, so it never unloads out at sea
    if self.latching then
        local bx, by = self.latching:berth()
        local dx, dy = bx - self.boat.x, by - self.boat.y
        self.boat:setDestination(bx, by)            -- keep pulling it in
        self._latchT = (self._latchT or 0) + dt
        if (dx * dx + dy * dy) < (20 * 20) or self._latchT > 2.5 then
            local p = self.latching
            self.latching, self._latchT = nil, 0
            self:openDock(p)
            return
        end
    elseif self.nearPort then
        if self.nearPort.id ~= self.dockSuppress then
            self.latching = self.nearPort           -- start the glide-in
            self._latchT = 0
            self.boat.coastT = 0                    -- docking beats coasting
        end
    else
        -- clear of the harbour we left: cast off and allow docking again
        if self.dockSuppress then
            Assets.playSfx("leave", 0.8)
            self.dockSuppress = nil
        end
    end

    self:updatePirate(dt)
    self:updateShark(dt)
    self.dolphins:update(dt, self.boat, self.terrain)
    self:updateHornAndFireworks(dt)

    -- Only targets a pirate still chasing: once scared off, leave it be.
    if self.game:owns("cannon") then
        local target = (self.pirate and self.pirate.state == "chase") and self.pirate or nil
        self.boat:updateCannon(dt, target, function() self:cannonHitPirate() end, self.game)
        -- once per encounter, so a quiet cannon reads as "buy kuler", not a bug
        if target and self.game:ammoCount() <= 0 then self:warnNoAmmo() end
        if not self.pirate then self._ammoWarned = false end
    end

    self:updateTreasure(dt)

    for i = #self.splashes, 1, -1 do
        local s = self.splashes[i]
        s.t = s.t + dt
        if s.t > 0.7 then table.remove(self.splashes, i) end
    end

    self:updateEating(dt)

    if self.dockPulse then
        self.dockPulse.t = self.dockPulse.t + dt
        if self.dockPulse.t > 1.0 then self.dockPulse = nil end
    end
    if (self.findPortHint or 0) > 0 then self.findPortHint = self.findPortHint - dt end
    if self.findPortHintDelay then          -- the post-treasure "Finn en havn!" reprise
        self.findPortHintDelay = self.findPortHintDelay - dt
        if self.findPortHintDelay <= 0 then
            self.findPortHintDelay = nil
            self.findPortHint = 8
            Assets.playNamedVoice("finn_en_havn")
        end
    end

    if self.game.touchCamera then
        -- No edge-hover on touch: a tap near the edge pins the synthetic mouse
        -- there and scrolls forever. Glide instead, aiming AHEAD of the motion.
        local lead = config.TOUCH_FOLLOW_LEAD
        self.camera:followAnchor(dt,
            self.boat.x + math.cos(self.boat.angle) * self.boat.speed * lead,
            self.boat.y + math.sin(self.boat.angle) * self.boat.speed * lead)
    else
        self.camera:edgeScroll(dt, self.boat.x, self.boat.y)  -- scroll, but never lose the boat
        if config.FOLLOW_CAMERA then
            self.camera:keepAnchorInView(self.boat.x, self.boat.y)  -- boat near edge pans the map
        end
    end
    self.camera:update(dt)

    self:updateCoinPops(dt)
    self._ammoWarnT = math.max(0, (self._ammoWarnT or 0) - dt)   -- see warnNoAmmo

    if self.toast.timer > 0 then
        self.toast.timer = self.toast.timer - dt
        self.toast.rise  = self.toast.rise + dt * 30
    end

    if self.shipPopup then           -- ship info card lingers a few seconds, then fades out
        self.shipPopup.t = self.shipPopup.t + dt
        if self.shipPopup.t > 9 then self.shipPopup = nil end
    end
end

-- ===== Horn + delivery fireworks ========================================

-- A toot capped at ~1s so a longer recording stays snappy, a smoke puff, and
-- the nearest ship within earshot answering back deeper a moment later.
function World:soundHorn()
    if (self._hornCd or 0) > 0 then return end
    self._hornCd = 0.6
    local src = Assets.playSfx("horn", 1.0)   -- full volume: it's the kid's own toot
    if src then self._hornStop = { src = src, t = 1.0 } end   -- first second only
    self.puffs[#self.puffs + 1] = { x = self.boat.x, y = self.boat.y, t = 0 }
    if not self._hornAnswer then
        local best, bestD2
        for _, s in ipairs(self.fleet.ships) do
            if not (s.dive and s.dive > 0.05) then     -- a dived sub can't answer
                local dx, dy = s.x - self.boat.x, s.y - self.boat.y
                local d2 = dx * dx + dy * dy
                if d2 < 1500 * 1500 and (not bestD2 or d2 < bestD2) then
                    best, bestD2 = s, d2
                end
            end
        end
        if best then self._hornAnswer = { ship = best, t = 1.2 } end
    end
end

-- Three bursts over the town, deferred to the dock closing so they pop as you
-- sail off. Each is a ring of sparks with a little gravity droop.
function World:startFireworks(port)
    for i = 0, 2 do
        self.fireworks[#self.fireworks + 1] = {
            x = port.x + (love.math.random() - 0.5) * 260,
            y = port.y + (love.math.random() - 0.5) * 260,
            z = 150 + love.math.random() * 110,
            delay = i * 0.45, t = 0,
            col = config.BUILDING_COLORS[love.math.random(#config.BUILDING_COLORS)],
            spin = love.math.random() * math.pi,
        }
    end
end

function World:updateHornAndFireworks(dt)
    self._hornCd = math.max(0, (self._hornCd or 0) - dt)
    if self._hornStop then
        self._hornStop.t = self._hornStop.t - dt
        if self._hornStop.t <= 0 then self._hornStop.src:stop(); self._hornStop = nil end
    end
    if self._hornAnswer then
        self._hornAnswer.t = self._hornAnswer.t - dt
        if self._hornAnswer.t <= 0 then
            Assets.playPitched("horn", 0.8, 0.55)      -- the big ship's deep reply
            local s = self._hornAnswer.ship
            self.puffs[#self.puffs + 1] = { x = s.x, y = s.y, t = 0 }
            self._hornAnswer = nil
        end
    end
    for i = #self.puffs, 1, -1 do
        local p = self.puffs[i]
        p.t = p.t + dt
        if p.t > 1.4 then table.remove(self.puffs, i) end
    end
    for i = #self.fireworks, 1, -1 do
        local f = self.fireworks[i]
        if f.delay > 0 then
            f.delay = f.delay - dt
            if f.delay <= 0 then Assets.playSfx("firework", 0.45) end
        else
            f.t = f.t + dt
            if f.t > 1.2 then table.remove(self.fireworks, i) end
        end
    end
end

-- smoke puffs rising from a horn blast
function World:drawPuffs()
    for _, p in ipairs(self.puffs) do
        local a = 1 - p.t / 1.4
        for k = 0, 2 do
            local tt = math.max(0, p.t - k * 0.14)
            local sx, sy = Iso.project(p.x, p.y, 46 + tt * 60 + k * 8)
            love.graphics.setColor(0.82, 0.82, 0.84, 0.4 * a)
            love.graphics.circle("fill", sx + k * 4 - 4, sy, 5 + tt * 13)
        end
    end
    love.graphics.setColor(1, 1, 1)
end

-- an expanding ring of sparks that droops and fades
function World:drawFireworks()
    for _, f in ipairs(self.fireworks) do
        if f.delay <= 0 and f.t > 0 then
            local p = f.t / 1.2
            local sx, sy = Iso.project(f.x, f.y, f.z)
            if p < 0.22 then                          -- the bright ignition flash
                love.graphics.setColor(1, 1, 0.9, 1 - p / 0.22)
                love.graphics.circle("fill", sx, sy, 6 * (1 - p / 0.22) + 2)
            end
            local r = 12 + p * 70
            for k = 1, 12 do
                local a = k / 12 * math.pi * 2 + f.spin
                local px = sx + math.cos(a) * r
                local py = sy + math.sin(a) * r * 0.75 + p * p * 42   -- gravity droop
                local tw = 0.6 + 0.4 * math.sin(f.t * 22 + k * 3.1)   -- sparkle
                love.graphics.setColor(f.col[1] + 0.3, f.col[2] + 0.3, f.col[3] + 0.3,
                    (1 - p) * tw)
                love.graphics.circle("fill", px, py, 2.6 * (1 - p) + 0.8)
            end
        end
    end
    love.graphics.setColor(1, 1, 1)
end

function World:checkIslandDiscovery()
    for _, isl in ipairs(self.terrain.islandCenters) do
        local dx, dy = self.boat.x - isl.x, self.boat.y - isl.y
        local reach = (isl.radius or 520) + 200   -- "discovered" on reaching its coast
        if (dx * dx + dy * dy) < (reach * reach) and not self:isDiscovered(isl.id) then
            table.insert(self.ms.discoveredIslands, isl.id)
            self.game:save()
            self:showToast("Ny øy oppdaget!")
            Assets.playSfx("deliver")
        end
    end
end

-- Sailing right around an island reveals its interior: you've seen it from
-- every side, so a dark blob left in the middle reads as a bug, not a mystery.
-- Ring points off the world edge are ignored, so a border island still counts.
function World:checkIslandFill()
    for _, isl in ipairs(self.terrain.islandCenters) do
        if not self._islandFilled[isl.id] then
            local all = true
            local n = 28
            for k = 0, n - 1 do
                local a = k / n * math.pi * 2
                local sx = isl.x + math.cos(a) * isl.radius
                local sy = isl.y + math.sin(a) * isl.radius
                if sx > 0 and sy > 0 and sx < config.WORLD_WIDTH and sy < config.WORLD_HEIGHT
                    and not self.fog:pointRevealed(sx, sy) then
                    all = false; break
                end
            end
            if all then
                self._islandFilled[isl.id] = true
                if self.fog:revealAround(isl.x, isl.y, isl.radius * 1.15) then
                    self._fogDirty = true
                    self.minimap:refresh()
                end
            end
        end
    end
end

function World:isDiscovered(id)
    for _, d in ipairs(self.ms.discoveredIslands) do
        if d == id then return true end
    end
    return false
end

-- ===== Treasure hunt ====================================================
-- Harbourmasters hand out maps; a pirate contests the chest you sail for. Lose
-- it and it isn't gone -- the chest returns to the pool for a later map.

-- Reveals the nearest un-found, un-mapped chest. Only called on a successful
-- delivery, so a map is a reward for trade rather than for visiting, and only
-- one is ever out. Returns true when one was actually handed over.
function World:revealTreasureMap(port)
    if self:activeTreasure() then return false end          -- one treasure at a time
    -- the cadence rule is Treasure.mapDue, pure and tested
    local everHad = #self.ms.treasuresMapped > 0 or #self.ms.treasuresFound > 0
    if not Treasure.mapDue(everHad, self._sinceMap or 99, config.TREASURE.MAP_COOLDOWN,
        love.math.random(), config.TREASURE.MAP_CHANCE) then
        return false
    end
    local best, bestD
    for _, t in ipairs(self.treasures) do
        if not t.found and not self.mapped[t.id] then
            local dx, dy = t.x - port.x, t.y - port.y
            local d = dx * dx + dy * dy
            if not bestD or d < bestD then bestD, best = d, t end
        end
    end
    if not best then return false end
    self.mapped[best.id] = true
    self.huntSeen = true                                    -- latches the shelf tally on
    self._sinceMap = 0                                      -- start the breather
    table.insert(self.ms.treasuresMapped, best.id)
    self.game:save()
    -- deferred to the dock closing, so it's its own moment
    self.pendingMapReveal = best
    return true
end

function World:openMapReveal(t)
    self.mapReveal = MapReveal.new(self, t)
    self:showToast("Finn skatten!")
    -- celebratory audio
    if not Assets.playNamedVoice("finn_skatten") and not Assets.playNamedVoice("skattekart") then
        Assets.playSfx("deliver")
    end
    Assets.playSfx("horn", 0.5)
end

function World:closeMapReveal()
    self.mapReveal = nil
end

-- the nearest mapped, un-found chest: what the marker points at
function World:activeTreasure()
    local best, bestD
    for _, t in ipairs(self.treasures) do
        if self.mapped[t.id] and not t.found then
            local dx, dy = t.x - self.boat.x, t.y - self.boat.y
            local d = dx * dx + dy * dy
            if not bestD or d < bestD then bestD, best = d, t end
        end
    end
    return best
end

-- These MUST be integrated as phase += dt * speed, never sin(absoluteTime *
-- speed): the speed rises with the heat, and getTime() is already large, so a
-- changing rate leaps hundreds of radians between frames. That is what made the
-- ring and arrow jump and skip as you closed in.
function World:updateHuntPhases(dt)
    local heat = self:treasureHeat()
    if not heat then return end
    local M = config.TREASURE_MODE
    self._ringPhase = (self._ringPhase or 0) + dt * (M.RING_COLD + (M.RING_HOT - M.RING_COLD) * heat)
    self._bobPhase  = (self._bobPhase or 0) + dt * (M.BOB_COLD + (M.BOB_HOT - M.BOB_COLD) * heat)
    self._beatPhase = (self._beatPhase or 0) + dt * (3 + 9 * heat)
end

function World:updateTreasure(dt)
    self:updateHuntPhases(dt)
    -- advance chest-open coin bursts
    for i = #self.treasureFX, 1, -1 do
        local fx = self.treasureFX[i]
        fx.t = fx.t + dt
        if fx.t > 1.4 then table.remove(self.treasureFX, i) end
    end

    -- a pirate races you to the active chest
    local active = self:activeTreasure()
    self:updateRace(dt, active)

    -- checked first, so a tie goes to the player
    local R = config.TREASURE.REACH
    for _, t in ipairs(self.treasures) do
        if self.mapped[t.id] and not t.found then
            local dx, dy = self.boat.x - t.x, self.boat.y - t.y
            if (dx * dx + dy * dy) < R * R and not self.latching and not self.dock then
                self:grabTreasure(t); return
            end
        end
    end

    -- otherwise the pirate takes it
    if active and self.racer and self.racer.state ~= "retreat" then
        local pdx, pdy = self.racer.x - active.x, self.racer.y - active.y
        if (pdx * pdx + pdy * pdy) < R * R then self:pirateStealsTreasure(active) end
    end
end

-- Spawns and steers the racer once you close in; who reaches the chest is
-- decided in updateTreasure.
function World:updateRace(dt, active)
    -- A racer that just stole a chest sails off briefly, then vanishes (a splash).
    if self._racerExitT then
        if self.racer then
            self.racer:update(dt, self.boat, self.terrain)
            self._racerExitT = self._racerExitT - dt
            if self._racerExitT <= 0 then
                self.splashes[#self.splashes + 1] = { x = self.racer.x, y = self.racer.y, t = 0 }
                self.racer = nil; Assets.stopChase()
                self._racerExitT = nil
            end
        else
            self._racerExitT = nil
        end
        return
    end

    if not active then
        if self.racer then                          -- no chest in play: send any racer off
            if self.racer.state ~= "retreat" then self.racer:flee() end
            self.racer:update(dt, self.boat, self.terrain)
            if self.racer.dead then self.racer = nil; Assets.stopChase() end
        end
        return
    end

    -- The cue is independent of the racer's placement, so it always fires on
    -- approach and re-arms once you've sailed clear.
    local dx, dy = self.boat.x - active.x, self.boat.y - active.y
    local d2 = dx * dx + dy * dy
    local trig2 = config.TREASURE.RACE_TRIGGER * config.TREASURE.RACE_TRIGGER
    if d2 < trig2 then
        if not active.cued and not self.dock and not self.latching then
            active.cued = true
            if not self.racer then self:spawnRacer(active) end
            Assets.playSfx("pirate_warn", 0.9)     -- the warning dong, ALWAYS
            Assets.playNamedVoice("fort_deg")      -- plus the voice when recorded
            if self.racer then Assets.startChase() end
            self:showToast("Fort deg, ta skatten før sjørøverne kommer!")
        end
    elseif d2 > trig2 * 1.4 then
        active.cued = nil                           -- sailed clear: arm the cue again
    end

    if self.racer then
        self.racer.goal = active                    -- make for the chest
        self.racer:update(dt, self.boat, self.terrain)
        if self.racer.dead then self.racer = nil; Assets.stopChase() end
    end
end

-- The X vanishes, so you aren't stuck circling it, and the chest goes back in
-- the pool for a later map.
function World:pirateStealsTreasure(t)
    t.cued = nil                       -- so it cues again if re-mapped later
    self.mapped[t.id] = nil
    for i, id in ipairs(self.ms.treasuresMapped) do
        if id == t.id then table.remove(self.ms.treasuresMapped, i); break end
    end
    self.game:save()
    if self.racer then self.racer:flee() end
    self._racerExitT = 1.4              -- it sails off with the loot, then vanishes
    self:showToast("Sjørøverne tok skatten!")
    Assets.playSfx("cannon_hit", 0.6)
end

-- placed at roughly your own distance from the chest: a straight dash beats it,
-- dawdling loses
function World:spawnRacer(t)
    local b = self.boat
    local pd = math.sqrt((b.x - t.x) ^ 2 + (b.y - t.y) ^ 2)
    local r = math.max(500, math.min(1400, pd))
    for _, rr in ipairs({ r, r * 0.8, r * 1.2 }) do
        for k = 0, 11 do
            local ang = (k / 12) * math.pi * 2 + love.math.random() * 0.5
            local x = t.x + math.cos(ang) * rr
            local y = t.y + math.sin(ang) * rr
            if x > 40 and y > 40 and x < config.WORLD_WIDTH - 40 and y < config.WORLD_HEIGHT - 40
                and self.terrain:isWater(x, y) then
                self.racer = Pirate.new(x, y, self.boat.maxSpeed)
                -- a notch slower than a hunting pirate: kids on small screens
                -- were losing the race by a hair
                self.racer.maxSpeed = self.racer.maxSpeed * 0.90
                self.racer.goal = t
                self.racer.angle = math.atan2(t.y - y, t.x - x)
                return
            end
        end
    end
end

-- stop the boat, send any racer packing, win the chest
function World:grabTreasure(t)
    self.boat:clearDestination()
    if self.racer then self.racer = nil; Assets.stopChase() end
    self:winTreasure(t)
end

function World:winTreasure(t)
    t.found = true
    table.insert(self.ms.treasuresFound, t.id)
    self.game:addCoins(config.TREASURE.GOLD)     -- persists the save
    self.treasureFX[#self.treasureFX + 1] = { x = t.x, y = t.y, t = 0, good = t.good }
    Assets.playSfx("deliver")
    if not Assets.playNamedVoice("skatt") then Assets.playSfx("coin", 0.8) end
    self:showToast("Skatt! +" .. config.TREASURE.GOLD .. " gull")

    if self:allTreasuresFound() then
        self:openWinScreen()
    else
        -- nudge onward with the same cue as the first voyage: oppdrag resume
        -- now, and a pre-reader needs telling
        self.findPortHintDelay = 3.5
    end
end

function World:openWinScreen()
    self.winScreen = WinScreen.new(self)
    self:showToast("Alle skatter funnet!")
    -- cheer first, then the looping song once it's nearly done
    if self._winSong then self._winSong:stop(); self._winSong = nil end
    Assets.setMusicVolume(0)
    local cheer = config.AUDIO_ON and Assets.namedVoice("cheer") or nil
    self._cheer = cheer
    if cheer then
        cheer:stop(); cheer:setVolume(1.0); cheer:play()
        self._songT = math.max(0.1, cheer:getDuration() - 0.25)   -- song after the cheer
    else
        self._songT = 0
    end
end

-- start the looping song once the cheer has nearly finished
function World:updateWinAudio(dt)
    if not self._songT then return end
    self._songT = self._songT - dt
    if self._songT <= 0 then
        self._songT = nil
        self._winSong = Assets.playLoopVoice("du_vant", 1.0, false, 1.12)  -- brighter, no reverb
        if not self._winSong then Assets.playSfx("deliver") end
    end
end

function World:closeWinScreen()
    if self._cheer then self._cheer:stop(); self._cheer = nil end
    if self._winSong then self._winSong:stop(); self._winSong = nil end
    self._songT = nil
    Assets.setMusicVolume(1.0)
    self.winScreen = nil
    self.game:newGame()   -- "Spill igjen": wipe progress and return to the title screen
end

function World:openAlbum()
    if self.dock then return end
    self.album = Album.new(self)
end

function World:closeAlbum()
    self.album = nil
end

-- only opens when no other modal is up
function World:openPause()
    if self.dock or self.album or self.mapReveal or self.winScreen then return end
    self.shipPopup = nil
    self.pause = PauseMenu.new(self)
end

function World:closePause()
    self.pause = nil
end

function World:togglePause()
    if self.pause then self:closePause() else self:openPause() end
end

-- save and return to the title screen
function World:exitToMenu()
    self:flushFog()              -- persist exploration
    self.game:save()
    self.game:setScene("menu")
end

-- Pirates appear rarely, on open sea with gold aboard, and despawn when they
-- give up or are shaken off.
function World:updatePirate(dt)
    -- The gap counts from the END of the previous shout: timing from the start
    -- cuts each one off partway and reads as a stutter, not a chant.
    if (self._cryLeft or 0) > 0 then
        local src = self._crySrc
        if not (src and src:isPlaying()) then
            self._cryT = self._cryT - dt
            if self._cryT <= 0 then
                self._cryLeft = self._cryLeft - 1
                self._cryT = config.PIRATE.CRY_GAP
                self._crySrc = Assets.playSfx("pirate_warn", 0.85)
            end
        end
    end
    if self.pirate then
        self.pirate:update(dt, self.boat, self.terrain, function() self:pirateHit() end)
        -- celebrate the moment it breaks off, however that happened
        if self.pirate.state == "retreat" and not self.pirate.fleeCued then
            self.pirate.fleeCued = true
            Assets.playNamedVoice("sjorover_rommer")
        end
        if self.pirate.dead then
            self.pirate = nil
            self.pirateCooldown = config.PIRATE.RESPAWN_GRACE
            Assets.stopChase()
        end
        return
    end

    -- only roll while actually sailing open water with gold aboard
    local eligible = self.game.state.coins > 0 and not self.latching and not self.dock
        and self.boat.speed > self.boat.maxSpeed * 0.3
    if not eligible then return end
    self.pirateCooldown = self.pirateCooldown - dt
    if self.pirateCooldown <= 0 and love.math.random() < dt / config.PIRATE.SPAWN_MEAN then
        self:spawnPirate()
    end
end

function World:spawnPirate()
    -- sweep several distance rings over many angles, so it still finds sea when
    -- the boat is in a pocket between islands
    local b = self.boat
    local px, py
    for _, r in ipairs({ 1200, 1000, 850, 700, 1350, 560 }) do
        for k = 0, 11 do
            local ang = (k / 12) * math.pi * 2 + love.math.random() * 0.52
            local x = b.x + math.cos(ang) * r
            local y = b.y + math.sin(ang) * r
            if x > 40 and y > 40 and x < config.WORLD_WIDTH - 40 and y < config.WORLD_HEIGHT - 40
                and self.terrain:isWater(x, y) then
                px, py = x, y; break
            end
        end
        if px then break end
    end
    if not px then return end          -- nowhere clear to appear; try again next roll
    self.pirate = Pirate.new(px, py, self.boat.maxSpeed)
    self.pirate.angle = math.atan2(self.boat.y - py, self.boat.x - px)
    -- more than one shout: a chant is what makes the arrival an event
    Assets.playSfx("pirate_warn", 0.85)
    self._cryLeft = config.PIRATE.CRY_TIMES - 1
    self._cryT    = config.PIRATE.CRY_GAP
    Assets.startChase()
    self:showToast("Sjørøvere!")
end

-- Sweeps a few angles at a random distance; finding nothing clear, the world
-- just runs without it.
function World:spawnShark()
    local b = self.boat
    for _ = 1, 24 do
        local r = config.SHARK.SPAWN_MIN
            + love.math.random() * (config.SHARK.SPAWN_MAX - config.SHARK.SPAWN_MIN)
        local ang = love.math.random() * math.pi * 2
        local x = b.x + math.cos(ang) * r
        local y = b.y + math.sin(ang) * r
        if x > 40 and y > 40 and x < config.WORLD_WIDTH - 40 and y < config.WORLD_HEIGHT - 40
            and self.terrain:isWater(x, y) then
            self.shark = Shark.new(x, y)
            return
        end
    end
end

-- The bounce reuses boat:collideCircle, but is skipped while latching so it
-- can't fight the auto-docking glide.
function World:updateShark(dt)
    if not self.shark then return end
    self.shark:update(dt, self.boat, self.terrain, self.pirate ~= nil, function()
        if not self.sharkSeen then
            self.sharkSeen = true
            self:showToast("En snill hai!")        -- "A friendly shark!"
        end
    end)
    if self.shark:isActive() and not self.latching then
        self.boat:collideCircle(self.shark.x, self.shark.y, self.shark.radius)
    end
end

-- One food unit is eaten every config.EAT_DISTANCE travelled, so a long voyage
-- is a reason to stock up.
function World:updateEating(dt)
    -- bites rise a touch, then drop and fade
    for i = #self.eaten, 1, -1 do
        local e = self.eaten[i]
        e.t = e.t + dt
        if e.t > 1.1 then table.remove(self.eaten, i) end
    end

    if self.latching or self.dock then return end
    self.sailDist = self.sailDist + self.boat.speed * dt
    if self.sailDist < config.EAT_DISTANCE then return end
    self.sailDist = self.sailDist - config.EAT_DISTANCE

    local id = self.game:eatFood()
    if not id then return end
    local item = self:shopItem(id)
    self.eaten[#self.eaten + 1] = {
        icon = item and item.icon or "box",
        x = self.boat.x, y = self.boat.y, t = 0,
        fig = love.math.random(4),                   -- which passenger does the munching
    }
    if not Assets.playNamedVoice("nam") then Assets.playSfx("coin", 0.5) end
    self:showToast("Nam nam nam!")
end

function World:shopItem(id)
    for _, it in ipairs(self.game.data.shop) do
        if it.id == id then return it end
    end
end

-- Drawn so it reads as MUNCHING, not dropping: the snack floats above the deck,
-- a passenger leans in and chomps it down in three bites with crumbs flying.
function World:drawEaten()
    for _, e in ipairs(self.eaten) do
        local p = e.t / 1.1                                    -- 0..1 over its life
        local rise = math.sin(math.min(p, 0.5) / 0.5 * (math.pi / 2)) * 36  -- float up + hold
        local sx, sy = Iso.project(e.x, e.y, 48 + rise)
        local wob = math.sin(e.t * 22) * 2                     -- jiggle = being chewed

        -- the eater: a passenger leaning in from the left
        local figS = 34
        Icons.draw("passenger" .. e.fig, sx - figS * 0.7, sy + wob, figS)

        -- the snack, bitten down in 3 chomps then gone (to the right of the mouth)
        local bites, frac = 3, p % (1 / 3) * 3                 -- frac = progress through this bite
        local stage = math.floor(p * bites)
        if stage < bites then
            local fs = 30 * (1 - stage / bites) * (0.9 + 0.12 * math.sin(e.t * 18))
            love.graphics.setColor(1, 1, 1)
            Icons.draw(e.icon, sx + 10, sy - 4 + wob, fs)
        end

        -- crumbs bursting out on each chomp, fading as the bite completes
        local cA = 1 - frac
        if cA > 0 then
            love.graphics.setColor(0.85, 0.70, 0.42, cA)
            for k = 1, 5 do
                local ang = k * 1.7 + e.t * 4
                local d = frac * 18
                love.graphics.circle("fill", sx + 10 + math.cos(ang) * d, sy - 4 + math.sin(ang) * d * 0.6, 2)
            end
        end
    end
    love.graphics.setColor(1, 1, 1)
end

-- It takes SCARE_HITS to drive a pirate off, so it really chases and shoots
-- first. No sinking -- it turns tail and may come back another day.
function World:cannonHitPirate()
    if not self.pirate or self.pirate.state ~= "chase" then return end
    self.splashes[#self.splashes + 1] = { x = self.pirate.x, y = self.pirate.y, t = 0 }
    self.pirate.hits = (self.pirate.hits or 0) + 1
    Assets.playSfx("cannon_hit", 0.9)
    self.camera:addShake(7)
    if self.pirate.hits >= config.CANNON.SCARE_HITS then
        self.pirate:flee()                            -- driven off; sails away
        self:pirateDropsGold(self.pirate.x, self.pirate.y)
    else
        self:showToast("Treff!")                      -- "Hit!" -- keep at it
    end
end

-- A hit costs a little gold, never below zero, and shakes the screen; going
-- broke makes the pirate give up.
-- The loot is what makes fighting worth doing -- the kanonkuler burned cost real
-- gold, so with no prize the correct play was always to run. The gold is
-- credited immediately; the tumbling coins are just the show.
function World:pirateDropsGold(x, y)
    self.game:addCoins(config.PIRATE.DROP_GOLD)
    self:showToast("Sjørøveren rømmer! Gullet er ditt!")
    Assets.playSfx("coin", 0.9)
    for _ = 1, 8 do
        local a  = love.math.random() * math.pi * 2
        local sp = 40 + love.math.random() * 70
        self.coinPops[#self.coinPops + 1] = {
            x = x, y = y, t = 0,
            vx = math.cos(a) * sp, vy = math.sin(a) * sp,
            spin = love.math.random() * math.pi * 2,
        }
    end
end

local COIN_POP_LIFE = 1.6
function World:updateCoinPops(dt)
    for i = #self.coinPops, 1, -1 do
        local c = self.coinPops[i]
        c.t = c.t + dt
        c.x, c.y = c.x + c.vx * dt, c.y + c.vy * dt
        c.vx, c.vy = c.vx * 0.94, c.vy * 0.94    -- drag, so they settle quickly
        c.spin = c.spin + dt * 6
        if c.t > COIN_POP_LIFE then table.remove(self.coinPops, i) end
    end
end

function World:drawCoinPops()
    for _, c in ipairs(self.coinPops) do
        local p = c.t / COIN_POP_LIFE
        local hop = math.sin(math.min(p * 2, 1) * math.pi) * 30   -- up, then down
        local sx, sy = Iso.project(c.x, c.y, 26 + hop)
        love.graphics.setColor(1, 1, 1, 1 - math.max(0, (p - 0.7) / 0.3))
        Icons.coin(sx, sy, Scale.overlay(11), c.spin)
    end
    love.graphics.setColor(1, 1, 1)
end

function World:pirateHit()
    local loss = math.min(config.PIRATE.HIT_GOLD, self.game.state.coins)
    if loss > 0 then self.game:addCoins(-loss) end
    Assets.playSfx("cannon_hit", 0.8)
    self.camera:addShake(10)
    if self.game.state.coins <= 0 and self.pirate then
        self.pirate:flee()
        self:showToast("Sjørøveren drar!")     -- nothing left to steal, it leaves
    else
        self:showToast("-" .. loss .. " gull!")
    end
end

-- Docks and picks what the screen shows:
--   deliver  carrying goods bound here
--   busy     already carrying a mission for another town
--   offer    this town has a job and the boat has room
--   visit    nothing to do right now
function World:openDock(port)
    -- harbours are always safe: a hunting pirate breaks off when you dock
    if self.pirate then
        self.pirate = nil
        self.pirateCooldown = config.PIRATE.RESPAWN_GRACE
        Assets.stopChase()
    end
    self.boat:clearDestination()   -- stop nudging while we're parked

    local earned, delivered = self.cargoSystem:tryDeliver(self.boat, port)
    local mode, offer
    if delivered > 0 then
        self.game:addCoins(earned)
        Assets.playSfx("deliver")
        mode = "deliver"
    elseif self.boat:cargoCount() > 0 then
        mode = "busy"                       -- already on a mission for another town
    else
        offer = self.cargoSystem:offerAt(port.id)
        mode = (offer and self.boat:hasRoom()) and "offer" or "visit"
    end

    -- No new oppdrag while a map is live: "Finn skatten først!". Cargo already
    -- aboard still gets delivered.
    if self:activeTreasure() and mode ~= "deliver" then
        mode, offer = "findfirst", nil
    end

    -- Granted up front so the deliver screen can offer the choice; the card
    -- pops once the dock closes. Counted before the roll, so the cooldown
    -- measures deliveries rather than docks visited.
    -- NOT during a hunt: mid-hunt deliveries used to tick the breather down,
    -- which cut the real gap between hunts from 3.2 deliveries to 2.2 -- maps
    -- arriving ~45% more often than config.TREASURE claimed.
    if delivered > 0 and not self:activeTreasure() then
        self._sinceMap = (self._sinceMap or 99) + 1
    end
    local mapGiven = (mode == "deliver") and self:revealTreasureMap(port) or false

    self.dock = PortScreen.new(self, port, {
        mode = mode, offer = offer, earned = earned, delivered = delivered,
        mission = self.boat.cargo[1],       -- so "busy" can name where to go
        mapGiven = mapGiven,                -- harbourmaster handed over a treasure map
    })
    self.dockSuppress = port.id    -- don't immediately re-pop while still in range
end

-- reveals are otherwise only written every ~8s
function World:flushFog()
    if self._fogDirty then
        self.ms.fog = self.fog:serialize()
        self._fogDirty = false
    end
end

function World:showToast(text)
    self.toast.text, self.toast.timer, self.toast.rise = text, 2.0, 0
end

-- Says the locker is empty, so a silent cannon reads as "buy kuler" not a bug.
-- The automatic battery says it ONCE per encounter and then hushes; a TAP is a
-- deliberate act, and total silence reads as broken, so it always answers with
-- a dry click and repeats the warning on a cooldown.
function World:warnNoAmmo(tapped)
    if tapped then Assets.playSfx("bump", 0.45) end     -- always something back
    if not tapped and self._ammoWarned then return end
    if (self._ammoWarnT or 0) > 0 then return end       -- don't repeat the speech
    self._ammoWarned, self._ammoWarnT = true, 2.5
    self:showToast("Tomt for kanonkuler! Kjøp flere i butikken.")
    if not Assets.playNamedVoice("tomt_for_kuler") then Assets.playSfx("bump", 0.7) end
end

function World:draw()
    love.graphics.clear(config.colors.water_deep)

    self.camera:attach()
    local _z = Profiler.mark()
    self:drawWorldSorted()
    Profiler.zone("world", _z)
    self:drawClouds()              -- soft clouds hanging over the mountain peaks
    _z = Profiler.mark()
    self:drawFog()                 -- dark over everything not yet explored
    Profiler.zone("fog", _z)
    self.camera:detach()

    -- washed before the HUD goes on, so the sea changes character but the
    -- panels stay readable
    self:drawHuntOverlay()

    _z = Profiler.mark()
    HUD.draw(self)
    Profiler.zone("hud", _z)

    if not self.dock and not self.album and not self.mapReveal and not self.winScreen
        and not self.pause then
        self:drawDockPulse()         -- "you picked this harbour" ring
        self:drawMooring()           -- rope + glints while tied up at a pier
        self:drawFindPortHint()      -- first-voyage "Finn en havn!" banner
        self:drawMissionPointer()    -- "go this way!" hint (cargo destination)
        self:drawTreasurePointer()   -- orange "to the treasure!" arrow + ring
        self:drawPirateIndicator()   -- red "danger this way!" arrow when off-screen
        _z = Profiler.mark()
        self.minimap:draw()          -- world map + treasure X's
        Profiler.zone("minimap", _z)
        self:drawShipPopup()         -- MarineTraffic-style card for a tapped ship
    end
    if self.dock then self.dock:draw() end            -- docking modal
    if self.album then self.album:draw() end          -- album overlay
    if self.mapReveal then self.mapReveal:draw() end  -- "Finn skatten!" card
    if self.winScreen then self.winScreen:draw() end  -- grand finale, on top of all
    if self.pause then self.pause:draw() end          -- pause/menu overlay, on top
end

-- anchored above the ship, following it as it moves
function World:drawShipPopup()
    if not self.shipPopup then return end
    local s = self.shipPopup.ship
    local sx, sy = self.camera:worldToScreen(s.x, s.y)
    ShipInfo.draw(s, sx, sy, self.game.fonts)
end

-- an off-screen pirate gets a red arrow pinned to the screen edge, so the
-- child knows which way the danger is
function World:drawPirateIndicator()
    if not self.pirate then return end
    local sw, sh = love.graphics.getDimensions()
    local px, py = self.camera:worldToScreen(self.pirate.x, self.pirate.y)
    local margin = 48
    if px >= 0 and px <= sw and py >= 0 and py <= sh then return end  -- visible: no arrow

    local cx, cy = sw / 2, sh / 2
    local ang = math.atan2(py - cy, px - cx)
    local ex = math.max(margin, math.min(sw - margin, px))
    local ey = math.max(margin, math.min(sh - margin, py))
    local pulse = 0.65 + 0.35 * math.sin(love.timer.getTime() * 8)

    love.graphics.push()
    love.graphics.translate(ex, ey)
    love.graphics.rotate(ang)
    love.graphics.setColor(0.10, 0, 0, 0.55)
    love.graphics.polygon("fill", -18, -13, 16, 0, -18, 13)
    love.graphics.setColor(0.88, 0.12, 0.10, pulse)
    love.graphics.polygon("fill", -13, -9, 13, 0, -13, 9)
    love.graphics.pop()
    love.graphics.setColor(1, 1, 1)
end

function World:portById(id)
    for _, p in ipairs(self.ports) do
        if p.id == id then return p end
    end
end
-- The mission arrow above the boat plus a ring on the destination town, so a
-- non-reader always knows where to go.
-- On a tap the PIER lights up, not the town: a strong glow and ring on the dock
-- with only a soft echo behind it, so a pre-reader learns the boat goes to the
-- bryggen rather than the houses.
function World:drawDockPulse()
    local dp = self.dockPulse
    if not dp then return end
    local a = 1 - dp.t / 1.0
    local tx2, ty2 = self.camera:worldToScreen(dp.p.x, dp.p.y)
    local px, py = self.camera:worldToScreen(dp.p:dockPoint())
    local r = Scale.overlay(120)
    -- gold = plain tap, good = the oppdrag's harbour, wrong = any other while
    -- carrying cargo
    local M = ({
        gold  = { town = {1.0, 0.72, 0.25, 0.22}, pier = {1.0, 0.85, 0.4, 0.18}, glint = {1, 0.95, 0.7} },
        good  = { town = {0.30, 0.95, 0.35, 0.26}, pier = {0.55, 1.0, 0.55, 0.20}, glint = {0.8, 1, 0.8} },
        wrong = { town = {1.0, 0.30, 0.22, 0.18}, pier = {1.0, 0.45, 0.38, 0.14}, glint = {1, 0.72, 0.62} },
    })[dp.mood or "gold"]
    love.graphics.setBlendMode("add")
    love.graphics.setColor(M.town[1], M.town[2], M.town[3], M.town[4] * 0.55 * a) -- soft echo on the town
    love.graphics.ellipse("fill", tx2, ty2, r * 1.1, r * 0.65)
    love.graphics.setColor(M.pier[1], M.pier[2], M.pier[3],                       -- the pier is the star
        math.min(1, M.pier[4] * 2.4) * a)
    love.graphics.ellipse("fill", px, py, r * 0.85, r * 0.5)
    love.graphics.setBlendMode("alpha")
    -- expanding ring on the pier
    local ring = r * (0.35 + 0.55 * dp.t)
    love.graphics.setLineWidth(math.max(2, Scale.overlay(5) * a))
    love.graphics.setColor(M.glint[1], M.glint[2], M.glint[3], 0.9 * a)
    love.graphics.ellipse("line", px, py, ring, ring * 0.5)
    love.graphics.setLineWidth(1)
    for i = 1, 6 do                                        -- glints popping over the dock
        local ph = dp.t * 3 - i * 0.12
        if ph > 0 and ph < 0.6 then
            local f = math.sin(ph / 0.6 * math.pi)
            local gx = px + math.cos(i * 2.4) * r * (0.25 + i * 0.09)
            local gy = py + math.sin(i * 2.4) * r * (0.15 + i * 0.05)
            local sr = Scale.overlay(7) * f
            love.graphics.setColor(M.glint[1], M.glint[2], M.glint[3], f * a)
            love.graphics.line(gx - sr, gy, gx + sr, gy)
            love.graphics.line(gx, gy - sr, gx, gy + sr)
        end
    end
    love.graphics.setColor(1, 1, 1)
end

-- shown once ever, so a brand-new captain knows what to do
function World:drawFindPortHint()
    if (self.findPortHint or 0) <= 0 then return end
    local fonts = self.game.fonts
    local sw = love.graphics.getWidth()
    love.graphics.setFont(fonts.big)
    local msg = "Finn en havn!"
    local pulse = 1 + 0.04 * math.sin(love.timer.getTime() * 4)
    local mx2 = sw / 2 - fonts.big:getWidth(msg) / 2
    local my2 = love.graphics.getHeight() * 0.16
    love.graphics.push()
    love.graphics.translate(sw / 2, my2 + fonts.big:getHeight() / 2)
    love.graphics.scale(pulse, pulse)
    love.graphics.translate(-sw / 2, -(my2 + fonts.big:getHeight() / 2))
    love.graphics.setColor(0.1, 0.08, 0.05, 0.6)
    love.graphics.print(msg, mx2 + 3, my2 + 3)
    love.graphics.setColor(1, 0.85, 0.3, math.min(1, self.findPortHint))
    love.graphics.print(msg, mx2, my2)
    love.graphics.pop()
    love.graphics.setColor(1, 1, 1)
end

-- a sagging rope to the pier tip and glints on the planks: a visible "moored"
function World:drawMooring()
    local p = self.latching or (self.dock and self.dock.port)
    if not p and self.nearPort and self.boat.speed < 12 then p = self.nearPort end
    if not p then return end
    local dpx, dpy = p:dockPoint()
    local bx, by = self.camera:worldToScreen(self.boat.x, self.boat.y)
    local px, py = self.camera:worldToScreen(dpx, dpy)
    local t = love.timer.getTime()
    local sag = Scale.overlay(12) + math.sin(t * 2) * Scale.overlay(3)
    love.graphics.setColor(0.80, 0.64, 0.40, 0.95)
    love.graphics.setLineWidth(math.max(2, Scale.overlay(3)))
    local n = 10
    for i = 0, n - 1 do
        local u0, u1 = i / n, (i + 1) / n
        love.graphics.line(
            bx + (px - bx) * u0, by + (py - by) * u0 + math.sin(u0 * math.pi) * sag,
            bx + (px - bx) * u1, by + (py - by) * u1 + math.sin(u1 * math.pi) * sag)
    end
    love.graphics.setLineWidth(1)
    for i = 1, 3 do                      -- little glints twinkling on the pier
        local a = math.sin(t * (1.4 + i * 0.5) + i * 2.0)
        if a > 0.4 then
            local f = (a - 0.4) / 0.6
            local gx2 = px + (i - 2) * Scale.overlay(14)
            local gy2 = py - Scale.overlay(8) - i * Scale.overlay(3)
            local r2 = Scale.overlay(5) * f
            love.graphics.setColor(1, 0.95, 0.7, f * 0.9)
            love.graphics.line(gx2 - r2, gy2, gx2 + r2, gy2)
            love.graphics.line(gx2, gy2 - r2, gx2, gy2 + r2)
        end
    end
    love.graphics.setColor(1, 1, 1)
end

-- The gold "sail to this town" costume: a swallowtail pennant-arrow, no badge --
-- an arrow alone says "that way", and the town has its own colour and ring.
-- File scope, NOT per frame: these tables are read, never written.
local MISSION_STYLE = {
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
    ringThick = 4, ringShadow = 7, ringShadowA = 0.5, ringAlpha = 0.95,
}

function World:drawMissionPointer()
    if self:activeTreasure() then return end   -- on a hunt: the treasure is the goal, not a harbour
    local m = self.boat.cargo[1]
    if not m then return end
    local port = self:portById(m.toId)
    if not port then return end

    local bx, by = self.camera:worldToScreen(self.boat.x, self.boat.y)
    local tx, ty = self.camera:worldToScreen(port.x, port.y)
    local t = love.timer.getTime()

    -- ring on the target town, when it's on screen
    local sw, sh = love.graphics.getWidth(), love.graphics.getHeight()
    if tx > 0 and tx < sw and ty > 0 and ty < sh then
        Pointer.ring(MISSION_STYLE, tx, ty,
            Scale.overlay(30 + math.sin(t * 4) * 7), m.color)
    end

    -- constant rates here, so absolute time is safe, unlike the hunt marker
    Pointer.draw(MISSION_STYLE, bx, by, tx, ty,
        Scale.overlay(64),                                    -- lift above the boat
        math.max(0, math.sin(t * 2.6)) * Scale.overlay(8),    -- hop toward target
        math.sin(t * 3) * 4,                                  -- gentle vertical wobble
        (1 + 0.05 * math.sin(t * 5)) * Scale.overlay(0.7))
end

-- Each mapped, un-found chest sits on a sandbank with a bobbing chest and ring,
-- plus the coin burst and rising sticker when one is won.
function World:drawTreasures()
    local t = love.timer.getTime()
    for _, tr in ipairs(self.treasures) do
        if self.mapped[tr.id] and not tr.found then
            local sx, sy = Iso.project(tr.x, tr.y, 0)
            local sand = config.colors.sand
            -- water halo, wet rim, dry top and speckles: reads as a sandbank
            love.graphics.setColor(0.46, 0.62, 0.66, 0.45)
            love.graphics.ellipse("fill", sx, sy + 2, 66, 34)        -- shallow-water halo
            love.graphics.setColor(sand.lip)
            love.graphics.ellipse("fill", sx, sy, 50, 25)            -- wet sand rim
            love.graphics.setColor(sand.top)
            love.graphics.ellipse("fill", sx, sy - 3, 39, 18)        -- dry sand top
            love.graphics.setColor(sand.dot)
            for k = 1, 7 do
                local a = k * 1.9
                love.graphics.circle("fill", sx + math.cos(a) * 22, sy - 3 + math.sin(a) * 9, 1.5)
            end
            local pr = 22 + math.sin(t * 4) * 4                       -- pulsing gold ring
            love.graphics.setColor(config.colors.gold[1], config.colors.gold[2], config.colors.gold[3], 0.8)
            love.graphics.setLineWidth(3); love.graphics.ellipse("line", sx, sy, pr + 8, (pr + 8) * 0.5)
            love.graphics.setLineWidth(1)
            local bob = math.sin(t * 2.2 + #tr.id) * 3               -- bobbing chest on the bank
            Icons.draw("chest", sx, sy - 16 + bob, 34)
        end
    end

    -- coins jump out of the opened chest and arc back down
    local gold = config.colors.gold
    for _, fx in ipairs(self.treasureFX) do
        local p = fx.t / 1.4
        local sx, sy = Iso.project(fx.x, fx.y, 0)
        local phase = fx.x % 1                                       -- per-chest variation
        for k = 1, 6 do
            local ang = (k / 6) * math.pi * 2 + phase * 6
            local d = p * (16 + (k % 3) * 12)                        -- fan outward
            local hop = math.sin(math.min(1, p) * math.pi) * (34 + (k % 2) * 16)  -- up then down
            local cx = sx + math.cos(ang) * d
            local cy = sy + math.sin(ang) * d * 0.5 - hop
            local r = 4 * (1 - p) + 2
            love.graphics.setColor(0.60, 0.45, 0.10, 1 - p)         -- dark rim
            love.graphics.ellipse("fill", cx, cy, r + 1, r + 1)
            love.graphics.setColor(gold[1], gold[2], gold[3], 1 - p) -- gold
            love.graphics.ellipse("fill", cx, cy, r, r)
        end
    end
    love.graphics.setColor(1, 1, 1)
end

-- How close the hunt is, 0..1, nil with no hunt on. THE single number
-- treasure-seeking mode runs on -- marker, beat, ring and sea wash all read it,
-- so they can't disagree. Squared, so the last stretch accelerates.
function World:treasureHeat(tr)
    tr = tr or self:activeTreasure()
    if not tr then return nil, nil end
    local M = config.TREASURE_MODE
    local dx, dy = tr.x - self.boat.x, tr.y - self.boat.y
    local d = math.sqrt(dx * dx + dy * dy)
    local h = (M.NEAR - d) / math.max(1, M.NEAR - M.HOT)
    h = math.max(0, math.min(1, h))
    return h * h, tr
end

-- the parchment wash that says "you are hunting" without a word; screen space,
-- over the world and under the HUD
function World:drawHuntOverlay()
    local heat, tr = self:treasureHeat()
    if not tr then return end
    local M = config.TREASURE_MODE
    local sw, sh = love.graphics.getDimensions()

    love.graphics.setColor(M.TINT[1], M.TINT[2], M.TINT[3],
        M.TINT_MIN + (M.TINT_MAX - M.TINT_MIN) * heat)
    love.graphics.rectangle("fill", 0, 0, sw, sh)

    -- corner darkening, strongest near the chest
    local a = M.VIGNETTE * heat
    if a > 0.002 then
        local band = math.min(sw, sh) * 0.22
        for i = 1, 6 do                                   -- cheap layered falloff
            local f = (i / 6)
            love.graphics.setColor(0.12, 0.07, 0.02, a * f * 0.22)
            local inset = band * (1 - f)
            love.graphics.rectangle("line", inset, inset, sw - inset * 2, sh - inset * 2,
                band * 0.5, band * 0.5)
        end
        love.graphics.setLineWidth(1)
    end
    love.graphics.setColor(1, 1, 1)
end

-- The hunt costume: an upright chest with a small orange arrow on its leading
-- edge. This is the WHOLE hunt indicator -- the top-centre banner that used to
-- duplicate it is gone, since that band is the most expensive strip of screen
-- on a phone and the chest says "treasure!" louder than a word he can't read.
-- The arrow is smaller than the gold mission one: the chest carries the
-- message, the arrow only the direction.
local TREASURE_ARROW = { 0.98, 0.46, 0.12 }   -- warm orange (not the gold mission arrow)
local TREASURE_STYLE = {
    shape = { 26, 0, 9, -15, 9, -6, -20, -9, -11, 0, -20, 9, 9, 6, 9, 15 },
    fill  = TREASURE_ARROW,
    line  = { 0.10, 0.06, 0.03 },
    badge = "chest",                -- drawn UPRIGHT -- see src/ui/pointer.lua
    badgeSize = 54,
    orbit = 30,                     -- ...so the arrow sits on the chest's edge
    ringThick = 3, ringShadow = 6, ringShadowA = 0.45, ringAlpha = 1,
}

function World:drawTreasurePointer()
    local heat, tr = self:treasureHeat()
    if not tr then return end

    local bx, by = self.camera:worldToScreen(self.boat.x, self.boat.y)
    local tx, ty = self.camera:worldToScreen(tr.x, tr.y)
    local t = love.timer.getTime()
    local sw, sh = love.graphics.getWidth(), love.graphics.getHeight()

    -- Warmer/colder: closer means faster and bigger. Phases are integrated in
    -- World:updateHuntPhases -- see the note there.
    local M = config.TREASURE_MODE

    -- pulsing ring on the chest when it's on screen
    if tx > 0 and tx < sw and ty > 0 and ty < sh then
        Pointer.ring(TREASURE_STYLE, tx, ty,
            Scale.overlay(28 + math.sin(self._ringPhase or 0) * 7), TREASURE_ARROW)
    end

    -- the heartbeat as you close in
    local beat  = 1 + 0.10 * heat * math.sin(self._beatPhase or 0)
    local scale = (M.MARKER_BASE + M.MARKER_GROW * heat) * beat * Scale.marker(1)

    -- Scale.marker, not overlay: the chest must be RECOGNISED, and proportional
    -- shrink makes it a brown blob on a phone
    Pointer.draw(TREASURE_STYLE, bx, by, tx, ty,
        Scale.marker(62),                                          -- lift above the boat
        math.max(0, math.sin(self._bobPhase or 0)) * Scale.marker(8),
        math.sin(t * 3) * 4,
        scale)
end

-- keyed on world indices, not screen, so the frayed fog edge stays put
local function fogNoise(a, b)
    local n = (a * 374761393 + b * 668265263) % 2147483647
    n = (n * ((n % 8191) * 15731 + 789221) + 1376312589) % 2147483647
    return (n % 1024) / 1024
end

-- File scope on purpose: inside drawFog's sub-cell loop this allocated up to
-- 25 closures per boundary tile PER FRAME.
local function fogCorner(u, v, z00, z10, z01, z11, bx0, by0, T)
    local z = z00 * (1 - u) * (1 - v) + z10 * u * (1 - v)
            + z01 * (1 - u) * v       + z11 * u * v
    return Iso.project(bx0 + u * T, by0 + v * T, z)
end

-- Covers unexplored tiles. Interior fog is one diamond per tile; boundary tiles
-- fray into noise-dithered sub-diamonds, so the dark doesn't read as blocky
-- steps. Follows the sloped surface, so islands stay hidden until you're close.
function World:drawFog()
    local T = config.TILE
    local fog, terrain = self.fog, self.terrain
    local minGx, minGy, maxGx, maxGy = self.camera:groundBounds()
    local i0, j0, i1, j1 = terrain:visibleRange(minGx, minGy, maxGx, maxGy)
    love.graphics.setColor(0.03, 0.05, 0.09, 1)

    local K = 5    -- sub-cells per tile side at the boundary
    local function corner(i, j)
        return fog:pointRevealed((i - 1) * T, (j - 1) * T) and 1 or 0
    end

    for i = i0, i1 do
        for j = j0, j1 do
            local r00, r10 = corner(i, j), corner(i + 1, j)
            local r11, r01 = corner(i + 1, j + 1), corner(i, j + 1)
            local sum = r00 + r10 + r11 + r01
            local centre = fog:pointRevealed((i - 0.5) * T, (j - 0.5) * T)
            local z00, z10 = terrain:cornerZ(i, j), terrain:cornerZ(i + 1, j)
            local z11, z01 = terrain:cornerZ(i + 1, j + 1), terrain:cornerZ(i, j + 1)
            local bx0, by0 = (i - 1) * T, (j - 1) * T

            if sum == 4 and centre then
            elseif sum == 0 and not centre then
                -- hidden: one dark diamond following the slope
                local ax, ay = Iso.project(bx0,     by0,     z00)
                local bx, by = Iso.project(bx0 + T, by0,     z10)
                local cx, cy = Iso.project(bx0 + T, by0 + T, z11)
                local dx, dy = Iso.project(bx0,     by0 + T, z01)
                love.graphics.polygon("fill", ax, ay, bx, by, cx, cy, dx, dy)
            else
                -- boundary: fray into sub-diamonds
                for a = 0, K - 1 do
                    for b = 0, K - 1 do
                        local uc, vc = (a + 0.5) / K, (b + 0.5) / K
                        local r = r00 * (1 - uc) * (1 - vc) + r10 * uc * (1 - vc)
                                + r01 * (1 - uc) * vc       + r11 * uc * vc
                        if r < fogNoise(i * K + a, j * K + b) then
                            local u0, u1 = a / K, (a + 1) / K
                            local v0, v1 = b / K, (b + 1) / K
                            local ax, ay = fogCorner(u0, v0, z00, z10, z01, z11, bx0, by0, T)
                            local bx, by = fogCorner(u1, v0, z00, z10, z01, z11, bx0, by0, T)
                            local cx, cy = fogCorner(u1, v1, z00, z10, z01, z11, bx0, by0, T)
                            local dx, dy = fogCorner(u0, v1, z00, z10, z01, z11, bx0, by0, T)
                            love.graphics.polygon("fill", ax, ay, bx, by, cx, cy, dx, dy)
                        end
                    end
                end
            end
        end
    end
    love.graphics.setColor(1, 1, 1)
end

local function byDepth(a, b)
    if a.depth == b.depth then return a.seq < b.seq end
    return a.depth < b.depth
end

-- Pass 1 is the flat ground, needing no sort; pass 2 is everything standing on
-- it, depth-sorted so buildings and trees overlap the boat correctly.
function World:drawWorldSorted()
    local minGx, minGy, maxGx, maxGy = self.camera:groundBounds()
    local i0, j0, i1, j1 = self.terrain:visibleRange(minGx, minGy, maxGx, maxGy)

    -- only water animates per-tile; land is baked into landMesh
    for i = i0, i1 do
        for j = j0, j1 do
            self.terrain:drawTile(i, j)
        end
    end

    -- baked ground: land, then the jagged shoreline over the water bases
    love.graphics.setColor(1, 1, 1)
    if self.terrain.landMesh  then love.graphics.draw(self.terrain.landMesh)  end
    if self.terrain.coastMesh then love.graphics.draw(self.terrain.coastMesh) end
    if self.terrain.roadMesh  then love.graphics.draw(self.terrain.roadMesh)  end

    -- pass 2; render lists are pooled across frames
    local vis = self._vis
    if not vis then vis = {}; self._vis = vis end
    for k = #vis, 1, -1 do vis[k] = nil end
    self.objects:collectVisible(i0, j0, i1, j1, vis)

    local objs = self._objs
    if not objs then objs = {}; self._objs = objs end
    local opool = self._objPool
    if not opool then opool = {}; self._objPool = opool end
    local no = 0
    local function entry(depth, kind, obj)
        no = no + 1
        local e = opool[no]; if not e then e = {}; opool[no] = e end
        e.depth = depth; e.kind = kind; e.obj = obj; e.seq = no
        objs[no] = e
    end
    if self.boat.destX then entry(Iso.depth(self.boat.destX, self.boat.destY), "dest", nil) end
    for vi = 1, #vis do entry(vis[vi].depth, "object", vis[vi]) end
    local ships = self.fleet.ships
    if ships then
        local mb = 120                                 -- cull ships well off-screen
        for mi = 1, #ships do
            local s = ships[mi]
            if s.x > minGx - mb and s.x < maxGx + mb and s.y > minGy - mb and s.y < maxGy + mb
                and not (s.dive and s.dive >= 1) then          -- fully-dived sub: invisible
                entry(Iso.depth(s.x, s.y), "ship", s)
            end
        end
    end
    entry(Iso.depth(self.boat.x, self.boat.y), "boat", nil)
    if self.pirate then entry(Iso.depth(self.pirate.x, self.pirate.y), "pirate", nil) end
    if self.racer then entry(Iso.depth(self.racer.x, self.racer.y), "racer", nil) end
    if self.shark and self.shark.dive < 0.95 then
        entry(Iso.depth(self.shark.x, self.shark.y), "shark", nil)
    end
    if self.dolphins:isVisible() then
        local dpx, dpy = self.dolphins:depthPos()
        entry(Iso.depth(dpx, dpy), "dolphins", nil)
    end
    for k = #objs, no + 1, -1 do objs[k] = nil end
    table.sort(objs, byDepth)
    for k = 1, no do
        local it = objs[k]
        if it.kind == "object" then Objects.draw(it.obj)
        elseif it.kind == "ship" then
            local s = it.obj
            local ok
            if s.look.billboard then
                ok = Objects.drawShipBillboard(s.look.img, s.x, s.y, s.angle, s.scale, s.dive)
            else
                ok = Objects.drawShipSprite(s.look.sprite, s.x, s.y, s.angle, s.scale)
            end
            if not ok then
                Objects.drawShip(s.x, s.y, s.angle, s.look.col or { 0.6, 0.62, 0.66 }, s.scale, 0)
            end
        elseif it.kind == "boat" then self.boat:draw()
        elseif it.kind == "pirate" then self.pirate:draw()
        elseif it.kind == "racer" then self.racer:draw()
        elseif it.kind == "shark" then self.shark:draw()
        elseif it.kind == "dolphins" then self.dolphins:draw()
        elseif it.kind == "dest" then self:drawDestinationMarker() end
    end

    -- cannonballs arc above everything
    if self.pirate then self.pirate:drawBalls() end
    if self.game:owns("cannon") then self.boat:drawCannonBalls() end
    self:drawSplashes()
    self:drawPuffs()
    self:drawFireworks()
    self:drawEaten()
    self:drawCoinPops()      -- a beaten pirate's loot tumbling onto the water
    self:drawTreasures()     -- chests on sandbanks + win bursts (camera-attached)
    love.graphics.setColor(1, 1, 1)
end

-- expanding rings and droplets where something splashed
function World:drawSplashes()
    for _, s in ipairs(self.splashes) do
        local p = s.t / 0.7
        local a = 1 - p
        local sx, sy = Iso.project(s.x, s.y, 0)
        local r = 18 + p * 60
        love.graphics.setColor(1, 1, 1, a * 0.8)
        love.graphics.setLineWidth(3)
        love.graphics.ellipse("line", sx, sy, r, r * 0.5)
        love.graphics.ellipse("line", sx, sy, r * 0.5, r * 0.25)
        love.graphics.setLineWidth(1)
        for k = 1, 7 do
            local ang = (k / 7) * math.pi * 2
            local d = p * 64
            local up = math.sin(p * math.pi) * 26
            love.graphics.setColor(0.92, 0.96, 1.0, a)
            love.graphics.circle("fill", sx + math.cos(ang) * d, sy + math.sin(ang) * d * 0.5 - up, 3 * (1 - p) + 1)
        end
    end
    love.graphics.setColor(1, 1, 1)
end

function World:drawDestinationMarker()
    local c = config.colors
    local sx, sy = Iso.project(self.boat.destX, self.boat.destY, 0)
    local pulse = 8 + math.sin(love.timer.getTime() * 6) * 3
    love.graphics.setColor(c.gold[1], c.gold[2], c.gold[3], 0.85)
    love.graphics.setLineWidth(3)
    love.graphics.ellipse("line", sx, sy, pulse + 8, (pulse + 8) * 0.5)
    love.graphics.setLineWidth(1)
end

-- Docked, all input goes to the dock screen. Docking is automatic, so there is
-- no load key.
function World:keypressed(key)
    if self.pause then self.pause:keypressed(key); return end
    if self.winScreen then self.winScreen:keypressed(key); return end
    if self.mapReveal then self.mapReveal:keypressed(key); return end
    if self.album then self.album:keypressed(key); return end
    if self.dock then self.dock:keypressed(key); return end
    if key == "c" then
        self.camera:centerOn(self.boat.x, self.boat.y)  -- recenter on the boat
    elseif key == "space" then
        self:soundHorn()                                -- toot! (ships answer)
    elseif key == "b" then
        self:openAlbum()                                -- open the treasure album
    -- DEV-ONLY playtest keys (config.DEV: never in shipped builds):
    --   G = +50 gold (also makes a pirate eligible to spawn)
    --   P = summon a pirate in close, right now, to test the cannon fight
    elseif not config.DEV then
        return
    elseif key == "g" then
        self.game:addCoins(50)
        self:showToast("+50 gull (dev)")
    elseif key == "p" then
        self:devSpawnPirateClose()
    elseif key == "k" then
        for _, t in ipairs(self.treasures) do      -- DEV: reveal every treasure map
            if not t.found and not self.mapped[t.id] then
                self.mapped[t.id] = true
                table.insert(self.ms.treasuresMapped, t.id)
                self.huntSeen = true
            end
        end
        self.game:save()
        self:showToast("Alle skattekart (dev)")
    end
end

-- DEV-ONLY: a pirate ~500 units off so a fight starts at once
function World:devSpawnPirateClose()
    if self.pirate then return end
    local b = self.boat
    for _, r in ipairs({ 500, 650, 400, 800 }) do
        for k = 0, 11 do
            local ang = (k / 12) * math.pi * 2 + love.math.random() * 0.52
            local x = b.x + math.cos(ang) * r
            local y = b.y + math.sin(ang) * r
            if x > 40 and y > 40 and x < config.WORLD_WIDTH - 40 and y < config.WORLD_HEIGHT - 40
                and self.terrain:isWater(x, y) then
                self.pirate = Pirate.new(x, y, self.boat.maxSpeed)
                self.pirate.angle = math.atan2(b.y - y, b.x - x)
                Assets.playSfx("pirate_warn", 0.85)
                Assets.startChase()
                self:showToast("Sjørøvere! (dev)")
                return
            end
        end
    end
end

function World:mousepressed(x, y, button)
    if self.pause then self.pause:mousepressed(x, y, button); return end
    if self.winScreen then self.winScreen:mousepressed(x, y, button); return end
    if self.mapReveal then self.mapReveal:mousepressed(x, y, button); return end
    if self.album then self.album:mousepressed(x, y, button); return end
    if self.dock then self.dock:mousepressed(x, y, button); return end
    if button == 1 then
        -- the gold plaque is the pause button: press in, fire on release
        if self._pauseBtnRect and Retro.press("hud.pause", self._pauseBtnRect, x, y) then
            return
        end
        -- The treasure row opens the album; the rest of the shelf swallows taps
        -- too, since poking your own stuff must never act on the world behind.
        local sr = self._shelfRects
        if sr then
            local tr = sr.treasures
            if tr and x >= tr.x and x <= tr.x + tr.w and y >= tr.y and y <= tr.y + tr.h then
                self:openAlbum(); return
            end
            for _, r in pairs(sr) do
                if x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h then return end
            end
        end
        if self.latching then return end   -- being pulled into the berth; ignore clicks
        -- The box hugs the hull and cabin, not a halo, so tapping the water
        -- nearby still means "sail there".
        local bx, by = self.camera:worldToScreen(self.boat.x, self.boat.y)
        local bw = (self.boat.def.spriteWidth or config.BOAT_SPRITE_WIDTH) * self.camera.zoom
        if x > bx - bw * 0.30 and x < bx + bw * 0.30
            and y > by - bw * 0.52 and y < by + bw * 0.05 then
            self:soundHorn(); return
        end
        -- The one trigger in the game. The automatic battery is untouched, so
        -- a child who never taps plays exactly as before. Only while it's
        -- attacking -- a ball spent on a fleeing ship buys nothing, so that
        -- tap falls through to sailing.
        if self.pirate and self.pirate.state == "chase" then
            local px, py = self.camera:worldToScreen(self.pirate.x, self.pirate.y)
            local hw = PIRATE_TAP_W * 0.5 * self.camera.zoom
            local hh = PIRATE_TAP_H * self.camera.zoom
            if x > px - hw and x < px + hw and y > py - hh and y < py + hh * 0.2 then
                local shot = self.boat:tapFire(self.pirate, self.game)
                if shot == "fired" or shot == "wait" then return end
                if shot == "empty" then self:warnNoAmmo(true); return end
                -- "far" or no cannon: fall through and sail toward it
            end
        end

        local ship = self.fleet:shipAt(x, y, self.camera)   -- hit test on the sprite
        if ship then                        -- tap a ship -> its info card (don't sail)
            self.shipPopup = { ship = ship, t = 0 }
            Assets.playSfx("coin", 0.5)
            return
        end
        self.shipPopup = nil                -- tap open water -> close any card and sail
        local wx, wy = self.camera:screenToWorld(x, y)
        -- Tapping the town means "sail there", so the destination snaps to the
        -- dock -- never the buildings, which just beached the boat.
        local hitPort
        for _, p in ipairs(self.ports) do
            local dpx, dpy = p:dockPoint()
            local d1 = (wx - dpx) ^ 2 + (wy - dpy) ^ 2      -- the pier itself
            local d2 = (wx - p.x) ^ 2 + (wy - p.y) ^ 2      -- the town itself
            if d1 < 130 * 130 or d2 < 170 * 170 then hitPort = p; break end
        end
        if hitPort then
            -- on an oppdrag the highlight answers "is it THIS one?": green for
            -- the delivery harbour, soft red for any other
            local m = self.boat.cargo[1]
            local mood = m and (hitPort.id == m.toId and "good" or "wrong") or "gold"
            self.dockPulse = { p = hitPort, t = 0, mood = mood }
            self.boat:setDestination(hitPort:dockPoint())
        else
            self.boat:setDestination(wx, wy)
        end
    elseif button == 2 then
        self.panning = true
    end
end

function World:mousereleased(x, y, button)
    -- always end panning on release, even under a modal, or the map stays stuck
    -- in drag mode after it closes
    if button == 2 then self.panning = false end
    if Retro.released("hud.pause", x, y) then self:openPause(); return end
    if self.pause and self.pause.mousereleased then self.pause:mousereleased(x, y, button) end
    if self.dock and self.dock.mousereleased then self.dock:mousereleased(x, y, button) end
end

function World:mousemoved(x, y, dx, dy)
    if self.winScreen or self.mapReveal or self.album or self.dock then return end
    if self.panning then self.camera:drag(dx, dy) end
end

return World
