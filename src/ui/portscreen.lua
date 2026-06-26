-- src/ui/portscreen.lua
-- The docking screen, styled like an early-90s strategy briefing: a beveled wood
-- panel with the harbour master's portrait, dither + scanlines, and a per-harbour
-- mood (cosy or scary, each with its own theme and music). The master gives the
-- order: frakt fisk, ta passasjerer, etc.
-- An overlay owned by the world scene. Modes: offer / busy / deliver / visit.

local config = require("src.config")
local Assets = require("src.assets")
local Retro  = require("src.ui.retro")
local Icons  = require("src.ui.icons")
local HarborMark = require("src.ui.harbormark")

local PortScreen = {}
PortScreen.__index = PortScreen

-- The Butikk's own look: a weathered, warm-lit pirate trading post (dark wood +
-- lantern glow), regardless of the harbour's cosy/scary mood.
local STORE = {
    wood   = {0.26, 0.17, 0.10}, woodhi = {0.42, 0.29, 0.16}, woodlo = {0.10, 0.06, 0.03},
    deep   = {0.16, 0.10, 0.06},
    lamp   = {1.00, 0.82, 0.42},
    text   = {0.96, 0.88, 0.66}, accent = {0.96, 0.74, 0.30}, dim = {0.55, 0.45, 0.30},
    crate  = {0.46, 0.33, 0.18}, cratehi = {0.62, 0.46, 0.26}, cratelo = {0.20, 0.13, 0.07},
    buy    = {0.30, 0.50, 0.26}, buyhi  = {0.46, 0.66, 0.36}, buylo  = {0.15, 0.27, 0.12},
    red    = {0.86, 0.36, 0.28},
}

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
    self.mapGiven  = info.mapGiven          -- harbourmaster handed over a treasure map
    self.mood  = port.def.mood or "cosy"
    self.theme = THEMES[self.mood] or THEMES.cosy
    self.t = 0
    self.shopOpen = false                 -- the Butikk is a full-screen sub-view
    self.shop = world.game.data.shop      -- the buyable catalog (data-driven)
    self.buyFlash = 0                     -- "Kjøpt!" confirmation timer
    self.storeMsg = nil                   -- transient store line, e.g. "Spar 30 til!"
    Assets.startDockMood(self.mood)
    self:playVoice()
    if self.mode == "deliver" then           -- raining gold coins
        self.coins = {}
        for i = 1, 70 do self.coins[i] = self:newCoin() end
        self.clinkT = 0
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
    if self.mode == "findfirst" then               -- turned away: "find the treasure first!"
        if not Assets.playNamedVoice("finn_skatten_forst") then Assets.playSfx("bump") end
        return
    end
    if self.mode == "offer" and Assets.playNamedVoice("oppdrag") then return end
    if self.mode == "busy" and Assets.playNamedVoice("feil_havn") then return end
    if Assets.playNamedVoice("dock_" .. self.port.id) then return end
    Assets.playSfx("horn")
end

local function inRect(r, mx, my)
    return mx >= r.x and mx <= r.x + r.w and my >= r.y and my <= r.y + r.h
end

function PortScreen:update(dt)
    self.t = self.t + dt
    if self.buyFlash > 0 then self.buyFlash = self.buyFlash - dt end
    if self.storeMsg then
        self.storeMsg.t = self.storeMsg.t - dt
        if self.storeMsg.t <= 0 then self.storeMsg = nil end
    end

    if self.coins then
        self.clinkT = (self.clinkT or 0) - dt
        for _, co in ipairs(self.coins) do
            if not co.rest then
                co.vy = co.vy + 900 * dt               -- gravity
                co.x = co.x + co.vx * dt
                co.y = co.y + co.vy * dt
                co.spin = co.spin + co.spinsp * dt
                if co.y >= co.floor then
                    co.y = co.floor
                    if self.clinkT <= 0 then           -- clink-klank as it hits the pile
                        self.clinkT = 0.04 + love.math.random() * 0.07
                        Assets.playPitched("coin_clink", 0.5, 0.7 + love.math.random() * 0.8)
                    end
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
    -- Widen the primary button when it carries the longer "Finn skatten!" label.
    local seilW = math.floor(pw * (self.mapGiven and 0.40 or 0.30))
    local butW  = math.floor(pw * 0.28)
    local rowY  = py + ph - btnH - pad
    return {
        pad = pad,
        panel   = { x = px, y = py, w = pw, h = ph },
        title   = { x = px, y = py, w = pw, h = titleH },
        portrait= { x = px + pad, y = bodyY, w = portraitW, h = bodyH },
        brief   = { x = px + portraitW + pad * 2, y = bodyY,
                    w = pw - portraitW - pad * 3, h = bodyH },
        seil    = { x = px + pw - seilW - pad, y = rowY, w = seilW, h = btnH },
        butikk  = { x = px + pw - seilW - pad - butW - pad, y = rowY, w = butW, h = btnH },
    }
end

-- Input (screen px -> panel-local px)
function PortScreen:mousepressed(mx, my, button)
    if button ~= 1 or not self._ox then return end
    mx = mx - self._ox
    my = my - self._oy

    -- Inside the store: click a crate to buy it, or Tilbake / Seil.
    if self.shopOpen then
        if self._crates then
            for _, c in ipairs(self._crates) do
                if inRect(c, mx, my) then self:tryBuy(c.item); return end
            end
        end
        if self._backRect and inRect(self._backRect, mx, my) then
            self.shopOpen = false                      -- back to the harbour-master briefing
        elseif self._seilRect and inRect(self._seilRect, mx, my) then
            self:confirm()
        end
        return
    end

    -- Focused screens (map handoff / turned-away / wrong harbour): no Butikk, the
    -- only thing to do is go -- any click sets sail.
    if self.mapGiven or self.mode == "findfirst" or self.mode == "busy" then
        self:confirm(); return
    end

    if not self._L then return end
    if inRect(self._L.butikk, mx, my) then
        self.shopOpen = true                       -- open the store...
        Assets.playNamedVoice("butikk")            -- ...with "Vil du kjøpe noe?"
    elseif inRect(self._L.seil, mx, my) then
        self:confirm()
    elseif not inRect(self._L.panel, mx, my) then
        self:confirm()
    end
end

function PortScreen:keypressed(key)
    if key == "space" or key == "return" or key == "kpenter" then
        if self.shopOpen then
            self.shopOpen = false                  -- back out of the store
        else
            self:confirm()
        end
    end
end

-- The buy button is always clickable. Clicking it:
--   already owned -> a voice "du har allerede en kanon" (so he learns he's set)
--   can afford    -> spend the gold, see it go down, happy fanfare
--   too poor      -> a gentle nudge (the "Spar X til!" maths is on screen)
function PortScreen:tryBuy(item)
    local game = self.world.game
    if not item then return end

    local ok
    if item.food then
        ok = game:buyFood(item.id, item.price)        -- food: buy again and again
    elseif game:owns(item.id) then
        if not Assets.playNamedVoice("har_" .. item.id) then  -- e.g. har_kanon.ogg
            Assets.playSfx("bump")
        end
        return
    else
        ok = game:buyUpgrade(item.id, item.price)     -- upgrade: one-time
    end

    if ok then
        self.buyFlash, self.buyItem = 1.4, item
        self.storeMsg = nil
        Assets.playSfx("coin")
        Assets.playSfx("deliver")              -- happy little fanfare
        if item.food then
            Assets.playNamedVoice("kjopt_mat")  -- my kid: "Du har kjøpt litt mat!"
        end
        self.world:showToast("Kjøpt: " .. item.name .. "!")
    else
        -- can't afford -> show the subtraction the store exists to teach
        local need = item.price - game.state.coins
        self.storeMsg = { text = "Spar " .. need .. " til!", t = 2.5 }
        Assets.playSfx("bump")
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
    -- screen is never skipped and the child can keep sailing town to town -- BUT
    -- if this delivery earned a treasure map, skip the new oppdrag and go straight
    -- into the hunt (the "Finn skatten!" card pops once this screen closes).
    if wasDeliver and not self.world.pendingMapReveal then
        local off = self.world.cargoSystem:offerAt(self.port.id)
        if off and self.world.boat:hasRoom() then
            self.world:openDock(self.port)
        end
    end
end

local bevel = Retro.bevel

function PortScreen:draw()
    local sw, sh = love.graphics.getWidth(), love.graphics.getHeight()

    -- The Butikk is its own bigger, full-panel screen.
    if self.shopOpen then self:drawStoreScreen(sw, sh); return end

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
    self:drawBrief(L, t)
    self:drawButtons(L, t)
end

function PortScreen:drawTitle(L, t)
    local th, T = self.theme, L.title
    bevel(T.x + t * 2, T.y + t * 2, T.w - t * 4, T.h - t * 2, th.title, th.hi, th.lo, t, true)
    -- town harbour badge (two gabled houses in the town colour)
    HarborMark.draw(T.x + L.pad * 2, T.y + T.h * 0.25, T.h * 0.58, T.h * 0.5, self.port.color)
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

function PortScreen:drawBrief(L, t)
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

        self:drawIconRow(o.icon, o.count, cx, B.y + B.h * 0.40, B.h * 0.16, o.figures)

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
        local fH = fb:getHeight()
        HarborMark.draw(cx - w2 / 2 - fH * 1.15, B.y + B.h * 0.78 + fH * 0.1,
            fH * 0.85, fH * 0.78, o.color or th.text)

    elseif self.mode == "busy" then
        love.graphics.setFont(fh)
        local t1 = "Feil havn!"
        love.graphics.setColor(th.accent)
        love.graphics.print(t1, cx - fh:getWidth(t1) / 2, B.y + B.h * 0.06)
        local m = self.mission
        if m then
            self:drawIconRow(m.icon, m.count, cx, B.y + B.h * 0.42, B.h * 0.16, m.figures)
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

    elseif self.mode == "deliver" and self.mapGiven then
        self:drawMapHandoff(B, cx, fh, fb, th)        -- epic treasure-map moment

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
    elseif self.mode == "findfirst" then
        -- turned away: the harbourmaster won't give a new oppdrag until the chest
        -- is found. A treasure chest + "Finn skatten først!"
        Icons.draw("chest", cx, B.y + B.h * 0.34, B.h * 0.36)
        local t1 = "Finn skatten først!"
        local f = (fh:getWidth(t1) <= B.w) and fh or fb
        love.graphics.setFont(f)
        local hop = math.abs(math.sin(self.t * 4)) * B.h * 0.03
        love.graphics.setColor(0, 0, 0, 0.4)
        love.graphics.print(t1, cx - f:getWidth(t1) / 2 + 2, B.y + B.h * 0.66 - hop + 2)
        love.graphics.setColor(th.accent)
        love.graphics.print(t1, cx - f:getWidth(t1) / 2, B.y + B.h * 0.66 - hop)

    else
        love.graphics.setFont(fh)
        local t = "Velkommen i havn!"
        love.graphics.setColor(th.text)
        love.graphics.print(t, cx - fh:getWidth(t) / 2, B.y + B.h / 2 - fh:getHeight() / 2)
    end
end

-- The harbourmaster presents a TREASURE MAP: a golden glow, the parchment map
-- (assets/ui/treasuremap.png) tilting gently, a bouncing "SKATTEKART!" and a few
-- sparkles -- the big, epic moment, with the gold reward small underneath.
function PortScreen:drawMapHandoff(B, cx, fh, fb, th)
    local t = self.t
    local gcx, gcy = cx, B.y + B.h * 0.50

    -- radiant golden glow behind the map
    for i = 6, 1, -1 do
        love.graphics.setColor(0.96, 0.80, 0.32, 0.05 * i)
        love.graphics.circle("fill", gcx, gcy, B.h * (0.12 + i * 0.055))
    end

    -- bouncing title
    love.graphics.setFont(fh)
    local title = "Skattekart!"
    local hop = math.abs(math.sin(t * 4)) * B.h * 0.05
    love.graphics.setColor(0, 0, 0, 0.4)
    love.graphics.print(title, cx - fh:getWidth(title) / 2 + 2, B.y + B.h * 0.02 - hop + 2)
    love.graphics.setColor(th.accent)
    love.graphics.print(title, cx - fh:getWidth(title) / 2, B.y + B.h * 0.02 - hop)

    -- the parchment map, gently swaying (chest icon fallback if the art is absent)
    local img = Assets.image("ui/treasuremap.png")
    if img then
        local mh = B.h * 0.52
        local s = mh / img:getHeight()
        love.graphics.setColor(0, 0, 0, 0.25)
        love.graphics.draw(img, gcx + 4, gcy + 5, math.sin(t * 1.5) * 0.04, s, s, img:getWidth() / 2, img:getHeight() / 2)
        love.graphics.setColor(1, 1, 1)
        love.graphics.draw(img, gcx, gcy, math.sin(t * 1.5) * 0.04, s, s, img:getWidth() / 2, img:getHeight() / 2)
    else
        Icons.draw("chest", gcx, gcy, B.h * 0.4)
    end

    -- sparkles twinkling around it
    for k = 1, 7 do
        local sp = (t * 1.2 + k * 0.43) % 1
        local rr = 1 - sp
        local a = k * 1.7
        local sx = gcx + math.cos(a) * B.h * 0.34
        local sy = gcy + math.sin(a) * B.h * 0.34 * 0.7
        love.graphics.setColor(1, 0.96, 0.62, rr)
        love.graphics.circle("fill", sx, sy, 1.5 + 3 * rr)
    end

    -- the gold reward, small, underneath
    love.graphics.setFont(fb)
    local g = "+" .. self.earned .. " gull"
    love.graphics.setColor(config.colors.gold)
    love.graphics.print(g, cx - fb:getWidth(g) / 2, B.y + B.h - fb:getHeight() - 2)
    love.graphics.setColor(1, 1, 1)
end

-- A beveled, centered-label button. `primary` picks the green action palette
-- (Seil!/Kjøp); otherwise the wooden secondary one (Butikk/Tilbake).
function PortScreen:labelButton(b, label, t, primary)
    local th = self.theme
    local mx, my = love.mouse.getPosition()
    mx, my = mx - self._ox, my - self._oy
    local hover = inRect(b, mx, my)
    local face = primary and (hover and th.btnhi or th.btn) or (hover and th.hi or th.face)
    bevel(b.x, b.y, b.w, b.h, face, primary and th.btnhi or th.hi,
          primary and th.btnlo or th.lo, t, true)
    local f = vfont(b.h * 0.40)
    love.graphics.setFont(f)
    local lx = b.x + b.w / 2 - f:getWidth(label) / 2
    local ly = b.y + b.h / 2 - f:getHeight() / 2
    love.graphics.setColor(0, 0, 0, 0.5); love.graphics.print(label, lx + 1, ly + 1)
    love.graphics.setColor(1, 1, 1);      love.graphics.print(label, lx, ly)
end

-- ===================== The Butikk (store) =====================
-- A bigger, full-panel rusty pirate trading post: dark weathered wood lit by
-- lanterns, a grid of wooden-crate goods. Click a crate to buy. Owned goods are
-- crossed out. The maths (your gold, prices, "Spar X til!") stays front-and-centre.

function PortScreen:drawStoreScreen(sw, sh)
    local pw = math.min(math.floor(sw * 0.90), 1040)
    local ph = math.min(math.floor(sh * 0.88), 740)
    self._ox = math.floor((sw - pw) / 2)
    self._oy = math.floor((sh - ph) / 2)

    love.graphics.setColor(0, 0, 0, 0.62)           -- dim the world behind
    love.graphics.rectangle("fill", 0, 0, sw, sh)

    love.graphics.push()
    love.graphics.translate(self._ox, self._oy)
    self:drawStorePanel(pw, ph)
    love.graphics.pop()
    love.graphics.setColor(1, 1, 1)
end

-- A small wall lantern casting a warm pool of light.
local function lantern(lx, ly, r)
    love.graphics.setColor(0.14, 0.09, 0.05)
    love.graphics.rectangle("fill", lx - 1, ly - r * 1.7, 2, r * 0.9)        -- bracket
    love.graphics.setColor(0.24, 0.17, 0.10)
    love.graphics.rectangle("fill", lx - r * 0.5, ly - r * 0.8, r, r * 1.6)  -- housing
    love.graphics.setColor(STORE.lamp[1], STORE.lamp[2], STORE.lamp[3], 0.95)
    love.graphics.rectangle("fill", lx - r * 0.3, ly - r * 0.5, r * 0.6, r)  -- flame glass
end

-- A weathered barrel of goods.
local function barrel(bx, by, w, h)
    love.graphics.setColor(0.34, 0.22, 0.12)
    love.graphics.rectangle("fill", bx, by, w, h)
    love.graphics.setColor(0.22, 0.14, 0.08)                                 -- side shading
    love.graphics.rectangle("fill", bx, by, w * 0.18, h)
    love.graphics.rectangle("fill", bx + w * 0.82, by, w * 0.18, h)
    love.graphics.setColor(0.50, 0.50, 0.55)                                 -- metal hoops
    love.graphics.rectangle("fill", bx, by + h * 0.16, w, h * 0.10)
    love.graphics.rectangle("fill", bx, by + h * 0.72, w, h * 0.10)
end

function PortScreen:drawStorePanel(pw, ph)
    local s = STORE
    local game = self.world.game
    local t = math.max(2, math.floor(ph / 110))
    local mx, my = love.mouse.getPosition()
    mx, my = mx - self._ox, my - self._oy

    -- panel: raised wood slab + sunken inner well
    bevel(0, 0, pw, ph, s.wood, s.woodhi, s.woodlo, t, true)
    bevel(t * 2, t * 2, pw - t * 4, ph - t * 4, s.deep, s.woodhi, s.woodlo, t, false)
    local ix, iy, iw, ih = t * 3, t * 3, pw - t * 6, ph - t * 6

    -- vertical woodgrain planks + faint scanlines
    love.graphics.setColor(0, 0, 0, 0.13)
    for xx = ix, ix + iw, 26 do love.graphics.rectangle("fill", xx, iy, 1, ih) end
    for yy = iy, iy + ih, 3 do love.graphics.rectangle("fill", ix, yy, iw, 1) end

    -- warm lantern glow in the top corners (additive pools)
    love.graphics.setBlendMode("add")
    love.graphics.setColor(s.lamp[1], s.lamp[2], s.lamp[3], 0.10)
    love.graphics.circle("fill", ix + iw * 0.10, iy + ih * 0.10, ih * 0.30)
    love.graphics.circle("fill", ix + iw * 0.90, iy + ih * 0.10, ih * 0.30)
    love.graphics.setBlendMode("alpha")
    lantern(ix + iw * 0.07, iy + ih * 0.12, ih * 0.045)
    lantern(ix + iw * 0.93, iy + ih * 0.12, ih * 0.045)

    -- hanging sign: BUTIKK
    local fT = vfont(ih * 0.085)
    love.graphics.setFont(fT)
    local title = "BUTIKK"
    local tw = fT:getWidth(title)
    local plY = iy + ih * 0.03
    bevel(pw / 2 - tw / 2 - 20, plY, tw + 40, fT:getHeight() + 14, s.crate, s.cratehi, s.cratelo, t, true)
    love.graphics.setColor(0, 0, 0, 0.5); love.graphics.print(title, pw / 2 - tw / 2 + 1, plY + 8)
    love.graphics.setColor(s.accent);    love.graphics.print(title, pw / 2 - tw / 2, plY + 7)

    -- your gold, centered under the sign (a coin + the running total)
    local fG = vfont(ih * 0.052)
    love.graphics.setFont(fG)
    local gold = "Gull: " .. game.state.coins
    local gw = fG:getWidth(gold)
    local gy = iy + ih * 0.155
    local cr = ih * 0.03
    love.graphics.setColor(0.6, 0.45, 0.1); love.graphics.circle("fill", pw / 2 - gw / 2 - cr * 1.6, gy + fG:getHeight() / 2, cr + 1)
    love.graphics.setColor(config.colors.gold); love.graphics.circle("fill", pw / 2 - gw / 2 - cr * 1.6, gy + fG:getHeight() / 2, cr)
    love.graphics.setColor(config.colors.gold); love.graphics.print(gold, pw / 2 - gw / 2, gy)

    -- the goods grid (3 columns)
    local cols = 3
    local n = #self.shop
    local rows = math.max(1, math.ceil(n / cols))
    local gridX, gridY = ix + iw * 0.04, iy + ih * 0.23
    local gridW, gridH = iw * 0.92, ih * 0.56
    local gap, rowGap = iw * 0.025, ih * 0.035
    local cw = (gridW - (cols - 1) * gap) / cols
    local ch = math.min((gridH - (rows - 1) * rowGap) / rows, cw * 0.92)
    self._crates = {}
    for i = 1, n do
        local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
        local rect = { x = gridX + col * (cw + gap), y = gridY + row * (ch + rowGap),
                       w = cw, h = ch, item = self.shop[i] }
        self._crates[i] = rect
        self:drawCrate(rect, mx, my, t)
    end

    -- bottom bar: barrels flanking the Tilbake / Seil! buttons
    local barH = ih * 0.11
    local barY = iy + ih - barH - ih * 0.02
    local bw, gapb = iw * 0.26, iw * 0.06
    local totalB = bw * 2 + gapb
    self._backRect = { x = ix + iw / 2 - totalB / 2, y = barY, w = bw, h = barH }
    self._seilRect = { x = ix + iw / 2 + gapb / 2,   y = barY, w = bw, h = barH }
    barrel(ix + iw * 0.02, barY + barH * 0.05, iw * 0.08, barH * 0.95)
    barrel(ix + iw * 0.90, barY + barH * 0.05, iw * 0.08, barH * 0.95)

    -- transient line just above the bar: "Spar X til!" or "Kjøpt!"
    local fM = vfont(ih * 0.058)
    love.graphics.setFont(fM)
    if self.buyFlash > 0 then
        love.graphics.setColor(s.buyhi[1], s.buyhi[2], s.buyhi[3], math.min(1, self.buyFlash))
        love.graphics.print("Kjøpt!", pw / 2 - fM:getWidth("Kjøpt!") / 2, barY - ih * 0.085)
    elseif self.storeMsg then
        love.graphics.setColor(s.accent)
        love.graphics.print(self.storeMsg.text, pw / 2 - fM:getWidth(self.storeMsg.text) / 2, barY - ih * 0.085)
    end

    self:storeButton(self._backRect, "Tilbake", t, false, mx, my)
    self:storeButton(self._seilRect, "Seil!", t, true, mx, my)
end

-- One goods crate: icon, name, price (with coin). Owned -> crossed out;
-- unaffordable -> dimmed with a red price; affordable -> brightens on hover.
function PortScreen:drawCrate(r, mx, my, t)
    local s = STORE
    local game = self.world.game
    local item = r.item
    local owned  = (not item.food) and game:owns(item.id)   -- food is never "owned"
    local stock  = item.food and game:foodCount(item.id) or 0
    local afford = game.state.coins >= item.price
    local hover  = inRect(r, mx, my)

    local face = (hover and not owned) and s.cratehi or s.crate
    bevel(r.x, r.y, r.w, r.h, face, s.cratehi, s.cratelo, t, true)
    bevel(r.x + t * 2, r.y + t * 2, r.w - t * 4, r.h - t * 4, s.wood, s.cratehi, s.cratelo,
          math.max(1, math.floor(t * 0.6)), false)

    Icons.draw(item.icon, r.x + r.w / 2, r.y + r.h * 0.34, r.h * 0.34)

    local fn = vfont(r.h * 0.13)
    love.graphics.setFont(fn)
    love.graphics.setColor(s.text)
    love.graphics.print(item.name, r.x + r.w / 2 - fn:getWidth(item.name) / 2, r.y + r.h * 0.60)

    local fp = vfont(r.h * 0.16)
    love.graphics.setFont(fp)
    local pr = tostring(item.price)
    local prw = fp:getWidth(pr)
    local py = r.y + r.h * 0.76
    local cr = r.h * 0.075
    local coinX = r.x + r.w / 2 - prw / 2 - cr * 1.5
    love.graphics.setColor(0.6, 0.45, 0.1); love.graphics.circle("fill", coinX, py + fp:getHeight() / 2, cr + 1)
    love.graphics.setColor(config.colors.gold); love.graphics.circle("fill", coinX, py + fp:getHeight() / 2, cr)
    love.graphics.setColor(afford and config.colors.gold or s.red)
    love.graphics.print(pr, r.x + r.w / 2 - prw / 2, py)

    -- food stock badge ("xN") in the top-right corner, when you have some aboard
    if item.food and stock > 0 then
        local fb = vfont(r.h * 0.15)
        love.graphics.setFont(fb)
        local lbl = "x" .. stock
        local bx = r.x + r.w - fb:getWidth(lbl) - t * 3
        love.graphics.setColor(0, 0, 0, 0.5); love.graphics.print(lbl, bx + 1, r.y + t * 3 + 1)
        love.graphics.setColor(s.text);       love.graphics.print(lbl, bx, r.y + t * 3)
    end

    if owned then
        love.graphics.setColor(0, 0, 0, 0.34); love.graphics.rectangle("fill", r.x, r.y, r.w, r.h)
        love.graphics.setColor(s.red); love.graphics.setLineWidth(math.max(3, t * 1.5))
        love.graphics.line(r.x + t * 3, r.y + t * 3, r.x + r.w - t * 3, r.y + r.h - t * 3)
        love.graphics.line(r.x + r.w - t * 3, r.y + t * 3, r.x + t * 3, r.y + r.h - t * 3)
        love.graphics.setLineWidth(1)
    elseif not afford then
        love.graphics.setColor(0, 0, 0, 0.20); love.graphics.rectangle("fill", r.x, r.y, r.w, r.h)
    elseif hover then
        love.graphics.setColor(s.buyhi[1], s.buyhi[2], s.buyhi[3], 0.9)
        love.graphics.setLineWidth(math.max(2, t))
        love.graphics.rectangle("line", r.x + 1, r.y + 1, r.w - 2, r.h - 2)
        love.graphics.setLineWidth(1)
    end
    love.graphics.setColor(1, 1, 1)
end

-- A store bottom-bar button (its own rusty palette; `primary` = the green Seil!).
function PortScreen:storeButton(b, label, t, primary, mx, my)
    local s = STORE
    local hover = inRect(b, mx, my)
    local face = primary and (hover and s.buyhi or s.buy) or (hover and s.woodhi or s.crate)
    bevel(b.x, b.y, b.w, b.h, face, primary and s.buyhi or s.cratehi,
          primary and s.buylo or s.cratelo, t, true)
    local f = vfont(b.h * 0.42)
    love.graphics.setFont(f)
    local lx = b.x + b.w / 2 - f:getWidth(label) / 2
    local ly = b.y + b.h / 2 - f:getHeight() / 2
    love.graphics.setColor(0, 0, 0, 0.5); love.graphics.print(label, lx + 1, ly + 1)
    love.graphics.setColor(1, 1, 1);      love.graphics.print(label, lx, ly)
end

-- A row of icons. With `figures` (a per-item list, e.g. passenger figures) each
-- slot can differ; otherwise it's `count` copies of `kind`.
function PortScreen:drawIconRow(kind, count, cx, y, s, figures)
    local n = figures and math.min(#figures, 6) or math.min(count, 6)
    local gap = s * 1.5
    local total = (n - 1) * gap
    for i = 1, n do
        self:drawIcon(figures and figures[i] or kind, cx - total / 2 + (i - 1) * gap, y, s)
    end
end

-- Delegate to the shared icon module (which prefers assets/icons/<kind>.png).
function PortScreen:drawIcon(kind, x, y, s)
    Icons.draw(kind, x, y, s)
end

function PortScreen:drawButtons(L, t)
    -- Single centred button (no Butikk) for the focused screens: the map handoff,
    -- the turned-away screen, and the wrong-harbour ("busy") screen.
    local single =
        (self.mapGiven and "Finn skatten!")
        or (self.mode == "findfirst" and "Seil!")
        or (self.mode == "busy" and "Seil videre")
    if single then
        local bw = math.floor(L.panel.w * 0.46)
        local b = { x = L.panel.x + (L.panel.w - bw) / 2, y = L.seil.y, w = bw, h = L.seil.h }
        self:labelButton(b, single, t, true)
        return
    end
    self:labelButton(L.butikk, "Butikk", t, false)   -- open the store
    self:labelButton(L.seil, "Seil!", t, true)       -- cast off
end

return PortScreen
