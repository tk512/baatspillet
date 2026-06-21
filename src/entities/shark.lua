-- src/entities/shark.lua
-- A friendly shark that wanders the open sea. The opposite of the pirate: there
-- is no danger here. It ambles over when you get near, and if you bump into it
-- the boat just softly bounces (the world calls boat:collideCircle, the very
-- same soft bounce as nudging an island) while the shark chomps once and darts
-- away. It won't pester -- after a bump it keeps its distance for a while. While
-- a pirate is hunting it dives out of sight, so the two never crowd the screen.
-- Tuning lives in config.SHARK. Lives in the flat ground plane; only draw() knows
-- the iso projection, and the world depth-sorts it like the boat and pirate.

local config = require("src.config")
local Assets = require("src.assets")
local Iso    = require("src.systems.iso")

local Shark = {}
Shark.__index = Shark

local S = config.SHARK
local FRAMES = { 1, 2, 3, 4, 3, 2 }     -- jaw closed -> wide -> closed (chomp)

local function angleDiff(a, b)
    local d = (b - a) % (2 * math.pi)
    if d > math.pi then d = d - 2 * math.pi end
    return d
end

local function approach(v, target, rate)        -- move v toward target, framerate-safe
    return v + (target - v) * math.min(1, rate)
end

function Shark.new(x, y)
    local self = setmetatable({}, Shark)
    self.x, self.y = x, y
    self.angle    = love.math.random() * 2 * math.pi
    self.speed    = S.SPEED
    self.targetAngle  = self.angle
    self.wanderT      = 0          -- countdown to the next idle heading change
    self.bumpCooldown = 0          -- won't bump again until this hits 0
    self.dartT        = 0          -- >0 while scooting away after a bump
    self.chompT       = love.math.random() * #FRAMES
    self.dive         = 1          -- starts hidden; mostly plays deep underwater
    self.surfaced     = false      -- the surfacing schedule (see update)
    self.phaseT       = S.SUBMERGED_MIN + love.math.random() * (S.SUBMERGED_MAX - S.SUBMERGED_MIN)
    self.radius       = S.RADIUS
    return self
end

-- True while the shark is up at the surface and can be bumped / will react.
function Shark:isActive()
    return self.dive < 0.4
end

function Shark:update(dt, boat, terrain, pirateActive, onBump)
    -- Surfacing schedule: it spends most of its time hidden, playing somewhere
    -- deep in the ocean, and only pops up briefly to look around (and maybe get
    -- bumped) before diving again. A hunting pirate keeps it down regardless.
    self.phaseT = self.phaseT - dt
    if self.phaseT <= 0 then
        self.surfaced = not self.surfaced
        if self.surfaced then
            self.phaseT = S.SURFACE_MIN + love.math.random() * (S.SURFACE_MAX - S.SURFACE_MIN)
        else
            self.phaseT = S.SUBMERGED_MIN + love.math.random() * (S.SUBMERGED_MAX - S.SUBMERGED_MIN)
        end
    end
    local wantUp = self.surfaced and not pirateActive
    self.dive = approach(self.dive, wantUp and 0 or 1, dt * S.DIVE_RATE)

    self.bumpCooldown = math.max(0, self.bumpCooldown - dt)
    self.dartT        = math.max(0, self.dartT - dt)

    local dx, dy = boat.x - self.x, boat.y - self.y
    local dist = math.sqrt(dx * dx + dy * dy)

    -- Decide where to head and how fast.
    local targetSpeed = S.SPEED
    if self.dartT > 0 then
        self.targetAngle = math.atan2(-dy, -dx)     -- scoot away from the boat
        targetSpeed = S.DART_SPEED
    elseif self:isActive() and self.bumpCooldown == 0 and not pirateActive
            and dist < S.CURIOUS_DIST then
        self.targetAngle = math.atan2(dy, dx)        -- curious: amble over
    else
        self.wanderT = self.wanderT - dt             -- idle meander
        if self.wanderT <= 0 then
            self.targetAngle = self.angle + (love.math.random() - 0.5) * 1.8
            self.wanderT = 2 + love.math.random() * 2
        end
        if self:isActive() then targetSpeed = S.SPEED * 0.4 end  -- dawdle & look around up top
    end

    -- Turn toward the target heading, then ease the speed toward its target.
    local diff = angleDiff(self.angle, self.targetAngle)
    self.angle = self.angle + math.max(-1, math.min(1, diff * 2)) * S.TURN_RATE * dt
    self.speed = approach(self.speed, targetSpeed, dt * 2)

    -- Move; if land is ahead, veer back toward open water (it stays at sea).
    local nx = self.x + math.cos(self.angle) * self.speed * dt
    local ny = self.y + math.sin(self.angle) * self.speed * dt
    if terrain:isWater(nx, ny) then
        self.x, self.y = nx, ny
    else
        self.angle = self.angle + 1.4 * dt
        self.speed = self.speed * 0.9
    end
    self.x = math.max(20, math.min(config.WORLD_WIDTH - 20, self.x))
    self.y = math.max(20, math.min(config.WORLD_HEIGHT - 20, self.y))

    -- Contact: react with a chomp + dart. The boat's bounce is applied by the
    -- world (boat:collideCircle), so here we only kick off the shark's reaction.
    if self:isActive() and self.bumpCooldown == 0
            and dist <= boat.radius + self.radius + 4 then
        self.dartT        = S.DART_TIME
        self.bumpCooldown = S.BUMP_COOLDOWN
        self.targetAngle  = math.atan2(-dy, -dx)
        if onBump then onBump() end
    end

    -- Jaw animation: a gentle idle chomp, faster while darting off.
    self.chompT = self.chompT + dt * (self.dartT > 0 and S.DART_CHOMP or S.CHOMP_RATE)
end

function Shark:draw()
    local img = Assets.image("shark/shark_" .. FRAMES[math.floor(self.chompT) % #FRAMES + 1] .. ".png")
    if not img then return end
    -- Keep the Assets default nearest filter: the sprite is pixel-art now, so it
    -- should stay crisp and chunky, not smoothed like the boat photo.

    -- Billboard like the boat: the sprite faces left, so mirror it when the
    -- shark is moving to the right on the iso screen.
    local vsx = (math.cos(self.angle) - math.sin(self.angle)) * Iso.SX
    local flip = (vsx >= 0) and -1 or 1

    local want = S.SPRITE_WIDTH
    local scale = want / img:getWidth()
    local sx, sy = Iso.project(self.x, self.y, 0)
    local vis = 1 - self.dive
    local sink = self.dive * want * 0.35           -- slip down into the water as it dives
    local bob = math.sin(love.timer.getTime() * 1.4) * 3

    -- soft shadow on the water (fades as it dives)
    love.graphics.setColor(0, 0, 0, 0.16 * vis)
    love.graphics.ellipse("fill", sx, sy + 5, want * 0.40, want * 0.11)

    love.graphics.setColor(1, 1, 1, vis)
    love.graphics.draw(img, sx, sy + bob + sink, 0, scale * flip, scale,
        img:getWidth() / 2, img:getHeight() * 0.55)
    love.graphics.setColor(1, 1, 1)
end

return Shark
