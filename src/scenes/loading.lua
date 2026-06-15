-- src/scenes/loading.lua
-- Loading screen due to World:load being heavy
-- Run as coroutine

local config = require("src.config")
local Loader = require("src.systems.loader")

local Loading = {}

function Loading:load(game)
    self.game = game
    self.t = 0
    self.done = false
    -- The big terrain loops call Loader.tick() to yield this coroutine.
    local World = game.scenes.world
    self.co = coroutine.create(function() World:load(game) end)
end

function Loading:update(dt)
    self.t = self.t + dt
    if self.done or not self.co then return end

    -- run one ~11ms slice of the build, then draw a frame
    Loader.deadline = love.timer.getTime() + 0.011
    local ok, err = coroutine.resume(self.co)
    Loader.deadline = math.huge
    if not ok then error(err) end

    if coroutine.status(self.co) == "dead" then     -- build finished
        self.done = true
        self.game.sceneName = "world"
        self.game.scene = self.game.scenes.world    -- install the built world
    end
end

function Loading:draw()
    local sw, sh = love.graphics.getWidth(), love.graphics.getHeight()
    local c = config.colors

    -- sea backdrop (top -> deep gradient in a few bands)
    for b = 0, 5 do
        local f = b / 5
        love.graphics.setColor(c.water_top[1] + (c.water_deep[1] - c.water_top[1]) * f,
                               c.water_top[2] + (c.water_deep[2] - c.water_top[2]) * f,
                               c.water_top[3] + (c.water_deep[3] - c.water_top[3]) * f)
        love.graphics.rectangle("fill", 0, sh * (b / 6), sw, sh / 6 + 1)
    end

    -- watery animation: rolling foam rows drifting across the sea
    local t = self.t
    for r = 1, 8 do
        local wy = sh * (0.12 + r * 0.095)
        local spacing = sw * 0.085
        local off = (t * (22 + r * 7)) % spacing
        love.graphics.setColor(c.foam[1], c.foam[2], c.foam[3], 0.09 + 0.05 * (0.5 + 0.5 * math.sin(t * 2 + r)))
        for x = -spacing, sw, spacing do
            local dx = x + off + (r % 2) * spacing * 0.5
            love.graphics.rectangle("fill", dx, wy + math.sin(t * 1.6 + x * 0.012) * 4, spacing * 0.5, 3)
        end
    end

    -- a few expanding ripple rings near the middle
    love.graphics.setLineWidth(3)
    for i = 0, 2 do
        local pr = ((t * 0.45 + i / 3) % 1)
        local rad = pr * sw * 0.22
        love.graphics.setColor(c.foam[1], c.foam[2], c.foam[3], 0.30 * (1 - pr))
        love.graphics.ellipse("line", sw / 2, sh * 0.44, rad, rad * 0.5)
    end
    love.graphics.setLineWidth(1)

    -- "Laster kartet…" with animated dots
    love.graphics.setFont(self.game.fonts.big)
    local dots = string.rep(".", (math.floor(self.t * 3) % 4))
    local label = "Laster kartet" .. dots
    love.graphics.setColor(0, 0, 0, 0.4)
    love.graphics.print(label, sw / 2 - self.game.fonts.big:getWidth("Laster kartet...") / 2 + 2, sh * 0.62 + 2)
    love.graphics.setColor(c.text)
    love.graphics.print(label, sw / 2 - self.game.fonts.big:getWidth("Laster kartet...") / 2, sh * 0.62)

    love.graphics.setColor(1, 1, 1)
end

function Loading:keypressed() end
function Loading:mousepressed() end

return Loading
