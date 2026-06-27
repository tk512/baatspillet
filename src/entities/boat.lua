-- src/entities/boat.lua
-- The player's boat. Movement in the flat ground plane is gentle: accelerates
-- and turns slowly, never sinks, bounces softly off land and can always sail
-- back out (speed is only damped when moving INTO an obstacle). draw() prefers a
-- side-view photo; drawVolumetric() is the code-drawn fallback when art is absent.

local config = require("src.config")
local Assets = require("src.assets")
local Iso    = require("src.systems.iso")

local Boat = {}
Boat.__index = Boat

-- Hull outline in local boat space (pointing along +X = "forward").
local HULL = {
    { 26,   0},  -- bow tip
    { 10, -13},  -- forward port
    {-18, -13},  -- aft port
    {-23,   0},  -- stern
    {-18,  13},  -- aft starboard
    { 10,  13},  -- forward starboard
}
local DECK_H  = 13   -- how tall the hull sits above the water
local CABIN_H = 16   -- cabin height above the deck

function Boat.new(def, x, y)
    local self = setmetatable({}, Boat)
    self.def      = def
    self.x        = x or 0
    self.y        = y or 0
    self.angle    = -math.pi / 4
    self.speed    = 0
    self.maxSpeed = def.speed
    self.accel    = def.accel
    self.turnRate = def.turn
    self.radius   = 20
    self.cargo    = {}
    self.capacity = def.capacity
    self.destX    = nil
    self.destY    = nil
    self.bumpCooldown = 0
    self.safeX, self.safeY = self.x, self.y  -- last position known to be water
    self.balls    = {}   -- player cannonballs in flight (only if a cannon is owned)
    self.cannonT  = 0    -- time until the cannon can fire again
    return self
end

-- Auto-cannon: while a pirate is in range, fire at it on an interval. We're
-- amateurs, so each ball flies a FIXED, slightly-wild trajectory (see
-- fireCannon) -- no homing, no leading -- and only counts as a hit if it happens
-- to pass close to the (moving) pirate. Most shots miss; landing one calls
-- onHit, which scares the pirate off rather than sinking it. Only called by the
-- world while the cannon is owned and the pirate is still attacking.
function Boat:updateCannon(dt, target, onHit)
    local C = config.CANNON
    self.cannonT = math.max(0, self.cannonT - dt)

    for i = #self.balls, 1, -1 do
        local b = self.balls[i]
        b.life = b.life + dt
        b.x = b.x + b.vx * dt
        b.y = b.y + b.vy * dt
        local consumed = false
        if target then
            local dx, dy = target.x - b.x, target.y - b.y
            local hitR = (target.radius or 26) + C.BALL_RADIUS
            if (dx * dx + dy * dy) < hitR * hitR then
                if onHit then onHit() end
                consumed = true
            end
        end
        if consumed or b.life > b.plan + 0.25 then
            table.remove(self.balls, i)             -- hit, or splashed (missed)
        end
    end

    if target and self.cannonT <= 0 then
        local dx, dy = target.x - self.x, target.y - self.y
        local dist = math.sqrt(dx * dx + dy * dy)
        if dist < C.FIRE_RANGE then
            self.cannonT = C.FIRE_INTERVAL
            self:fireCannon(target, dist)
        end
    end
end

-- Fire one wild shot: aim at where the pirate is RIGHT NOW (no leading) and add
-- a random angular SPREAD, then commit the ball to that straight path. Because
-- the pirate keeps moving and our aim is off, a moving ship is hard to hit -- as
-- it should be for a 5-year-old's first cannon.
function Boat:fireCannon(target, dist)
    local C = config.CANNON
    local ang = math.atan2(target.y - self.y, target.x - self.x)
    ang = ang + (love.math.random() * 2 - 1) * C.SPREAD
    self.balls[#self.balls + 1] = {
        x = self.x, y = self.y,
        vx = math.cos(ang) * C.BALL_SPEED, vy = math.sin(ang) * C.BALL_SPEED,
        life = 0, plan = dist / C.BALL_SPEED,
    }
    Assets.playSfx("cannon", 0.8)
end

-- Cannonballs arc over the water (a parabolic screen height), like the pirate's.
function Boat:drawCannonBalls()
    local C = config.CANNON
    for _, b in ipairs(self.balls) do
        local pr = math.min(1, b.life / math.max(0.01, b.plan))
        local h = math.sin(pr * math.pi) * 55
        local sx, sy = Iso.project(b.x, b.y, h)
        local gx, gy = Iso.project(b.x, b.y, 0)
        love.graphics.setColor(0, 0, 0, 0.18); love.graphics.ellipse("fill", gx, gy + 2, 7, 3)
        love.graphics.setColor(0.10, 0.10, 0.12); love.graphics.circle("fill", sx, sy, C.BALL_RADIUS * 0.6 + 2)
        love.graphics.setColor(0.85, 0.86, 0.92); love.graphics.circle("fill", sx - 2, sy - 2, C.BALL_RADIUS * 0.4)
    end
    love.graphics.setColor(1, 1, 1)
end

-- Keep the boat on water. Called each frame after update(): if it wandered onto
-- land, send it back to the last water spot and steer toward open water. Never
-- wipes the destination, so it can't get stuck against a shore.
local DIRS8 = { {1,0},{-1,0},{0,1},{0,-1},{1,1},{1,-1},{-1,1},{-1,-1} }
function Boat:blockLand(terrain)
    if terrain:isWater(self.x, self.y) then
        self.safeX, self.safeY = self.x, self.y
        return
    end
    local S = self.radius + 8
    local nx, ny = 0, 0
    for _, d in ipairs(DIRS8) do
        if terrain:isWater(self.x + d[1] * S, self.y + d[2] * S) then
            nx, ny = nx + d[1], ny + d[2]
        end
    end
    self.x, self.y = self.safeX, self.safeY  -- back to water
    if nx ~= 0 or ny ~= 0 then
        self.angle = math.atan2(ny, nx)       -- face open water
    end
    self.speed = self.speed * config.BOUNCE_DAMPING
    self:softHit()
end

function Boat:cargoCount() return #self.cargo end
function Boat:hasRoom()    return #self.cargo < self.capacity end

function Boat:setDestination(x, y) self.destX, self.destY = x, y end
function Boat:clearDestination()   self.destX, self.destY = nil, nil end

local function angleDiff(a, b)
    local d = (b - a) % (2 * math.pi)
    if d > math.pi then d = d - 2 * math.pi end
    return d
end

function Boat:update(dt)
    self.bumpCooldown = math.max(0, self.bumpCooldown - dt)

    local throttle, steer = 0, 0
    local manual = false
    if love.keyboard.isDown("up", "w")    then throttle =  1;   manual = true end
    if love.keyboard.isDown("down", "s")  then throttle = -0.5; manual = true end
    if love.keyboard.isDown("left", "a")  then steer = -1;      manual = true end
    if love.keyboard.isDown("right", "d") then steer =  1;      manual = true end
    if manual then self:clearDestination() end

    -- Auto-steer toward a clicked destination.
    if self.destX then
        local dx, dy = self.destX - self.x, self.destY - self.y
        local dist = math.sqrt(dx * dx + dy * dy)
        if dist < 14 then
            self:clearDestination()
        else
            local diff = angleDiff(self.angle, math.atan2(dy, dx))
            steer = math.max(-1, math.min(1, diff * 2))
            throttle = math.min(1, dist / 120)
        end
    end

    self.angle = self.angle + steer * self.turnRate * dt

    local targetSpeed = throttle * self.maxSpeed
    if self.speed < targetSpeed then
        self.speed = math.min(targetSpeed, self.speed + self.accel * dt)
    else
        self.speed = math.max(targetSpeed, self.speed - self.accel * 1.5 * dt)
    end

    self.x = self.x + math.cos(self.angle) * self.speed * dt
    self.y = self.y + math.sin(self.angle) * self.speed * dt

    self:clampToWorld()
end

function Boat:clampToWorld()
    local r = self.radius
    local hitX = self.x < r or self.x > config.WORLD_WIDTH  - r
    local hitY = self.y < r or self.y > config.WORLD_HEIGHT - r
    self.x = math.max(r, math.min(config.WORLD_WIDTH  - r, self.x))
    self.y = math.max(r, math.min(config.WORLD_HEIGHT - r, self.y))
    if hitX or hitY then self:softHit() end
end

-- Soft circular collision (islands). Speed is only damped when moving INTO the
-- obstacle, and the destination is kept, so the boat can always sail back out.
function Boat:collideCircle(cx, cy, cr)
    local dx, dy = self.x - cx, self.y - cy
    local dist = math.sqrt(dx * dx + dy * dy)
    local minDist = cr + self.radius
    if dist >= minDist then return end
    if dist < 0.001 then dx, dy, dist = 1, 0, 1 end

    local nx, ny = dx / dist, dy / dist
    self.x = cx + nx * minDist     -- push out to the surface
    self.y = cy + ny * minDist

    local vx = math.cos(self.angle) * self.speed
    local vy = math.sin(self.angle) * self.speed
    local into = vx * nx + vy * ny  -- < 0 means heading into the obstacle
    if into < 0 then
        -- reflect the heading away from the surface, soften the speed
        local rvx = vx - 2 * into * nx
        local rvy = vy - 2 * into * ny
        self.angle = math.atan2(rvy, rvx)
        self.speed = self.speed * config.BOUNCE_DAMPING
        self:softHit()
        return true               -- a real bump (caller may react, e.g. skerry FX)
    end
    return false
end

function Boat:softHit()
    if self.bumpCooldown == 0 then
        Assets.playSfx("bump")
        self.bumpCooldown = 0.35
    end
end

local function rot(px, py, a, ox, oy)
    local c, s = math.cos(a), math.sin(a)
    return ox + px * c - py * s, oy + px * s + py * c
end

-- Foam wake for the photo billboard. It trails horizontally off the stern along
-- the waterline (an iso wake would just hide behind the tall sprite): a froth at
-- the hull plus foam dabs that fan out, drift back and fade.
function Boat:drawWake(sx, sy, want)
    local t = love.timer.getTime()
    local vsx = (math.cos(self.angle) - math.sin(self.angle)) * Iso.SX
    local wdir = (vsx >= 0) and -1 or 1       -- bow faces travel; wake goes opposite
    local spd = 0
    if self.maxSpeed and self.maxSpeed > 0 then spd = math.min(1, self.speed / self.maxSpeed) end

    if spd <= 0.05 then return end            -- no foam when the boat is still

    local sternX = sx + wdir * want * 0.30
    local line = sy + want * 0.02             -- the waterline

    -- a small churning froth right at the stern
    for k = 1, 5 do
        local nz = math.sin(t * 8 + k * 1.7) * 0.5 + 0.5
        love.graphics.setColor(1, 1, 1, (0.25 + 0.30 * nz) * spd)
        love.graphics.circle("fill",
            sternX + wdir * k * want * 0.018,
            line + (k % 3 - 1) * want * 0.03 + nz * want * 0.012,
            want * (0.03 + 0.025 * nz))
    end

    -- a short trailing wake: little noisy foam dabs that drift back and fade
    local n = 14
    for k = 1, n do
        local ph = (t * 0.5 + k / n) % 1
        local fade = (1 - ph) * spd
        if fade > 0.01 then
            local jx = math.sin(t * 6 + k * 5.1) * want * 0.025
            local fx = sternX + wdir * ph * want * 0.7 + jx
            local fan = (0.03 + ph * 0.11) * want
            local nz = math.sin(t * 5 + k * 2.3) * want * 0.02
            local r = want * (0.022 + ph * 0.03) * (0.7 + 0.6 * (math.sin(t * 9 + k) * 0.5 + 0.5))
            for row = -1, 1, 2 do
                love.graphics.setColor(1, 1, 1, 0.65 * fade)
                love.graphics.circle("fill", fx, line + row * fan + nz, r)
            end
            love.graphics.setColor(0.92, 0.97, 0.99, 0.35 * fade)
            love.graphics.circle("fill", fx, line + nz * 0.5, r * 0.85)
        end
    end
    love.graphics.setColor(1, 1, 1)
end

function Boat:draw()
    -- Side-profile billboard: a bow-right photo (def.sprite) and a bow-left one
    -- (def.spriteLeft / <base>_left.png), picked by on-screen heading. No
    -- rotation. With no left photo, mirror the right one.
    local rightImg = self.def.sprite and Assets.image("boats/" .. self.def.sprite)
    if rightImg then
        local base = self.def.sprite:gsub("%.png$", "")
        -- projected x velocity: which way the boat moves on the iso screen
        local vsx = (math.cos(self.angle) - math.sin(self.angle)) * Iso.SX
        local img, flip = rightImg, 1
        if vsx < 0 then
            local leftImg = Assets.image("boats/" .. (self.def.spriteLeft or (base .. "_left.png")))
            if leftImg then img, flip = leftImg, 1
            else flip = -1 end                  -- no left art: mirror the right photo
        end

        -- Linear filter: it's a downscaled photo, so sub-pixel sampling keeps the
        -- boat gliding smoothly rather than snapping to whole pixels.
        if img:getFilter() ~= "linear" then img:setFilter("linear", "linear") end

        local sx, sy = Iso.project(self.x, self.y, 0)
        local want = (self.def.spriteWidth or config.BOAT_SPRITE_WIDTH)
        local scale = want / img:getWidth()
        self:drawWake(sx, sy, want)
        love.graphics.setColor(1, 1, 1)
        love.graphics.draw(img, sx, sy, 0, scale * flip, scale,
            img:getWidth() / 2, img:getHeight() * 0.85)
        return
    end
    self:drawVolumetric()
end

function Boat:drawVolumetric()
    local c = config.colors

    -- Hull outline rotated by heading; keep a sea-level and deck-level projection
    -- for each point.
    local base, deck = {}, {}
    for _, p in ipairs(HULL) do
        local gx, gy = rot(p[1], p[2], self.angle, self.x, self.y)
        local bx, by = Iso.project(gx, gy, 0)
        local dx, dy = Iso.project(gx, gy, DECK_H)
        base[#base + 1] = { bx, by }
        deck[#deck + 1] = { dx, dy }
    end

    -- Soft shadow / wake on the water.
    local sxc, syc = Iso.project(self.x, self.y, 0)
    love.graphics.setColor(0, 0, 0, 0.16)
    love.graphics.ellipse("fill", sxc, syc + 4, 26, 13)
    self:drawVolumetricWake(sxc, syc)

    -- Hull side walls; hidden faces get painted over by the deck.
    love.graphics.setColor(c.boat_hull_dk)
    local n = #base
    for i = 1, n do
        local a, b = i, (i % n) + 1
        love.graphics.polygon("fill",
            deck[a][1], deck[a][2], deck[b][1], deck[b][2],
            base[b][1], base[b][2], base[a][1], base[a][2])
    end

    -- Deck (top face).
    local deckPoly = {}
    for i = 1, n do deckPoly[#deckPoly + 1] = deck[i][1]; deckPoly[#deckPoly + 1] = deck[i][2] end
    love.graphics.setColor(c.boat_hull)
    love.graphics.polygon("fill", deckPoly)
    love.graphics.setColor(c.boat_deck)
    love.graphics.polygon("line", deckPoly)

    -- Cabin: a little box sitting on the deck, in the player boat's color.
    self:drawCabin(c)
end

-- Old simple wake, kept only for the code-drawn volumetric fallback boat.
function Boat:drawVolumetricWake(sxc, syc)
    if self.speed < 25 then return end
    local a = math.min(0.35, self.speed / self.maxSpeed * 0.35)
    -- two streaks trailing the stern (opposite the heading)
    local bx, by = rot(-26, 0, self.angle, self.x, self.y)
    local px, py = Iso.project(bx, by, 0)
    love.graphics.setColor(1, 1, 1, a)
    love.graphics.ellipse("fill", px, py + 2, 10, 5)
    love.graphics.setColor(1, 1, 1, a * 0.6)
    love.graphics.ellipse("fill", (px + sxc) / 2, (py + syc) / 2 + 2, 7, 3)
end

function Boat:drawCabin(c)
    local cabin = { {6, -8}, {6, 8}, {-10, 8}, {-10, -8} }
    local lo, hi = {}, {}
    for _, p in ipairs(cabin) do
        local gx, gy = rot(p[1], p[2], self.angle, self.x, self.y)
        local lx, ly = Iso.project(gx, gy, DECK_H)
        local hx, hy = Iso.project(gx, gy, DECK_H + CABIN_H)
        lo[#lo + 1] = { lx, ly }
        hi[#hi + 1] = { hx, hy }
    end
    local col = self.def.color or c.boat_cabin
    -- walls
    love.graphics.setColor(col[1] * 0.7, col[2] * 0.7, col[3] * 0.7)
    local n = #lo
    for i = 1, n do
        local a, b = i, (i % n) + 1
        love.graphics.polygon("fill",
            hi[a][1], hi[a][2], hi[b][1], hi[b][2],
            lo[b][1], lo[b][2], lo[a][1], lo[a][2])
    end
    -- roof
    local roof = {}
    for i = 1, n do roof[#roof + 1] = hi[i][1]; roof[#roof + 1] = hi[i][2] end
    love.graphics.setColor(col)
    love.graphics.polygon("fill", roof)
end

return Boat
