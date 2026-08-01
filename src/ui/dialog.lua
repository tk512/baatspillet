-- The one modal ask: a dimmed screen, a wooden plaque, a title, and a column of
-- finger-sized buttons. The in-game pause overlay and the title screen's "Vil du
-- avslutte?" are the same object with different words -- so they are the same
-- code, and a fix to the press handling or the sizing lands on both.
--
-- Buttons are `{ label, action, face, hi, lo }`. The FIRST one is the safe one
-- by convention (green, "keep playing"), because that is the one a child who
-- taps at random should land on. Only labels are text: the colour carries it.
--
-- `id` prefixes the Retro press ids, so two dialogs can never share a held
-- button. `onOutside` is what a tap beside the plaque means -- always something
-- harmless; a modal a five-year-old cannot escape is a trap.

local Retro = require("src.ui.retro")

local Dialog = {}
Dialog.__index = Dialog

Dialog.SAFE = { face = { 0.30, 0.50, 0.28 }, hi = { 0.44, 0.68, 0.40 }, lo = { 0.15, 0.28, 0.14 } }

function Dialog.new(id, fonts, title, buttons, onOutside)
    return setmetatable({
        id = id, fonts = fonts, title = title, buttons = buttons,
        onOutside = onOutside, t = 0,
    }, Dialog)
end

function Dialog:update(dt) self.t = self.t + dt end

-- Panel rect + one rect per button, sized to the screen. Input reads the same
-- layout the draw did, so the hit boxes cannot drift from the wood.
function Dialog:layout()
    local sw, sh = love.graphics.getDimensions()
    local bw  = math.min(sw * 0.6, 460)
    local bh  = math.max(46, math.floor(sh * 0.085))
    local gap = math.floor(bh * 0.28)
    local titleH = self.fonts.big:getHeight()
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

function Dialog:draw()
    local sw, sh = love.graphics.getDimensions()
    love.graphics.setColor(0, 0, 0, 0.55)
    love.graphics.rectangle("fill", 0, 0, sw, sh)

    local P, rects = self:layout()
    Retro.plaque(P.x, P.y, P.w, P.h, math.max(3, math.floor(P.h / 70)))

    love.graphics.setFont(self.fonts.big)
    love.graphics.setColor(0.98, 0.94, 0.78)
    love.graphics.print(self.title,
        P.x + P.w / 2 - self.fonts.big:getWidth(self.title) / 2, P.y + P.pad)

    for i, r in ipairs(rects) do
        local label = r.btn.label
        if type(label) == "function" then label = label() end
        Retro.button(self.id .. i, r, label, self.fonts.normal,
            { face = r.btn.face or { 0.36, 0.25, 0.15 },
              hi = r.btn.hi or { 0.52, 0.38, 0.24 },
              lo = r.btn.lo or { 0.22, 0.15, 0.09 },
              textCol = { 0.98, 0.94, 0.80 } })
    end
    love.graphics.setColor(1, 1, 1)
end

-- Always returns true: a modal swallows the click, or the screen behind it acts
-- on a tap meant for the dialog (the title screen would set sail).
function Dialog:mousepressed(x, y, button)
    if button ~= 1 then return true end
    local P, rects = self:layout()
    for i, r in ipairs(rects) do
        if Retro.press(self.id .. i, r, x, y) then return true end
    end
    if not Retro.inRect(P, x, y) and self.onOutside then self.onOutside() end
    return true
end

function Dialog:mousereleased(x, y, button)
    if button ~= 1 then return true end
    local _, rects = self:layout()
    for i, r in ipairs(rects) do
        if Retro.released(self.id .. i, x, y) then r.btn.action(); return true end
    end
    return true
end

function Dialog:keypressed(key)
    if key == "escape" and self.onOutside then self.onOutside() end
end

return Dialog
