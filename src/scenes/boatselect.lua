-- src/scenes/boatselect.lua
-- "Velg båten din": pick a boat (with a Kjøp/lock state for premium boats) and
-- name it on a chunky, child-friendly on-screen keyboard (with ÆØÅ) -- no reliance
-- on the OS keyboard, so it works the same on an iPad. Reached from "set sail".

local config  = require("src.config")
local Assets  = require("src.assets")
local Retro   = require("src.ui.retro")
local Objects = require("src.systems.objects")
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
    self.edited = (game.state.boatName ~= nil)   -- has the player personalised it?
    local boats = game.data.boats
    self.index = 1
    for i, b in ipairs(boats) do
        if b.id == game.state.selectedBoat then self.index = i end
    end
    self.name = game.state.boatName or boats[self.index].name
    self.bought = 0                              -- "Kjøpt!" flash timer
    self.offer = false                           -- the premium-pack offer card, when up
end

function BoatSelect:def() return self.game.data.boats[self.index] end
function BoatSelect:owned() return self.game:ownsBoat(self:def().id) end
function BoatSelect:displayName() return upperFirst(self.name) end

function BoatSelect:update(dt)
    self.t = self.t + dt
    if self.bought > 0 then self.bought = self.bought - dt end
end

function BoatSelect:cycle(d)
    local n = #self.game.data.boats
    self.index = ((self.index - 1 + d) % n) + 1
    if not self.edited then self.name = self:def().name end   -- show each boat's own name
    Assets.playSfx("leave", 0.5)
end

function BoatSelect:selectBoat(i)
    if i == self.index then return end
    self.index = i
    if not self.edited then self.name = self:def().name end
    Assets.playSfx("leave", 0.5)
end

function BoatSelect:randomName()
    self.name = NAMES[love.math.random(#NAMES)]
    self.edited = true
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
function BoatSelect:primary()
    if self:owned() then self:setSail() else self.offer = true end
end

-- Buy the whole premium pack (pretend for now -- Game:unlockPremium just flips the
-- flag; real App Store IAP plugs in there later). Unlocks ALL premium boats at once.
function BoatSelect:confirmPurchase()
    self.game:unlockPremium()
    self.offer = false
    self.bought = 1.6
    Assets.playSfx("coin", 0.9)
end

function BoatSelect:setSail()
    local def = self:def()
    local nm = upperFirst((self.name or ""):gsub("^%s+", ""):gsub("%s+$", ""))
    self.game.state.selectedBoat = def.id
    self.game.state.boatName = (nm ~= "") and nm or def.name
    self.game:save()
    Assets.setMusicVolume(1.0)
    self.game:setScene("loading")
end

function BoatSelect:back() self.game:setScene("menu") end

-- ---- layout ---------------------------------------------------------------

function BoatSelect:layout()
    local sw, sh = love.graphics.getDimensions()
    local k = sh / 800
    local cx = sw / 2
    local ed = self.editing
    local previewY = math.floor(sh * (ed and 0.24 or 0.32))
    local previewW = math.min(sw * (ed and 0.30 or 0.42), (ed and 230 or 320) * k)
    local nameW, nameH, gap, nyttW = 340 * k, 54 * k, 12 * k, 150 * k
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

    return {
        k = k, cx = cx, previewY = previewY, previewW = previewW,
        statsY = math.floor(sh * 0.57),
        strip = strip,
        nameBox = { x = gx, y = math.floor(sh * 0.64), w = nameW, h = nameH },
        nytt = { x = gx + nameW + gap, y = math.floor(sh * 0.64), w = nyttW, h = nameH },
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
    local k = sh / 800
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

local function button(r, label, font)
    local t = math.max(2, math.floor(r.h * 0.12))
    Retro.bevel(r.x, r.y, r.w, r.h, hover(r) and W.hi or W.face, W.hi, W.lo, t, true)
    love.graphics.setFont(font); love.graphics.setColor(W.text)
    love.graphics.print(label, r.x + r.w / 2 - font:getWidth(label) / 2, r.y + r.h / 2 - font:getHeight() / 2)
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
    if def.frames and Objects.hasBoatFrames(def.frames) then
        -- spin the rendered 3D-model frames like a turntable (centred in the preview)
        local tint = owned and { 1, 1, 1 } or { 0.5, 0.52, 0.56 }
        love.graphics.push()
        love.graphics.translate(L.cx, L.previewY + bob)
        Objects.drawBoatFrames(def.frames, 0, 0, self.t * 0.7, L.previewW * 1.1,
            def.frameOffset, def.frameCW, tint, 0.5)
        love.graphics.pop()
    elseif def.model then
        -- spin the volumetric "3D" boat like a turntable to show it off
        local col = owned and def.color or { 0.5, 0.52, 0.56 }
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
            if owned then love.graphics.setColor(1, 1, 1) else love.graphics.setColor(0.45, 0.47, 0.52) end
            love.graphics.draw(img, L.cx, L.previewY + bob, 0, scale, scale, img:getWidth() / 2, img:getHeight() / 2)
        else
            love.graphics.setColor(def.color)
            love.graphics.ellipse("fill", L.cx, L.previewY + bob, L.previewW * 0.4, L.previewW * 0.18)
        end
    end
    if not owned then
        local s, lx, ly = 26 * L.k, L.cx, L.previewY + bob
        love.graphics.setColor(W.lo); love.graphics.setLineWidth(math.max(2, 5 * L.k))
        love.graphics.arc("line", "open", lx, ly - s * 0.2, s * 0.5, math.pi, 2 * math.pi)
        love.graphics.setColor(W.accent); love.graphics.rectangle("fill", lx - s * 0.6, ly - s * 0.2, s * 1.2, s, 4, 4)
        love.graphics.setColor(W.lo); love.graphics.circle("fill", lx, ly + s * 0.25, s * 0.14)
        love.graphics.setLineWidth(1)
    end
end

-- One boat in the filmstrip: framed thumbnail, gold frame if selected, padlock if
-- it's a locked premium boat (so its "fanciness" is on show to entice buying).
function BoatSelect:drawThumb(r, def, i)
    local owned = self.game:ownsBoat(def.id)
    local sel = (i == self.index)
    local t = math.max(2, math.floor(r.h * 0.12))
    Retro.bevel(r.x, r.y, r.w, r.h, sel and W.hi or W.face, W.hi, W.lo, t, true)
    local hasFrames = def.frames and Objects.hasBoatFrames(def.frames)
    local img = (not def.model and not hasFrames) and def.sprite and Assets.image("boats/" .. def.sprite)
    if hasFrames then
        love.graphics.push()
        love.graphics.translate(r.x + r.w / 2, r.y + r.h * 0.85)
        Objects.drawBoatFrames(def.frames, 0, 0, -0.6, r.w * 0.78,
            def.frameOffset, def.frameCW, owned and { 1, 1, 1 } or { 0.5, 0.52, 0.56 })
        love.graphics.pop()
    elseif def.model then
        love.graphics.push()
        love.graphics.translate(r.x + r.w / 2, r.y + r.h * 0.62)
        local s = r.h / 56
        love.graphics.scale(s, s)
        Objects.drawYacht(0, 0, -0.7, owned and def.color or { 0.5, 0.52, 0.56 }, 1.0, 0)
        love.graphics.pop()
    elseif img then
        if img:getFilter() ~= "linear" then img:setFilter("linear", "linear") end
        local pad = t * 2
        local s = math.min((r.w - pad * 2) / img:getWidth(), (r.h - pad * 2) / img:getHeight())
        if owned then love.graphics.setColor(1, 1, 1) else love.graphics.setColor(0.5, 0.52, 0.56) end
        love.graphics.draw(img, r.x + r.w / 2, r.y + r.h / 2, 0, s, s, img:getWidth() / 2, img:getHeight() / 2)
    else
        love.graphics.setColor(def.color)
        love.graphics.ellipse("fill", r.x + r.w / 2, r.y + r.h / 2, r.w * 0.35, r.h * 0.25)
    end
    if sel then
        love.graphics.setColor(W.accent); love.graphics.setLineWidth(math.max(2, 3 * (r.h / 100)))
        love.graphics.rectangle("line", r.x, r.y, r.w, r.h); love.graphics.setLineWidth(1)
    end
    if not owned then
        local s = r.h * 0.30
        local lx, ly = r.x + r.w - s * 0.8, r.y + s * 0.8
        love.graphics.setColor(W.lo); love.graphics.setLineWidth(math.max(2, s * 0.16))
        love.graphics.arc("line", "open", lx, ly - s * 0.18, s * 0.30, math.pi, 2 * math.pi)
        love.graphics.setColor(W.accent); love.graphics.rectangle("fill", lx - s * 0.38, ly - s * 0.18, s * 0.76, s * 0.55, 2, 2)
        love.graphics.setLineWidth(1)
    end
end

-- The premium-pack offer card ("Kaptein-pakken"): one purchase unlocks all the
-- fancy boats (and future maps/extras). Laid out top-down so it always fits.
function BoatSelect:offerLayout()
    local sw, sh = love.graphics.getDimensions()
    local k = sh / 800
    local P = config.PREMIUM
    local pw = math.min(sw * 0.72, 560 * k)
    local pad, lineH, btnH = 26 * k, 38 * k, 74 * k
    local y = pad
    local titleY = y; y = y + 44 * k + 16 * k
    local perkY = y;  y = y + #P.perks * lineH + 16 * k
    local subY = y;   y = y + 22 * k + 12 * k
    local kjopY = y;  y = y + btnH + 12 * k
    local tilbakeY = y; y = y + 46 * k + pad
    local ph = y
    local px, py = (sw - pw) / 2, (sh - ph) / 2
    return {
        k = k, x = px, y = py, w = pw, h = ph, lineH = lineH,
        titleY = py + titleY, perkY = py + perkY, subY = py + subY,
        kjop = { x = px + pw / 2 - 170 * k, y = py + kjopY, w = 340 * k, h = btnH },
        tilbake = { x = px + pw / 2 - 95 * k, y = py + tilbakeY, w = 190 * k, h = 46 * k },
    }
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

    love.graphics.setFont(fonts.normal)
    local py = O.perkY
    for _, perk in ipairs(P.perks) do
        love.graphics.setColor(W.accent); love.graphics.print("*", O.x + 54 * O.k, py)
        love.graphics.setColor(W.text); love.graphics.print(perk, O.x + 84 * O.k, py)
        py = py + O.lineH
    end

    love.graphics.setFont(fonts.small); love.graphics.setColor(W.text)
    local sub = "Betal én gang"
    love.graphics.print(sub, O.x + O.w / 2 - fonts.small:getWidth(sub) / 2, O.subY)

    button(O.kjop, "Kjøp  " .. P.price, fonts.big)
    button(O.tilbake, "Tilbake", fonts.small)
    love.graphics.setColor(1, 1, 1)
end

function BoatSelect:draw()
    local sw, sh = love.graphics.getDimensions()
    local fonts = self.game.fonts
    local L = self:layout()
    local def = self:def()

    love.graphics.clear(config.colors.water_deep)
    local wv = config.colors.wave
    love.graphics.setColor(wv[1], wv[2], wv[3], 0.35)
    for yy = 0, sh, math.floor(28 * L.k) do
        love.graphics.rectangle("fill", 0, yy, sw, math.floor(3 * L.k))
    end

    love.graphics.setFont(fonts.title); love.graphics.setColor(W.text)
    local title = "Velg båten din"
    love.graphics.print(title, L.cx - fonts.title:getWidth(title) / 2, math.floor(sh * 0.06))

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
        statBar("Plass", def.capacity / 8, sx, L.statsY + 28 * L.k, 300 * L.k, fonts.small)

        nameField(L.nameBox, self:displayName(), false, fonts.normal)
        button(L.nytt, "Nytt navn", fonts.small)
        button(L.sail, self:owned() and "Sett seil!" or "Lås opp", fonts.big)
        button(L.back, "Tilbake", fonts.small)
    end

    if self.offer then self:drawOffer() end

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
        if hit(O.kjop, x, y) then self:confirmPurchase()
        elseif hit(O.tilbake, x, y) then self.offer = false end
        return
    end
    if self.editing then
        for _, key in ipairs(self:keyLayout()) do
            if hit(key, x, y) then
                if key.kind == "letter" then self:insert(key.label)
                elseif key.kind == "back" then self:backspace()
                elseif key.kind == "space" then self:insert(" ")
                elseif key.kind == "done" then self.editing = false end
                return
            end
        end
        return
    end
    local L = self:layout()
    for i, r in ipairs(L.strip) do
        if hit(r, x, y) then self:selectBoat(i); return end
    end
    if hit(L.nytt, x, y) then self:randomName()
    elseif hit(L.nameBox, x, y) then self.editing = true
    elseif hit(L.sail, x, y) then self:primary()
    elseif hit(L.back, x, y) then self:back() end
end

function BoatSelect:keypressed(key)
    if self.offer then
        if key == "escape" then self.offer = false end
        return
    end
    if self.editing then
        if key == "return" or key == "kpenter" or key == "escape" then self.editing = false
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
