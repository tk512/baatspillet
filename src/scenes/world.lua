-- src/scenes/world.lua
-- The playable isometric ocean scene: islands, ports, the boat, the cargo
-- economy, the follow camera and the HUD.
--
-- Movement and collision happen in the flat ground plane; only drawing knows
-- about the isometric projection. Objects + boat are depth-sorted so the boat
-- slips behind or in front of raised land.

local config       = require("src.config")
local Assets       = require("src.assets")
local Iso          = require("src.systems.iso")
local Camera       = require("src.systems.camera")
local Terrain      = require("src.systems.terrain")
local Objects      = require("src.systems.objects")
local CargoSystem  = require("src.systems.cargo")
local Fog          = require("src.systems.fog")
local Treasure     = require("src.systems.treasure")
local Loader       = require("src.systems.loader")
local Boat         = require("src.entities.boat")
local Port         = require("src.entities.port")
local Pirate       = require("src.entities.pirate")
local Shark        = require("src.entities.shark")
local HUD          = require("src.ui.hud")
local Minimap      = require("src.ui.minimap")
local Album        = require("src.ui.album")
local MapReveal    = require("src.ui.mapreveal")
local WinScreen    = require("src.ui.winscreen")
local PortScreen   = require("src.ui.portscreen")
local Icons        = require("src.ui.icons")
local ShipInfo     = require("src.ui.shipinfo")
local PauseMenu    = require("src.ui.pausemenu")

local World = {}

-- Spread the town houses across the available OpenGFX cottage sprites, chosen
-- deterministically from the tile coords so a given map always looks the same
-- (worldgen is seeded; F6 must reproduce it). Missing art -> Objects.draw uses
-- the code-drawn building fallback.
local HOUSE_SPRITES = {
    "props/houses/house_1.png", "props/houses/house_2.png", "props/houses/house_3.png",
    "props/houses/house_4.png", "props/houses/house_5.png", "props/houses/house_6.png",
    "props/houses/house_7.png",
}
local function houseSprite(i, j)
    return HOUSE_SPRITES[(i * 7 + j * 13) % #HOUSE_SPRITES + 1]
end

-- Houses out in the countryside (away from the towns) bring back the original
-- brick house (props/house.png) -- weighted so it's the common sight -- mixed with
-- a few cottages for variety. Deterministic per tile.
local COUNTRY_HOUSES = {
    "props/house.png", "props/house.png", "props/house.png", "props/house.png",
    "props/houses/house_1.png", "props/houses/house_2.png", "props/houses/house_7.png",
}
local function countryHouseSprite(i, j)
    return COUNTRY_HOUSES[(i * 7 + j * 13) % #COUNTRY_HOUSES + 1]
end

-- Apartment blocks for the dense core of bigger towns (deterministic per tile).
local BLOCK_SPRITES = {
    "props/blocks/block_1.png", "props/blocks/block_2.png",
    "props/blocks/block_3.png", "props/blocks/block_4.png",
}
local function blockSprite(i, j)
    return BLOCK_SPRITES[(i * 5 + j * 11) % #BLOCK_SPRITES + 1]
end

function World:load(game)
    self.game    = game
    self.camera  = Camera.new()
    self.panning = false
    self.toast   = { text = "", timer = 0, rise = 0 }

    -- Ports (data-driven). Created first so the terrain can snap them to coasts.
    self.ports = {}
    for _, def in ipairs(game.data.ports) do
        self.ports[#self.ports + 1] = Port.new(def)
    end

    -- Build the procedurally heightmapped iso world (and place the ports).
    self.terrain = Terrain.new(self.ports)

    -- Boat: the player's "best" unlocked boat, started on open water.
    local unlocked = game.state.unlockedBoats
    local boatDef  = game:getBoatDef(unlocked[#unlocked])
    local sx, sy   = self:findStartWater(config.WORLD_WIDTH / 2, config.WORLD_HEIGHT / 2)
    self.boat = Boat.new(boatDef, sx, sy)

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
        if (p.kind == "forest" or p.kind == "house")
            and (ptile.level or 0) >= config.MOUNTAINS.TREELINE_LEVEL then
            -- above the treeline: bare rock/snow, no forests or houses
        elseif p.kind == "forest" then
            self.objects:add({
                tx = p.tx, ty = p.ty, z = pz, kind = "forest",
                draw = function(_, g) Objects.drawForest(g, p.salt) end,
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
    -- Cities: scatter buildings around each port to show how big the town is.
    for _, port in ipairs(self.ports) do
        self:scatterCity(port)
    end
    self:spawnLighthouses()    -- a lighthouse on the seaward coast of each town
    self:spawnPowerPlant()     -- the (in)famous Klokkarvik power plant

    self.ambientObstacles = {}  -- skerry bump circles (static)
    self.ships = {}             -- all ambient ships (idle + moving), solid + clickable
    self.shipPopup = nil        -- MarineTraffic-style info card, when a ship is tapped
    self:buildShipPool()        -- choose photo billboards if any exist, else OpenGFX sprites
    self:scatterAmbientBoats(26)
    self:scatterSkerries(14)    -- rocky outcrops dotting the open sea
    self:spawnVikingSky()      -- the real cruise ship at anchor outside Bergen

    self.cargoSystem = CargoSystem.new(self.ports)

    -- Fog of war: restore explored area from the save, then light up where the
    -- boat already is so the starting patch is visible.
    self.fog = Fog.new(game.state.fog)
    self.fog:revealAround(self.boat.x, self.boat.y, config.FOG_REVEAL)
    self._fogSaveT = 0

    -- World map (top-right): a Civ-style top-down map of the explored ocean,
    -- sharing the fog grid. Built last so terrain, ports and fog all exist.
    self.minimap = Minimap.new(self)

    -- Treasure hunt: chests on sandbanks off the biggest islands. Placement is
    -- seeded; the save only remembers which are found / mapped.
    local foundSet = {}
    for _, id in ipairs(game.state.treasuresFound or {}) do foundSet[id] = true end
    self.treasures = Treasure.build(self.terrain, foundSet)
    self.mapped = {}
    for _, id in ipairs(game.state.treasuresMapped or {}) do self.mapped[id] = true end
    self.album       = nil    -- the album overlay, when open
    self.mapReveal   = nil    -- the "Finn skatten!" reveal card, when up
    self.winScreen   = nil    -- the grand all-found finale, when up
    self.pause       = nil    -- the pause/menu overlay, when up
    self.racer       = nil    -- a pirate racing you to the active chest, when one's out
    self.treasureFX  = {}      -- chest-open coin bursts
    -- The "Finn skatten!" card appears only when a map is freshly granted on a
    -- delivery -- never on load and never during an active hunt (then the only job
    -- is to go find the chest the X/arrow already point to).
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

    self.splashes = {}       -- short-lived water bursts (e.g. a zapped pirate)
    self.eaten = {}          -- falling-food "Nam nam nam" bites
    self.sailDist = 0        -- distance sailed toward the next bite

    collectgarbage("collect")

    -- TEMPORARY: jump straight to the all-found finale (menu "Se finale" button).
    if game.previewWin then
        game.previewWin = nil
        self.pendingMapReveal = nil    -- no treasure card under the preview finale
        for _, tr in ipairs(self.treasures) do tr.found = true end
        self:openWinScreen()           -- closing it resets to the title, like a real win
    end
end

-- Scatter houses around a port's pad to make it read as a town. Count + spread
-- come from the port's `size` (config.CITY_SIZES). Houses only land on dry,
-- non-pad tiles, nearest-first, so they cluster around the harbour.
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

    -- Landmark placeholders for this town (blocky stand-ins; drop a matching
    -- PNG at assets/props/<sprite> later and it swaps in automatically). Which
    -- ones a town gets depends on its size + what it produces.
    local size = port.def.size or "small"
    local big  = (size == "medium" or size == "large")
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
    -- Big towns get a dense core of apartment blocks (cands are nearest-first, so
    -- the blocks cluster at the centre) ringed by cottages further out.
    local blockCore = big and math.floor(spec.houses * 0.4) or 0
    local placed = 0
    for k = 1, #cands do
        if not taken[k] and placed < spec.houses then
            placed = placed + 1
            local c = cands[k]
            local sprite = (placed <= blockCore) and blockSprite(c.i, c.j) or houseSprite(c.i, c.j)
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

-- A land tile that touches water on at least one side (so a lighthouse sits right
-- on the shore, not inland).
function World:tileIsCoast(i, j)
    local T = config.TILE
    local function water(a, b) return self.terrain:isWater((a - 0.5) * T, (b - 0.5) * T) end
    if water(i, j) then return false end
    return water(i + 1, j) or water(i - 1, j) or water(i, j + 1) or water(i, j - 1)
end

-- One lighthouse per town, on the most-seaward coastal tile near the harbour, so
-- it stands at the river/fjord mouth greeting boats. Placeholder-first: missing
-- art falls back to Objects.drawLighthouse.
function World:spawnLighthouses()
    local R = 9
    for _, port in ipairs(self.ports) do
        local best, bestScore
        for di = -R, R do
            for dj = -R, R do
                local i, j = port.tx + di, port.ty + dj
                if self:landTileFree(i, j) and self:tileIsCoast(i, j) then
                    -- count land neighbours: more = more solidly attached (not a thin
                    -- spit), so the lighthouse + its keeper's hut sit on land, not water.
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

-- A buildable land tile (in bounds, dry, not a harbour pad).
function World:landTileFree(i, j)
    if i < 1 or j < 1 or i > self.terrain.nx or j > self.terrain.ny then return false end
    if self.terrain.buildMask[i] and self.terrain.buildMask[i][j] then return false end
    local T = config.TILE
    return not self.terrain:isWater((i - 0.5) * T, (j - 0.5) * T)
end

-- Any land tile (in bounds, dry -- a pad counts as land).
function World:isLandTile(i, j)
    if i < 1 or j < 1 or i > self.terrain.nx or j > self.terrain.ny then return false end
    local T = config.TILE
    return not self.terrain:isWater((i - 0.5) * T, (j - 0.5) * T)
end

-- Solid ground for a building: the tile is buildable AND its four neighbours are
-- land, so a tile-filling building never sits at the shoreline hanging over water.
function World:solidLand(i, j)
    return self:landTileFree(i, j)
        and self:isLandTile(i + 1, j) and self:isLandTile(i - 1, j)
        and self:isLandTile(i, j + 1) and self:isLandTile(i, j - 1)
end

-- A big power plant on the land at Klokkarvik (an internal joke). Sits on a 2x2
-- patch of dry land, preferring a spot inland from the harbour. Placeholder-first:
-- a grey lot if the art is missing.
function World:spawnPowerPlant()
    if not Assets.image("props/powerplant.png") then return end
    local port = self:portById("klokkarvik")
    if not port then return end
    -- Pick the most INTERIOR land tile near the port: the one with the most land in
    -- its 3x3 neighbourhood, so the plant sits well inside the island and doesn't
    -- hang over the water. Ties broken toward the port.
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
        -- Clear nearby trees/houses so nothing hides the plant.
        self.objects:removeWhere(function(o)
            return (o.kind == "forest" or o.kind == "house")
                and o.tx >= i0 - 2 and o.tx <= i0 + 2 and o.ty >= j0 - 2 and o.ty <= j0 + 2
        end)
        -- Small footprint (~1 tile) so it tucks onto the little island.
        self.objects:add({
            tx = i0, ty = j0, w = 1, h = 1, z = self.terrain:tileZ(i0, j0),
            sprite = "props/powerplant.png", spriteScale = 1.2, kind = "powerplant",
            draw = function(_, g) Objects.drawLot(g, { 0.5, 0.5, 0.52 }) end,
        })
    end
end

-- Find a nearby water tile to start the boat on (spirals out from a guess).
function World:findStartWater(gx, gy)
    local T = config.TILE
    for r = 0, 40 do
        for a = 0, math.max(1, r * 6) do
            local ang = (a / math.max(1, r * 6)) * math.pi * 2
            local x = gx + math.cos(ang) * r * T
            local y = gy + math.sin(ang) * r * T
            if x > 0 and y > 0 and x < config.WORLD_WIDTH and y < config.WORLD_HEIGHT
               and self.terrain:isWater(x, y) then
                return x, y
            end
        end
    end
    return gx, gy
end

-- Decide the look of ambient ships: if any photo boats (src/data/ships.lua) have
-- their art present, the fleet is those stylized real-boat billboards; otherwise
-- it falls back to the OpenGFX 8-direction sprite ships.
function World:buildShipPool()
    self.shipDefs = {}
    for _, d in ipairs(self.game.data.ships or {}) do
        if Assets.image("ships_photos/" .. d.photo .. ".png") then
            self.shipDefs[#self.shipDefs + 1] = d
        end
    end
    self.usePhotos = #self.shipDefs > 0
end

-- One ship's visual + metadata (a random pick from the active pool). A given boat
-- always renders at ONE size (its def.scale, default 1) -- the same ship is never
-- shown bigger in one place than another; variety comes from adding more boats.
function World:pickShipLook()
    if self.usePhotos then
        local d = self.shipDefs[love.math.random(#self.shipDefs)]
        return { billboard = true, img = "ships_photos/" .. d.photo .. ".png", def = d }
    end
    return {
        billboard = false,
        sprite = config.AMBIENT_SHIPS[love.math.random(#config.AMBIENT_SHIPS)],
        col = config.SHIP_COLORS[love.math.random(#config.SHIP_COLORS)],
        def = { name = "Skip", country = "", type = "Lasteskip" },
    }
end

-- Register an ambient ship. opts: moving/speed/turn/turnDir, or an explicit `look`
-- (e.g. the Viking Sky). Size is fixed per boat (look.def.scale, default 1).
function World:addShip(gx, gy, angle, opts)
    opts = opts or {}
    local look = opts.look or self:pickShipLook()
    local scale = (look.def and look.def.scale) or 1.0
    local w = look.billboard and config.AMBIENT_PHOTO_WIDTH or config.AMBIENT_SHIP_WIDTH
    local s = {
        x = gx, y = gy, angle = angle, scale = scale,
        r = w * scale * config.AMBIENT_SHIP_RADIUS_FRAC,
        look = look,
        moving = opts.moving or false,
        speed = opts.speed or 0, turn = opts.turn, turnDir = opts.turnDir,
    }
    self.ships[#self.ships + 1] = s
    return s
end

-- A couple of ambient ships sitting in the sea just outside each harbour.
function World:spawnAmbientShips()
    for _, port in ipairs(self.ports) do
        local gx = port.x + port.seaDx * 260
        local gy = port.y + port.seaDy * 260
        if self.terrain:isWater(gx, gy) then
            local ang = math.atan2(-port.seaDx, port.seaDy)
            self:addShip(gx, gy, ang, { moving = false })
        end
    end
end

-- The real "Viking Sky" cruise liner, anchored on the open water just outside
-- Bergen. It's now a normal (stationary) ship like the rest: flat on the water,
-- no bob/shadow, and tappable for its info card (Viking Sky, Norge). A bit larger
-- than the others, as the landmark. Missing art -> the world runs without it.
function World:spawnVikingSky()
    if not Assets.image("props/vikingsky.png") then return end
    local port = self:portById("bergen")
    if not port then return end

    -- Anchor it well out from the harbour and off to one side (not right on the
    -- pier): step further out + along the shore until we hit open water.
    local sidex, sidey = -port.seaDy, port.seaDx      -- unit vector along the shore
    local gx, gy
    for _, d in ipairs({ 740, 860, 620, 980, 540 }) do
        for _, side in ipairs({ 560, -560, 360, -360, 0 }) do
            local x = port.x + port.seaDx * d + sidex * side
            local y = port.y + port.seaDy * d + sidey * side
            if x > 0 and y > 0 and x < config.WORLD_WIDTH and y < config.WORLD_HEIGHT
                and self.terrain:isWater(x, y) then
                gx, gy = x, y; break
            end
        end
        if gx then break end
    end
    if not gx then return end

    self:addShip(gx, gy, 0, {
        moving = false,
        look = {
            billboard = true,
            img = "props/vikingsky.png",
            def = { name = "Viking Sky", country = "Norge", type = "Cruiseskip", scale = 1.5 },
        },
    })
end

-- Scatter idle boats of various sizes around the open sea, just bobbing, to
-- make the world feel alive. Only on water tiles with water all around, so none
-- end up jammed onto a coast.
-- Water with clear water `m` units in all four directions: a spot a ship of that
-- reach can sit (or sail through) without clipping a coast.
function World:openSea(gx, gy, m)
    return self.terrain:isWater(gx, gy)
        and self.terrain:isWater(gx + m, gy) and self.terrain:isWater(gx - m, gy)
        and self.terrain:isWater(gx, gy + m) and self.terrain:isWater(gx, gy - m)
end

-- Clonking into a skerry: shake the whole screen, a comical "doooink!", and a
-- "Du traff et skjær!" toast. A short cooldown so grinding along one doesn't spam.
function World:hitSkerry()
    if self._skerryCd > 0 then return end
    self._skerryCd = 1.2
    self.camera:addShake(14)
    Assets.playSfx("doink", 0.9)
    self:showToast("Du traff et skjær!")
end

-- A random open-sea spot clear of the player's start AND every harbour (so a ship
-- never sits on a port and steals the docking click). Returns nil if none found.
function World:findShipSpot()
    local W, H = config.WORLD_WIDTH, config.WORLD_HEIGHT
    for _ = 1, 800 do
        local gx, gy = love.math.random() * W, love.math.random() * H
        local sdx, sdy = gx - self.boat.x, gy - self.boat.y
        if (sdx * sdx + sdy * sdy) > (600 * 600) and self:openSea(gx, gy, 70)
            and not self:nearAnyPort(gx, gy, 560) then
            return gx, gy
        end
    end
end

local function lookForDef(d)
    return { billboard = true, img = "ships_photos/" .. d.photo .. ".png", def = d }
end

-- Populate the sea. With real photo boats we place exactly ONE of each (there's
-- only one Aidaluna, one Viking Sky, etc. -- never the same ship twice); the sea
-- fills out as more boats are added to src/data/ships.lua. Without photos we fall
-- back to scattering `count` generic OpenGFX sprite ships (duplicates are fine).
function World:scatterAmbientBoats(count)
    if self.usePhotos then
        for _, d in ipairs(self.shipDefs) do
            local gx, gy = self:findShipSpot()
            if gx then
                self:addShip(gx, gy, love.math.random() * math.pi * 2,
                    { moving = false, look = lookForDef(d) })
            end
        end
        return
    end
    count = count or 18
    for _ = 1, count do
        local gx, gy = self:findShipSpot()
        if gx then self:addShip(gx, gy, love.math.random() * math.pi * 2, { moving = false }) end
    end
end

-- Scatter rocky skerries across the open sea: little outcrops that dot the water
-- and give the boat something to weave between. Solid (added to ambientObstacles,
-- so the boat bumps off them), kept well clear of harbours and the start spot.
function World:scatterSkerries(count)
    count = count or 12
    local T = config.TILE
    local W, H = config.WORLD_WIDTH, config.WORLD_HEIGHT
    local placed, tries = 0, 0
    while placed < count and tries < 800 do
        tries = tries + 1
        local gx, gy = love.math.random() * W, love.math.random() * H
        local sdx, sdy = gx - self.boat.x, gy - self.boat.y
        if (sdx * sdx + sdy * sdy) > (500 * 500) and self:openSea(gx, gy, 90)
            and not self:nearAnyPort(gx, gy, 600) then
            placed = placed + 1
            local salt = love.math.random() * 1000
            self.ambientObstacles[#self.ambientObstacles + 1] = { x = gx, y = gy, r = 22 }
            self.objects:add({
                tx = math.floor(gx / T) + 1, ty = math.floor(gy / T) + 1, z = 0,
                draw = function(_, g) Objects.drawSkerry(g, salt) end,
            })
        end
    end
end

-- A handful of ships that actually sail a slow, gentle course (cargo ships are
-- slow), so the sea looks alive. They're drawn in the depth-sorted pass (like the
-- boat) since they move; idle scattered boats stay in the static object layer.
-- Each turns away from coasts/edges rather than beaching itself.
function World:scatterMovingShips(count)
    count = count or 6
    local W, H = config.WORLD_WIDTH, config.WORLD_HEIGHT
    local placed, tries = 0, 0
    while placed < count and tries < 800 do
        tries = tries + 1
        local gx, gy = love.math.random() * W, love.math.random() * H
        local sdx, sdy = gx - self.boat.x, gy - self.boat.y
        if (sdx * sdx + sdy * sdy) > (700 * 700) and self:openSea(gx, gy, 110) then
            placed = placed + 1
            self:addShip(gx, gy, love.math.random() * math.pi * 2, {
                moving  = true,
                speed   = config.AMBIENT_SHIP_SPEED * (0.7 + love.math.random() * 0.6),
                turn    = 0.5 + love.math.random() * 0.4,       -- slow, lazy turns
                turnDir = (love.math.random() < 0.5) and -1 or 1,
            })
        end
    end
end

-- Sail each moving ship forward; if land or the world edge is close ahead, ease
-- the heading around (its fixed turnDir) until open water lies ahead again. Slow
-- and forgiving, never an obstacle the player must dodge.
function World:updateMovingShips(dt)
    local W, H = config.WORLD_WIDTH, config.WORLD_HEIGHT
    for _, s in ipairs(self.ships) do
        if s.moving then
            local lk = s.r + 70
            local ax = s.x + math.cos(s.angle) * lk
            local ay = s.y + math.sin(s.angle) * lk
            local blocked = ax < 60 or ay < 60 or ax > W - 60 or ay > H - 60
                or not self.terrain:isWater(ax, ay)
            if blocked then
                s.angle = s.angle + s.turnDir * s.turn * dt
            else
                s.x = s.x + math.cos(s.angle) * s.speed * dt
                s.y = s.y + math.sin(s.angle) * s.speed * dt
            end
        end
    end
end

-- The ambient ship under a screen tap (mx,my), or nil. Tested in SCREEN space
-- against each ship's on-screen sprite box: the billboard rises UP from its
-- waterline anchor, so a ground-circle test (which assumes z=0) would only catch
-- clicks at the very base. Nearest sprite-centre wins on overlap.
function World:shipAt(mx, my)
    local zoom = self.camera.zoom
    local best, bestD
    for _, s in ipairs(self.ships) do
        local ax, ay = self.camera:worldToScreen(s.x, s.y)   -- waterline anchor (bottom-centre)
        local wWorld, aspect
        if s.look.billboard then
            local img = Assets.image(s.look.img)
            wWorld = config.AMBIENT_PHOTO_WIDTH * s.scale
            aspect = img and (img:getHeight() / img:getWidth()) or 0.5
        else
            wWorld = config.AMBIENT_SHIP_WIDTH * s.scale
            aspect = 0.5
        end
        local onW = wWorld * zoom * 1.1                       -- a little finger-slack
        local onH = wWorld * aspect * zoom
        local left, right = ax - onW / 2, ax + onW / 2
        local top, bottom = ay - onH, ay + onH * 0.2          -- waterline + slight slack below
        if mx >= left and mx <= right and my >= top and my <= bottom then
            local cx, cy = ax, ay - onH / 2
            local d = (mx - cx) ^ 2 + (my - cy) ^ 2
            if not bestD or d < bestD then best, bestD = s, d end
        end
    end
    return best
end

-- True if (x,y) is within `r` of any town (so we don't park clouds over them).
function World:nearAnyPort(x, y, r)
    for _, p in ipairs(self.ports) do
        local dx, dy = x - p.x, y - p.y
        if dx * dx + dy * dy < r * r then return true end
    end
    return false
end

-- Float a couple of clouds above each tall-enough island summit, so clouds
-- gather around mountains and skip the flat little islands.
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

-- A cloud puff: rows of chunky pixel blocks within a radius. A cloud is a few
-- overlapping puffs, drawn in world space and lifted to their z over the peaks.
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
    -- Safety net: never stay stuck in right-drag panning across a modal opening
    -- or a loss of window focus (a release can be swallowed in either case).
    if self.panning and (self.dock or self.album or self.mapReveal or self.winScreen or self.pause
        or not love.window.hasFocus()) then
        self.panning = false
    end

    -- While a modal overlay is up (pause/win/reveal/album/docking), the world is frozen.
    if self.pause then self.pause:update(dt); return end
    if self.winScreen then self.winScreen:update(dt); self:updateWinAudio(dt); return end
    if self.mapReveal then self.mapReveal:update(dt); return end
    if self.album then self.album:update(dt); return end
    if self.dock then self.dock:update(dt); return end

    -- Dock just closed and a treasure map is waiting: pop the "Finn skatten!" card
    -- now (deferred so it follows the harbourmaster, not stacked over the dock).
    if self.pendingMapReveal then
        local t = self.pendingMapReveal
        self.pendingMapReveal = nil
        self:openMapReveal(t)
        return
    end

    self.terrain:update(dt)
    self.boat:update(dt)
    self.boat:blockLand(self.terrain)   -- keep the boat on the water
    self:updateMovingShips(dt)

    -- Sprite ships are solid: bump off them instead of sliding underneath. But
    -- docking always wins -- while latching in (or already in a port's range) we
    -- skip ship collision so a vessel near the harbour can't block the approach.
    self._skerryCd = math.max(0, (self._skerryCd or 0) - dt)
    if not self.latching and not self.nearPort then
        for _, s in ipairs(self.ambientObstacles) do   -- skerries: clonk + shake on a real hit
            if self.boat:collideCircle(s.x, s.y, s.r) then self:hitSkerry() end
        end
        for _, s in ipairs(self.ships) do              -- ambient ships
            self.boat:collideCircle(s.x, s.y, s.r)
        end
    end

    for _, port in ipairs(self.ports) do port:update(dt) end

    -- Reveal fog around the boat; flush new discoveries to disk only rarely
    -- (serializing the whole grid every frame is costly).
    if self.fog:revealAround(self.boat.x, self.boat.y, config.FOG_REVEAL) then
        self._fogDirty = true
        self.minimap:refresh()          -- paint the newly-revealed cells onto the map
    end
    self._fogSaveT = self._fogSaveT + dt
    if self._fogDirty and self._fogSaveT > 8 then
        self.game.state.fog = self.fog:serialize()
        self.game:save(); self._fogDirty = false; self._fogSaveT = 0
    end

    self:checkIslandDiscovery()

    self.nearPort = nil
    for _, port in ipairs(self.ports) do
        if port:isBoatInRange(self.boat) then self.nearPort = port; break end
    end

    -- Docking "latch": once close, the boat is gently pulled into the berth and
    -- the screen only opens once it's parked, so it doesn't unload out at sea.
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
        end
    else
        -- Sailed clear of the harbour we just left: cast off, beep once, and
        -- allow docking here again.
        if self.dockSuppress then
            Assets.playSfx("leave", 0.8)
            self.dockSuppress = nil
        end
    end

    self:updatePirate(dt)
    self:updateShark(dt)

    -- Auto-cannon (only once bought): fire back at an attacking pirate. We only
    -- target one that's still chasing -- once scared off (retreating), leave it
    -- be so it can sail away. Balls already in flight still finish their arc.
    if self.game:owns("cannon") then
        local target = (self.pirate and self.pirate.state == "chase") and self.pirate or nil
        self.boat:updateCannon(dt, target, function() self:cannonHitPirate() end)
    end

    self:updateTreasure(dt)

    -- Advance short-lived splash bursts.
    for i = #self.splashes, 1, -1 do
        local s = self.splashes[i]
        s.t = s.t + dt
        if s.t > 0.7 then table.remove(self.splashes, i) end
    end

    self:updateEating(dt)

    self.camera:edgeScroll(dt, self.boat.x, self.boat.y)  -- scroll, but never lose the boat
    if config.FOLLOW_CAMERA then
        self.camera:keepAnchorInView(self.boat.x, self.boat.y)  -- boat near edge pans the map
    end
    self.camera:update(dt)

    if self.toast.timer > 0 then
        self.toast.timer = self.toast.timer - dt
        self.toast.rise  = self.toast.rise + dt * 30
    end

    if self.shipPopup then           -- ship info card lingers a few seconds, then fades out
        self.shipPopup.t = self.shipPopup.t + dt
        if self.shipPopup.t > 9 then self.shipPopup = nil end
    end
end

function World:checkIslandDiscovery()
    for _, isl in ipairs(self.terrain.islandCenters) do
        local dx, dy = self.boat.x - isl.x, self.boat.y - isl.y
        local reach = (isl.radius or 520) + 200   -- "discovered" on reaching its coast
        if (dx * dx + dy * dy) < (reach * reach) and not self:isDiscovered(isl.id) then
            table.insert(self.game.state.discoveredIslands, isl.id)
            self.game:save()
            self:showToast("Ny øy oppdaget!")
            Assets.playSfx("deliver")
        end
    end
end

function World:isDiscovered(id)
    for _, d in ipairs(self.game.state.discoveredIslands) do
        if d == id then return true end
    end
    return false
end

-- ===== Treasure hunt ====================================================
-- Harbourmasters hand out maps; sail onto a mapped chest and a pirate sweeps in
-- to contest it. With the cannon you scare him off and win the chest; with no
-- cannon the pirates take it -- but it's never lost, the X just stays so you can
-- come back once you've bought a cannon. Collectibles fill the album.

-- A harbourmaster reveals the nearest un-found, un-mapped chest to this port. The
-- caller only invokes it on a successful delivery, so maps are a reward for trade
-- (not every visit), and only one is out at a time. No cannon needed to GET a map
-- -- you just can't win the chest without one (the pirate takes it), which is how
-- the player learns they need the cannon.
-- Returns true if a map was actually handed over (so the dock screen can show
-- the "Finn skatten!" choice).
function World:revealTreasureMap(port)
    if self:activeTreasure() then return false end          -- one treasure at a time
    -- The very first map (never had one) is guaranteed so the hunt is introduced;
    -- after that it's an occasional surprise on delivery, not every time.
    local everHad = #self.game.state.treasuresMapped > 0 or #self.game.state.treasuresFound > 0
    if everHad and love.math.random() >= config.TREASURE.MAP_CHANCE then return false end
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
    table.insert(self.game.state.treasuresMapped, best.id)
    self.game:save()
    -- Defer the big "Finn skatten!" card until the dock screen closes, so it
    -- reads as its own moment after the harbourmaster (see World:update).
    self.pendingMapReveal = best
    return true
end

function World:openMapReveal(t)
    self.mapReveal = MapReveal.new(self, t)
    self:showToast("Finn skatten!")
    -- celebratory audio (Finn-Erik's voice can replace these later)
    if not Assets.playNamedVoice("finn_skatten") and not Assets.playNamedVoice("skattekart") then
        Assets.playSfx("deliver")
    end
    Assets.playSfx("horn", 0.5)
end

function World:closeMapReveal()
    self.mapReveal = nil
end

-- The nearest mapped, un-found chest -- what the gold arrow points to.
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

function World:updateTreasure(dt)
    -- advance chest-open coin bursts
    for i = #self.treasureFX, 1, -1 do
        local fx = self.treasureFX[i]
        fx.t = fx.t + dt
        if fx.t > 1.4 then table.remove(self.treasureFX, i) end
    end

    -- A pirate races you to the active chest (spawns + moves here).
    local active = self:activeTreasure()
    self:updateRace(dt, active)

    -- YOU grab any chest you reach -- checked first, so a tie goes to the player.
    local R = config.TREASURE.REACH
    for _, t in ipairs(self.treasures) do
        if self.mapped[t.id] and not t.found then
            local dx, dy = self.boat.x - t.x, self.boat.y - t.y
            if (dx * dx + dy * dy) < R * R and not self.latching and not self.dock then
                self:grabTreasure(t); return
            end
        end
    end

    -- ...otherwise, if the pirate got there first, it steals the chest.
    if active and self.racer and self.racer.state ~= "retreat" then
        local pdx, pdy = self.racer.x - active.x, self.racer.y - active.y
        if (pdx * pdx + pdy * pdy) < R * R then self:pirateStealsTreasure(active) end
    end
end

-- The treasure race: once you're closing in on the active chest a (slightly
-- slower) pirate sets off for it too. This just spawns + steers the racer; who
-- actually reaches it is decided in updateTreasure (player first).
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

    -- "Fort deg!" cue + send the pirate off, when you first come within range of
    -- the chest. The cue is independent of the racer placement, so the voice
    -- always fires on approach (re-arms once you've sailed well clear).
    local dx, dy = self.boat.x - active.x, self.boat.y - active.y
    local d2 = dx * dx + dy * dy
    local trig2 = config.TREASURE.RACE_TRIGGER * config.TREASURE.RACE_TRIGGER
    if d2 < trig2 then
        if not active.cued and not self.dock and not self.latching then
            active.cued = true
            if not self.racer then self:spawnRacer(active) end
            if not Assets.playNamedVoice("fort_deg") then Assets.playSfx("pirate_warn", 0.9) end
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

-- The pirate beat you to it: it makes off with the chest, so the X vanishes (no
-- deadlock -- you're not stuck circling it). The chest goes back in the pool, so
-- a later delivery can hand you its map again for another go.
function World:pirateStealsTreasure(t)
    t.cued = nil                       -- so it cues again if re-mapped later
    self.mapped[t.id] = nil
    for i, id in ipairs(self.game.state.treasuresMapped) do
        if id == t.id then table.remove(self.game.state.treasuresMapped, i); break end
    end
    self.game:save()
    if self.racer then self.racer:flee() end
    self._racerExitT = 1.4              -- it sails off with the loot, then vanishes
    self:showToast("Sjørøverne tok skatten!")
    Assets.playSfx("cannon_hit", 0.6)
end

-- Drop a pirate into the race, out at roughly your own distance from the chest
-- (it's slower, so a straight dash beats it; dawdle and it wins).
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
                self.racer.goal = t
                self.racer.angle = math.atan2(t.y - y, t.x - x)
                return
            end
        end
    end
end

-- Reaching a chest grabs it: stop the boat, send any racer packing, win it.
function World:grabTreasure(t)
    self.boat:clearDestination()
    if self.racer then self.racer = nil; Assets.stopChase() end
    self:winTreasure(t)
end

function World:winTreasure(t)
    t.found = true
    table.insert(self.game.state.treasuresFound, t.id)
    self.game:addCoins(config.TREASURE.GOLD)     -- persists the save
    self.treasureFX[#self.treasureFX + 1] = { x = t.x, y = t.y, t = 0, good = t.good }
    Assets.playSfx("deliver")
    if not Assets.playNamedVoice("skatt") then Assets.playSfx("coin", 0.8) end
    self:showToast("Skatt! +" .. config.TREASURE.GOLD .. " gull")

    local all = true
    for _, tr in ipairs(self.treasures) do if not tr.found then all = false; break end end
    if all then self:openWinScreen() end
end

function World:openWinScreen()
    self.winScreen = WinScreen.new(self)
    self:showToast("Alle skatter funnet!")
    -- Duck the world music; a cheer plays first, then the looping celebration song
    -- starts once the cheer is (nearly) done (see World:update's winScreen branch).
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

-- Once the cheer has (almost) finished, start the looping celebration song.
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

-- Pause / menu overlay. Only opens when no other modal is up; ESC and the bottom-
-- right menu button toggle it.
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

-- Save and return to the title screen (what the old ESC did; now the pause menu's
-- "Hovedmeny" button).
function World:exitToMenu()
    self:flushFog()              -- persist exploration
    self.game:save()
    self.game:setScene("menu")
end

-- Pirates appear rarely while sailing the open sea with gold to lose. Once one
-- is hunting we run its AI; it despawns when it gives up or is shaken off.
function World:updatePirate(dt)
    if self.pirate then
        self.pirate:update(dt, self.boat, self.terrain, function() self:pirateHit() end)
        if self.pirate.dead then
            self.pirate = nil
            self.pirateCooldown = config.PIRATE.RESPAWN_GRACE
            Assets.stopChase()
        end
        return
    end

    -- only roll for a spawn while actually sailing open water with gold aboard
    local eligible = self.game.state.coins > 0 and not self.latching and not self.dock
        and self.boat.speed > self.boat.maxSpeed * 0.3
    if not eligible then return end
    self.pirateCooldown = self.pirateCooldown - dt
    if self.pirateCooldown <= 0 and love.math.random() < dt / config.PIRATE.SPAWN_MEAN then
        self:spawnPirate()
    end
end

function World:spawnPirate()
    -- Find open water to appear on: sweep several distance rings (preferring a
    -- dramatic ~1200 away, falling back closer) over many angles, so it still
    -- finds sea when the boat is in a pocket between the big islands.
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
    Assets.playSfx("pirate_warn", 0.95)
    Assets.startChase()
    self:showToast("Sjørøvere!")
end

-- Drop the friendly shark onto open water a little way from the boat. It sweeps
-- a few angles at a random distance in [SPAWN_MIN, SPAWN_MAX]; if nothing clear
-- is found the world simply runs without it (it's purely ambient).
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

-- Run the friendly shark and apply its soft bounce. It dives away while a pirate
-- is hunting. The bounce reuses boat:collideCircle (the island-nudge feel), but
-- we skip it while latching so it can't fight the auto-docking glide.
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

-- Crew + passengers eat as you sail. Every config.EAT_DISTANCE travelled, one
-- food unit aboard is eaten: it drops off the boat with a "Nam nam nam!". The
-- longer the voyage, the more gets eaten -- a reason to stock up at the shop.
function World:updateEating(dt)
    -- advance falling-food bites (rise a touch, then drop + fade)
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

-- Draw the eating in world space so it's clearly a passenger MUNCHING the food
-- (not dropping it): the snack floats up above the deck and a passenger leans in
-- and chomps it down in three bites, with crumbs flying, while "Nam nam nam!"
-- shows. Reads as eating from a glance.
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

-- Your cannon landed a hit. It takes a few hits to drive a pirate off, so it
-- really chases and shoots you first; only once it has taken SCARE_HITS does it
-- turn tail and sail away (and it may return another day). No sinking, no spoils.
function World:cannonHitPirate()
    if not self.pirate or self.pirate.state ~= "chase" then return end
    self.splashes[#self.splashes + 1] = { x = self.pirate.x, y = self.pirate.y, t = 0 }
    self.pirate.hits = (self.pirate.hits or 0) + 1
    Assets.playSfx("cannon_hit", 0.9)
    self.camera:addShake(7)
    if self.pirate.hits >= config.CANNON.SCARE_HITS then
        self.pirate:flee()                            -- driven off; sails away
        self:showToast("Sjørøveren rømmer!")          -- "The pirate flees!"
    else
        self:showToast("Treff!")                      -- "Hit!" -- keep at it
    end
end

-- A cannonball struck the boat: lose a little gold (never below zero) and shake
-- the screen. If you're now broke the pirate gives up and sails off.
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

-- Dock at a port and pop the docking screen. Decides what the screen shows:
--   deliver  - carrying goods bound for this town (gold!)
--   busy     - already carrying a mission for another town
--   offer    - this town has a job and the boat has room
--   visit    - nothing to do right now
function World:openDock(port)
    -- Harbours are always safe: any hunting pirate breaks off when you dock.
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

    -- While you've a treasure map on the go, no new oppdrag -- the harbourmaster
    -- turns you away: "Finn skatten først!" (find the treasure first). Deliveries
    -- of cargo you already carry still go through.
    if self:activeTreasure() and mode ~= "deliver" then
        mode, offer = "findfirst", nil
    end

    -- A treasure map is a reward for a delivery -- but not every time (a chance,
    -- with the very first one guaranteed so the hunt always gets introduced), and
    -- only when no hunt is already on the go. Granted up front so the deliver
    -- screen can offer the choice (Finn skatten! vs Butikk); the big card pops
    -- once the dock closes.
    local mapGiven = (mode == "deliver") and self:revealTreasureMap(port) or false

    self.dock = PortScreen.new(self, port, {
        mode = mode, offer = offer, earned = earned, delivered = delivered,
        mission = self.boat.cargo[1],       -- so "busy" can name where to go
        mapGiven = mapGiven,                -- harbourmaster handed over a treasure map
    })
    self.dockSuppress = port.id    -- don't immediately re-pop while still in range
end

-- Flush explored fog into save state immediately (e.g. on ESC to menu), since
-- reveals are otherwise only written every ~8s.
function World:flushFog()
    if self._fogDirty then
        self.game.state.fog = self.fog:serialize()
        self._fogDirty = false
    end
end

function World:showToast(text)
    self.toast.text, self.toast.timer, self.toast.rise = text, 2.0, 0
end

function World:draw()
    love.graphics.clear(config.colors.water_deep)

    self.camera:attach()
    self:drawWorldSorted()
    self:drawClouds()              -- soft clouds hanging over the mountain peaks
    self:drawFog()                 -- dark over everything not yet explored
    self.camera:detach()

    HUD.draw(self)

    if not self.dock and not self.album and not self.mapReveal and not self.winScreen
        and not self.pause then
        self:drawMissionPointer()    -- "go this way!" hint (cargo destination)
        self:drawTreasurePointer()   -- orange "to the treasure!" arrow + ring
        self:drawPirateIndicator()   -- red "danger this way!" arrow when off-screen
        self.minimap:draw()          -- world map + treasure X's
        self:drawShipPopup()         -- MarineTraffic-style card for a tapped ship
        HUD.drawPauseButton(self)    -- tappable pause/menu (bottom-right)
    end
    if self.dock then self.dock:draw() end            -- docking modal
    if self.album then self.album:draw() end          -- album overlay
    if self.mapReveal then self.mapReveal:draw() end  -- "Finn skatten!" card
    if self.winScreen then self.winScreen:draw() end  -- grand finale, on top of all
    if self.pause then self.pause:draw() end          -- pause/menu overlay, on top
end

-- The info card for a tapped ship, anchored above it (it follows a moving ship).
function World:drawShipPopup()
    if not self.shipPopup then return end
    local s = self.shipPopup.ship
    local sx, sy = self.camera:worldToScreen(s.x, s.y)
    ShipInfo.draw(s, sx, sy, self.game.fonts)
end

-- When a hunting pirate is off-screen, pin a pulsing red arrow to the screen
-- edge pointing at it, so the child knows which way the danger is (to flee).
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

-- While on a mission, draw a big bouncing arrow above the boat pointing toward
-- the destination town, plus a pulsing ring on that town, so a non-reader
-- always knows where to go next.
function World:drawMissionPointer()
    if self:activeTreasure() then return end   -- on a hunt: the treasure is the goal, not a harbour
    local m = self.boat.cargo[1]
    if not m then return end
    local port = self:portById(m.toId)
    if not port then return end

    local bx, by = self.camera:worldToScreen(self.boat.x, self.boat.y)
    local tx, ty = self.camera:worldToScreen(port.x, port.y)
    local ang = math.atan2(ty - by, tx - bx)
    local t = love.timer.getTime()

    -- pulsing ring on the target town (if it's on screen)
    local sw, sh = love.graphics.getWidth(), love.graphics.getHeight()
    if tx > 0 and tx < sw and ty > 0 and ty < sh then
        local pr = 30 + math.sin(t * 4) * 7
        love.graphics.setColor(0, 0, 0, 0.5)
        love.graphics.setLineWidth(7); love.graphics.circle("line", tx, ty, pr)
        love.graphics.setColor(m.color[1], m.color[2], m.color[3], 0.95)
        love.graphics.setLineWidth(4); love.graphics.circle("line", tx, ty, pr)
        love.graphics.setLineWidth(1)
    end

    -- A big, bold arrow hovering above the boat, bobbing toward the target.
    local hx, hy = bx, by - 88 + math.sin(t * 3) * 7
    local s = (1 + 0.07 * math.sin(t * 5)) * 1.4
    love.graphics.push()
    love.graphics.translate(hx, hy)
    love.graphics.rotate(ang)
    love.graphics.scale(s, s)
    -- canonical arrow pointing +x (tip → head corners → shaft → tail)
    local arrow = {
         34,   0,   -- tip
         14, -20,   -- head top corner
         14,  -8,   -- step in to shaft
        -30,  -8,   -- shaft tail top
        -30,   8,   -- shaft tail bottom
         14,   8,   -- step out
         14,  20,   -- head bottom corner
    }
    love.graphics.setColor(0, 0, 0, 0.28)                -- soft drop shadow
    love.graphics.push(); love.graphics.translate(3, 4)
    love.graphics.polygon("fill", arrow); love.graphics.pop()
    love.graphics.setColor(0.99, 0.83, 0.22)             -- bright gold fill
    love.graphics.polygon("fill", arrow)
    love.graphics.setColor(0.10, 0.08, 0.05)             -- thick dark outline
    love.graphics.setLineWidth(6); love.graphics.polygon("line", arrow)
    love.graphics.setLineWidth(1)
    love.graphics.pop()
    love.graphics.setColor(1, 1, 1)
end

-- In-world treasure markers (camera-attached): each mapped, un-found chest rests
-- on a little sandbank with a bobbing chest + pulsing ring so the spot is visible
-- as you sail up. Plus the short coin-burst + rising sticker when a chest is won.
function World:drawTreasures()
    local t = love.timer.getTime()
    for _, tr in ipairs(self.treasures) do
        if self.mapped[tr.id] and not tr.found then
            local sx, sy = Iso.project(tr.x, tr.y, 0)
            local sand = config.colors.sand
            -- a little sandbank poking out of the shallows: water halo, wet rim,
            -- dry sandy top + a few speckles, so it clearly reads as a sand bank.
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

    -- A few gold coins jump out of the opened chest and arc back down, then fade.
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

-- An always-on, distinctly-coloured "treasure" arrow above the boat toward the
-- active chest, plus a pulsing ring on the chest when it's on screen -- so the
-- youngest players can always find their way to the treasure.
local TREASURE_ARROW = { 0.98, 0.46, 0.12 }   -- warm orange (not the gold mission arrow)
function World:drawTreasurePointer()
    local tr = self:activeTreasure()
    if not tr then return end

    local bx, by = self.camera:worldToScreen(self.boat.x, self.boat.y)
    local tx, ty = self.camera:worldToScreen(tr.x, tr.y)
    local ang = math.atan2(ty - by, tx - bx)
    local t = love.timer.getTime()
    local sw, sh = love.graphics.getWidth(), love.graphics.getHeight()

    -- pulsing ring on the chest when it's on screen
    if tx > 0 and tx < sw and ty > 0 and ty < sh then
        local pr = 28 + math.sin(t * 4) * 7
        love.graphics.setColor(0, 0, 0, 0.45)
        love.graphics.setLineWidth(6); love.graphics.circle("line", tx, ty, pr)
        love.graphics.setColor(TREASURE_ARROW)
        love.graphics.setLineWidth(3); love.graphics.circle("line", tx, ty, pr)
        love.graphics.setLineWidth(1)
    end

    -- the arrow, bobbing above the boat
    local hx, hy = bx, by - 84 + math.sin(t * 3) * 6
    local s = (1 + 0.07 * math.sin(t * 5)) * 1.35
    love.graphics.push(); love.graphics.translate(hx, hy); love.graphics.rotate(ang); love.graphics.scale(s, s)
    local arrow = { 30, 0, 12, -17, 12, -7, -26, -7, -26, 7, 12, 7, 12, 17 }
    love.graphics.setColor(0, 0, 0, 0.28)
    love.graphics.push(); love.graphics.translate(3, 4); love.graphics.polygon("fill", arrow); love.graphics.pop()
    love.graphics.setColor(TREASURE_ARROW); love.graphics.polygon("fill", arrow)
    love.graphics.setColor(0.10, 0.06, 0.03); love.graphics.setLineWidth(5); love.graphics.polygon("line", arrow)
    love.graphics.setLineWidth(1)
    love.graphics.pop()
    love.graphics.setColor(1, 1, 1)
end

-- Deterministic noise in [0,1) per world sub-cell. Keyed on world indices (not
-- screen), so the frayed fog edge stays put as the camera scrolls.
local function fogNoise(a, b)
    local n = (a * 374761393 + b * 668265263) % 2147483647
    n = (n * ((n % 8191) * 15731 + 789221) + 1376312589) % 2147483647
    return (n % 1024) / 1024
end

-- Cover every visible, not-yet-explored tile with dark "unknown". Interior fog
-- is one diamond per tile (cheap); along the reveal boundary the tile is frayed
-- into granular sub-diamonds (a noise-dithered edge, like the coastline / peaks),
-- so the dark doesn't read as hard blocky steps. Follows the sloped surface so
-- unexplored islands, cities and props stay hidden until the boat sails close.
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
                -- fully revealed: nothing to draw
            elseif sum == 0 and not centre then
                -- fully hidden: a single dark diamond following the slope
                local ax, ay = Iso.project(bx0,     by0,     z00)
                local bx, by = Iso.project(bx0 + T, by0,     z10)
                local cx, cy = Iso.project(bx0 + T, by0 + T, z11)
                local dx, dy = Iso.project(bx0,     by0 + T, z01)
                love.graphics.polygon("fill", ax, ay, bx, by, cx, cy, dx, dy)
            else
                -- boundary: fray into granular sub-diamonds (noise-dithered)
                for a = 0, K - 1 do
                    for b = 0, K - 1 do
                        local uc, vc = (a + 0.5) / K, (b + 0.5) / K
                        local r = r00 * (1 - uc) * (1 - vc) + r10 * uc * (1 - vc)
                                + r01 * (1 - uc) * vc       + r11 * uc * vc
                        if r < fogNoise(i * K + a, j * K + b) then
                            local u0, u1 = a / K, (a + 1) / K
                            local v0, v1 = b / K, (b + 1) / K
                            local function P(u, v)
                                local z = z00 * (1 - u) * (1 - v) + z10 * u * (1 - v)
                                        + z01 * (1 - u) * v       + z11 * u * v
                                return Iso.project(bx0 + u * T, by0 + v * T, z)
                            end
                            local ax, ay = P(u0, v0)
                            local bx, by = P(u1, v0)
                            local cx, cy = P(u1, v1)
                            local dx, dy = P(u0, v1)
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

-- Pass 1 draws the flat ground (no occlusion, no sort needed); pass 2 draws the
-- things sitting on it (objects, boat, pirate, destination marker) depth-sorted
-- among themselves so buildings and trees overlap the boat correctly.
function World:drawWorldSorted()
    local minGx, minGy, maxGx, maxGy = self.camera:groundBounds()
    local i0, j0, i1, j1 = self.terrain:visibleRange(minGx, minGy, maxGx, maxGy)

    -- Only water tiles draw per-tile (they animate); full-land tiles are baked
    -- into landMesh and draw nothing here.
    for i = i0, i1 do
        for j = j0, j1 do
            self.terrain:drawTile(i, j)
        end
    end

    -- Baked static ground: full-land tiles, then the jagged shoreline over the
    -- water bases.
    love.graphics.setColor(1, 1, 1)
    if self.terrain.landMesh  then love.graphics.draw(self.terrain.landMesh)  end
    if self.terrain.coastMesh then love.graphics.draw(self.terrain.coastMesh) end

    -- Pass 2. Render lists are pooled and reused across frames.
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
    if self.ships then
        local mb = 120                                 -- cull ships well off-screen
        for mi = 1, #self.ships do
            local s = self.ships[mi]
            if s.x > minGx - mb and s.x < maxGx + mb and s.y > minGy - mb and s.y < maxGy + mb then
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
    for k = #objs, no + 1, -1 do objs[k] = nil end
    table.sort(objs, byDepth)
    for k = 1, no do
        local it = objs[k]
        if it.kind == "object" then Objects.draw(it.obj)
        elseif it.kind == "ship" then
            local s = it.obj
            local ok
            if s.look.billboard then
                ok = Objects.drawShipBillboard(s.look.img, s.x, s.y, s.angle, s.scale)
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
        elseif it.kind == "dest" then self:drawDestinationMarker() end
    end

    -- cannonballs arc above everything in the world (still camera-attached)
    if self.pirate then self.pirate:drawBalls() end
    if self.game:owns("cannon") then self.boat:drawCannonBalls() end
    self:drawSplashes()
    self:drawEaten()
    self:drawTreasures()     -- chests on sandbanks + win bursts (camera-attached)
    love.graphics.setColor(1, 1, 1)
end

-- Expanding rings + droplets where something splashed (a zapped pirate). Drawn
-- in world space, camera-attached.
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

-- While docked, all input goes to the docking screen. Docking itself is
-- automatic (sail up to a port and the screen pops), so there's no load key.
function World:keypressed(key)
    if self.pause then self.pause:keypressed(key); return end
    if self.winScreen then self.winScreen:keypressed(key); return end
    if self.mapReveal then self.mapReveal:keypressed(key); return end
    if self.album then self.album:keypressed(key); return end
    if self.dock then self.dock:keypressed(key); return end
    if key == "c" then
        self.camera:centerOn(self.boat.x, self.boat.y)  -- recenter on the boat
    elseif key == "b" then
        self:openAlbum()                                -- open the treasure album
    -- DEV-ONLY playtest keys (remove before shipping):
    --   G = +50 gold (also makes a pirate eligible to spawn)
    --   P = summon a pirate in close, right now, to test the cannon fight
    elseif key == "g" then
        self.game:addCoins(50)
        self:showToast("+50 gull (dev)")
    elseif key == "p" then
        self:devSpawnPirateClose()
    elseif key == "k" then
        for _, t in ipairs(self.treasures) do      -- DEV: reveal every treasure map
            if not t.found and not self.mapped[t.id] then
                self.mapped[t.id] = true
                table.insert(self.game.state.treasuresMapped, t.id)
            end
        end
        self.game:save()
        self:showToast("Alle skattekart (dev)")
    end
end

-- DEV-ONLY: drop a pirate ~500 units away on open water so a fight starts at
-- once. Mirrors spawnPirate but at close range. Remove with the G/P keys above.
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
                Assets.playSfx("pirate_warn", 0.95)
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
        local pb = self._pauseBtnRect      -- bottom-right menu button -> pause overlay
        if pb and x >= pb.x and x <= pb.x + pb.w and y >= pb.y and y <= pb.y + pb.h then
            self:openPause(); return
        end
        local r = self._skatterRect       -- clicking the "Skatter" bar opens the album
        if r and x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h then
            self:openAlbum(); return
        end
        if self.latching then return end   -- being pulled into the berth; ignore clicks
        local ship = self:shipAt(x, y)      -- screen-space hit test on the sprite
        if ship then                        -- tap a ship -> its info card (don't sail)
            self.shipPopup = { ship = ship, t = 0 }
            Assets.playSfx("coin", 0.5)
            return
        end
        self.shipPopup = nil                -- tap open water -> close any card and sail
        local wx, wy = self.camera:screenToWorld(x, y)
        self.boat:setDestination(wx, wy)
    elseif button == 2 then
        self.panning = true
    end
end

function World:mousereleased(x, y, button)
    -- Always end panning on the right-button release, even if a modal is up --
    -- otherwise a release swallowed while a screen is open leaves the map "stuck"
    -- in drag mode after it closes.
    if button == 2 then self.panning = false end
end

function World:mousemoved(x, y, dx, dy)
    if self.winScreen or self.mapReveal or self.album or self.dock then return end
    if self.panning then self.camera:drag(dx, dy) end
end

-- Wheel zoom is intentionally ignored: the kid kept zooming all the way out.
-- The view stays at config.CAMERA_DEFAULT_ZOOM.
function World:wheelmoved(dx, dy)
end

return World
