-- The isometric camera. On desktop it doesn't chase: you edge-scroll or
-- right-drag, and C recentres. On touch it glides after the boat
-- (followAnchor).

local config = require("src.config")
local Iso    = require("src.systems.iso")
local Scale  = require("src.ui.scale")

local Camera = {}
Camera.__index = Camera

function Camera.new()
    local self = setmetatable({}, Camera)
    self.gx = config.WORLD_WIDTH  / 2   -- ground point shown at screen center
    self.gy = config.WORLD_HEIGHT / 2
    self.zoom = config.CAMERA_DEFAULT_ZOOM
    self.shakeMag = 0                    -- screen-shake magnitude (px), decays
    self.shakeX, self.shakeY = 0, 0
    return self
end

-- brief shake; the strongest of any overlapping kicks wins
function Camera:addShake(mag)
    self.shakeMag = math.max(self.shakeMag, mag)
end

function Camera:centerOn(gx, gy)
    self.gx, self.gy = gx, gy
    self:clamp()
end
Camera.snapTo = Camera.centerOn

function Camera:update(dt)
    self:clamp()
    if self.shakeMag > 0 then
        self.shakeMag = math.max(0, self.shakeMag - 40 * dt)   -- decay
        self.shakeX = (love.math.random() * 2 - 1) * self.shakeMag
        self.shakeY = (love.math.random() * 2 - 1) * self.shakeMag
    else
        self.shakeX, self.shakeY = 0, 0
    end
end

function Camera:clamp()
    self.gx = math.max(0, math.min(config.WORLD_WIDTH,  self.gx))
    self.gy = math.max(0, math.min(config.WORLD_HEIGHT, self.gy))
end

-- Move by a screen-space delta; the iso inverse keeps panning aligned with
-- what you see.
function Camera:panScreen(sx, sy)
    local gdx, gdy = Iso.unproject(sx / self.zoom, sy / self.zoom)
    self.gx = self.gx + gdx
    self.gy = self.gy + gdy
    self:clamp()
end

-- Scrolls within EDGE px of a border. With an anchor the drift is capped so
-- the boat can't scroll off-screen.
function Camera:edgeScroll(dt, anchorX, anchorY)
    if not love.window.hasFocus() then return end
    local mx, my = love.mouse.getPosition()
    local w, h = love.graphics.getDimensions()
    local EDGE = config.EDGE_SCROLL_MARGIN
    local sx, sy = 0, 0
    if mx < EDGE then sx = -1 elseif mx > w - EDGE then sx = 1 end
    if my < EDGE then sy = -1 elseif my > h - EDGE then sy = 1 end
    if sx ~= 0 or sy ~= 0 then
        local step = config.EDGE_SCROLL_SPEED * dt
        self:panScreen(sx * step, sy * step)
        if anchorX then self:keepAnchorInView(anchorX, anchorY) end
    end
end

-- Holds the anchor in the screen's central band. In iso u = gx-gy, v = gx+gy
-- space the screen offset is linear in each, so u and v clamp independently.
function Camera:keepAnchorInView(bx, by)
    local w, h = love.graphics.getDimensions()
    local keep = config.EDGE_SCROLL_KEEP or 0.34
    local maxU = (w * keep) / (Iso.SX * self.zoom)   -- screen X offset uses (gx-gy)*SX
    local maxV = (h * keep) / (Iso.SY * self.zoom)   -- screen Y offset uses (gx+gy)*SY
    local bu, bv = bx - by, bx + by
    local u = math.max(bu - maxU, math.min(bu + maxU, self.gx - self.gy))
    local v = math.max(bv - maxV, math.min(bv + maxV, self.gx + self.gy))
    self.gx = (u + v) / 2
    self.gy = (v - u) / 2
    self:clamp()
end

-- Touch follow: keepAnchorInView's band, but eased over time so the map glides
-- after the boat instead of lurching. Frame-rate independent via exp decay.
function Camera:followAnchor(dt, bx, by)
    local w, h = love.graphics.getDimensions()
    local keep = config.TOUCH_FOLLOW_KEEP
    local maxU = (w * keep) / (Iso.SX * self.zoom)
    local maxV = (h * keep) / (Iso.SY * self.zoom)
    local bu, bv = bx - by, bx + by
    local u = math.max(bu - maxU, math.min(bu + maxU, self.gx - self.gy))
    local v = math.max(bv - maxV, math.min(bv + maxV, self.gx + self.gy))
    local tx, ty = (u + v) / 2, (v - u) / 2      -- nearest pos that holds the band
    local k = 1 - math.exp(-config.TOUCH_FOLLOW_LERP * dt)
    self.gx = self.gx + (tx - self.gx) * k
    self.gy = self.gy + (ty - self.gy) * k
    self:clamp()
end

function Camera:drag(dx, dy)
    self:panScreen(-dx, -dy)
end

function Camera:attach()
    local cx, cy = Iso.project(self.gx, self.gy)
    -- Snap to whole DEVICE pixels, not whole units: unit snapping steps 2-3
    -- device pixels on retina and the boat judders against the glide camera.
    local dpi = love.graphics.getDPIScale()
    local ox = math.floor((love.graphics.getWidth()  / 2 - cx * self.zoom + self.shakeX) * dpi + 0.5) / dpi
    local oy = math.floor((love.graphics.getHeight() / 2 - cy * self.zoom + self.shakeY) * dpi + 0.5) / dpi
    love.graphics.push()
    love.graphics.translate(ox, oy)
    love.graphics.scale(self.zoom, self.zoom)
end

function Camera:detach()
    love.graphics.pop()
end

-- ground -> screen px, matching attach()'s transform
function Camera:worldToScreen(gx, gy)
    local cx, cy = Iso.project(self.gx, self.gy)
    local dpi = love.graphics.getDPIScale()
    local ox = math.floor((love.graphics.getWidth()  / 2 - cx * self.zoom) * dpi + 0.5) / dpi
    local oy = math.floor((love.graphics.getHeight() / 2 - cy * self.zoom) * dpi + 0.5) / dpi
    local ix, iy = Iso.project(gx, gy, 0)
    return ix * self.zoom + ox, iy * self.zoom + oy
end

-- screen px -> ground, assuming the click is on the water
function Camera:screenToWorld(sx, sy)
    local cx, cy = Iso.project(self.gx, self.gy)
    local isoX = (sx - love.graphics.getWidth()  / 2) / self.zoom + cx
    local isoY = (sy - love.graphics.getHeight() / 2) / self.zoom + cy
    return Iso.unproject(isoX, isoY)
end

-- ground-space bounds of what's on screen, for tile culling
function Camera:groundBounds()
    local w, h = love.graphics.getWidth(), love.graphics.getHeight()
    local minGx, minGy = math.huge, math.huge
    local maxGx, maxGy = -math.huge, -math.huge
    for _, corner in ipairs({ {0, 0}, {w, 0}, {0, h}, {w, h} }) do
        local gx, gy = self:screenToWorld(corner[1], corner[2])
        minGx = math.min(minGx, gx); maxGx = math.max(maxGx, gx)
        minGy = math.min(minGy, gy); maxGy = math.max(maxGy, gy)
    end
    return minGx, minGy, maxGx, maxGy
end

return Camera
