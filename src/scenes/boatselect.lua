-- src/scenes/boatselect.lua
-- "Velg båten din": pick a boat (with a Kjøp/lock state for premium boats) and
-- name it on a chunky, child-friendly on-screen keyboard (with ÆØÅ) -- no reliance
-- on the OS keyboard, so it works the same on an iPad. Reached from "set sail".

local config  = require("src.config")
local Assets  = require("src.assets")
local Retro   = require("src.ui.retro")
local Scale   = require("src.ui.scale")
local Scene   = require("src.ui.pixelscene")
local Objects = require("src.systems.objects")
local IAP     = require("src.systems.iap")
local utf8    = require("utf8")

local W = Retro.WOOD
local BoatSelect = {}

-- Silly boat names for the "Nytt navn" shuffle. Add or edit freely.
local NAMES = {
    "Tøffe", "Balder", "Dieseldyret", "Uflax", "Sjømannens Trøst", "Simsalabim",
    "Måsen", "Skvulpen", "Sjøsprøyt", "Dønningen",
}
local MAXLEN = 14

-- On-screen keyboard, alphabetical so little ones can find letters, ÆØÅ included.
local KB_ROWS = {
    { "A", "B", "C", "D", "E", "F", "G", "H", "I", "J" },
    { "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T" },
    { "U", "V", "W", "X", "Y", "Z", "Æ", "Ø", "Å" },
}
local LOWER = { ["Æ"] = "æ", ["Ø"] = "ø", ["Å"] = "å" }
local UPPER = { ["æ"] = "Æ", ["ø"] = "Ø", ["å"] = "Å" }
local function lower(ch) return LOWER[ch] or ch:lower() end

-- Capitalise the first letter (ÆØÅ-aware) so names read "Sjøormen", not "sjøormen".
local function upperFirst(s)
    if s == "" then return s end
    local off = utf8.offset(s, 2)
    local first = off and s:sub(1, off - 1) or s
    local rest = off and s:sub(off) or ""
    return (UPPER[first] or first:upper()) .. rest
end

function BoatSelect:load(game)
    self.game = game
    self.t = 0
    self.editing = false
    local boats = game.data.boats
    self.index = 1
    for i, b in ipairs(boats) do
        if b.id == game.state.selectedBoat then self.index = i end
    end
    -- Names are PER BOAT: switching boats shows that boat's own (or its saved
    -- custom) name. `edited` = this boat has a custom name already.
    self.name = game:boatDisplayName(boats[self.index].id)
    self.edited = (game.state.boatNames[boats[self.index].id] ~= nil)
    self.bought = 0                              -- "Kjøpt!" flash timer
    self.offer = false                           -- the premium-pack offer card, when up
end

function BoatSelect:def() return self.game.data.boats[self.index] end
function BoatSelect:owned() return self.game:ownsBoat(self:def().id) end
function BoatSelect:displayName() return upperFirst(self.name) end

function BoatSelect:update(dt)
    self.t = self.t + dt
    if self.bought > 0 then self.bought = self.bought - dt end
    if (self.goldMsgT or 0) > 0 then self.goldMsgT = self.goldMsgT - dt end
    IAP.update(dt)
    -- post-purchase party: gold bursts popping over the new fleet
    if (self.celebrate or 0) > 0 then
        self.celebrate = self.celebrate - dt
        self._celebT = (self._celebT or 0) - dt
        if self._celebT <= 0 then
            self._celebT = 0.22
            local L = self:layout()
            local prem = {}
            for i, b in ipairs(self.game.data.boats) do
                if (b.premium or b.cost) and self.game:ownsBoat(b.id) then
                    prem[#prem + 1] = L.strip[i]
                end
            end
            if #prem == 0 then prem[1] = L.strip[self.index] end
            local r = prem[love.math.random(#prem)]
            if r then
                Retro.burst(r.x + love.math.random() * r.w,
                            r.y + love.math.random() * r.h)
            end
        end
    end
end

-- The chooser's backdrop: the title screen's pixel language (dithered sky +
-- sea, sun, clouds, horizon islands) baked ONCE onto a virtual-res canvas and
-- upscaled with a nearest filter; rebaked only when the window size changes.
-- The only per-frame extras (drawBackground) are three tiny sailboats and a
-- handful of wave-glint rectangles -- positions are pure functions of time, so
-- nothing is stored or allocated per frame.
function BoatSelect:buildBackground(sw, sh)
    local VH = Scene.VRES_H
    local scale = sh / VH
    local VW = math.max(4, math.floor(sw / scale + 0.5))
    local horizon = math.floor(VH * 0.30)

    local cv = love.graphics.newCanvas(VW, VH)
    cv:setFilter("nearest", "nearest")
    love.graphics.setCanvas(cv)
    love.graphics.clear(0, 0, 0, 0)

    Scene.dithGradient(0, 0, VW, horizon, { 0.36, 0.60, 0.88 }, { 0.82, 0.90, 0.96 }, 10)
    Scene.dithGradient(0, horizon, VW, VH - horizon,
        config.colors.water_top, config.colors.water_deep, 8)

    -- horizon islands (grass crest over a sandy base), like the title screen's
    local grass, gdk = config.colors.grass.top, config.colors.grass.lip
    local sand = config.colors.sand.top
    local function island(cx, halfW, height)
        Scene.hill(cx, horizon + math.floor(VH * 0.008), halfW, math.floor(height * 0.35), sand, sand)
        Scene.hill(cx, horizon, halfW * 0.84, height, gdk, grass)
    end
    island(VW * 0.11, VW * 0.085, VH * 0.10)
    island(VW * 0.68, VW * 0.055, VH * 0.07)
    island(VW * 0.92, VW * 0.095, VH * 0.13)

    Scene.cloud(VW * 0.22, VH * 0.10, VW * 0.07)
    Scene.cloud(VW * 0.52, VH * 0.055, VW * 0.045)
    Scene.cloud(VW * 0.70, VH * 0.14, VW * 0.055)

    local sunX, sunY, sunR = VW * 0.85, VH * 0.115, math.floor(VH * 0.06)
    Scene.sun(sunX, sunY, sunR)
    Scene.sunReflection(sunX, horizon, VH, sunR, VH * 0.016)

    love.graphics.setCanvas()
    love.graphics.setColor(1, 1, 1)
    self.bg, self.bgW, self.bgH = cv, sw, sh
    self.bgScale, self.bgHorizon = scale, horizon * scale
end

function BoatSelect:drawBackground(sw, sh)
    if not self.bg or self.bgW ~= sw or self.bgH ~= sh then
        self:buildBackground(sw, sh)
    end
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(self.bg, 0, 0, 0, self.bgScale, self.bgScale)

    -- tiny sailboats drifting across the horizon band
    local t = self.t
    local hy = self.bgHorizon
    local k = sh / 800
    for i = 1, 3 do
        local ph = (t * (0.011 + i * 0.004) + i * 0.37) % 1.15 - 0.075
        Scene.miniBoat(ph * sw, hy + (10 + i * 24) * k, (0.45 + i * 0.2) * k,
            config.SHIP_COLORS[(i % #config.SHIP_COLORS) + 1])
    end

    -- wave glints twinkling on the water
    local wv = config.colors.wave
    local blk = math.max(2, math.floor(sh / Scene.VRES_H) * 2)
    for i = 1, 26 do
        local tw = 0.5 + 0.5 * math.sin(t * (0.9 + (i % 5) * 0.23) + i * 2.1)
        if tw > 0.55 then
            local gx = ((i * 0.381966 + 0.13) % 1) * sw
            local gy = hy + ((i * 0.618034 + 0.29) % 1) * (sh - hy) * 0.96
            love.graphics.setColor(wv[1], wv[2], wv[3], (tw - 0.55) * 1.1)
            love.graphics.rectangle("fill", gx, gy, blk * (2 + (i % 3)), blk * 0.5)
        end
    end
    love.graphics.setColor(1, 1, 1)
end

-- Selecting a boat. A LOCKED boat explains itself out loud — the player can't
-- read, so assets/voice/laast.ogg ("Den er låst! Spør en voksen!") is the real
-- UI here; until it's recorded the visual rope/padlock carry it alone.
function BoatSelect:announce()
    if not self.game:ownsBoat(self:def().id) then
        if not Assets.playNamedVoice("laast") then Assets.playSfx("leave", 0.35) end
    else
        Assets.playSfx("leave", 0.5)
    end
end

-- Persist the current boat's custom name THE MOMENT it exists: a rename must
-- survive switching boats (or leaving the screen) without sailing first —
-- especially for a boat someone paid for.
function BoatSelect:commitName()
    if not self.edited then return end
    local nm = upperFirst((self.name or ""):gsub("^%s+", ""):gsub("%s+$", ""))
    self.game.state.boatNames[self:def().id] = (nm ~= "") and nm or nil
    self.game:save()
end

-- Refresh the name field for the (newly) selected boat.
function BoatSelect:syncName()
    local id = self:def().id
    self.name = self.game:boatDisplayName(id)
    self.edited = (self.game.state.boatNames[id] ~= nil)
end

function BoatSelect:cycle(d)
    self:commitName()                    -- don't lose an edit on the old boat
    local n = #self.game.data.boats
    self.index = ((self.index - 1 + d) % n) + 1
    self:syncName()
    self:announce()
end

function BoatSelect:selectBoat(i)
    if i == self.index then return end
    self:commitName()                    -- don't lose an edit on the old boat
    self.index = i
    self:syncName()
    self:announce()
end

function BoatSelect:randomName()
    self.name = NAMES[love.math.random(#NAMES)]
    self.edited = true
    self:commitName()
    Assets.playSfx("coin", 0.5)
end

-- Append a letter from the keyboard. First keystroke on an un-personalised name
-- clears the default so the child types a fresh name.
function BoatSelect:insert(ch)
    if not self.edited then self.name = ""; self.edited = true end
    if utf8.len(self.name) < MAXLEN then self.name = self.name .. lower(ch) end
end

function BoatSelect:backspace()
    self.edited = true
    local off = utf8.offset(self.name, -1)
    if off then self.name = self.name:sub(1, off - 1) end
end

-- The big bottom button: sail if we own this boat; otherwise show the pack offer.
-- self.offer states: false | "card" (the pitch) | "gate" (parental gate)
-- | "busy" (store transaction in flight).
function BoatSelect:primary()
    local def = self:def()
    if self:owned() then
        self:setSail()
    elseif def.cost and not def.premium then
        -- the GOLD boat: the saving-up reward, no store involved
        if self.game:buyBoat(def.id) then
            self.bought = 1.6
            self.celebrate, self._celebT = 2.4, 0
            if not Assets.playNamedVoice("kjopt_baat") then Assets.playNamedVoice("cheer") end
            Assets.playSfx("coin", 0.9)
        else
            self.goldMsg = ("Spar %d gull til!"):format(def.cost - self.game.state.coins)
            self.goldMsgT = 2.2
            Assets.playSfx("leave", 0.4)
        end
    else
        Assets.playNamedVoice("spor_en_voksen")   -- optional clip; card is the fallback
        self.offer = "card"
    end
end

-- Parental gate (Kids-category rule: a child must not be able to reach the
-- purchase alone). A multiplication question stops a 5-year-old cold but is
-- trivial for the grown-up he fetches. Fresh numbers every time.
function BoatSelect:openGate()
    local a, b = love.math.random(6, 9), love.math.random(6, 9)
    local right = a * b
    local answers = { right, right + love.math.random(1, 5), right - love.math.random(1, 5) }
    -- shuffle
    for i = #answers, 2, -1 do
        local j = love.math.random(i)
        answers[i], answers[j] = answers[j], answers[i]
    end
    local correct
    for i, v in ipairs(answers) do if v == right then correct = i end end
    self.gate = { q = ("Hva er %d × %d?"):format(a, b), answers = answers, correct = correct }
    self.offer = "gate"
end

-- Kick off the real purchase (or the dev-stub pretend one; src/systems/iap.lua).
function BoatSelect:startBuy()
    self.offer = "busy"
    IAP.buy(function(ok, err)
        if ok then self:purchaseSucceeded()
        else
            self.storeErr = err or "Kjøpet ble avbrutt"
            self.offer = "card"
        end
    end)
end

-- The moment the pack lands: back to the chooser, big cheer, and gold bursts
-- raining over the newly-unlocked (now gold-framed) boats for a few seconds.
function BoatSelect:purchaseSucceeded()
    self.game:unlockPremium()
    self.offer = false
    self.bought = 1.6
    self.celebrate, self._celebT = 3.2, 0
    if not Assets.playNamedVoice("kjopt_pakken") then Assets.playNamedVoice("cheer") end
    Assets.playSfx("coin", 0.9)
end

-- "Gjenopprett kjøp": Apple requires a visible way to re-grant a non-consumable
-- bought earlier (new device, reinstall). Success unlocks exactly like a buy.
function BoatSelect:startRestore()
    self.offer = "busy"
    IAP.restore(function(ok, err)
        if ok then self:purchaseSucceeded()
        else
            self.storeErr = err or "Fant ingen tidligere kjøp"
            self.offer = "card"
        end
    end)
end

function BoatSelect:setSail()
    local def = self:def()
    local nm = upperFirst((self.name or ""):gsub("^%s+", ""):gsub("%s+$", ""))
    self.game.state.selectedBoat = def.id
    self.game.state.boatNames[def.id] = (nm ~= "") and nm or def.name
    self.game:save()
    self.game:setScene("mapselect")   -- world choice next; it starts "loading"
end

function BoatSelect:back()
    self:commitName()                    -- leaving the screen keeps the rename
    self.game:setScene("menu")
end

-- ---- layout ---------------------------------------------------------------

function BoatSelect:layout()
    local sw, sh = love.graphics.getDimensions()
    local k = Scale.ui(1)   -- read/tapped UI: phone-boosted (see src/ui/scale.lua)
    local cx = sw / 2
    local ed = self.editing
    local previewY = math.floor(sh * (ed and 0.24 or 0.32))
    local previewW = math.min(sw * (ed and 0.30 or 0.42), (ed and 230 or 320) * k)
    local nameW, nameH, gap, nyttW = 340 * k, 46 * k, 12 * k, 150 * k
    local groupW = nameW + gap + nyttW
    local gx = cx - groupW / 2

    -- filmstrip of ALL boats (free + locked premium), so the fancy paid ones are
    -- on show and entice a purchase.
    local boats = self.game.data.boats
    local nb = #boats
    local thumbW = math.min((sw * 0.86) / nb, 150 * k)
    local thumbH = thumbW * 0.52
    local sgap = 14 * k
    local sx0 = cx - (nb * thumbW + (nb - 1) * sgap) / 2
    local stripY = math.floor(sh * 0.42)
    local strip = {}
    for i = 1, nb do
        strip[i] = { x = sx0 + (i - 1) * (thumbW + sgap), y = stripY, w = thumbW, h = thumbH }
    end

    -- Rows FLOW from the strip downward (strip → Fart → name row) instead of
    -- sitting at fixed screen fractions — phone-boosted sizes can't overlap.
    local statsY = math.floor(stripY + thumbH + 14 * k)
    local nameY  = math.floor(statsY + 26 * k + 12 * k)

    return {
        k = k, cx = cx, previewY = previewY, previewW = previewW,
        statsY = statsY,
        strip = strip,
        nameBox = { x = gx, y = nameY, w = nameW, h = nameH },
        nytt = { x = gx + nameW + gap, y = nameY, w = nyttW, h = nameH },
        sail = { x = cx - 170 * k, y = math.floor(sh * 0.80), w = 340 * k, h = 76 * k },
        back = { x = 20 * k, y = 20 * k, w = 130 * k, h = 52 * k },
        -- name box while editing: centred above the keyboard
        editBox = { x = cx - math.min(sw * 0.6, 460 * k) / 2, y = math.floor(sh * 0.40),
                    w = math.min(sw * 0.6, 460 * k), h = 58 * k },
    }
end

-- Keyboard key rects (recomputed each call -- cheap, a few dozen rects).
function BoatSelect:keyLayout()
    local sw, sh = love.graphics.getDimensions()
    local k = Scale.ui(1)
    local kw = math.floor(math.min((sw * 0.92) / 10, 96 * k))
    local kh = math.floor(kw * 0.92)
    local gap = math.floor(kw * 0.12)
    local topY = math.floor(sh * 0.50)
    local keys = {}
    for r, row in ipairs(KB_ROWS) do
        local n = #row
        local x0 = (sw - (n * kw + (n - 1) * gap)) / 2
        local y = topY + (r - 1) * (kh + gap)
        for c, ch in ipairs(row) do
            keys[#keys + 1] = { x = x0 + (c - 1) * (kw + gap), y = y, w = kw, h = kh, kind = "letter", label = ch }
        end
    end
    local y = topY + 3 * (kh + gap)
    local aw, spw = kw * 2 + gap, kw * 4 + gap * 3
    local x0 = (sw - (aw * 2 + spw + gap * 2)) / 2
    keys[#keys + 1] = { x = x0, y = y, w = aw, h = kh, kind = "back", label = "Slett" }
    keys[#keys + 1] = { x = x0 + aw + gap, y = y, w = spw, h = kh, kind = "space", label = "Mellomrom" }
    keys[#keys + 1] = { x = x0 + aw + gap + spw + gap, y = y, w = aw, h = kh, kind = "done", label = "Ferdig" }
    return keys
end

-- ---- drawing --------------------------------------------------------------

local function hover(r)
    local mx, my = love.mouse.getPosition()
    return mx >= r.x and mx <= r.x + r.w and my >= r.y and my <= r.y + r.h
end

-- A sagging harbour rope from (x1,y) to (x2,y) with knots at the ends: the
-- "berth is roped off" cue on locked boats. Pure segments, no allocations.
local function ropeAcross(x1, x2, y, sag, thick)
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

-- Shimmer for something BOUGHT: a glint travelling around the frame plus
-- twinkling corner stars — the unmistakable "this one is yours now".
local function sparkleFrame(r, t, phase)
    local per = 2 * (r.w + r.h)
    local p = ((t * 0.30 + (phase or 0)) % 1) * per
    local x, y
    if p < r.w then x, y = r.x + p, r.y
    elseif p < r.w + r.h then x, y = r.x + r.w, r.y + (p - r.w)
    elseif p < 2 * r.w + r.h then x, y = r.x + r.w - (p - r.w - r.h), r.y + r.h
    else x, y = r.x, r.y + r.h - (p - 2 * r.w - r.h) end
    love.graphics.setColor(1, 0.9, 0.4, 0.35)
    love.graphics.circle("fill", x, y, math.max(3, r.h * 0.10))
    love.graphics.setColor(1, 0.96, 0.65, 0.95)
    love.graphics.circle("fill", x, y, math.max(2, r.h * 0.05))
    for i = 0, 3 do
        local a = math.sin(t * (1.3 + i * 0.4) + i * 1.7 + (phase or 0) * 6)
        if a > 0.5 then
            local f = (a - 0.5) * 2
            local cx = (i % 2 == 0) and r.x or r.x + r.w
            local cy = (i < 2) and r.y or r.y + r.h
            local sr = r.h * 0.10 * f
            love.graphics.setColor(1, 0.97, 0.8, f)
            love.graphics.line(cx - sr, cy, cx + sr, cy)
            love.graphics.line(cx, cy - sr, cx, cy + sr)
        end
    end
end

-- A chunky gold padlock centred on (x,y), body height s.
local function padlock(x, y, s)
    love.graphics.setColor(0.35, 0.28, 0.16); love.graphics.setLineWidth(math.max(2, s * 0.22))
    love.graphics.arc("line", "open", x, y - s * 0.28, s * 0.44, math.pi, 2 * math.pi)
    love.graphics.setColor(0.95, 0.78, 0.28)
    love.graphics.rectangle("fill", x - s * 0.55, y - s * 0.28, s * 1.1, s * 0.85, s * 0.12, s * 0.12)
    love.graphics.setColor(0.55, 0.42, 0.14)
    love.graphics.circle("fill", x, y + s * 0.12, s * 0.13)
    love.graphics.setLineWidth(1)
end

-- The big action button, readable without reading: GREEN with a little sail
-- when the boat is yours ("Sett seil!"), GOLD with a padlock when it's locked
-- ("L\195\165s opp" -- the text is for the grown-up being fetched).
local function actionButton(id, r, owned, label, font)
    local t = math.max(2, math.floor(r.h * 0.12))
    local down = Retro.isDown(id)
    local face = owned and { 0.30, 0.50, 0.28 } or { 0.66, 0.52, 0.20 }
    local hi   = owned and { 0.42, 0.66, 0.38 } or { 0.85, 0.70, 0.32 }
    local lo   = owned and { 0.16, 0.30, 0.15 } or { 0.38, 0.28, 0.10 }
    if hover(r) and not down then face = hi end
    Retro.bevel(r.x, r.y, r.w, r.h, face, hi, lo, t, not down)
    if down then r = { x = r.x + t, y = r.y + t, w = r.w, h = r.h } end  -- nudge content
    love.graphics.setFont(font)
    local gs = r.h * 0.42                       -- glyph size
    local tw = font:getWidth(label)
    local total = gs * 1.4 + tw
    local gx = r.x + r.w / 2 - total / 2 + gs * 0.5
    if owned then                               -- little white sail + mast
        love.graphics.setColor(0.96, 0.95, 0.90)
        love.graphics.polygon("fill", gx, r.y + r.h / 2 - gs * 0.55,
            gx, r.y + r.h / 2 + gs * 0.35, gx + gs * 0.75, r.y + r.h / 2 + gs * 0.35)
        love.graphics.setLineWidth(math.max(2, gs * 0.10))
        love.graphics.line(gx, r.y + r.h / 2 - gs * 0.55, gx, r.y + r.h / 2 + gs * 0.45)
        love.graphics.setLineWidth(1)
    else
        padlock(gx + gs * 0.3, r.y + r.h / 2, gs * 0.75)
    end
    love.graphics.setColor(1, 1, 1)
    love.graphics.print(label, gx + gs * 1.0, r.y + r.h / 2 - font:getHeight() / 2)
end

local function button(id, r, label, font)
    Retro.button(id, r, label, font)
end

local function statBar(label, frac, x, y, w, font)
    love.graphics.setFont(font); love.graphics.setColor(W.text)
    love.graphics.print(label, x, y - 2)
    local bx = x + font:getWidth("Plass") + 14
    local pips, on = 5, math.max(1, math.floor(frac * 5 + 0.5))
    local pw = (w - bx + x) / pips
    for i = 1, pips do
        love.graphics.setColor(i <= on and W.accent or W.deep)
        love.graphics.rectangle("fill", bx + (i - 1) * pw, y, pw - 4, font:getHeight(), 2, 2)
    end
end

local function nameField(box, text, showCursor, font)
    Retro.bevel(box.x, box.y, box.w, box.h, W.deep, W.hi, W.lo, math.max(2, box.h * 0.10), false)
    love.graphics.setFont(font); love.graphics.setColor(W.text)
    local ty = box.y + box.h / 2 - font:getHeight() / 2
    love.graphics.print(text, box.x + 14, ty)
    if showCursor then
        love.graphics.rectangle("fill", box.x + 14 + font:getWidth(text) + 2, ty + 2, 2, font:getHeight() - 4)
    end
end

function BoatSelect:drawKeyboard()
    local fonts = self.game.fonts
    for _, key in ipairs(self:keyLayout()) do
        local t = math.max(2, math.floor(key.h * 0.12))
        Retro.bevel(key.x, key.y, key.w, key.h, hover(key) and W.hi or W.face, W.hi, W.lo, t, true)
        local f = (key.kind == "letter") and fonts.big or fonts.small
        love.graphics.setFont(f)
        love.graphics.setColor(key.kind == "letter" and W.text or W.accent)
        love.graphics.print(key.label, key.x + key.w / 2 - f:getWidth(key.label) / 2,
            key.y + key.h / 2 - f:getHeight() / 2)
    end
end

function BoatSelect:drawPreview(L, def)
    local owned = self:owned()
    local bob = math.sin(self.t * 1.5) * 5 * L.k
    -- Locked boats stay FULL COLOUR (grey reads as "broken" to a child; pretty
    -- + rope + padlock reads as "for later"). See the lock overlay below.
    if def.frames and Objects.hasBoatFrames(def.frames) then
        -- spin the rendered 3D-model frames like a turntable (centred in the preview)
        love.graphics.push()
        love.graphics.translate(L.cx, L.previewY + bob)
        Objects.drawBoatFrames(def.frames, 0, 0, self.t * 0.7, L.previewW * 1.1,
            def.frameOffset, def.frameCW, { 1, 1, 1 }, 0.5)
        love.graphics.pop()
    elseif def.model then
        -- spin the volumetric "3D" boat like a turntable to show it off
        local col = def.color
        love.graphics.push()
        love.graphics.translate(L.cx, L.previewY + 14 * L.k + bob)
        love.graphics.scale(2.3 * L.k, 2.3 * L.k)
        Objects.drawYacht(0, 0, self.t * 0.7, col, 1.0, 0)
        love.graphics.pop()
    else
        local img = def.sprite and Assets.image("boats/" .. def.sprite)
        love.graphics.setColor(0, 0, 0, 0.18)
        love.graphics.ellipse("fill", L.cx, L.previewY + L.previewW * 0.12, L.previewW * 0.45, L.previewW * 0.10)
        if img then
            if img:getFilter() ~= "linear" then img:setFilter("linear", "linear") end
            local scale = L.previewW / img:getWidth()
            love.graphics.setColor(1, 1, 1)
            love.graphics.draw(img, L.cx, L.previewY + bob, 0, scale, scale, img:getWidth() / 2, img:getHeight() / 2)
        else
            love.graphics.setColor(def.color)
            love.graphics.ellipse("fill", L.cx, L.previewY + bob, L.previewW * 0.4, L.previewW * 0.18)
        end
    end
    if not owned then
        local rw = L.previewW * 0.85
        local ry = L.previewY + bob * 0.3
        ropeAcross(L.cx - rw, L.cx + rw, ry, 22 * L.k, math.max(3, 7 * L.k))
        padlock(L.cx, ry + 22 * L.k + 34 * L.k, 52 * L.k)
    end
end

-- The boat art alone, centred in a rect (shared by the filmstrip thumbs and
-- the Kaptein-pakken card's mini showcases).
local function boatArt(r, def)
    local t = math.max(2, math.floor(r.h * 0.12))
    local hasFrames = def.frames and Objects.hasBoatFrames(def.frames)
    local img = (not def.model and not hasFrames) and def.sprite and Assets.image("boats/" .. def.sprite)
    if hasFrames then
        love.graphics.push()
        love.graphics.translate(r.x + r.w / 2, r.y + r.h * 0.85)
        Objects.drawBoatFrames(def.frames, 0, 0, -0.6, r.w * 0.78,
            def.frameOffset, def.frameCW, { 1, 1, 1 })
        love.graphics.pop()
    elseif def.model then
        love.graphics.push()
        love.graphics.translate(r.x + r.w / 2, r.y + r.h * 0.62)
        local s = r.h / 56
        love.graphics.scale(s, s)
        Objects.drawYacht(0, 0, -0.7, def.color, 1.0, 0)
        love.graphics.pop()
    elseif img then
        if img:getFilter() ~= "linear" then img:setFilter("linear", "linear") end
        local pad = t * 2
        local s = math.min((r.w - pad * 2) / img:getWidth(), (r.h - pad * 2) / img:getHeight())
        love.graphics.setColor(1, 1, 1)
        love.graphics.draw(img, r.x + r.w / 2, r.y + r.h / 2, 0, s, s, img:getWidth() / 2, img:getHeight() / 2)
    else
        love.graphics.setColor(def.color)
        love.graphics.ellipse("fill", r.x + r.w / 2, r.y + r.h / 2, r.w * 0.35, r.h * 0.25)
    end
end

-- One boat in the filmstrip: framed thumbnail, gold frame if selected, padlock if
-- it's a locked premium boat (so its "fanciness" is on show to entice buying).
-- Owned premium boats keep a permanent GOLD frame — the captain's fleet.
function BoatSelect:drawThumb(r, def, i)
    local owned = self.game:ownsBoat(def.id)
    local sel = (i == self.index)
    local t = math.max(2, math.floor(r.h * 0.12))
    Retro.bevel(r.x, r.y, r.w, r.h, sel and W.hi or W.face, W.hi, W.lo, t, true)
    boatArt(r, def)
    if (def.premium or def.cost) and owned then
        love.graphics.setColor(W.accent); love.graphics.setLineWidth(math.max(2, 4 * (r.h / 100)))
        love.graphics.rectangle("line", r.x + 1, r.y + 1, r.w - 2, r.h - 2)
        love.graphics.setLineWidth(1)
        sparkleFrame(r, self.t, i * 0.31)   -- bought = it shimmers
    end
    if sel then
        love.graphics.setColor(W.accent); love.graphics.setLineWidth(math.max(2, 3 * (r.h / 100)))
        love.graphics.rectangle("line", r.x, r.y, r.w, r.h); love.graphics.setLineWidth(1)
    end
    if not owned then
        local ry = r.y + r.h * 0.42
        ropeAcross(r.x + 2, r.x + r.w - 2, ry, r.h * 0.10, math.max(2, r.h * 0.045))
        padlock(r.x + r.w / 2, ry + r.h * 0.16, r.h * 0.26)
        if def.cost and not def.premium then
            -- gold-price chip: this one is bought with coins, not the pack
            local f = self.game.fonts.small
            local lbl = tostring(def.cost)
            local cr2 = r.h * 0.10
            local cw2 = cr2 * 2 + 6 + f:getWidth(lbl)
            local cx2 = r.x + r.w / 2 - cw2 / 2
            local cy2 = r.y + r.h - cr2 * 1.6
            love.graphics.setColor(0.6, 0.45, 0.1)
            love.graphics.circle("fill", cx2 + cr2, cy2, cr2 + 1)
            love.graphics.setColor(config.colors.gold)
            love.graphics.circle("fill", cx2 + cr2, cy2, cr2)
            love.graphics.setFont(f)
            love.graphics.print(lbl, cx2 + cr2 * 2 + 6, cy2 - f:getHeight() / 2)
        end
    end
end

-- The premium-pack offer card ("Kaptein-pakken"). No bullet lists: the boats
-- themselves are the pitch (gold-framed mini showcases), one quiet line for
-- the grown-up, and a heart-marked "spør mamma eller pappa". Top-down layout
-- so it always fits.
function BoatSelect:offerLayout()
    local sw, sh = love.graphics.getDimensions()
    local k = Scale.ui(1)
    local pw = math.min(sw * 0.80, 640 * k)
    local pad, btnH = 24 * k, 72 * k
    local y = pad
    local titleY = y;  y = y + 44 * k + 12 * k
    -- the showcase: every premium boat, side by side
    local boats = {}
    for _, b in ipairs(self.game.data.boats) do
        if b.premium then boats[#boats + 1] = b end
    end
    local n = math.max(1, #boats)
    local bgap = 14 * k
    local bw = math.min((pw - pad * 2 - (n - 1) * bgap) / n, 170 * k)
    local bh = bw * 0.62
    local boatsY = y; y = y + bh + 10 * k
    local subY = y;    y = y + 20 * k + 8 * k
    local askY = y;    y = y + 24 * k + 12 * k
    local kjopY = y;   y = y + btnH + 10 * k
    local rowY = y;    y = y + 44 * k + pad      -- Tilbake + Gjenopprett, one row
    local ph = y
    local px, py = (sw - pw) / 2, (sh - ph) / 2
    local total = n * bw + (n - 1) * bgap
    local showcase = {}
    for i = 1, #boats do
        showcase[i] = { x = px + pw / 2 - total / 2 + (i - 1) * (bw + bgap),
                        y = py + boatsY, w = bw, h = bh, def = boats[i] }
    end
    local rowW = 190 * k + 16 * k + 240 * k
    local rowX = px + pw / 2 - rowW / 2
    return {
        k = k, x = px, y = py, w = pw, h = ph,
        titleY = py + titleY, subY = py + subY, askY = py + askY,
        showcase = showcase,
        kjop = { x = px + pw / 2 - 170 * k, y = py + kjopY, w = 340 * k, h = btnH },
        tilbake = { x = rowX, y = py + rowY, w = 190 * k, h = 44 * k },
        -- Apple requires a visible restore path for non-consumables
        restore = { x = rowX + 190 * k + 16 * k, y = py + rowY, w = 240 * k, h = 44 * k },
    }
end


-- The parental gate: same plaque, one grown-up question, three answers.
function BoatSelect:gateLayout()
    local sw, sh = love.graphics.getDimensions()
    local k = Scale.ui(1)
    local pw = math.min(sw * 0.72, 560 * k)
    local pad, btnH = 26 * k, 64 * k
    local y = pad
    local titleY = y; y = y + 44 * k + 10 * k
    local qY = y;     y = y + 34 * k + 16 * k
    local ansY = y;   y = y + btnH + 14 * k
    local tilbakeY = y; y = y + 42 * k + pad
    local ph = y
    local px, py = (sw - pw) / 2, (sh - ph) / 2
    local aw = (pw - pad * 2 - 24 * k) / 3
    local answers = {}
    for i = 1, 3 do
        answers[i] = { x = px + pad + (i - 1) * (aw + 12 * k), y = py + ansY, w = aw, h = btnH }
    end
    return {
        k = k, x = px, y = py, w = pw, h = ph,
        titleY = py + titleY, qY = py + qY,
        answers = answers,
        tilbake = { x = px + pw / 2 - 95 * k, y = py + tilbakeY, w = 190 * k, h = 42 * k },
    }
end

function BoatSelect:drawGate()
    local sw, sh = love.graphics.getDimensions()
    local fonts = self.game.fonts
    local G = self:gateLayout()
    love.graphics.setColor(0, 0, 0, 0.6); love.graphics.rectangle("fill", 0, 0, sw, sh)
    Retro.plaque(G.x, G.y, G.w, G.h, math.max(3, math.floor(G.h / 70)))

    love.graphics.setFont(fonts.big); love.graphics.setColor(W.accent)
    local t1 = "Spør en voksen!"
    love.graphics.print(t1, G.x + G.w / 2 - fonts.big:getWidth(t1) / 2, G.titleY)

    love.graphics.setFont(fonts.normal); love.graphics.setColor(W.text)
    love.graphics.print(self.gate.q, G.x + G.w / 2 - fonts.normal:getWidth(self.gate.q) / 2, G.qY)

    for i, r in ipairs(G.answers) do
        button("bs.gate" .. i, r, tostring(self.gate.answers[i]), fonts.big)
    end
    button("bs.gateback", G.tilbake, "Tilbake", fonts.small)
    love.graphics.setColor(1, 1, 1)
end

function BoatSelect:drawOffer()
    local sw, sh = love.graphics.getDimensions()
    local fonts = self.game.fonts
    local P = config.PREMIUM
    local O = self:offerLayout()
    love.graphics.setColor(0, 0, 0, 0.6); love.graphics.rectangle("fill", 0, 0, sw, sh)
    Retro.plaque(O.x, O.y, O.w, O.h, math.max(3, math.floor(O.h / 70)))

    love.graphics.setFont(fonts.big); love.graphics.setColor(W.accent)
    love.graphics.print(P.name, O.x + O.w / 2 - fonts.big:getWidth(P.name) / 2, O.titleY)

    -- THE pitch: the boats themselves, gold-framed, twinkling
    for i, r in ipairs(O.showcase) do
        Retro.bevel(r.x, r.y, r.w, r.h, W.deep, W.hi, W.lo,
            math.max(2, math.floor(r.h * 0.06)), false)
        boatArt(r, r.def)
        love.graphics.setColor(W.accent)
        love.graphics.setLineWidth(math.max(2, r.h * 0.045))
        love.graphics.rectangle("line", r.x, r.y, r.w, r.h)
        love.graphics.setLineWidth(1)
        local a = math.sin(self.t * 2.2 + i * 2.1)
        if a > 0.2 then                            -- a star glints on each boat
            local f = (a - 0.2) / 0.8
            local px = r.x + r.w * (0.18 + 0.12 * i)
            local py2 = r.y + r.h * 0.22
            local sr = r.h * 0.10 * f
            love.graphics.setColor(1, 0.97, 0.8, f)
            love.graphics.line(px - sr, py2, px + sr, py2)
            love.graphics.line(px, py2 - sr, px, py2 + sr)
        end
    end

    love.graphics.setFont(fonts.small); love.graphics.setColor(W.text)
    local sub = "Alle de fine båtene – og nye som kommer! Betal én gang."
    love.graphics.print(sub, O.x + O.w / 2 - fonts.small:getWidth(sub) / 2, O.subY)

    -- neutral, adult-directed: a fact about who buys, not a nudge to go beg
    love.graphics.setFont(fonts.small)
    local ask = "En voksen må hjelpe til med kjøpet"
    love.graphics.setColor(W.text[1], W.text[2], W.text[3], 0.85)
    love.graphics.print(ask, O.x + O.w / 2 - fonts.small:getWidth(ask) / 2, O.askY)

    button("bs.kjop", O.kjop, "Kjøp  " .. IAP.price(), fonts.big)
    button("bs.cardback", O.tilbake, "Tilbake", fonts.small)

    button("bs.restore", O.restore, "Gjenopprett kjøp", fonts.small)

    if self.storeErr then
        love.graphics.setColor(0.9, 0.35, 0.25)
        love.graphics.print(self.storeErr,
            O.x + O.w / 2 - fonts.small:getWidth(self.storeErr) / 2, O.subY - 26 * O.k)
    end

    if self.offer == "busy" then
        love.graphics.setColor(0, 0, 0, 0.55)
        love.graphics.rectangle("fill", O.x, O.y, O.w, O.h)
        love.graphics.setFont(fonts.normal); love.graphics.setColor(W.accent)
        local m = "Vent litt…"
        love.graphics.print(m, O.x + O.w / 2 - fonts.normal:getWidth(m) / 2,
            O.y + O.h / 2 - fonts.normal:getHeight() / 2)
    end
    love.graphics.setColor(1, 1, 1)
end

function BoatSelect:draw()
    local sw, sh = love.graphics.getDimensions()
    local fonts = self.game.fonts
    local L = self:layout()
    local def = self:def()

    love.graphics.clear(config.colors.water_deep)
    self:drawBackground(sw, sh)

    -- title with a soft shadow so it pops against the pale sky
    love.graphics.setFont(fonts.title)
    local title = "Velg båten din"
    local tx = L.cx - fonts.title:getWidth(title) / 2
    local ty = math.floor(sh * 0.06)
    love.graphics.setColor(0.13, 0.11, 0.09, 0.5)
    love.graphics.print(title, tx + math.max(2, 3 * L.k), ty + math.max(2, 3 * L.k))
    love.graphics.setColor(W.text)
    love.graphics.print(title, tx, ty)

    self:drawPreview(L, def)

    if self.editing then
        nameField(L.editBox, self:displayName(), (self.t * 2) % 1 < 0.5, fonts.big)
        self:drawKeyboard()
    else
        for i, r in ipairs(L.strip) do
            self:drawThumb(r, self.game.data.boats[i], i)
        end
        local sx = L.cx - 150 * L.k
        statBar("Fart", (def.speed - 120) / 110, sx, L.statsY, 300 * L.k, fonts.small)

        nameField(L.nameBox, self:displayName(), false, fonts.normal)
        button("bs.nytt", L.nytt, "Nytt navn", fonts.small)
        local lbl = "Sett seil!"
        if not self:owned() then
            lbl = (def.cost and not def.premium)
                and ("Lås opp – %d gull"):format(def.cost) or "Lås opp"
        end
        actionButton("bs.sail", L.sail, self:owned(), lbl, fonts.big)
        if (self.goldMsgT or 0) > 0 then
            love.graphics.setFont(fonts.normal)
            love.graphics.setColor(0.95, 0.45, 0.3)
            love.graphics.print(self.goldMsg,
                L.cx - fonts.normal:getWidth(self.goldMsg) / 2,
                L.sail.y - fonts.normal:getHeight() - 8 * L.k)
            love.graphics.setColor(1, 1, 1)
        end
        button("bs.back", L.back, "Tilbake", fonts.small)
    end

    if self.offer == "gate" then self:drawGate()
    elseif self.offer then self:drawOffer() end

    if (self.celebrate or 0) > 0 then
        local f = math.min(1, self.celebrate / 0.5)      -- fade out at the end
        local msg = "Hurra! Du er kaptein!"
        love.graphics.setFont(fonts.big)
        local bob = math.sin(self.t * 6) * 4 * L.k
        local mx2 = L.cx - fonts.big:getWidth(msg) / 2
        local my2 = sh * 0.16 + bob
        love.graphics.setColor(0.1, 0.08, 0.05, 0.6 * f)
        love.graphics.print(msg, mx2 + 3 * L.k, my2 + 3 * L.k)
        love.graphics.setColor(1, 0.85, 0.3, f)
        love.graphics.print(msg, mx2, my2)
        love.graphics.setColor(1, 1, 1)
    end

    if self.bought > 0 then
        love.graphics.setFont(fonts.big); love.graphics.setColor(W.accent)
        local m = "Kjøpt!"
        love.graphics.print(m, L.cx - fonts.big:getWidth(m) / 2, L.previewY - 70 * L.k)
    end
    love.graphics.setColor(1, 1, 1)
end

-- ---- input ----------------------------------------------------------------

local function hit(r, x, y) return x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h end

function BoatSelect:mousepressed(x, y, button)
    if button ~= 1 then return end
    if self.offer then
        local O = self:offerLayout()
        if self.offer == "card" then
            if Retro.press("bs.kjop", O.kjop, x, y) then return end
            if Retro.press("bs.restore", O.restore, x, y) then return end
            if Retro.press("bs.cardback", O.tilbake, x, y) then return end
            if not hit(O, x, y) then self.offer = false; self.storeErr = nil end
        elseif self.offer == "gate" then
            local G = self:gateLayout()
            for i, r in ipairs(G.answers) do
                if Retro.press("bs.gate" .. i, r, x, y) then return end
            end
            if Retro.press("bs.gateback", G.tilbake, x, y) then return end
            if not hit(G, x, y) then self.offer = "card" end   -- outside: step back
        end
        -- "busy": ignore clicks until the store settles
        return
    end
    if self.editing then
        for _, key in ipairs(self:keyLayout()) do
            if hit(key, x, y) then
                if key.kind == "letter" then self:insert(key.label)
                elseif key.kind == "back" then self:backspace()
                elseif key.kind == "space" then self:insert(" ")
                elseif key.kind == "done" then self.editing = false; self:commitName() end
                return
            end
        end
        return
    end
    local L = self:layout()
    for i, r in ipairs(L.strip) do
        if hit(r, x, y) then self:selectBoat(i); return end   -- selection: instant
    end
    if hit(L.nameBox, x, y) then self.editing = true; return end
    if Retro.press("bs.nytt", L.nytt, x, y) then return end
    if Retro.press("bs.sail", L.sail, x, y) then return end
    Retro.press("bs.back", L.back, x, y)
end

-- Buttons fire on RELEASE (Retro press protocol: squish in, act on lift).
function BoatSelect:mousereleased(x, y, button)
    if button ~= 1 then return end
    if self.offer == "card" then
        local O = self:offerLayout()
        if Retro.released("bs.kjop", x, y) then
            if config.PREMIUM.PARENTAL_GATE then self:openGate() else self:startBuy() end
        elseif Retro.released("bs.restore", x, y) then self:startRestore()
        elseif Retro.released("bs.cardback", x, y) then
            self.offer = false; self.storeErr = nil
        end
        return
    elseif self.offer == "gate" then
        local G = self:gateLayout()
        for i, r in ipairs(G.answers) do
            if Retro.released("bs.gate" .. i, x, y) then
                if i == self.gate.correct then self:startBuy()
                else self.offer = "card" end     -- wrong answer: no purchase
                return
            end
        end
        if Retro.released("bs.gateback", x, y) then self.offer = "card" end
        return
    elseif self.offer then
        return   -- busy
    end
    if self.editing then return end
    local L = self:layout()
    if Retro.released("bs.nytt", x, y) then self:randomName()
    elseif Retro.released("bs.sail", x, y) then self:primary()
    elseif Retro.released("bs.back", x, y) then self:back() end
end

function BoatSelect:keypressed(key)
    if self.offer then
        if key == "escape" and self.offer ~= "busy" then
            self.offer = (self.offer == "gate") and "card" or false
        end
        return
    end
    if self.editing then
        if key == "return" or key == "kpenter" or key == "escape" then
            self.editing = false; self:commitName()
        elseif key == "backspace" then self:backspace() end
        return
    end
    if key == "left" then self:cycle(-1)
    elseif key == "right" then self:cycle(1)
    elseif key == "return" or key == "kpenter" then self:primary()
    elseif key == "escape" then self:back() end
end

function BoatSelect:textinput(t)   -- physical keyboard (desktop); on-screen handles touch
    if self.editing then self:insert(t) end
end

return BoatSelect
