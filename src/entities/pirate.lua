-- A rare hunter that chases and lobs slow cannonballs. Deliberately gentle:
-- slower than the player, dodge-able shots, and it gives up when you stay away
-- or run out of gold. Tuning in config.PIRATE; the world calls drawBalls()
-- after the depth sort.

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
    self.hits     = 0                        -- cannon hits taken (flees at SCARE_HITS)
    self.fireT    = P.FIRE_INTERVAL * 0.7   -- a moment before the first shot
    self.balls    = {}
    self.farT     = 0                       -- how long you've been out of reach
    self.huntT    = 0                       -- total hunt time (bored at HUNT_TIME)
    self.retreatT = 0                       -- time retreating (gone at RETREAT_MAX)
    self.muzzle   = 0                       -- muzzle-flash timer
    self.dead     = false
    -- which way it circles you, fixed for its whole life: re-rolling it per frame
    -- makes it wobble on the spot instead of orbiting
    self.orbitDir = (love.math.random() < 0.5) and -1 or 1
    return self
end

-- break off and sail away; update() removes it once far enough
function Pirate:flee()
    self.state = "retreat"
end

-- How far off "straight at you" an attacking pirate steers, given how far out it
-- is. ONE continuous rule rather than a close-in / hold / back-off state machine,
-- which judders along its own boundaries: well outside its station it aims AT you
-- (offset 0), on station it aims across you and circles (a quarter turn), inside
-- it aims away (a half turn) and peels off. `dir` is which way it orbits, fixed
-- per pirate so it doesn't dither.
--
-- Pure, and tested, because "the pirate rams you and clips through the hull" is a
-- feel bug that reads as broken art and gets blamed on the sprite.
function Pirate.stationOffset(dist, standoff, dir)
    if not standoff or standoff <= 0 then return 0 end
    local err = (dist - standoff) / standoff        -- >0 too far, <0 too close
    err = math.max(-1, math.min(1, err))
    return dir * (1 - err) * math.pi * 0.5
end

-- steering whisker: is the water clear for `look` units along `ang`?
function Pirate:clearAhead(terrain, ang, look)
    for d = 70, look, 70 do
        if not terrain:isWater(self.x + math.cos(ang) * d, self.y + math.sin(ang) * d) then
            return false
        end
    end
    return true
end

-- Heading toward `baseAng` but around land: when straight ahead is blocked,
-- fan out to the smallest clear turn, so it rounds an island.
function Pirate:steerAround(terrain, baseAng)
    local look = 230
    if self:clearAhead(terrain, baseAng, look) then return baseAng end
    for _, off in ipairs({ 0.5, -0.5, 0.9, -0.9, 1.4, -1.4, 1.9, -1.9, 2.5, -2.5 }) do
        if self:clearAhead(terrain, baseAng + off, look) then return baseAng + off end
    end
    return baseAng    -- boxed in: hold course, the move step nudges it off
end

function Pirate:update(dt, boat, terrain, onHit)
    -- a racer (self.goal) makes for a fixed point and ignores the boat
    local racing = self.goal and self.state ~= "retreat"
    local aimX = racing and self.goal.x or boat.x
    local aimY = racing and self.goal.y or boat.y
    local sdx, sdy = aimX - self.x, aimY - self.y
    local dist = math.sqrt((boat.x - self.x) ^ 2 + (boat.y - self.y) ^ 2)   -- to the boat

    -- steer toward the aim point (chase/race) or away (retreat), around islands.
    -- An ATTACKING pirate holds a firing station instead: see Pirate.stationOffset.
    local baseAng
    if self.state == "retreat" then
        baseAng = math.atan2(-sdy, -sdx)
    elseif racing then
        baseAng = math.atan2(sdy, sdx)
    else
        baseAng = math.atan2(sdy, sdx)
                  + Pirate.stationOffset(dist, P.STANDOFF, self.orbitDir)
    end
    local targetAng = self:steerAround(terrain, baseAng)
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

    -- attacking chasers only: a racer just wants the chest
    self.muzzle = math.max(0, self.muzzle - dt)
    if self.state == "chase" and not self.goal then
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

    -- Lifecycle. A racer never gives up on its own -- the world removes it when
    -- the race is decided.
    if self.state == "retreat" then
        -- bounded either way: chasing a fleeing pirate can't keep it alive
        self.retreatT = self.retreatT + dt
        if dist > P.DESPAWN_DIST or self.retreatT > P.RETREAT_MAX then self.dead = true end
    elseif not self.goal then
        if dist > P.GIVEUP_DIST then self.farT = self.farT + dt else self.farT = 0 end
        if self.farT > P.GIVEUP_TIME then self:flee() end
        self.huntT = self.huntT + dt
        if self.huntT > P.HUNT_TIME then self:flee() end   -- robbery visits are bounded
    end
end

function Pirate:fire(boat)
    local dx, dy = boat.x - self.x, boat.y - self.y
    local dist = math.sqrt(dx * dx + dy * dy)
    local plan = dist / P.BALL_SPEED
    local bvx, bvy = math.cos(boat.angle) * boat.speed, math.sin(boat.angle) * boat.speed
    local tx = boat.x + bvx * plan * 0.8        -- partial lead: still dodge-able
    local ty = boat.y + bvy * plan * 0.8
    local bowOff = 32 * (P.LENGTH or 2.6)           -- fire from the (long) bow
    local mx = self.x + math.cos(self.angle) * bowOff
    local my = self.y + math.sin(self.angle) * bowOff
    -- Aimed FROM THE MUZZLE, not the hull centre. The ball leaves ~83 units up a
    -- long bow, so a heading taken from the centre is off by that whole offset:
    -- negligible at range, the entire shot at close quarters. It is why a pirate
    -- sitting on top of you used to land nothing at all.
    local ang = math.atan2(ty - my, tx - mx)
    self.balls[#self.balls + 1] = {
        x = mx, y = my,
        vx = math.cos(ang) * P.BALL_SPEED, vy = math.sin(ang) * P.BALL_SPEED,
        life = 0, plan = plan,
    }
    self.muzzle = 0.14
    Assets.playSfx("cannon", 0.97)
end

-- length scales faster than width: a long low galleon, not a tower
local LEN = config.PIRATE.LENGTH or 2.6
local WID = config.PIRATE.WIDTH or 1.45
-- a longer hull silhouette (drawn-out bow + stern), in local boat space
local HULL = { { 30, 0 }, { 12, -12 }, { -22, -12 }, { -30, 0 }, { -22, 12 }, { 12, 12 } }

-- tattered black sail, screen-space billboard
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

-- cannonballs arc over the water on a parabolic screen height
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
