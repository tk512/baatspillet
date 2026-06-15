-- src/ui/portscreen.lua
-- The docking screen, styled like an early-90s strategy briefing: a beveled wood
-- panel with the harbour master's portrait, dither + scanlines, and a per-harbour
-- mood (cosy or scary, each with its own theme and music). The master gives the
-- order: frakt fisk, ta passasjerer, etc.
-- An overlay owned by the world scene. Modes: offer / busy / deliver / visit.

local config = require("src.config")
local Assets = require("src.assets")
local Retro  = require("src.ui.retro")

local PortScreen = {}
PortScreen.__index = PortScreen

-- Color themes: warm wood vs cold stone.
local THEMES = {
    cosy = {
        face = {0.40, 0.29, 0.19}, hi = {0.62, 0.46, 0.30}, lo = {0.20, 0.14, 0.09},
        title = {0.28, 0.18, 0.11}, accent = {0.95, 0.80, 0.36},
        text = {0.96, 0.91, 0.76}, well = {0.15, 0.10, 0.07}, dither = {0, 0, 0, 0.10},
        btn = {0.30, 0.50, 0.26}, btnhi = {0.45, 0.66, 0.36}, btnlo = {0.16, 0.28, 0.13},
    },
    scary = {
        face = {0.22, 0.24, 0.28}, hi = {0.38, 0.40, 0.46}, lo = {0.08, 0.09, 0.12},
        title = {0.13, 0.09, 0.12}, accent = {0.88, 0.32, 0.28},
        text = {0.86, 0.86, 0.90}, well = {0.06, 0.07, 0.10}, dither = {0, 0, 0, 0.16},
        btn = {0.45, 0.20, 0.20}, btnhi = {0.62, 0.32, 0.30}, btnlo = {0.22, 0.10, 0.10},
    },
}

local fontCache = {}
local function vfont(px)
    px = math.max(6, math.floor(px))
    if not fontCache[px] then
        fontCache[px] = love.graphics.newFont(px)
        fontCache[px]:setFilter("nearest", "nearest")
    end
    return fontCache[px]
end

function PortScreen.new(world, port, info)
    local self = setmetatable({}, PortScreen)
    self.world = world
    self.port  = port
    self.mode  = info.mode
    self.offer = info.offer
    self.earned    = info.earned or 0
    self.delivered = info.delivered or 0
    self.mission   = info.mission           -- current job (for the "busy" message)
    self.mood  = port.def.mood or "cosy"
    self.theme = THEMES[self.mood] or THEMES.cosy
    self.t = 0
    Assets.startDockMood(self.mood)
    self:playVoice()
    if self.mode == "deliver" then           -- raining gold coins
        self.coins = {}
        for i = 1, 70 do self.coins[i] = self:newCoin() end
        self.coinSndT, self.coinSndN = 0, 0
    end
    return self
end

local function rnd(a, b) return a + love.math.random() * (b - a) end

-- One gold coin. They start staggered above the screen so they rain in, bounce
-- on a floor near the bottom, and settle into a pile.
function PortScreen:newCoin()
    local sw, sh = love.graphics.getWidth(), love.graphics.getHeight()
    return {
        x = rnd(sw * 0.08, sw * 0.92),
        y = rnd(-sh * 2.4, -10),                      -- staggered so they rain in over time
        vx = rnd(-25, 25), vy = rnd(40, 160),
        spin = rnd(0, 6.28), spinsp = rnd(4, 10),
        r = rnd(sh * 0.011, sh * 0.022),
        floor = sh * 0.90 + rnd(-sh * 0.05, sh * 0.06), -- varied so the pile has depth
        rest = false,
    }
end

-- Briefing -> recorded "Du har et oppdrag!", wrong harbour -> "FEIL HAVN!",
-- else a per-town clip (dock_<id>.ogg) if recorded, else a boat horn.
function PortScreen:playVoice()
    if self.mode == "offer" and Assets.playNamedVoice("oppdrag") then return end
    if self.mode == "busy" and Assets.playNamedVoice("feil_havn") then return end
    if Assets.playNamedVoice("dock_" .. self.port.id) then return end
    Assets.playSfx("horn")
end

function PortScreen:update(dt)
    self.t = self.t + dt
    if self.coins then
        for _, co in ipairs(self.coins) do
            if not co.rest then
                co.vy = co.vy + 900 * dt               -- gravity
                co.x = co.x + co.vx * dt
                co.y = co.y + co.vy * dt
                co.spin = co.spin + co.spinsp * dt
                if co.y >= co.floor then
                    co.y = co.floor
                    if co.vy > 80 then                 -- bounce, losing energy
                        co.vy = -co.vy * 0.45
                        co.vx = co.vx * 0.7
                        co.spinsp = co.spinsp * 0.6
                    else                               -- come to rest in the pile
                        co.vy, co.vx, co.spinsp, co.rest = 0, 0, 0, true
                    end
                end
            end
        end
        -- a quick cascade of coin blips right after delivery
        self.coinSndT = self.coinSndT + dt
        if self.coinSndN < 7 and self.coinSndT > self.coinSndN * 0.09 then
            Assets.playSfx("coin"); self.coinSndN = self.coinSndN + 1
        end
    end
end

function PortScreen:drawCoin(co)
    local sq = math.abs(math.cos(co.spin))          -- fake spin: squish the width
    local rx = co.r * (0.22 + 0.78 * sq)
    love.graphics.setColor(0.60, 0.45, 0.10)         -- dark rim
    love.graphics.ellipse("fill", co.x, co.y, rx + 1, co.r + 1)
    love.graphics.setColor(0.88, 0.68, 0.20)         -- gold
    love.graphics.ellipse("fill", co.x, co.y, rx, co.r)
    love.graphics.setColor(0.99, 0.88, 0.45)         -- highlight
    love.graphics.ellipse("fill", co.x - rx * 0.2, co.y - co.r * 0.2, rx * 0.5, co.r * 0.5)
end

-- Panel fills the (size-capped) area; everything is laid out relative to it.
function PortScreen:layout(vw, vh)
    local pw, ph, px, py = vw, vh, 0, 0
    local pad = math.max(3, math.floor(vw * 0.03))
    local titleH = math.floor(ph * 0.16)
    local btnH = math.floor(ph * 0.16)
    local bodyY = py + titleH + pad
    local bodyH = ph - titleH - btnH - pad * 3
    local portraitW = math.floor(pw * 0.36)
    return {
        pad = pad,
        panel   = { x = px, y = py, w = pw, h = ph },
        title   = { x = px, y = py, w = pw, h = titleH },
        portrait= { x = px + pad, y = bodyY, w = portraitW, h = bodyH },
        brief   = { x = px + portraitW + pad * 2, y = bodyY,
                    w = pw - portraitW - pad * 3, h = bodyH },
        seil    = { x = px + pw - math.floor(pw * 0.40) - pad, y = py + ph - btnH - pad,
                    w = math.floor(pw * 0.40), h = btnH },
        speaker = { x = px + pad, y = py + ph - btnH - pad, w = btnH, h = btnH },
    }
end

local function inRect(r, mx, my)
    return mx >= r.x and mx <= r.x + r.w and my >= r.y and my <= r.y + r.h
end

-- Input (screen px -> panel-local px)
function PortScreen:mousepressed(mx, my, button)
    if button ~= 1 or not self._L then return end
    mx = mx - self._ox
    my = my - self._oy
    if inRect(self._L.speaker, mx, my) then
        self:playVoice()
    elseif inRect(self._L.seil, mx, my) then
        self:confirm()
    elseif not inRect(self._L.panel, mx, my) then
        self:confirm()
    end
end

function PortScreen:keypressed(key)
    if key == "space" or key == "return" or key == "kpenter" then
        self:confirm()
    end
end

function PortScreen:confirm()
    local wasDeliver = (self.mode == "deliver")
    if self.mode == "offer" and self.offer then
        self.world.cargoSystem:tryPickup(self.world.boat, self.port)
        Assets.playSfx("horn")
        self.world:showToast("Ombord!")
    end
    Assets.stopDockMood()
    self.world.dock = nil

    -- After the HURRA screen, offer the next mission right away so the reward
    -- screen is never skipped and the child can keep sailing town to town.
    if wasDeliver then
        local off = self.world.cargoSystem:offerAt(self.port.id)
        if off and self.world.boat:hasRoom() then
            self.world:openDock(self.port)
        end
    end
end

local bevel = Retro.bevel

function PortScreen:draw()
    local sw, sh = love.graphics.getWidth(), love.graphics.getHeight()
    -- Panel size capped so it stays a tidy dialog (and the text readable) on big
    -- monitors. Drawn at full resolution; the retro feel comes from the bevels,
    -- dither and blocky icons.
    local pw = math.min(math.floor(sw * 0.80), 880)
    local ph = math.min(math.floor(sh * 0.82), 600)
    self._ox = math.floor((sw - pw) / 2)   -- centre the panel on screen
    self._oy = math.floor((sh - ph) / 2)
    self._L = self:layout(pw, ph)

    -- dim the screen behind the panel
    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.rectangle("fill", 0, 0, sw, sh)

    love.graphics.push()
    love.graphics.translate(self._ox, self._oy)
    self:drawRetro(self._L, pw, ph)
    love.graphics.pop()

    -- raining gold coins pour over the whole screen during a delivery
    if self.coins then
        for _, co in ipairs(self.coins) do self:drawCoin(co) end
    end
    love.graphics.setColor(1, 1, 1, 1)
end

function PortScreen:drawRetro(L, vw, vh)
    local th = self.theme
    local P = L.panel
    local t = math.max(1, math.floor(vh / 120))   -- bevel thickness

    -- double bevel: raised outer, sunken inner groove
    bevel(P.x, P.y, P.w, P.h, th.face, th.hi, th.lo, t, true)
    bevel(P.x + t * 2, P.y + t * 2, P.w - t * 4, P.h - t * 4, th.face, th.hi, th.lo, t, false)

    -- woodgrain dither + faint scanlines
    love.graphics.setColor(th.dither)
    for yy = P.y + t * 3, P.y + P.h - t * 3, 2 do
        love.graphics.rectangle("fill", P.x + t * 3, yy, P.w - t * 6, 1)
    end

    self:drawTitle(L, t)
    self:drawPortrait(L, t)
    self:drawBrief(L)
    self:drawButtons(L, t)
end

function PortScreen:drawTitle(L, t)
    local th, T = self.theme, L.title
    bevel(T.x + t * 2, T.y + t * 2, T.w - t * 4, T.h - t * 2, th.title, th.hi, th.lo, t, true)
    -- town flag swatch
    local fy = T.y + T.h * 0.5
    love.graphics.setColor(self.port.color)
    love.graphics.rectangle("fill", T.x + L.pad * 2, T.y + T.h * 0.28, T.h * 0.28, T.h * 0.45)
    -- town name (gold, with a hard shadow)
    local f = vfont(T.h * 0.42)
    love.graphics.setFont(f)
    local name = self.port.name
    local nx = T.x + T.w / 2 - f:getWidth(name) / 2
    local ny = T.y + T.h / 2 - f:getHeight() / 2
    love.graphics.setColor(0, 0, 0, 0.6); love.graphics.print(name, nx + 1, ny + 1)
    love.graphics.setColor(th.accent);    love.graphics.print(name, nx, ny)
end

-- Blocky dock backdrop behind the portrait (water, quay, crane, crates), kept
-- muted so the face stays the focus. Scary harbours get a colder version.
function PortScreen:drawDockBackdrop(x, y, w, h)
    local scary = (self.mood == "scary")
    local water = scary and {0.18, 0.20, 0.24} or {0.28, 0.42, 0.52}
    local wstk  = scary and {0.30, 0.32, 0.36} or {0.40, 0.54, 0.62}
    local quay  = scary and {0.20, 0.18, 0.20} or {0.34, 0.25, 0.16}
    local seam  = scary and {0.12, 0.11, 0.13} or {0.24, 0.17, 0.10}
    local edge  = scary and {0.30, 0.28, 0.30} or {0.44, 0.33, 0.20}
    local waterH = h * 0.58

    love.graphics.setColor(water)
    love.graphics.rectangle("fill", x, y, w, waterH)
    love.graphics.setColor(wstk[1], wstk[2], wstk[3], 0.55)        -- water glints
    for i = 1, 3 do love.graphics.rectangle("fill", x, y + waterH * (0.25 + i * 0.18), w, 2) end

    -- crane silhouette in the back
    love.graphics.setColor(0.15, 0.15, 0.17, 0.85)
    local mx = x + w * 0.74
    love.graphics.rectangle("fill", mx, y + waterH * 0.12, 5, waterH * 0.78)        -- mast
    love.graphics.rectangle("fill", mx - w * 0.22, y + waterH * 0.12, w * 0.27, 5)  -- jib
    love.graphics.rectangle("fill", mx - w * 0.20, y + waterH * 0.17, 3, waterH * 0.18) -- cable

    -- planked quay
    love.graphics.setColor(quay)
    love.graphics.rectangle("fill", x, y + waterH, w, h - waterH)
    love.graphics.setColor(edge)
    love.graphics.rectangle("fill", x, y + waterH - 3, w, 4)                         -- quay edge
    love.graphics.setColor(seam)
    for i = 1, 4 do love.graphics.rectangle("fill", x, y + waterH + (h - waterH) * (i / 5), w, 2) end

    -- a few stacked crates (the loading area), in muted town colours
    local cr = config.BUILDING_COLORS
    local s = w * 0.13
    local function crate(cx, cy, col)
        love.graphics.setColor(col[1] * 0.8, col[2] * 0.8, col[3] * 0.8)
        love.graphics.rectangle("fill", cx, cy, s, s)
        love.graphics.setColor(0, 0, 0, 0.25)
        love.graphics.rectangle("line", cx, cy, s, s)
    end
    crate(x + w * 0.05, y + h - s, cr[1])
    crate(x + w * 0.05 + s * 0.55, y + h - s * 2, cr[3])
    crate(x + w * 0.80, y + h - s, cr[4])
    love.graphics.setColor(1, 1, 1)
end

function PortScreen:drawPortrait(L, t)
    local th, R = self.theme, L.portrait
    bevel(R.x, R.y, R.w, R.h, th.well, th.hi, th.lo, t, false)   -- sunken frame
    local ix, iy, iw, ih = R.x + t * 2, R.y + t * 2, R.w - t * 4, R.h - t * 4
    self:drawDockBackdrop(ix, iy, iw, ih)

    -- port-specific portrait if present, else the shared default harbour master
    local img = Assets.portPortrait(self.port.id) or Assets.portPortrait("default")
    if img then
        local s = math.min(iw / img:getWidth(), ih / img:getHeight())
        love.graphics.setColor(1, 1, 1)
        love.graphics.draw(img, ix + iw / 2, iy + ih / 2, 0, s, s,
            img:getWidth() / 2, img:getHeight() / 2)
    else
        self:drawHarborMaster(ix, iy, iw, ih)
    end

    -- name plate under the portrait; "Havnesjef <name>" if the town data names them
    local f = vfont(R.h * 0.075)
    love.graphics.setFont(f)
    local master = self.port.def and self.port.def.master
    local label = master and ("Havnesjef " .. master) or "Havnesjef"
    love.graphics.setColor(0, 0, 0, 0.5)
    love.graphics.print(label, R.x + R.w / 2 - f:getWidth(label) / 2 + 1, R.y + R.h - f:getHeight() - 3)
    love.graphics.setColor(th.accent)
    love.graphics.print(label, R.x + R.w / 2 - f:getWidth(label) / 2, R.y + R.h - f:getHeight() - 4)
end

-- Pixel-art placeholder harbour master, used until a real portrait is dropped in.
function PortScreen:drawHarborMaster(x, y, w, h)
    local u = w / 12                       -- pixel unit
    local function px(cx, cy, cw, ch, col)
        love.graphics.setColor(col)
        love.graphics.rectangle("fill", x + cx * u, y + cy * u, cw * u, ch * u)
    end
    if self.mood == "scary" then
        px(2, 11, 8, 3, {0.10, 0.10, 0.13})            -- shoulders (dark cloak)
        px(3, 4, 6, 7, {0.07, 0.07, 0.10})             -- hood
        px(4, 6, 4, 4, {0.18, 0.16, 0.18})             -- shadowed face
        px(4.5, 7.5, 1, 1, {0.95, 0.30, 0.25})         -- glowing eyes
        px(6.5, 7.5, 1, 1, {0.95, 0.30, 0.25})
    else
        px(2, 11, 8, 3, {0.20, 0.30, 0.52})            -- navy jacket
        px(3, 10, 6, 2, {0.85, 0.84, 0.80})            -- collar
        px(3.5, 4, 5, 6, {0.85, 0.68, 0.52})           -- face
        px(3.5, 2.5, 5, 2, {0.90, 0.88, 0.84})         -- cap
        px(3, 4, 6, 1, {0.20, 0.22, 0.30})             -- cap brim
        px(4, 6, 1, 1, {0.15, 0.12, 0.10})             -- eyes
        px(7, 6, 1, 1, {0.15, 0.12, 0.10})
        px(3.5, 8, 5, 2, {0.80, 0.80, 0.80})           -- big white beard
    end
end

function PortScreen:drawBrief(L)
    local th, B = self.theme, L.brief
    local cx = B.x + B.w / 2
    local fh = vfont(B.h * 0.14)
    local fb = vfont(B.h * 0.11)

    if self.mode == "offer" and self.offer then
        local o = self.offer
        love.graphics.setFont(fh)
        local head = "Oppdrag, kaptein!"
        love.graphics.setColor(th.accent)
        love.graphics.print(head, cx - fh:getWidth(head) / 2, B.y + B.h * 0.04)

        self:drawIconRow(o.icon, o.count, cx, B.y + B.h * 0.40, B.h * 0.16)

        love.graphics.setFont(fb)
        local verb = (o.mode == "passengers") and "Ta" or "Frakt"
        local noun = (o.mode == "passengers")
            and (o.count .. " passasjerer") or (o.count .. " " .. string.lower(o.type))
        local l1 = verb .. " " .. noun
        love.graphics.setColor(th.text)
        love.graphics.print(l1, cx - fb:getWidth(l1) / 2, B.y + B.h * 0.62)
        -- destination, in its town colour, with a flag
        local l2 = "til " .. o.toName
        local w2 = fb:getWidth(l2)
        love.graphics.setColor(o.color or th.text)
        love.graphics.print(l2, cx - w2 / 2, B.y + B.h * 0.78)
        love.graphics.rectangle("fill", cx - w2 / 2 - fb:getHeight() * 0.9,
            B.y + B.h * 0.78 + fb:getHeight() * 0.15, fb:getHeight() * 0.5, fb:getHeight() * 0.7)

    elseif self.mode == "busy" then
        love.graphics.setFont(fh)
        local t1 = "Feil havn!"
        love.graphics.setColor(th.accent)
        love.graphics.print(t1, cx - fh:getWidth(t1) / 2, B.y + B.h * 0.06)
        local m = self.mission
        if m then
            self:drawIconRow(m.icon, m.count, cx, B.y + B.h * 0.42, B.h * 0.16)
            love.graphics.setFont(fb)
            local l1 = "Du har allerede oppdrag!"
            love.graphics.setColor(th.text)
            love.graphics.print(l1, cx - fb:getWidth(l1) / 2, B.y + B.h * 0.62)
            local l2 = "Reis til " .. m.toName .. "!"
            love.graphics.setColor(m.color or th.text)
            love.graphics.print(l2, cx - fb:getWidth(l2) / 2, B.y + B.h * 0.78)
        else
            love.graphics.setFont(fb)
            local l1 = "Kom tilbake senere!"
            love.graphics.setColor(th.text)
            love.graphics.print(l1, cx - fb:getWidth(l1) / 2, B.y + B.h * 0.5)
        end

    elseif self.mode == "deliver" then
        self:drawIconRow("smile", math.max(1, self.delivered), cx, B.y + B.h * 0.16, B.h * 0.16)
        -- big bouncing "HURRA!" so a toddler instantly gets that this is GOOD
        local pulse = 1 + 0.10 * math.sin(self.t * 9)
        local hop = math.abs(math.sin(self.t * 4)) * B.h * 0.05
        love.graphics.setFont(fh)
        local t1 = "HURRA!"
        love.graphics.push()
        love.graphics.translate(cx, B.y + B.h * 0.46 - hop)
        love.graphics.scale(pulse, pulse)
        love.graphics.setColor(0, 0, 0, 0.3)
        love.graphics.print(t1, -fh:getWidth(t1) / 2 + 2, -fh:getHeight() / 2 + 2)
        love.graphics.setColor(th.accent)
        love.graphics.print(t1, -fh:getWidth(t1) / 2, -fh:getHeight() / 2)
        love.graphics.pop()
        love.graphics.setFont(fb)
        local t2 = "+" .. self.earned .. " gull"
        love.graphics.setColor(config.colors.gold)
        love.graphics.print(t2, cx - fb:getWidth(t2) / 2, B.y + B.h * 0.68)
    else
        love.graphics.setFont(fh)
        local t = "Velkommen i havn!"
        love.graphics.setColor(th.text)
        love.graphics.print(t, cx - fh:getWidth(t) / 2, B.y + B.h / 2 - fh:getHeight() / 2)
    end
end

function PortScreen:drawIconRow(kind, count, cx, y, s)
    count = math.min(count, 6)
    local gap = s * 1.5
    local total = (count - 1) * gap
    for i = 1, count do
        self:drawIcon(kind, cx - total / 2 + (i - 1) * gap, y, s)
    end
end

function PortScreen:drawIcon(kind, x, y, s)
    if kind == "passenger" or kind == "smile" then
        love.graphics.setColor(0.95, 0.80, 0.55)
        love.graphics.rectangle("fill", x - s * 0.22, y - s * 0.55, s * 0.44, s * 0.44)  -- head
        love.graphics.setColor(0.30, 0.45, 0.70)
        love.graphics.rectangle("fill", x - s * 0.40, y - s * 0.10, s * 0.80, s * 0.55)  -- body
    elseif kind == "fish" then
        love.graphics.setColor(0.55, 0.68, 0.82)
        love.graphics.rectangle("fill", x - s * 0.45, y - s * 0.22, s * 0.7, s * 0.44)   -- body
        love.graphics.polygon("fill", x + s * 0.25, y, x + s * 0.5, y - s * 0.3, x + s * 0.5, y + s * 0.3)
        love.graphics.setColor(0.12, 0.14, 0.18)
        love.graphics.rectangle("fill", x - s * 0.32, y - s * 0.08, s * 0.12, s * 0.12)  -- eye
    elseif kind == "apple" then
        love.graphics.setColor(0.80, 0.30, 0.25)
        love.graphics.rectangle("fill", x - s * 0.35, y - s * 0.35, s * 0.7, s * 0.7)
    else
        love.graphics.setColor(0.60, 0.45, 0.28)
        love.graphics.rectangle("fill", x - s * 0.4, y - s * 0.4, s * 0.8, s * 0.8)
        love.graphics.setColor(0.40, 0.30, 0.20)
        love.graphics.rectangle("fill", x - s * 0.4, y - s * 0.05, s * 0.8, s * 0.1)
    end
end

function PortScreen:drawButtons(L, t)
    local th = self.theme
    local mx, my = love.mouse.getPosition()
    mx, my = mx - self._ox, my - self._oy

    -- Seil! button
    local b = L.seil
    local hover = inRect(b, mx, my)
    bevel(b.x, b.y, b.w, b.h, hover and th.btnhi or th.btn, th.btnhi, th.btnlo, t, true)
    local f = vfont(b.h * 0.42)
    love.graphics.setFont(f)
    local label = "Seil!"
    love.graphics.setColor(0, 0, 0, 0.5)
    love.graphics.print(label, b.x + b.w / 2 - f:getWidth(label) / 2 + 1, b.y + b.h / 2 - f:getHeight() / 2 + 1)
    love.graphics.setColor(1, 1, 1)
    love.graphics.print(label, b.x + b.w / 2 - f:getWidth(label) / 2, b.y + b.h / 2 - f:getHeight() / 2)

    -- Speaker / replay button (so a non-reader can hear the order again)
    local s = L.speaker
    bevel(s.x, s.y, s.w, s.h, th.face, th.hi, th.lo, t, true)
    local cxp, cyp = s.x + s.w / 2, s.y + s.h / 2
    local u = s.h * 0.12
    love.graphics.setColor(th.accent)
    love.graphics.rectangle("fill", cxp - u * 2, cyp - u, u * 1.4, u * 2)        -- speaker box
    love.graphics.polygon("fill", cxp - u * 0.6, cyp - u, cxp + u, cyp - u * 2,
        cxp + u, cyp + u * 2, cxp - u * 0.6, cyp + u)                            -- cone
    love.graphics.rectangle("fill", cxp + u * 1.6, cyp - u * 0.4, u * 0.5, u * 0.8)  -- sound wave
end

return PortScreen
