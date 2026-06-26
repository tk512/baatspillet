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

local World = {}

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
                tx = p.tx, ty = p.ty, z = pz,
                draw = function(_, g) Objects.drawForest(g, p.salt) end,
            })
        elseif p.kind == "house" then
            self.objects:add({
                tx = p.tx, ty = p.ty, z = pz,
                sprite = "props/house.png",
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

    self:spawnAmbientShips()
    self:scatterAmbientBoats()
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
    local T = config.TILE
    local ti, tj, R = port.tx, port.ty, spec.spread
    local cands = {}
    for di = -R, R do
        for dj = -R, R do
            local i, j = ti + di, tj + dj
            if i >= 1 and j >= 1 and i <= self.terrain.nx and j <= self.terrain.ny then
                local pad = self.terrain.buildMask[i] and self.terrain.buildMask[i][j]
                local gx, gy = (i - 0.5) * T, (j - 0.5) * T
                if not pad and not self.terrain:isWater(gx, gy) then
                    cands[#cands + 1] = { i = i, j = j, d = di * di + dj * dj }
                end
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
    if big then marks[#marks + 1] = { sprite = "props/market.png", fn = Objects.drawMarket } end
    if big then marks[#marks + 1] = { sprite = "props/crane.png",  fn = Objects.drawCrane } end
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
    local placed = 0
    for k = 1, #cands do
        if not taken[k] and placed < spec.houses then
            placed = placed + 1
            local c = cands[k]
            self.objects:add({
                tx = c.i, ty = c.j, z = self.terrain:tileZ(c.i, c.j), sprite = "props/house.png",
                draw = function(_, g)
                    Objects.building(g.cx, g.cy, 16, 16, g.z, 22, 14,
                        config.colors.building_wall, config.colors.building_dk)
                end,
            })
        end
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

-- A couple of ambient ships bobbing in the sea just outside each harbor.
function World:spawnAmbientShips()
    local T = config.TILE
    for si, port in ipairs(self.ports) do
        local gx = port.x + port.seaDx * 260
        local gy = port.y + port.seaDy * 260
        if self.terrain:isWater(gx, gy) then
            local col = config.SHIP_COLORS[((si) % #config.SHIP_COLORS) + 1]
            local ang = math.atan2(-port.seaDx, port.seaDy)
            local phase = si * 1.3
            self.objects:add({
                tx = math.floor(gx / T) + 1, ty = math.floor(gy / T) + 1, z = 0,
                draw = function(_, g)
                    local bob = math.sin(love.timer.getTime() * 1.2 + phase) * 2
                    Objects.drawShip(g.cx, g.cy, ang, col, 1.0, bob)
                end,
            })
        end
    end
end

-- The real "Viking Sky" cruise liner, lying at anchor on the open water just
-- outside Bergen. It's a photo billboard (assets/props/vikingsky.png) that holds
-- still and bobs gently on the waves -- a big landmark, several times the ferry.
-- If the art is missing the world just runs without it (placeholder-first).
function World:spawnVikingSky()
    local img = Assets.image("props/vikingsky.png")
    if not img then return end
    -- The PNG is pre-baked small (~160px) so it reads as a slightly-pixelated
    -- retro sprite; nearest filtering (Assets default) keeps it crisp, no moiré.

    local port = self:portById("bergen")
    if not port then return end

    -- Anchor it well out from the harbour and off to one side (not right on the
    -- pier): step further out + along the shore until we hit open water.
    local T = config.TILE
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

    local groundY = Assets.imageGroundY("props/vikingsky.png") or img:getHeight()
    local scale   = 115 / img:getWidth()          -- on-screen length (~0.8x the ferry's 140)
    local shW     = img:getWidth() * scale         -- for the cast shadow
    self.objects:add({
        tx = math.floor(gx / T) + 1, ty = math.floor(gy / T) + 1, z = 0,
        draw = function()
            local bob = math.sin(love.timer.getTime() * 0.6) * 4   -- gentle wave bob
            local sx, sy = Iso.project(gx, gy, 0)
            love.graphics.setColor(0, 0, 0, 0.16)                  -- soft shadow on the water
            love.graphics.ellipse("fill", sx, sy + 4, shW * 0.42, shW * 0.08)
            love.graphics.setColor(1, 1, 1)
            love.graphics.draw(img, sx, sy + bob, 0, scale, scale, img:getWidth() / 2, groundY)
        end,
    })
end

-- Scatter idle boats of various sizes around the open sea, just bobbing, to
-- make the world feel alive. Only on water tiles with water all around, so none
-- end up jammed onto a coast.
function World:scatterAmbientBoats(count)
    count = count or 18
    local T = config.TILE
    local W, H = config.WORLD_WIDTH, config.WORLD_HEIGHT
    local function openWater(gx, gy)
        return self.terrain:isWater(gx, gy)
            and self.terrain:isWater(gx + 70, gy) and self.terrain:isWater(gx - 70, gy)
            and self.terrain:isWater(gx, gy + 70) and self.terrain:isWater(gx, gy - 70)
    end
    local placed, tries = 0, 0
    while placed < count and tries < 600 do
        tries = tries + 1
        local gx, gy = love.math.random() * W, love.math.random() * H
        -- keep them away from the player's starting spot so they don't crowd it
        local sdx, sdy = gx - self.boat.x, gy - self.boat.y
        if (sdx * sdx + sdy * sdy) > (600 * 600) and openWater(gx, gy) then
            placed = placed + 1
            local scale = 0.55 + love.math.random() * 1.05   -- tiny dinghy to big freighter
            local col   = config.SHIP_COLORS[love.math.random(#config.SHIP_COLORS)]
            local ang   = love.math.random() * math.pi * 2
            local phase = love.math.random() * 6.28
            local rate  = 0.8 + love.math.random() * 0.7      -- each bobs at its own pace
            self.objects:add({
                tx = math.floor(gx / T) + 1, ty = math.floor(gy / T) + 1, z = 0,
                draw = function(_, g)
                    local bob = math.sin(love.timer.getTime() * rate + phase) * 2
                    Objects.drawShip(g.cx, g.cy, ang, col, scale, bob)
                end,
            })
        end
    end
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
    if self.panning and (self.dock or self.album or self.mapReveal or self.winScreen
        or not love.window.hasFocus()) then
        self.panning = false
    end

    -- While a modal overlay is up (win/reveal/album/docking), the world is frozen.
    if self.winScreen then self.winScreen:update(dt); return end
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
    if not active then
        if self.racer then                          -- no chest in play: send any racer off
            if self.racer.state ~= "retreat" then self.racer:flee() end
            self.racer:update(dt, self.boat, self.terrain)
            if self.racer.dead then self.racer = nil; Assets.stopChase() end
        end
        return
    end

    if not self.racer and not self.dock and not self.latching then
        local dx, dy = self.boat.x - active.x, self.boat.y - active.y
        if (dx * dx + dy * dy) < config.TREASURE.RACE_TRIGGER * config.TREASURE.RACE_TRIGGER then
            self:spawnRacer(active)
        end
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
    self.mapped[t.id] = nil
    for i, id in ipairs(self.game.state.treasuresMapped) do
        if id == t.id then table.remove(self.game.state.treasuresMapped, i); break end
    end
    self.game:save()
    if self.racer then self.racer:flee() end
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
                Assets.playSfx("pirate_warn", 0.9)
                Assets.startChase()
                self:showToast("Sjørøvere! Kappløp om skatten!")
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
    if not Assets.playNamedVoice("du_vant") and not Assets.playNamedVoice("bra_jobba") then
        Assets.playSfx("deliver")
    end
    Assets.playSfx("horn", 0.7)
end

function World:closeWinScreen()
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

    if not self.dock and not self.album and not self.mapReveal and not self.winScreen then
        self:drawMissionPointer()    -- "go this way!" hint (cargo destination)
        self:drawTreasurePointer()   -- orange "to the treasure!" arrow + ring
        self:drawPirateIndicator()   -- red "danger this way!" arrow when off-screen
        self.minimap:draw()          -- world map + treasure X's
        HUD.drawMusicButton(self)    -- tappable music on/off (bottom-right)
    end
    if self.dock then self.dock:draw() end            -- docking modal
    if self.album then self.album:draw() end          -- album overlay
    if self.mapReveal then self.mapReveal:draw() end  -- "Finn skatten!" card
    if self.winScreen then self.winScreen:draw() end  -- grand finale, on top of all
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

    for _, fx in ipairs(self.treasureFX) do
        local p = fx.t / 1.4
        local sx, sy = Iso.project(fx.x, fx.y, 0)
        love.graphics.setColor(1, 1, 1, 1 - p)                       -- collectible rises
        Icons.draw(fx.good, sx, sy - 20 - p * 40, 30)
        for k = 1, 8 do                                              -- coins fly out
            local ang = (k / 8) * math.pi * 2
            local d, up = p * 50, math.sin(math.min(p, 0.6) * math.pi) * 30
            love.graphics.setColor(config.colors.gold[1], config.colors.gold[2], config.colors.gold[3], 1 - p)
            love.graphics.circle("fill", sx + math.cos(ang) * d, sy + math.sin(ang) * d * 0.5 - up, 3 * (1 - p) + 1)
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
    if self.winScreen then self.winScreen:mousepressed(x, y, button); return end
    if self.mapReveal then self.mapReveal:mousepressed(x, y, button); return end
    if self.album then self.album:mousepressed(x, y, button); return end
    if self.dock then self.dock:mousepressed(x, y, button); return end
    if button == 1 then
        local mb = self._musicBtnRect      -- tap the speaker to toggle music/sound
        if mb and x >= mb.x and x <= mb.x + mb.w and y >= mb.y and y <= mb.y + mb.h then
            config.AUDIO_ON = not config.AUDIO_ON
            Assets.refreshAudio()
            return
        end
        local r = self._skatterRect       -- clicking the "Skatter" bar opens the album
        if r and x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h then
            self:openAlbum(); return
        end
        if self.latching then return end   -- being pulled into the berth; ignore clicks
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
