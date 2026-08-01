-- Every non-player vessel plus the skerries they weave between: spawning
-- (populate), the sail-about AI (wait/goal/free) and the tap test (shipAt).
-- world.lua reads fleet.ships for the draw pass and collision, fleet.obstacles
-- for skerry bumps. Add a boat in src/data/ships.lua, not here.

local config  = require("src.config")
local Assets  = require("src.assets")
local Objects = require("src.systems.objects")

local Fleet = {}
Fleet.__index = Fleet

-- module-level so world.lua shares it (clouds keep off the towns)
function Fleet.nearAnyPort(ports, x, y, r, except)
    for _, p in ipairs(ports) do
        if p ~= except then
            local dx, dy = x - p.x, y - p.y
            if dx * dx + dy * dy < r * r then return true end
        end
    end
    return false
end

local function portById(ports, id)
    for _, p in ipairs(ports) do
        if p.id == id then return p end
    end
end

local function lookForDef(d)
    return { billboard = true, img = "ships_photos/" .. d.photo .. ".png", def = d }
end

-- deps: terrain, ports, objects, boat (spawn clearance + AI LOD distance),
-- data (the ships.lua list), splash (optional fn(x,y) for the sub's bubbles)
function Fleet.new(deps)
    local self = setmetatable({}, Fleet)
    self.terrain = deps.terrain
    self.ports   = deps.ports
    self.objects = deps.objects
    self.boat    = deps.boat
    self.data    = deps.data or {}
    self.splash  = deps.splash
    self.ships     = {}   -- all ambient ships (idle + moving), solid + clickable
    self.obstacles = {}   -- skerry + rig bump circles (static)
    -- The fleet's OWN generator, seeded from the map (CLAUDE.md, "Determinism":
    -- same seed -> same world, and F6 must reproduce it). The terrain always
    -- obeyed that because it is noise, but everything SCATTERED here -- skerries,
    -- ambient ships, oil rigs, buoy jitter -- ran on love.math.random, which LÖVE
    -- seeds from the clock. So the sea furniture moved on every single load: a
    -- platform you sailed out to yesterday was somewhere else today, and no
    -- amount of checking a position in one run said anything about the next.
    --
    -- A LOCAL generator rather than seeding the global one, so gameplay
    -- randomness -- where a pirate appears, fireworks, the dolphins -- stays
    -- genuinely different every time.
    self.rng = love.math.newRandomGenerator(config.WORLD_SEED)
    return self
end

-- one call from World:load
-- `sea` is the current map's sea-furniture table (maps.lua), nil for a map that
-- wants none -- which is Norge, deliberately.
function Fleet:populate(sea)
    self:buildShipPool()
    self:scatterAmbientBoats(26)
    self:scatterSkerries(14)
    self:spawnVikingSky()
    sea = sea or {}
    -- `rigs` is either a list of exact spots (what shipped maps use) or a COUNT
    -- to scatter, which prints a paste-ready list in dev so a new map can be
    -- scattered once and then frozen.
    if type(sea.rigs) == "table" then self:placeRigs(sea.rigs)
    elseif sea.rigs then self:scatterRigs(sea.rigs, sea.rig) end
    if sea.buoys then self:layBuoys() end
end

-- photo billboards when their art is present, else OpenGFX sprite ships
function Fleet:buildShipPool()
    self.shipDefs = {}
    for _, d in ipairs(self.data) do
        if Assets.image("ships_photos/" .. d.photo .. ".png") then
            self.shipDefs[#self.shipDefs + 1] = d
        end
    end
    self.usePhotos = #self.shipDefs > 0
end

-- A ship's visual + metadata. One boat always renders at ONE size (def.scale);
-- variety comes from adding boats, never from resizing the same one.
function Fleet:pickShipLook()
    if self.usePhotos then
        local d = self.shipDefs[self.rng:random(#self.shipDefs)]
        return lookForDef(d)
    end
    return {
        billboard = false,
        sprite = config.AMBIENT_SHIPS[self.rng:random(#config.AMBIENT_SHIPS)],
        col = config.SHIP_COLORS[self.rng:random(#config.SHIP_COLORS)],
        def = { name = "Skip", country = "", type = "Lasteskip" },
    }
end

-- opts: moving/speed/turn/turnDir, or an explicit `look`
function Fleet:addShip(gx, gy, angle, opts)
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
        patrol = opts.patrol, baseSpeed = opts.speed or 0,
        bounce = opts.bounce or false,
        home = opts.home,        -- {x,y,r,min}: shuttle leash for a home-port boat
        route = opts.route,      -- ferry stops [{x,y},...]; loops, dwelling at each
        visits = opts.visits,    -- ports this liner calls at now and then
        dwell = opts.dwell,      -- pause length at a stop (default AMBIENT_VISIT.DWELL)
    }
    if s.route then              -- ferries begin lying at their first stop
        s.routeI = 1
        s.waitT = (s.dwell or config.AMBIENT_VISIT.DWELL) * (0.3 + self.rng:random() * 0.7)
    end
    if look.def and look.def.submarine then
        -- s.dive: 0 surfaced .. 1 under; drives clipping, collision and taps
        local U = config.SUBMARINE
        s.submarine = true
        s.dive = 1
        s.subState = "under"
        -- first surfacing comes sooner, so the surprise lands early
        s.subT = (U.SUBMERGED_MIN + self.rng:random() * (U.SUBMERGED_MAX - U.SUBMERGED_MIN)) * 0.5
    end
    self.ships[#self.ships + 1] = s
    return s
end

-- only when the player is near: no mystery blubbs from across the ocean
function Fleet:subFX(s)
    local dx, dy = s.x - self.boat.x, s.y - self.boat.y
    if (dx * dx + dy * dy) > config.SUBMARINE.FX_DIST * config.SUBMARINE.FX_DIST then return end
    if self.splash then self.splash(s.x, s.y) end
    Assets.playSfx("blubb", 0.9)
end

-- Peek-a-boo cycle: deep -> rise -> cruise surfaced -> sink. Movement is
-- untouched, so every surfacing happens somewhere new.
function Fleet:updateDive(s, dt)
    local U = config.SUBMARINE
    if s.subState == "under" then
        s.subT = s.subT - dt
        if s.subT <= 0 then
            s.subState = "rising"
            self:subFX(s)
        end
    elseif s.subState == "rising" then
        s.dive = s.dive - dt / U.TRANSITION
        if s.dive <= 0 then
            s.dive = 0
            s.subState = "up"
            s.subT = U.SURFACE_MIN + self.rng:random() * (U.SURFACE_MAX - U.SURFACE_MIN)
        end
    elseif s.subState == "up" then
        s.subT = s.subT - dt
        if s.subT <= 0 then
            s.subState = "sinking"
            self:subFX(s)
        end
    else -- sinking
        s.dive = s.dive + dt / U.TRANSITION
        if s.dive >= 1 then
            s.dive = 1
            s.subState = "under"
            s.subT = U.SUBMERGED_MIN + self.rng:random() * (U.SUBMERGED_MAX - U.SUBMERGED_MIN)
        end
    end
end

-- The Viking Sky, anchored outside Bergen as a landmark. An ordinary
-- stationary ship otherwise; without its art the world just runs without it.
function Fleet:spawnVikingSky()
    if not Assets.image("props/vikingsky.png") then return end
    local port = portById(self.ports, "bergen")
    if not port then return end

    -- out from the harbour and off to one side, never on the pier
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
            def = { name = "Viking Sky", country = "Norge", type = "Cruiseskip", scale = 1.15 },
        },
    })
end

-- clear water `m` units in all four directions
function Fleet:openSea(gx, gy, m)
    return self.terrain:isWater(gx, gy)
        and self.terrain:isWater(gx + m, gy) and self.terrain:isWater(gx - m, gy)
        and self.terrain:isWater(gx, gy + m) and self.terrain:isWater(gx, gy - m)
end

-- Clear of the player's start and every harbour, so a ship can't sit on a port
-- and steal the docking click. nil if none found.
function Fleet:findShipSpot()
    local W, H = config.WORLD_WIDTH, config.WORLD_HEIGHT
    for _ = 1, 800 do
        local gx, gy = self.rng:random() * W, self.rng:random() * H
        local sdx, sdy = gx - self.boat.x, gy - self.boat.y
        if (sdx * sdx + sdy * sdy) > (600 * 600) and self:openSea(gx, gy, 70)
            and not Fleet.nearAnyPort(self.ports, gx, gy, 560) then
            return gx, gy
        end
    end
end

-- open water all the way `dist` out along `ang`?
function Fleet:clearAlong(gx, gy, ang, dist)
    local c, s = math.cos(ang), math.sin(ang)
    for t = 40, dist, 40 do
        if not self.terrain:isWater(gx + c * t, gy + s * t) then return false end
    end
    return true
end

-- Spawn + heading for a cruise ship: open water at least `reach` BOTH ways
-- along the line, so the patrol is a real lane and not a puddle. With `port`
-- set it's a ring outside that harbour, still clear of the pier. nil if no lane.
function Fleet:findCruiseLane(reach, port)
    for _ = 1, 20 do
        local gx, gy
        if port then
            local a = self.rng:random() * math.pi * 2
            local r = config.AMBIENT_HOME_MIN
                + self.rng:random() * (config.AMBIENT_HOME_LEASH - config.AMBIENT_HOME_MIN)
            local x, y = port.x + math.cos(a) * r, port.y + math.sin(a) * r
            if x > 60 and y > 60 and x < config.WORLD_WIDTH - 60
                and y < config.WORLD_HEIGHT - 60 and self:openSea(x, y, 70)
                and not Fleet.nearAnyPort(self.ports, x, y, 560, port) then
                gx, gy = x, y
            end
        else
            gx, gy = self:findShipSpot()
            if not gx then return end
        end
        if gx then
            for _ = 1, 8 do
                local a = self.rng:random() * math.pi * 2
                if self:clearAlong(gx, gy, a, reach)
                    and self:clearAlong(gx, gy, a + math.pi, reach) then
                    return gx, gy, a
                end
            end
        end
    end
end

-- Two-stop ferry route around `port`'s island, with an all-water line between
-- the stops so the pathfinding-less ferry can't beach. nil if the coast is
-- too tight.
function Fleet:buildFerryRoute(port)
    local W, H = config.WORLD_WIDTH, config.WORLD_HEIGHT
    local base = math.atan2(port.seaDy, port.seaDx)
    -- from the PIER TIP, not the town centre: never dwell on the dock art
    local dpx, dpy = port.x, port.y
    if port.dockPoint then dpx, dpy = port:dockPoint() end
    local ax, ay
    for _, dist in ipairs({ 300, 380, 460 }) do
        for _, side in ipairs({ 0, 0.5, -0.5, 1.0, -1.0 }) do
            local a = base + side
            local x, y = dpx + math.cos(a) * dist, dpy + math.sin(a) * dist
            if x > 60 and y > 60 and x < W - 60 and y < H - 60 and self:openSea(x, y, 60) then
                ax, ay = x, y; break
            end
        end
        if ax then break end
    end
    if not ax then return end
    local bx, by, bestD = nil, nil, 0
    for _ = 1, 60 do                       -- farthest reachable spot wins
        local a = self.rng:random() * math.pi * 2
        local r = 550 + self.rng:random() * 500
        local x, y = port.x + math.cos(a) * r, port.y + math.sin(a) * r
        if x > 60 and y > 60 and x < W - 60 and y < H - 60 and self:openSea(x, y, 60)
            and not Fleet.nearAnyPort(self.ports, x, y, 560, port) then
            local dx, dy = x - ax, y - ay
            local d = math.sqrt(dx * dx + dy * dy)
            if d > 350 and d > bestD and self:clearAlong(ax, ay, math.atan2(dy, dx), d) then
                bestD, bx, by = d, x, y
            end
        end
    end
    if not bx then return end
    return { { x = ax, y = ay }, { x = bx, y = by } }
end

-- open water in the ring outside the pier, so docking stays clear
function Fleet:findAnchorage(port)
    local V = config.AMBIENT_VISIT
    for _ = 1, 50 do
        local a = self.rng:random() * math.pi * 2
        local r = V.RING_MIN + self.rng:random() * (V.RING_MAX - V.RING_MIN)
        local x, y = port.x + math.cos(a) * r, port.y + math.sin(a) * r
        if x > 60 and y > 60 and x < config.WORLD_WIDTH - 60 and y < config.WORLD_HEIGHT - 60
            and self:openSea(x, y, 60) and not Fleet.nearAnyPort(self.ports, x, y, 560, port) then
            return x, y
        end
    end
end

-- Exactly ONE of each photo boat -- there is only one Aidaluna -- so the sea
-- fills out by adding boats to ships.lua. Without photos, `count` generic
-- sprite ships are scattered instead and duplicates are fine.
-- Boats flagged `cruise` in ships.lua sail slowly instead of lying at anchor,
-- turning around when land blocks the way. A `home` boat runs a ferry route
-- (buildFerryRoute); a `visits` boat calls at its listed cities now and then.
function Fleet:scatterAmbientBoats(count)
    if self.usePhotos then
        for _, d in ipairs(self.shipDefs) do
            local gx, gy = self:findShipSpot()
            local angle = self.rng:random() * math.pi * 2
            local opts = { moving = false, look = lookForDef(d) }
            if d.cruise then
                opts.moving = true
                opts.speed = d.speed or config.AMBIENT_CRUISE_SPEED
                opts.bounce = true
                if d.visits then                 -- liner calling at its cities
                    local list = {}
                    for _, pid in ipairs(d.visits) do
                        local p = portById(self.ports, pid)
                        if p then list[#list + 1] = p end
                    end
                    if #list > 0 then opts.visits = list end
                end
                local home = d.home and portById(self.ports, d.home)
                if d.patrol and home then     -- excitable: speeds up near the player
                    opts.patrol = d.patrol
                end
                -- leashOnly: no A→B ferry route — the boat just hangs around
                -- its island (fewer heading flips for one-sided sprites)
                local route = (not d.leashOnly) and home and self:buildFerryRoute(home)
                if route then                    -- ferry: spawn at stop A, bound for B
                    opts.route = route
                    opts.dwell = config.AMBIENT_HOME_DWELL
                    gx, gy = route[1].x, route[1].y
                    angle = math.atan2(route[2].y - route[1].y, route[2].x - route[1].x)
                else
                    local reach = home and config.AMBIENT_HOME_LANE or config.AMBIENT_CRUISE_LANE
                    local cx, cy, ca = self:findCruiseLane(reach, home)
                    if cx and home then          -- no route fits: leash a lane instead
                        opts.home = { x = home.x, y = home.y,
                                      r = config.AMBIENT_HOME_LEASH,
                                      min = config.AMBIENT_HOME_MIN }
                    end
                    if not cx and home then      -- tight coast at home: any open lane
                        cx, cy, ca = self:findCruiseLane(config.AMBIENT_CRUISE_LANE)
                    end
                    if cx then gx, gy, angle = cx, cy, ca end   -- else: any spot, still bounces
                    if d.heading then angle = d.heading end     -- data-driven drift direction
                end
            end
            if gx then self:addShip(gx, gy, angle, opts) end
        end
        return
    end
    count = count or 18
    for _ = 1, count do
        local gx, gy = self:findShipSpot()
        if gx then self:addShip(gx, gy, self.rng:random() * math.pi * 2, { moving = false }) end
    end
end

-- Scatter rocky skerries across the open sea: little outcrops that dot the water
-- and give the boat something to weave between. Solid (added to self.obstacles,
-- so the boat bumps off them), kept well clear of harbours and the start spot.
function Fleet:scatterSkerries(count)
    count = count or 12
    local T = config.TILE
    local W, H = config.WORLD_WIDTH, config.WORLD_HEIGHT
    local placed, tries = 0, 0
    while placed < count and tries < 800 do
        tries = tries + 1
        local gx, gy = self.rng:random() * W, self.rng:random() * H
        local sdx, sdy = gx - self.boat.x, gy - self.boat.y
        if (sdx * sdx + sdy * sdy) > (500 * 500) and self:openSea(gx, gy, 90)
            and not Fleet.nearAnyPort(self.ports, gx, gy, 600) then
            placed = placed + 1
            local salt = self.rng:random() * 1000
            self.obstacles[#self.obstacles + 1] = { x = gx, y = gy, r = 22 }
            self.objects:add({
                tx = math.floor(gx / T) + 1, ty = math.floor(gy / T) + 1, z = 0,
                draw = function(_, g) Objects.drawSkerry(g, salt) end,
            })
        end
    end
end

-- ── Sea furniture ────────────────────────────────────────────────────────────
-- Switched on per map by its `sea` table (src/data/maps.lua), because an oil rig
-- in a fjord is the same mistake as a glass tower in one. Both go in during
-- populate(), which runs inside the loading coroutine, so the placement search
-- costs nothing at play time.

-- Offshore platforms, out where there is nothing else. They are SOLID -- the
-- point of a structure in open water is that you sail around it -- and the bump
-- circle is generous, since the sprite's legs are far wider than its deck and
-- clipping through a leg reads as the art being broken.
--
-- They also keep APART from each other: left to pure chance two would eventually
-- land in sight of one another and read as one confused industrial estate rather
-- than as separate landmarks worth sailing out to.
-- `over` is the map's optional per-map override (a `rig` table in its `sea`
-- entry): Norway's platforms belong far out in the North Sea, not tucked between
-- islands, so Norge asks for much more open water than Amerika does.
function Fleet:scatterRigs(count, over)
    if not count or count <= 0 then return 0 end
    local R = config.SEA.RIG
    over = over or {}
    local CLEAR     = over.clear    or R.CLEAR
    local FROM_PORT = over.fromPort or R.FROM_PORT
    local NEAR_PORT = over.nearPort or R.NEAR_PORT
    local APART     = over.apart    or R.APART
    local T = config.TILE
    local W, H = config.WORLD_WIDTH, config.WORLD_HEIGHT

    -- A platform belongs in an ANNULUS round the towns: far enough out to be
    -- offshore (FROM_PORT), close enough in to be somewhere the boat goes
    -- (NEAR_PORT). Both bounds were learned the hard way. With only a lower
    -- bound, "far from every harbour" and "far from the game" turn out to be the
    -- same place -- Norge's towns only span x 3500..9000, so the rigs went to
    -- the map's outer margins where nobody sails. The upper bound is what keeps
    -- them in the water you actually cross.
    local cand, tries = {}, 0
    while #cand < 240 and tries < 4000 do
        tries = tries + 1
        local gx, gy = self.rng:random() * W, self.rng:random() * H
        local bdx, bdy = gx - self.boat.x, gy - self.boat.y
        -- Off the map's own edge too. openSea samples through tileIndexAt, which
        -- CLAMPS to the map, so a point hard against the border reads as having
        -- open water on that side -- a rig came out at y = 26, wedged into the
        -- top edge. The border is a wall, so treat it like one.
        local inBounds = gx > CLEAR and gy > CLEAR
                     and gx < W - CLEAR and gy < H - CLEAR
        if inBounds
           and (bdx * bdx + bdy * bdy) > R.FROM_BOAT * R.FROM_BOAT
           and self:openSea(gx, gy, CLEAR)
           and not Fleet.nearAnyPort(self.ports, gx, gy, FROM_PORT)
           and Fleet.nearAnyPort(self.ports, gx, gy, NEAR_PORT) then
            cand[#cand + 1] = { x = gx, y = gy }
        end
    end
    if #cand == 0 then return 0 end

    -- Farthest-point selection: each platform goes to whichever remaining spot
    -- is furthest from the ones already standing. That spreads them over the
    -- water the map actually has, without needing to know where that water is.
    -- On its own it drives everything into the map's corners, which is what the
    -- annulus above is holding back.
    local chosen = { cand[1] }
    while #chosen < count do
        local best, bestD = nil, -1
        for _, c in ipairs(cand) do
            local near = math.huge
            for _, k in ipairs(chosen) do
                local dx, dy = c.x - k.x, c.y - k.y
                local d = dx * dx + dy * dy
                if d < near then near = d end
            end
            if near > bestD then best, bestD = c, near end
        end
        if not best or bestD < APART * APART then break end   -- no room left
        chosen[#chosen + 1] = best
    end

    for _, c in ipairs(chosen) do self:addRig(c.x, c.y) end
    if config.DEV then
        -- Paste-ready, because a scattered map is meant to be FROZEN once it
        -- looks right: see the note on `rigs` in src/data/maps.lua.
        local out = {}
        for _, c in ipairs(chosen) do
            out[#out + 1] = ("{ %d, %d }"):format(math.floor(c.x), math.floor(c.y))
        end
        print("rigs = { " .. table.concat(out, ", ") .. " },")
    end
    return #chosen
end

-- One rig, at an exact spot. Both the authored list and the scatter come through
-- here, so they cannot drift apart in size, sprite or bump radius.
function Fleet:addRig(gx, gy)
    local R = config.SEA.RIG
    local T = config.TILE
    if config.DEV and not self:openSea(gx, gy, 120) then
        print(("WARNING: rig at (%d, %d) is not in open water"):format(gx, gy))
    end
    do
        local salt = (gx * 131 + gy * 977) % 1000
        local obj = self.objects:add({
            -- TWO tiles wide, matching the 128px sprite. Objects.draw scales a
            -- sprite to FILL the footprint and Iso.footprint makes that exactly
            -- tiles*64, so 2 tiles + a 128px canvas is TTD's own 1:1 pixel scale.
            -- Getting this pair out of step is what makes a rig either a giant or
            -- a postage stamp.
            tx = math.floor(gx / T) + 1, ty = math.floor(gy / T) + 1, z = 0,
            w = 2, h = 2,
            sprite = "props/rig/rig.png",
            draw = function(_, g) Objects.drawRig(g, salt) end,
        })
        self.obstacles[#self.obstacles + 1] =
            { x = gx, y = gy, r = R.RADIUS, kind = "rig", obj = obj }
    end
end

-- Rigs at coordinates the map states outright. This is what a shipped map uses:
-- procedural placement is fine for finding good spots, but it moves the moment
-- the terrain, the channels or a tuning number changes, and then every position
-- has to be re-checked. Written down, they are the same on every device and any
-- one of them can be nudged by hand without touching the rules.
function Fleet:placeRigs(list)
    for _, r in ipairs(list) do self:addRig(r[1], r[2]) end
    return #list
end

-- Rigs are placed before the treasure is, because populate() runs first -- so a
-- platform can end up standing on a sandbank with a chest on it. Its bump circle
-- would then make that chest unreachable, and a hunt you cannot finish is a dead
-- end with no way out of it: the marker keeps pointing at something the boat
-- physically cannot get to. Losing one platform out of six is invisible; that is
-- not. Called from World:load once the treasures exist.
function Fleet:unblockTreasures(treasures)
    if not treasures or #treasures == 0 then return 0 end
    local gone = 0
    for i = #self.obstacles, 1, -1 do
        local o = self.obstacles[i]
        if o.kind == "rig" then
            for _, tr in ipairs(treasures) do
                local dx, dy = tr.x - o.x, tr.y - o.y
                -- the rig's own reach plus room to sail up and take the chest
                local pad = o.r + 220
                if dx * dx + dy * dy < pad * pad then
                    if config.DEV then
                        print(("WARNING: rig at (%d, %d) stands on a treasure -- "
                            .. "withdrawn. Move it in maps.lua."):format(o.x, o.y))
                    end
                    if o.obj then self.objects:removeWhere(function(q) return q == o.obj end) end
                    table.remove(self.obstacles, i)
                    gone = gone + 1
                    break
                end
            end
        end
    end
    return gone
end

-- A row of markers leading out of each harbour mouth, the way a real channel is
-- marked. NOT decoration: a five-year-old cannot read a town name, but he can
-- follow a line of red buoys, and they are visible from further out than the
-- town is. They are deliberately NOT solid (config.SEA.BUOY.RADIUS = 0) --
-- bumping off the thing you were told to follow teaches the wrong lesson.
--
-- The line is aimed from the port toward open water: the bearing with the most
-- water along it wins, which is the harbour's approach by definition. A port
-- whose approach can't be found simply gets no buoys rather than a row across
-- a headland.
function Fleet:layBuoys()
    local B = config.SEA.BUOY
    local T = config.TILE
    local reach = B.FIRST + B.STEP * (B.COUNT - 1)
    local n = 0
    for _, p in ipairs(self.ports) do
        local best, bestScore = nil, 0
        for k = 0, 23 do                              -- 24 bearings, 15 degrees apart
            local a = k * math.pi / 12
            local c, s = math.cos(a), math.sin(a)
            local score = 0
            for d = B.FIRST, reach, 60 do
                if self.terrain:isWater(p.x + c * d, p.y + s * d) then score = score + 1
                else break end
            end
            if score > bestScore then best, bestScore = a, score end
        end
        -- the whole row must be afloat, or it isn't a channel
        if best and bestScore >= math.ceil((reach - B.FIRST) / 60) then
            local c, s = math.cos(best), math.sin(best)
            local nx, ny = -s, c                      -- sideways, for the jitter
            for i = 1, B.COUNT do
                local d = B.FIRST + B.STEP * (i - 1)
                local off = (self.rng:random() * 2 - 1) * B.JITTER
                local bx, by = p.x + c * d + nx * off, p.y + s * d + ny * off
                if self.terrain:isWater(bx, by) then
                    n = n + 1
                    local phase = self.rng:random() * 6.28
                    self.objects:add({
                        tx = math.floor(bx / T) + 1, ty = math.floor(by / T) + 1, z = 0,
                        draw = function(_, g) Objects.drawBuoy(g, phase) end,
                    })
                end
            end
        end
    end
    return n
end

-- Water (and world) clear along the ship's whole look-ahead ray on `ang`?
-- Sampled at several points, not just the tip, so a thin headland between the
-- ship and the far sample can't slip through (a coast-hugging liner would
-- otherwise walk straight onto it).
local function clearAt(self, s, c, sn, d, W, H)
    local ax, ay = s.x + c * d, s.y + sn * d
    return ax >= 60 and ay >= 60 and ax <= W - 60 and ay <= H - 60
        and self.terrain:isWater(ax, ay)
end

-- `lk` overrides the look-ahead reach: ships stuck in a pocket smaller than
-- their normal horizon (see escape mode below) probe just 20 units so they can
-- creep back out of the channel they came in by.
local function aheadClear(self, s, ang, W, H, lk)
    lk = lk or (s.escape and 20 or s.r + 70)
    local c, sn = math.cos(ang), math.sin(ang)
    return clearAt(self, s, c, sn, 12, W, H)
        and clearAt(self, s, c, sn, lk * 0.45, W, H)
        and clearAt(self, s, c, sn, lk, W, H)
end

-- Steer a ship toward s.goal: ease the heading onto the target, swing aside
-- (its fixed turnDir) when land blocks the way, creep along until open again.
-- Arriving drops anchor for s.dwell seconds; the goal timeout gives up on
-- unreachable spots so nobody circles a fjord forever.
function Fleet:steerShip(s, dt, W, H)
    local V = config.AMBIENT_VISIT
    local g = s.goal
    local dx, dy = g.x - s.x, g.y - s.y
    if (dx * dx + dy * dy) < 70 * 70 then                    -- arrived: lie at anchor
        s.goal = nil
        s.waitT = s.dwell or V.DWELL
        return
    end
    s.goalT = (s.goalT or V.TIMEOUT) - dt
    if s.goalT <= 0 then                                     -- unreachable: give up
        s.goal, s.goalT = nil, nil
        if s.route then s.waitT = s.dwell or V.DWELL end     -- ferry tries the next stop
        return
    end
    -- While skirting land, commit to the swing for a moment (s.avoidT) instead
    -- of re-aiming at the goal every frame -- otherwise the ship hugs the coast
    -- at a crawl (turn in, turn out, repeat) and long legs time out.
    if s.avoidT and s.avoidT > 0 then
        s.avoidT = s.avoidT - dt
    else
        local want = math.atan2(dy, dx)
        local diff = (want - s.angle + math.pi) % (math.pi * 2) - math.pi
        local step = V.TURN_RATE * dt
        s.angle = s.angle + math.max(-step, math.min(step, diff))
    end
    if not aheadClear(self, s, s.angle, W, H) then
        s.avoidT = 1.2
        s.angle = s.angle + (s.turnDir or 1) * V.TURN_RATE * 2.2 * dt
        if not aheadClear(self, s, s.angle, W, H) then return end   -- hold this frame
    end
    -- the actual step is guarded too: noise coasts have slivers thinner than
    -- any look-ahead sampling, and a ship must never end up ON land
    local nx = s.x + math.cos(s.angle) * s.speed * dt
    local ny = s.y + math.sin(s.angle) * s.speed * dt
    if self.terrain:isWater(nx, ny) then s.x, s.y = nx, ny end
end

-- One AI step for one ship, over `dt` seconds. Three modes, in priority order:
--   waitT  -- lying at anchor on a stop; when it runs out a ferry heads for its
--             next route stop, a visitor just resumes cruising
--   goal   -- steering somewhere specific (ferry stop / city anchorage)
--   free   -- the plain slow cruise: straight line, turn around (bounce) when
--             land, the world edge, or the home leash blocks the way; `visits`
--             liners schedule their next city call from here
-- Slow and forgiving, never an obstacle the player must dodge.
function Fleet:stepShip(s, dt, W, H)
    local V = config.AMBIENT_VISIT
    if s.submarine then self:updateDive(s, dt) end
    if s.bounceCd and s.bounceCd > 0 then s.bounceCd = s.bounceCd - dt end
    local ox, oy = s.x, s.y

    if s.waitT then
        s.waitT = s.waitT - dt
        if s.waitT <= 0 then
            s.waitT = nil
            if s.route then                          -- next ferry stop
                s.routeI = (s.routeI or 1) % #s.route + 1
                s.goal = s.route[s.routeI]
                s.goalT = V.TIMEOUT
            end
        end
    elseif s.goal then
        self:steerShip(s, dt, W, H)
    else
        if s.visits then                             -- time for a city call?
            s.visitT = (s.visitT or (V.INTERVAL_MIN
                + self.rng:random() * (V.INTERVAL_MAX - V.INTERVAL_MIN))) - dt
            if s.visitT <= 0 then
                s.visitT = V.INTERVAL_MIN
                    + self.rng:random() * (V.INTERVAL_MAX - V.INTERVAL_MIN)
                local port, bestD2                   -- call at the NEAREST city
                for _, p in ipairs(s.visits) do
                    local px, py = p.x - s.x, p.y - s.y
                    local d2 = px * px + py * py
                    if not bestD2 or d2 < bestD2 then port, bestD2 = p, d2 end
                end
                local gx, gy = self:findAnchorage(port)
                if gx then
                    -- allow the crossing time it actually needs (detours
                    -- around islands included), TIMEOUT as the floor
                    local eta = math.sqrt(bestD2) / math.max(1, s.speed)
                    s.goal, s.goalT = { x = gx, y = gy }, math.max(V.TIMEOUT, eta * 1.8)
                    s.dwell = V.DWELL
                end
            end
        end

        local blocked = not aheadClear(self, s, s.angle, W, H)
        if not blocked and s.home then
            -- Shuttle inside the home ring: past the leash heading away, or
            -- inside the keep-out ring heading at the pier -> turn around.
            -- (The two can't both hold, so it can't freeze between them.)
            local hx, hy = s.x - s.home.x, s.y - s.home.y
            local d2 = hx * hx + hy * hy
            local outbound = (hx * math.cos(s.angle) + hy * math.sin(s.angle)) > 0
            if (d2 > s.home.r * s.home.r and outbound)
                or (s.home.min and d2 < s.home.min * s.home.min and not outbound) then
                blocked = true
            end
        end
        if blocked then
            if s.bounce then
                if not s.bounceCd or s.bounceCd <= 0 then
                    s.angle = s.angle + math.pi
                    s.bounceCd = 2.0
                end
            else
                s.angle = s.angle + s.turnDir * s.turn * dt
            end
        else
            -- guard the step itself (see steerShip): never end up ON land
            local nx = s.x + math.cos(s.angle) * s.speed * dt
            local ny = s.y + math.sin(s.angle) * s.speed * dt
            if self.terrain:isWater(nx, ny) then s.x, s.y = nx, ny end
        end
    end

    -- Escape mode: a ship that steered into a pocket smaller than its
    -- look-ahead sees "land" every way and would spin in place forever.
    -- A few stuck seconds shrink its horizon (aheadClear above) so it
    -- can nose back out; open water ahead restores the full horizon.
    if not s.waitT then
        local mdx, mdy = s.x - ox, s.y - oy
        if (mdx * mdx + mdy * mdy) < 1e-9 then
            s.stuckT = (s.stuckT or 0) + dt
            if s.stuckT > 5 then s.escape = true end
        else
            s.stuckT = 0
            if s.escape and aheadClear(self, s, s.angle, W, H, s.r + 70) then
                s.escape = nil
            end
        end
    end
end

-- Sail every moving ship. Ships near the player tick every frame; ships beyond
-- AMBIENT_LOD.FAR (well off any screen) bank their dt and tick in batched steps
-- of ~AMBIENT_LOD.STEP seconds instead -- same total time, a fraction of the
-- isWater probes -- so adding boats to ships.lua stays ~free. The banked step is
-- identical maths (speeds/timers scale linearly with dt) and every position step
-- is still isWater-guarded, so nothing beaches.
function Fleet:update(dt)
    local W, H = config.WORLD_WIDTH, config.WORLD_HEIGHT
    local L = config.AMBIENT_LOD
    local far2 = L.FAR * L.FAR
    local bx, by = self.boat.x, self.boat.y
    for _, s in ipairs(self.ships) do
        if s.moving then
            local step = dt
            local dx, dy = s.x - bx, s.y - by
            -- patrol boats get EXCITED when the player is near: full throttle
            if s.patrol then
                local near = s.patrol.near or 1700
                s.speed = ((dx * dx + dy * dy) < near * near)
                    and (s.patrol.speed or 150) or s.baseSpeed
            end
            if (dx * dx + dy * dy) > far2 then
                s.lodT = (s.lodT or 0) + dt
                if s.lodT >= L.STEP then step = s.lodT; s.lodT = 0
                else step = nil end                   -- banked; tick later
            elseif s.lodT and s.lodT > 0 then
                step = dt + s.lodT; s.lodT = 0        -- came near: flush the bank
            end
            if step then self:stepShip(s, step, W, H) end
        end
    end

    -- Gentle ship-vs-ship separation: hulls that drift into each other ease
    -- apart instead of overlapping. Only MOVING ships get nudged (anchored
    -- ones hold their spot), every nudge is isWater-guarded, and the push is
    -- half the overlap per frame -- polite fenders, not physics. A dived
    -- submarine is ghosted through. Squared-distance early-out keeps the
    -- pairwise sweep ~free at fleet sizes.
    local ships = self.ships
    for i = 1, #ships - 1 do
        local a = ships[i]
        if not (a.dive and a.dive > 0.05) then
            for j = i + 1, #ships do
                local b = ships[j]
                if not (b.dive and b.dive > 0.05) then
                    local dx, dy = b.x - a.x, b.y - a.y
                    local minD = (a.r + b.r) * 0.9
                    local d2 = dx * dx + dy * dy
                    if d2 < minD * minD and d2 > 1e-6 then
                        local d = math.sqrt(d2)
                        local push = (minD - d) * 0.5
                        local ux, uy = dx / d, dy / d
                        if a.moving then
                            local nx, ny = a.x - ux * push, a.y - uy * push
                            if self.terrain:isWater(nx, ny) then a.x, a.y = nx, ny end
                        end
                        if b.moving then
                            local nx, ny = b.x + ux * push, b.y + uy * push
                            if self.terrain:isWater(nx, ny) then b.x, b.y = nx, ny end
                        end
                    end
                end
            end
        end
    end
end

-- The ambient ship under a screen tap (mx,my), or nil. Tested in SCREEN space
-- against each ship's on-screen sprite box: the billboard rises UP from its
-- waterline anchor, so a ground-circle test (which assumes z=0) would only catch
-- clicks at the very base. Nearest sprite-centre wins on overlap.
function Fleet:shipAt(mx, my, camera)
    local zoom = camera.zoom
    local best, bestD
    for _, s in ipairs(self.ships) do
        -- a diving/dived submarine can't be tapped (you can't see it)
        if not (s.dive and s.dive > 0.3) then
            local ax, ay = camera:worldToScreen(s.x, s.y)   -- waterline anchor (bottom-centre)
            local wWorld, aspect
            if s.look.billboard then
                local img = Assets.image(s.look.img)
                wWorld = config.AMBIENT_PHOTO_WIDTH * s.scale
                aspect = img and (img:getHeight() / img:getWidth()) or 0.5
            else
                wWorld = config.AMBIENT_SHIP_WIDTH * s.scale
                aspect = 0.5
            end
            local onW = wWorld * zoom * 1.1                   -- a little finger-slack
            local onH = wWorld * aspect * zoom
            local left, right = ax - onW / 2, ax + onW / 2
            local top, bottom = ay - onH, ay + onH * 0.2      -- waterline + slight slack below
            if mx >= left and mx <= right and my >= top and my <= bottom then
                local cx, cy = ax, ay - onH / 2
                local d = (mx - cx) ^ 2 + (my - cy) ^ 2
                if not bestD or d < bestD then best, bestD = s, d end
            end
        end
    end
    return best
end

return Fleet
