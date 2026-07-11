-- src/ui/retro.lua
-- Shared chunky-bevel drawing for the title, HUD and dock screens.

local Haptics = require("src.systems.haptics")

local Retro = {}

-- Warm-wood palette, shared with portscreen's cosy theme.
Retro.WOOD = {
    face   = {0.40, 0.29, 0.19},
    hi     = {0.62, 0.46, 0.30},
    lo     = {0.20, 0.14, 0.09},
    accent = {0.95, 0.80, 0.36},
    text   = {0.96, 0.91, 0.76},
    deep   = {0.28, 0.18, 0.11},   -- recessed wood
}

-- Filled rect with a 3D edge: light top/left + dark bottom/right when raised,
-- swapped for a sunken groove. `t` is edge thickness; raised defaults true.
function Retro.bevel(x, y, w, h, face, hi, lo, t, raised)
    if raised == nil then raised = true end
    love.graphics.setColor(face)
    love.graphics.rectangle("fill", x, y, w, h)
    local a, b = hi, lo
    if not raised then a, b = lo, hi end
    love.graphics.setColor(a)
    love.graphics.rectangle("fill", x, y, w, t)
    love.graphics.rectangle("fill", x, y, t, h)
    love.graphics.setColor(b)
    love.graphics.rectangle("fill", x, y + h - t, w, t)
    love.graphics.rectangle("fill", x + w - t, y, t, h)
end

-- Wooden plaque (raised outer bevel + sunken inner well). Returns the inner
-- content rect (x, y, w, h). Shared by the HUD plaques and the minimap frame.
function Retro.plaque(x, y, w, h, t)
    local W = Retro.WOOD
    Retro.bevel(x, y, w, h, W.face, W.hi, W.lo, t, true)
    Retro.bevel(x + t, y + t, w - 2 * t, h - 2 * t, W.deep, W.hi, W.lo,
        math.max(1, math.floor(t * 0.6)), false)
    return x + t * 2, y + t * 2, w - t * 4, h - t * 4
end

-- ── The shared "locked" language: harbour rope + gold padlock ──────────────
-- (used by the boat chooser and the map chooser; full-colour content behind a
-- rope reads as "for later", never "broken")
function Retro.ropeAcross(x1, x2, y, sag, thick)
    love.graphics.setColor(0.80, 0.64, 0.40)
    love.graphics.setLineWidth(thick)
    local n = 12
    for j = 0, n - 1 do
        local u0, u1 = j / n, (j + 1) / n
        love.graphics.line(
            x1 + (x2 - x1) * u0, y + math.sin(u0 * math.pi) * sag,
            x1 + (x2 - x1) * u1, y + math.sin(u1 * math.pi) * sag)
    end
    love.graphics.setColor(0.55, 0.40, 0.22)
    love.graphics.circle("fill", x1, y, thick * 1.4)
    love.graphics.circle("fill", x2, y, thick * 1.4)
    love.graphics.setLineWidth(1)
end

function Retro.padlock(x, y, s)
    love.graphics.setColor(0.35, 0.28, 0.16); love.graphics.setLineWidth(math.max(2, s * 0.22))
    love.graphics.arc("line", "open", x, y - s * 0.28, s * 0.44, math.pi, 2 * math.pi)
    love.graphics.setColor(0.95, 0.78, 0.28)
    love.graphics.rectangle("fill", x - s * 0.55, y - s * 0.28, s * 1.1, s * 0.85, s * 0.12, s * 0.12)
    love.graphics.setColor(0.55, 0.42, 0.14)
    love.graphics.circle("fill", x, y + s * 0.12, s * 0.13)
    love.graphics.setLineWidth(1)
end

-- ── Press feedback + star-burst ─────────────────────────────────────────────
-- Every button presses IN while held and fires on RELEASE, with a little gold
-- burst on success — the kids-app squish. Fire-on-release also gives "slide
-- your finger off to cancel" for free. Immediate-mode protocol (`id` = any
-- unique string per screen):
--
--   mousepressed:   if Retro.press(id, rect, x, y[, ox, oy]) then return end
--                   (rect and x,y in the caller's space; ox,oy = that space's
--                   screen offset, for panels drawn under a translate)
--   draw:           sunken = Retro.isDown(id)  (or use Retro.button)
--   mousereleased:  if Retro.released(id, x, y) then <the action> end
--                   (x,y in SCREEN space — the rect was captured at press time)
--
-- game.lua pumps Retro.updateFx/drawFx globally and calls Retro.cancelPress
-- after every release + on scene switches, so state can never get stuck.

Retro._pressed = nil      -- id of the held button
Retro._pressRect = nil    -- its rect, captured in screen space at press time
Retro._fx = {}

local function inRect(r, x, y)
    return x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h
end
Retro.inRect = inRect

function Retro.press(id, r, x, y, ox, oy)
    if inRect(r, x, y) then
        ox, oy = ox or 0, oy or 0
        Retro._pressed = id
        Retro._pressRect = { x = r.x + ox, y = r.y + oy, w = r.w, h = r.h }
        Haptics.tap()          -- iPhone: a light tick as the button goes in
        return true
    end
    return false
end

-- Held AND still hovering: sliding off pops the button back up.
function Retro.isDown(id)
    if Retro._pressed ~= id then return false end
    local mx, my = love.mouse.getPosition()
    return inRect(Retro._pressRect, mx, my)
end

function Retro.released(id, x, y)
    if Retro._pressed ~= id then return false end
    local r = Retro._pressRect
    Retro._pressed, Retro._pressRect = nil, nil
    if inRect(r, x, y) then
        Retro.burst(x, y)
        Haptics.thump()        -- iPhone: a firmer tap as it fires
        return true
    end
    return false   -- slid off: cancelled
end

function Retro.cancelPress() Retro._pressed, Retro._pressRect = nil, nil end

-- The standard wooden button, press-aware: raised normally, brighter on hover,
-- sunken with the label nudged down-right while held. opts: face/hi/lo colour
-- overrides, textCol.
function Retro.button(id, r, label, font, opts)
    opts = opts or {}
    local W = Retro.WOOD
    local t = math.max(2, math.floor(r.h * 0.12))
    local down = Retro.isDown(id)
    local mx, my = love.mouse.getPosition()
    local face = opts.face or W.face
    if not down and inRect(r, mx, my) then face = opts.hi or W.hi end
    Retro.bevel(r.x, r.y, r.w, r.h, face, opts.hi or W.hi, opts.lo or W.lo, t, not down)
    local off = down and t or 0
    love.graphics.setFont(font)
    love.graphics.setColor(opts.textCol or W.text)
    love.graphics.print(label, r.x + r.w / 2 - font:getWidth(label) / 2 + off,
        r.y + r.h / 2 - font:getHeight() / 2 + off)
end

-- A quick gold star-burst + expanding ring at (x, y). Sizes/speeds scale with
-- the window so it reads the same on a phone and a desktop.
function Retro.burst(x, y, col)
    local k = love.graphics.getHeight() / 800
    local fx = Retro._fx
    for i = 1, 10 do
        local a = (i / 10) * 2 * math.pi + love.math.random() * 0.6
        local sp = (150 + love.math.random() * 170) * k
        fx[#fx + 1] = {
            x = x, y = y,
            vx = math.cos(a) * sp, vy = math.sin(a) * sp - 70 * k,
            t = 0, life = 0.4 + love.math.random() * 0.25,
            r = (2.5 + love.math.random() * 3) * k, col = col,
        }
    end
    fx[#fx + 1] = { ring = true, x = x, y = y, t = 0, life = 0.32, k = k }
end

function Retro.updateFx(dt)
    local fx = Retro._fx
    for i = #fx, 1, -1 do
        local p = fx[i]
        p.t = p.t + dt
        if p.t >= p.life then
            table.remove(fx, i)
        elseif not p.ring then
            p.x = p.x + p.vx * dt
            p.y = p.y + p.vy * dt
            p.vy = p.vy + 640 * dt * (love.graphics.getHeight() / 800)
        end
    end
end

function Retro.drawFx()
    for _, p in ipairs(Retro._fx) do
        local f = 1 - p.t / p.life
        if p.ring then
            love.graphics.setColor(1, 0.9, 0.45, f * 0.9)
            love.graphics.setLineWidth(math.max(2, 3 * p.k))
            love.graphics.circle("line", p.x, p.y, (1 - f) * 44 * p.k + 6 * p.k)
            love.graphics.setLineWidth(1)
        else
            local c = p.col or { 1, 0.85, 0.32 }
            love.graphics.setColor(c[1], c[2], c[3], f)
            love.graphics.circle("fill", p.x, p.y, p.r * f + 1)
        end
    end
    love.graphics.setColor(1, 1, 1)
end

return Retro
