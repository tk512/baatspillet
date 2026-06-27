-- src/ui/pausemenu.lua
-- A simple in-game pause overlay in the wooden retro style: dims the world and
-- shows a centred plaque with big, touch-friendly buttons (Fortsett, Lyd on/off,
-- Fullskjerm, Hovedmeny). Built so it works the same with a mouse or an iPad tap.

local config = require("src.config")
local Assets = require("src.assets")
local Retro  = require("src.ui.retro")

local PauseMenu = {}
PauseMenu.__index = PauseMenu

function PauseMenu.new(world)
    local self = setmetatable({}, PauseMenu)
    self.world = world
    self.t = 0
    self.buttons = {
        { label = "Fortsett",   action = function() world:closePause() end },
        { label = function() return "Lyd: " .. (config.AUDIO_ON and "På" or "Av") end,
          action = function() config.AUDIO_ON = not config.AUDIO_ON; Assets.refreshAudio() end },
        { label = "Gå ut",      action = function() world:exitToMenu() end },
    }
    return self
end

function PauseMenu:update(dt) self.t = self.t + dt end

-- Lay the panel out (also used by mousepressed). Returns the panel rect and a list
-- of button rects, sized to the screen so it scales on any resolution / iPad.
function PauseMenu:layout()
    local sw, sh = love.graphics.getDimensions()
    local fonts = self.world.game.fonts
    local bw = math.min(sw * 0.6, 460)
    local bh = math.max(46, math.floor(sh * 0.085))
    local gap = math.floor(bh * 0.28)
    local titleH = fonts.big:getHeight()
    local pad = math.floor(bh * 0.5)
    local n = #self.buttons
    local ph = pad + titleH + pad + n * bh + (n - 1) * gap + pad
    local pw = bw + pad * 2
    local px = math.floor((sw - pw) / 2)
    local py = math.floor((sh - ph) / 2)
    local rects = {}
    local by = py + pad + titleH + pad
    for i = 1, n do
        rects[i] = { x = px + pad, y = by, w = bw, h = bh, btn = self.buttons[i] }
        by = by + bh + gap
    end
    return { x = px, y = py, w = pw, h = ph, titleH = titleH, pad = pad }, rects
end

function PauseMenu:draw()
    local sw, sh = love.graphics.getDimensions()
    local fonts = self.world.game.fonts
    love.graphics.setColor(0, 0, 0, 0.55)
    love.graphics.rectangle("fill", 0, 0, sw, sh)

    local P, rects = self:layout()
    local t = math.max(3, math.floor(P.h / 70))
    Retro.plaque(P.x, P.y, P.w, P.h, t)

    love.graphics.setFont(fonts.big)
    love.graphics.setColor(0.98, 0.94, 0.78)
    local title = "Pause"
    love.graphics.print(title, P.x + P.w / 2 - fonts.big:getWidth(title) / 2, P.y + P.pad)

    love.graphics.setFont(fonts.normal)
    for _, r in ipairs(rects) do
        local bt = math.max(2, math.floor(r.h * 0.12))
        Retro.bevel(r.x, r.y, r.w, r.h, { 0.36, 0.25, 0.15 }, { 0.52, 0.38, 0.24 },
            { 0.22, 0.15, 0.09 }, bt, true)
        local label = r.btn.label
        if type(label) == "function" then label = label() end
        love.graphics.setColor(0.98, 0.94, 0.80)
        love.graphics.print(label,
            r.x + r.w / 2 - fonts.normal:getWidth(label) / 2,
            r.y + r.h / 2 - fonts.normal:getHeight() / 2)
    end
    love.graphics.setColor(1, 1, 1)
end

local function inRect(r, x, y) return x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h end

function PauseMenu:mousepressed(x, y, button)
    if button ~= 1 then return end
    local P, rects = self:layout()
    for _, r in ipairs(rects) do
        if inRect(r, x, y) then
            Assets.playSfx("leave", 0.5)
            r.btn.action()
            return
        end
    end
    if not inRect(P, x, y) then self.world:closePause() end   -- tap outside = resume
end

function PauseMenu:keypressed(key)
    if key == "escape" then self.world:closePause() end
end

return PauseMenu
