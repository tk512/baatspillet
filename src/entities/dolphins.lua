-- src/entities/dolphins.lua
-- A little pod of dolphins that comes to play when the boat sails fast: they
-- porpoise alongside in staggered arcs, splashing as they enter and leave the
-- water, then peel off and dive after a while. Pure joy, no interaction -- they
-- never block or bump the boat, and they only show on open water. Everything is
-- code-drawn (crescent body + dorsal fin + belly), so no art is needed; drop
-- Finn-Erik's voice at assets/voice/delfiner.ogg and it plays when they arrive.
-- Movement lives in the flat ground plane; the world depth-sorts the pod like
-- the boat and shark. Tuning in config.DOLPHINS.

local config = require("src.config")
local Assets = require("src.assets")
local Iso    = require("src.systems.iso")

local Dolphins = {}
Dolphins.__index = Dolphins

local D = config.DOLPHINS
local TAU = math.pi * 2

function Dolphins.new()
    local self = setmetatable({}, Dolphins)
    self.playing  = false
    self.cooldown = D.FIRST_WAIT     -- they can show up soon after setting sail
    self.fastT    = 0                -- how long the boat has been at speed
    self.slowT    = 0                -- how long it's been dawdling (ends the visit)
    self.members  = {}
    for i = 1, D.COUNT do
        self.members[i] = {
            -- staggered offsets: a loose diagonal line off one side of the bow
            side  = D.SIDE + (i - 1) * 26,
            along = 40 - (i - 1) * 46,
            phase = (i - 1) * 0.37,      -- jump cycles out of step
            x = 0, y = 0, z = 0, up = false,
        }
    end
    self.ripples = {}                -- entry/exit splashes {x, y, t}
    return self
end

function Dolphins:isVisible() return self.playing end

-- Anchor point for the world's depth sort (the pod swims beside the boat).
function Dolphins:depthPos()
    local m = self.members[1]
    return m.x, m.y
end

function Dolphins:update(dt, boat, terrain)
    -- age the little splashes regardless of state
    for i = #self.ripples, 1, -1 do
        local r = self.ripples[i]
        r.t = r.t + dt
        if r.t > 0.6 then table.remove(self.ripples, i) end
    end

    local fast = boat.speed > boat.maxSpeed * D.TRIGGER_FRAC
    if not self.playing then
        self.cooldown = math.max(0, self.cooldown - dt)
        self.fastT = fast and (self.fastT + dt) or 0
        -- they join once you've held full sail for a moment, on open water
        if self.cooldown <= 0 and self.fastT > 1.5
            and terrain:isWater(boat.x + math.cos(boat.angle + 1.57) * D.SIDE,
                                boat.y + math.sin(boat.angle + 1.57) * D.SIDE) then
            self.playing = true
            self.playT   = D.PLAY_TIME
            self.slowT   = 0
            for _, m in ipairs(self.members) do m.phase = m.phase % 1 end
            if not Assets.playNamedVoice("delfiner") then
                Assets.playPitched("blubb", 0.5, 1.7)   -- excited chirpy bubbles
            end
        end
        return
    end

    -- playing: ride along beside the boat
    self.playT = self.playT - dt
    self.slowT = (boat.speed < boat.maxSpeed * 0.3) and (self.slowT + dt) or 0
    if self.playT <= 0 or self.slowT > 2.5 then     -- bored, or you stopped: dive away
        self.playing = false
        self.cooldown = D.COOLDOWN_MIN + love.math.random() * (D.COOLDOWN_MAX - D.COOLDOWN_MIN)
        return
    end

    local ca, sa = math.cos(boat.angle), math.sin(boat.angle)
    local px, py = -sa, ca                          -- the boat's port side
    self.flip = ((ca - sa) >= 0) and 1 or -1        -- screen-x travel: which way to face
    for i, m in ipairs(self.members) do
        m.x = boat.x + px * m.side + ca * m.along
        m.y = boat.y + py * m.side + sa * m.along
        m.water = terrain:isWater(m.x, m.y)          -- near shore: stay under

        m.phase = m.phase + dt / D.PERIOD
        local u = m.phase % 1
        -- first AIR_FRAC of the cycle is the leap; the rest is a glide below
        local wasUp = m.up
        m.up = m.water and u < 0.55
        m.z = m.up and math.sin((u / 0.55) * math.pi) * D.JUMP_H or 0
        m.u = u

        -- splash + a soft "blub" where it breaks the surface (leader only, so
        -- three dolphins don't turn into a drum machine)
        if m.up ~= wasUp and m.water then
            self.ripples[#self.ripples + 1] = { x = m.x, y = m.y, t = 0 }
            if i == 1 and m.up then
                Assets.playPitched("blubb", 0.3, 1.4 + love.math.random() * 0.5)
            end
        end
    end
end

-- One dolphin body, drawn in screen space: dark back, pale belly, dorsal fin.
-- `pitch` tips the nose up on the way out of the water and down on re-entry;
-- `flip` mirrors it to face the way the pod is moving on screen. Exported so
-- the title screen can send a pod across its sea band too.
function Dolphins.drawBody(sx, sy, s, pitch, flip)
    love.graphics.push()
    love.graphics.translate(sx, sy)
    love.graphics.rotate(pitch * flip)
    love.graphics.scale(s * flip, s)
    love.graphics.setColor(0.36, 0.44, 0.53)                    -- back
    love.graphics.polygon("fill",
        17, 0,   8, -5,   -4, -5,  -12, -2,  -17, -6,  -15, 0,  -17, 6, -11, 3, -4, 4, 8, 4)
    love.graphics.polygon("fill", -1, -5, 4, -5, 1, -10)        -- dorsal fin
    love.graphics.setColor(0.78, 0.84, 0.88)                    -- belly
    love.graphics.polygon("fill", 14, 1, 6, 4, -4, 3, -9, 2, 6, 2)
    love.graphics.pop()
end

function Dolphins:draw()
    -- ripples first, at the waterline
    for _, r in ipairs(self.ripples) do
        local p = r.t / 0.6
        local sx, sy = Iso.project(r.x, r.y, 0)
        love.graphics.setColor(1, 1, 1, (1 - p) * 0.7)
        love.graphics.setLineWidth(2)
        love.graphics.ellipse("line", sx, sy, 8 + p * 20, (8 + p * 20) * 0.5)
        love.graphics.setLineWidth(1)
    end

    for _, m in ipairs(self.members) do
        if m.up and m.z > 0.5 then
            local sx, sy = Iso.project(m.x, m.y, m.z)
            local gx, gy = Iso.project(m.x, m.y, 0)
            -- which way is it travelling on screen? (same trick as the boat)
            local vsx = self.flip or 1
            -- pitch: nose up leaving the water, level at the top, down going in
            local pitch = (m.u / 0.55 - 0.5) * 1.5
            love.graphics.setColor(0, 0, 0, 0.14)                -- shadow on the sea
            love.graphics.ellipse("fill", gx, gy + 2, 14, 5)
            Dolphins.drawBody(sx, sy, 1.15, pitch, vsx)
        end
    end
    love.graphics.setColor(1, 1, 1)
end

return Dolphins
