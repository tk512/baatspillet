-- In-game pause overlay: dims the world, centres a plaque with big touch-sized
-- buttons.

local config = require("src.config")
local Assets = require("src.assets")
local Retro  = require("src.ui.retro")

local PauseMenu = {}
PauseMenu.__index = PauseMenu

function PauseMenu.new(world)
    local self = setmetatable({}, PauseMenu)
    self.world = world
    self.t = 0
    -- Two choices only. No Lyd toggle: the voice prompts ARE the pre-reader UI,
    -- so muting in-game is a footgun; volume is the platform's job (desktop
    -- keeps the M key for grown-ups).
    self.buttons = {
        { label = "Fortsett", action = function() world:closePause() end,
          face = { 0.30, 0.50, 0.28 }, hi = { 0.44, 0.68, 0.40 }, lo = { 0.15, 0.28, 0.14 } },
        { label = "Gå ut",    action = function() world:exitToMenu() end },
    }
    return self
end

function PauseMenu:update(dt) self.t = self.t + dt end

-- Panel rect + button rects, sized to the screen. Also used by mousepressed.
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

    for i, r in ipairs(rects) do
        local label = r.btn.label
        if type(label) == "function" then label = label() end
        Retro.button("pause" .. i, r, label, fonts.normal,
            { face = r.btn.face or { 0.36, 0.25, 0.15 },
              hi = r.btn.hi or { 0.52, 0.38, 0.24 },
              lo = r.btn.lo or { 0.22, 0.15, 0.09 },
              textCol = { 0.98, 0.94, 0.80 } })
    end
    love.graphics.setColor(1, 1, 1)
end

local function inRect(r, x, y) return x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h end

function PauseMenu:mousepressed(x, y, button)
    if button ~= 1 then return end
    local P, rects = self:layout()
    for i, r in ipairs(rects) do
        if Retro.press("pause" .. i, r, x, y) then return end
    end
    if not inRect(P, x, y) then self.world:closePause() end   -- tap outside = resume
end

function PauseMenu:mousereleased(x, y, button)
    if button ~= 1 then return end
    local _, rects = self:layout()
    for i, r in ipairs(rects) do
        if Retro.released("pause" .. i, x, y) then
            Assets.playSfx("leave", 0.5)
            r.btn.action()
            return
        end
    end
end

function PauseMenu:keypressed(key)
    if key == "escape" then self.world:closePause() end
end

return PauseMenu
