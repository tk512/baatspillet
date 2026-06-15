-- src/entities/pirate.lua
-- A rare AI hunter that chases the player and lobs slow cannonballs. Tuning is
-- in config.PIRATE. Deliberately gentle: slower than the player so it can be
-- outrun, shots are slow and dodge-able, and it gives up when you stay far away
-- or run out of gold. Lives in the ground plane; only draw() knows about the iso
-- projection. The world depth-sorts it and calls drawBalls() afterwards.

local config = require("src.config")
local Assets = require("src.assets")
local Iso    = require("src.systems.iso")

local Pirate = {}
Pirate.__index = Pirate

local P = config.PIRATE

local function angleDiff(a, b)
    local d = (b - a) % (2 * math.pi)
    if d > math.pi then d = d - 2 * math.pi end
    return d
end

function Pirate.new(x, y, playerMaxSpeed)
    local self = setmetatable({}, Pirate)
    self.x, self.y = x, y
    self.angle    = 0
    self.speed    = 0
    self.maxSpeed = playerMaxSpeed * P.SPEED_FRAC
    self.turnRate = 1.5
    self.radius   = 26
    self.state    = "chase"                 -- "chase" | "retreat"
    self.fireT    = P.FIRE_INTERVAL * 0.7   -- a moment before the first shot
    self.balls    = {}
    self.farT     = 0                       -- how long you've been out of reach
    self.muzzle   = 0                       -- muzzle-flash timer
    self.dead     = false
    return self
end

-- Break off and sail away (when you're broke or it loses interest). Vanishes
-- once far enough, in update().
function Pirate:flee()
    self.state = "retreat"
end

function Pirate:update(dt, boat, terrain, onHit)
    local dx, dy = boat.x - self.x, boat.y - self.y
    local dist = math.sqrt(dx * dx + dy * dy)

    -- steer toward the boat (chase) or away from it (retreat)
    local targetAng = (self.state == "retreat") and math.atan2(-dy, -dx) or math.atan2(dy, dx)
    local diff = angleDiff(self.angle, targetAng)
    self.angle = self.angle + math.max(-1, math.min(1, diff * 2)) * self.turnRate * dt

    -- accelerate toward top speed (a touch faster when fleeing)
    local target = self.maxSpeed * (self.state == "retreat" and 1.15 or 1.0)
    self.speed = self.speed + (target - self.speed) * math.min(1, dt * 1.5)

    -- move; if land is ahead, veer to find open water (islands shield the boat)
    local nx = self.x + math.cos(self.angle) * self.speed * dt
    local ny = self.y + math.sin(self.angle) * self.speed * dt
    if terrain:isWater(nx, ny) then
        self.x, self.y = nx, ny
    else
        self.angle = self.angle + 1.2 * dt
        self.speed = self.speed * 0.9
    end
    self.x = math.max(20, math.min(config.WORLD_WIDTH - 20, self.x))
    self.y = math.max(20, math.min(config.WORLD_HEIGHT - 20, self.y))

    -- cannon fire (only while chasing and within range)
    self.muzzle = math.max(0, self.muzzle - dt)
    if self.state == "chase" then
        self.fireT = self.fireT - dt
        if self.fireT <= 0 and dist < P.FIRE_RANGE then
            self.fireT = P.FIRE_INTERVAL
            self:fire(boat)
        end
    end

    -- advance cannonballs; a ball that reaches the boat scores a hit
    for i = #self.balls, 1, -1 do
        local b = self.balls[i]
        b.life = b.life + dt
        b.x = b.x + b.vx * dt
        b.y = b.y + b.vy * dt
        local bdx, bdy = boat.x - b.x, boat.y - b.y
        local hitR = boat.radius + P.BALL_RADIUS
        if (bdx * bdx + bdy * bdy) < hitR * hitR then
            table.remove(self.balls, i)
            if onHit then onHit() end
        elseif b.life > b.plan + 0.3 then
            table.remove(self.balls, i)         -- splashed harmlessly (missed)
        end
    end

    -- losing interest / vanishing
    if self.state == "chase" then
        if dist > P.GIVEUP_DIST then self.farT = self.farT + dt else self.farT = 0 end
        if self.farT > P.GIVEUP_TIME then self:flee() end
    elseif dist > P.DESPAWN_DIST then
        self.dead = true
    end
end

-- Lob a cannonball toward where the boat is heading, and BOOM.
function Pirate:fire(boat)
    local dx, dy = boat.x - self.x, boat.y - self.y
    local dist = math.sqrt(dx * dx + dy * dy)
    local plan = dist / P.BALL_SPEED
    local bvx, bvy = math.cos(boat.angle) * boat.speed, math.sin(boat.angle) * boat.speed
    local tx = boat.x + bvx * plan * 0.8        -- partial lead (so it's still dodge-able)
    local ty = boat.y + bvy * plan * 0.8
    local ang = math.atan2(ty - self.y, tx - self.x)
    local bowOff = 32 * (P.LENGTH or 2.6)           -- fire from the (long) bow
    local mx = self.x + math.cos(self.angle) * bowOff
    local my = self.y + math.sin(self.angle) * bowOff
    self.balls[#self.balls + 1] = {
        x = mx, y = my,
        vx = math.cos(ang) * P.BALL_SPEED, vy = math.sin(ang) * P.BALL_SPEED,
        life = 0, plan = plan,
    }
    self.muzzle = 0.14
    Assets.playSfx("cannon", 0.97)
end

-- Scale length more than width so it reads as a long, low galleon, not a tower.
local LEN = config.PIRATE.LENGTH or 2.6
local WID = config.PIRATE.WIDTH or 1.45
-- a longer hull silhouette (drawn-out bow + stern), in local boat space
local HULL = { { 30, 0 }, { 12, -12 }, { -22, -12 }, { -30, 0 }, { -22, 12 }, { 12, 12 } }

-- A tattered black sail (screen-space billboard) with a ragged, torn bottom.
local function draggedSail(cx, topY, halfW, h)
    local poly = {
        cx - halfW, topY,
        cx + halfW, topY,
        cx + halfW, topY + h,
        cx + halfW * 0.55, topY + h - h * 0.16,
        cx + halfW * 0.15, topY + h,
        cx - halfW * 0.22, topY + h - h * 0.18,
        cx - halfW * 0.6, topY + h,
        cx - halfW, topY + h - h * 0.12,
    }
    love.graphics.setColor(0.12, 0.12, 0.15); love.graphics.polygon("fill", poly)
    love.graphics.setColor(0.07, 0.07, 0.09)                 -- a couple of dark tear seams
    love.graphics.setLineWidth(2)
    love.graphics.line(cx - halfW * 0.3, topY + 2, cx - halfW * 0.35, topY + h * 0.8)
    love.graphics.line(cx + halfW * 0.35, topY + 2, cx + halfW * 0.3, topY + h * 0.85)
    love.graphics.setLineWidth(1)
end

function Pirate:draw()
    local t = love.timer.getTime()
    local z = math.sin(t * 1.6) * 2
    local co, si = math.cos(self.angle), math.sin(self.angle)
    -- length on +x, beam on y, then rotate by heading
    local function rot(px, py)
        local lx, ly = px * LEN, py * WID
        return self.x + (lx * co - ly * si), self.y + (lx * si + ly * co)
    end

    local hullH = 17                                  -- moderate freeboard (not tall)
    local base, deck = {}, {}
    local minx, miny, maxx, maxy = 1e9, 1e9, -1e9, -1e9
    for _, p in ipairs(HULL) do
        local wx, wy = rot(p[1], p[2])
        local bx, by = Iso.project(wx, wy, z)
        local dx, dy = Iso.project(wx, wy, z + hullH)
        base[#base + 1] = { bx, by }
        deck[#deck + 1] = { dx, dy }
        if bx < minx then minx = bx end; if bx > maxx then maxx = bx end
        if by < miny then miny = by end; if by > maxy then maxy = by end
    end

    -- long looming shadow matching the hull footprint
    love.graphics.setColor(0, 0, 0, 0.22)
    love.graphics.ellipse("fill", (minx + maxx) / 2, (miny + maxy) / 2 + 5,
        (maxx - minx) / 2 + 6, (maxy - miny) / 2 + 5)

    -- near-black hull sides + deck
    love.graphics.setColor(0.12, 0.08, 0.06)
    local n = #base
    for i = 1, n do
        local a, b = i, (i % n) + 1
        love.graphics.polygon("fill", deck[a][1], deck[a][2], deck[b][1], deck[b][2],
            base[b][1], base[b][2], base[a][1], base[a][2])
    end
    local poly = {}
    for i = 1, n do poly[#poly + 1] = deck[i][1]; poly[#poly + 1] = deck[i][2] end
    love.graphics.setColor(0.22, 0.15, 0.10); love.graphics.polygon("fill", poly)
    love.graphics.setColor(0.55, 0.12, 0.10)                 -- blood-red trim line
    love.graphics.setLineWidth(3); love.graphics.polygon("line", poly)
    love.graphics.setLineWidth(1)

    -- a row of gun ports down each long side (edges 2→3 port, 5→6 starboard)
    local function gunports(p, q)
        for k = 1, 4 do
            local f = (k - 0.5) / 4
            local px = deck[p][1] + (deck[q][1] - deck[p][1]) * f
            local py = deck[p][2] + (deck[q][2] - deck[p][2]) * f
            love.graphics.setColor(0.03, 0.02, 0.02); love.graphics.circle("fill", px, py, 3)
            love.graphics.setColor(0.7, 0.14, 0.08, 0.7); love.graphics.circle("fill", px, py, 1.3)
        end
    end
    gunports(2, 3); gunports(6, 5)

    -- main mast + tattered sail with a glowing-eyed skull (moderate height)
    local mx, my = Iso.project(self.x, self.y, z + hullH)
    love.graphics.setColor(0.08, 0.06, 0.04)
    love.graphics.setLineWidth(4); love.graphics.line(mx, my, mx, my - 60)
    love.graphics.setLineWidth(3); love.graphics.line(mx - 28, my - 50, mx + 28, my - 50)  -- yard-arm
    love.graphics.setLineWidth(1)
    draggedSail(mx, my - 50, 26, 38)

    local skx, sky, sr = mx, my - 31, 8
    love.graphics.setColor(0.88, 0.87, 0.9); love.graphics.circle("fill", skx, sky, sr)
    love.graphics.setColor(0.82, 0.81, 0.84)
    love.graphics.polygon("fill", skx - sr * 0.7, sky + sr * 0.5, skx + sr * 0.7, sky + sr * 0.5,
        skx + sr * 0.35, sky + sr * 1.25, skx - sr * 0.35, sky + sr * 1.25)   -- jaw
    local glow = 0.55 + 0.45 * math.sin(t * 6)
    love.graphics.setColor(0.5, 0.05, 0.04)
    love.graphics.circle("fill", skx - sr * 0.4, sky - sr * 0.1, sr * 0.36)
    love.graphics.circle("fill", skx + sr * 0.4, sky - sr * 0.1, sr * 0.36)
    love.graphics.setColor(1, 0.2, 0.12, glow)               -- glowing red eyes
    love.graphics.circle("fill", skx - sr * 0.4, sky - sr * 0.1, sr * 0.17)
    love.graphics.circle("fill", skx + sr * 0.4, sky - sr * 0.1, sr * 0.17)
    love.graphics.setColor(0.10, 0.08, 0.10)
    love.graphics.rectangle("fill", skx - sr * 0.18, sky + sr * 0.32, sr * 0.36, sr * 0.5)  -- nose

    -- skull-and-crossbones flag streaming from the masthead
    love.graphics.setColor(0.05, 0.05, 0.06)
    love.graphics.polygon("fill", mx, my - 60, mx + 22, my - 56, mx, my - 52)
    love.graphics.setColor(0.82, 0.82, 0.88); love.graphics.circle("fill", mx + 8, my - 56, 2)

    -- muzzle flash + smoke just after firing (at the bow)
    if self.muzzle > 0 then
        local bx, by = rot(30, 0)
        local fx, fy = Iso.project(bx, by, z + 8)
        local f = self.muzzle / 0.14
        love.graphics.setColor(0.72, 0.72, 0.72, f * 0.5); love.graphics.circle("fill", fx, fy - 4, 12 * f)
        love.graphics.setColor(1, 0.78, 0.30, f); love.graphics.circle("fill", fx, fy, 13 * f)
        love.graphics.setColor(1, 0.45, 0.10, f * 0.85); love.graphics.circle("fill", fx, fy, 8 * f)
    end
    love.graphics.setColor(1, 1, 1)
end

-- Cannonballs arc through the air (a parabolic screen height) over the water.
function Pirate:drawBalls()
    for _, b in ipairs(self.balls) do
        local pr = math.min(1, b.life / math.max(0.01, b.plan))
        local h = math.sin(pr * math.pi) * 55
        local sx, sy = Iso.project(b.x, b.y, h)
        local gx, gy = Iso.project(b.x, b.y, 0)
        love.graphics.setColor(0, 0, 0, 0.18); love.graphics.ellipse("fill", gx, gy + 2, 7, 3)
        love.graphics.setColor(0.08, 0.08, 0.10); love.graphics.circle("fill", sx, sy, P.BALL_RADIUS * 0.6 + 2)
        love.graphics.setColor(0.24, 0.24, 0.28); love.graphics.circle("fill", sx - 2, sy - 2, P.BALL_RADIUS * 0.4)
    end
    love.graphics.setColor(1, 1, 1)
end

return Pirate
