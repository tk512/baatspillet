-- src/scenes/menu.lua
-- Title screen in an early-90s strategy-game style: the scene sits inside a
-- chunky beveled wooden frame over a dithered pixel sky, sun and horizon
-- islands. The title bounces in letter by letter, a recorded voice (my kid)
-- says it once, then a water splash erupts. The "Klar til å sette seil" button
-- is a carved wooden sign swaying on ropes. Keyboard (Enter/Space) or mouse.

local config = require("src.config")
local Assets = require("src.assets")
local Retro  = require("src.ui.retro")
local utf8   = require("utf8")

local Menu = {}

local TAU  = math.pi * 2
local WOOD = Retro.WOOD

-- Bayer 4x4 ordered-dither matrix (0..15), for the crosshatched VGA gradients.
local BAYER = {
    { 0, 8, 2, 10 }, { 12, 4, 14, 6 }, { 3, 11, 1, 9 }, { 15, 7, 13, 5 },
}

-- Elastic ease: overshoots 1 then wobbles back, for a letter springing in.
local function easeOutElastic(p)
    if p <= 0 then return 0 end
    if p >= 1 then return 1 end
    local c4 = TAU / 3
    return 2 ^ (-10 * p) * math.sin((p * 10 - 0.75) * c4) + 1
end

local function clamp01(x)
    if x < 0 then return 0 end
    if x > 1 then return 1 end
    return x
end

local function lerp(a, b, t) return a + (b - a) * t end

-- Split a string into a list of UTF-8 characters (so "å" is one letter).
local function splitChars(s)
    local t = {}
    for _, code in utf8.codes(s) do t[#t + 1] = utf8.char(code) end
    return t
end

-- Biggest font for `text` that still fits within targetW (capped at maxSize).
local function fitFont(text, targetW, maxSize)
    local size = math.floor(maxSize)
    local f = love.graphics.newFont(size)
    local w = f:getWidth(text)
    if w > targetW then
        size = math.max(8, math.floor(size * targetW / w))
        f = love.graphics.newFont(size)
    end
    return f
end

function Menu:load(game)
    self.game = game
    self.t = 0
    Assets.stopDockMood()      -- in case we came straight from a dock
    Assets.stopChase()         -- ...or a pirate chase

    -- Welcome fonts sized to the screen.
    local sw, sh = love.graphics.getWidth(), love.graphics.getHeight()
    self.welcomeFont = fitFont("Velkommen til", sw * 0.48, sh * 0.12)
    self.titleFont   = fitFont("Båtspillet!",   sw * 0.75, sh * 0.30)
    self.welcomeText, self.welcomeChars = "Velkommen til", splitChars("Velkommen til")
    self.titleText,   self.titleChars   = "Båtspillet!",   splitChars("Båtspillet!")

    -- carved-sign label font, sized to the wooden plank
    local _, _, bw, bh = self:buttonRect()
    self.signFont = fitFont("Klar til å sette seil", bw * 0.84, bh * 0.6)

    -- The game's artist, my boy Finn-Erik, waves from the bottom-right corner.
    self.artist = Assets.image("menu/finnerik.png")
    if self.artist then self.artist:setFilter("nearest", "nearest") end

    -- a few small pixel sailboats drifting across the sea band
    self.boats = {}
    for i = 1, 4 do
        self.boats[i] = {
            x = love.math.random(0, sw),
            y = love.math.random(sh * 0.52, sh * 0.80),
            speed = love.math.random(16, 40),
            scale = love.math.random(70, 130) / 100,
            color = self.game.data.boats[love.math.random(#self.game.data.boats)].color,
        }
    end

    -- The real boat (his boat!) cruising big across the sea, left to right.
    local hw = sw * 0.24
    self.hero = { x = -hw, y = sh * 0.74, w = hw, speed = sw * 0.13 }

    -- A little shark (the toy, photographed) cruising the other way, low in the
    -- foreground water, chomping its jaw as it goes. Frames are pre-aligned by
    -- the snout (see tools/make_shark.py) so we just swap them in place. Friendly,
    -- not scary -- the harbours are always safe.
    self.sharkFrames = {}
    for i = 1, 4 do
        local img = Assets.image("shark/shark_" .. i .. ".png")   -- pixel-art: keep nearest
        self.sharkFrames[i] = img
    end
    if self.sharkFrames[1] then
        local sw2 = sw * 0.16
        self.shark = { x = sw + sw2, y = sh * 0.86, w = sw2, speed = sw * 0.06,
                       frames = { 1, 2, 3, 4, 3, 2 }, frameDur = 0.18 }
    end

    -- A Coast Guard helicopter that flies in after a short wait (5-10s), buzzing
    -- left-to-right across the sky with its rotors spun in code (the photo's static
    -- blades were cropped; see tools/make_heli.py). When it arrives, my boy's own
    -- "chopper" recording plays. It waits off-screen until startAt, then flies and
    -- wraps, sounding again each lap.
    if Assets.image("menu/helicopter.png") then
        local hw = sw * 0.20
        -- speed tuned so one crossing (~7.8s) matches the chopper clip's fade
        -- in/out, so the sound swells in as it enters and trails off as it leaves
        self.heli = { x = -hw, y = sh * 0.30, w = hw, speed = sw * 0.18,
                      startAt = 5 + love.math.random() * 5, flying = false }
    end

    -- The passenger action-figures playfully pop up from the bottom edge to peek,
    -- then duck back down -- each on its own gentle rhythm so it's never crowded
    -- (usually just one peeking at a time). My boy loves a peek-a-boo.
    self.passengerImgs = {}
    for i = 1, 4 do self.passengerImgs[i] = Assets.image("icons/passenger" .. i .. ".png") end
    self.peekers = {}
    if self.passengerImgs[1] then
        local slots = { 0.14, 0.33, 0.54, 0.70 }
        for i, fx in ipairs(slots) do
            self.peekers[i] = {
                fig     = ((i - 1) % 4) + 1,
                x       = sw * fx,
                offset  = i * 2.3,                 -- staggered starts
                period  = 8.5 + i * 0.9,           -- each its own rhythm
                peekDur = 2.4,                     -- how long a peek lasts
                sway    = love.math.random() * TAU,
            }
        end
    end

    -- Voice first (words bounce in to match), then the splash + wave crash.
    self.splash = {}
    self.splashFired = false
    Assets.playVoice("velkommen")   -- my kid: "Velkommen til Båtspillet!"

    -- Splash right after the voice finishes; if there's no voice (or audio off),
    -- splash once the words land.
    local v = Assets.voice and Assets.voice.velkommen
    if v and config.AUDIO_ON then
        self.splashAt = v:getDuration() + 0.1
        Assets.setMusicVolume(0.25)  -- duck the music under the voice
    else
        self.splashAt = 1.8
    end

    collectgarbage("collect")
end

-- The frame, sky, sea, sun and islands never move, so we bake them once into a
-- small ~VGA canvas and upscale with a nearest filter. That gives a uniform
-- mid-90s pixel density on any monitor without hand-tuned block sizes. Only the
-- waves/boats/splash/title animate, drawn crisp at full res on top.
local VRES_H = 540   -- virtual scanlines (between VGA 480 and SVGA 600)

-- A clean pixel disc (every virtual pixel inside the radius), filled at vres.
local function pixelDisc(cx, cy, r, col)
    love.graphics.setColor(col)
    local r2 = r * r
    for by = -r, r do
        local span = math.floor(math.sqrt(math.max(0, r2 - by * by)))
        if span > 0 then
            love.graphics.rectangle("fill", cx - span, cy + by, span * 2, 1)
        end
    end
end

-- A smooth pixel hill (parabola), lighter band along the grassy top.
local function pixelHill(cx, baseY, halfW, height, col, top)
    for bx = -halfW, halfW do
        local f = bx / halfW
        local hh = math.floor(height * (1 - f * f))
        if hh > 0 then
            love.graphics.setColor(col)
            love.graphics.rectangle("fill", cx + bx, baseY - hh, 1, hh)
            love.graphics.setColor(top)                 -- sunlit crest
            love.graphics.rectangle("fill", cx + bx, baseY - hh, 1, math.max(1, hh * 0.18))
        end
    end
end

-- A soft pixel cloud: a few overlapping discs with a dithered flat bottom.
local function pixelCloud(cx, cy, w)
    local white = { 0.97, 0.98, 1.0 }
    pixelDisc(cx, cy, w * 0.5, white)
    pixelDisc(cx - w * 0.5, cy + w * 0.12, w * 0.34, white)
    pixelDisc(cx + w * 0.55, cy + w * 0.10, w * 0.38, white)
    pixelDisc(cx + w * 0.12, cy - w * 0.18, w * 0.30, white)
    love.graphics.setColor(0.86, 0.90, 0.96)            -- soft underside shadow
    love.graphics.rectangle("fill", cx - w * 0.8, cy + w * 0.30, w * 1.6, 1)
end

function Menu:buildBackground(sw, sh)
    local VH = VRES_H
    local sx_s, sy_s = sw / VH, sh / VH    -- per-axis upscale (fills exactly)
    local VW = math.floor(sw / sx_s + 0.5)

    local fw = math.floor(math.min(VW, VH) * 0.05)      -- frame border (vres px)
    local t1 = math.max(2, math.floor(fw * 0.34))       -- outer raised edge
    local t2 = math.max(1, math.floor(fw * 0.20))       -- inner sunken groove
    local sx, sy = fw + t2, fw + t2
    local sceneW, sceneH = VW - 2 * sx, VH - 2 * sy
    local horizonY = sy + math.floor(sceneH * 0.46)

    local cv = love.graphics.newCanvas(VW, VH)
    cv:setFilter("nearest", "nearest")
    love.graphics.setCanvas(cv)
    love.graphics.clear(0, 0, 0, 0)
    love.graphics.setColor(1, 1, 1, 1)

    -- wooden frame slab + sunken inner well (the scene sits inside the well)
    Retro.bevel(0, 0, VW, VH, WOOD.face, WOOD.hi, WOOD.lo, t1, true)
    Retro.bevel(fw, fw, VW - 2 * fw, VH - 2 * fw, WOOD.deep, WOOD.hi, WOOD.lo, t2, false)

    -- Dithered sky: a blue-to-pale gradient, crosshatched with the Bayer matrix.
    local skyTop = { 0.36, 0.60, 0.88 }
    local skyLow = { 0.82, 0.90, 0.96 }
    local levels = 10
    for yy = sy, horizonY - 1 do
        local f = (yy - sy) / (horizonY - sy)
        local fl = f * levels
        local idx = math.floor(fl)
        local frac = fl - idx
        local c0 = idx / levels
        local c1 = math.min(1, (idx + 1) / levels)
        local row = (yy % 4) + 1
        for xx = sx, sx + sceneW - 1 do
            local thresh = (BAYER[row][(xx % 4) + 1] + 0.5) / 16
            local m = frac > thresh and c1 or c0
            love.graphics.setColor(lerp(skyTop[1], skyLow[1], m), lerp(skyTop[2], skyLow[2], m),
                lerp(skyTop[3], skyLow[3], m))
            love.graphics.rectangle("fill", xx, yy, 1, 1)
        end
    end

    -- Dithered sea: water_top at the horizon down to water_deep at the bottom.
    local wTop, wDeep = config.colors.water_top, config.colors.water_deep
    local seaBottom = sy + sceneH - 1
    for yy = horizonY, seaBottom do
        local f = (yy - horizonY) / (seaBottom - horizonY)
        local fl = f * 8
        local idx = math.floor(fl)
        local frac = fl - idx
        local row = (yy % 4) + 1
        for xx = sx, sx + sceneW - 1 do
            local thresh = (BAYER[row][(xx % 4) + 1] + 0.5) / 16
            local m = (idx + (frac > thresh and 1 or 0)) / 8
            love.graphics.setColor(lerp(wTop[1], wDeep[1], m), lerp(wTop[2], wDeep[2], m),
                lerp(wTop[3], wDeep[3], m))
            love.graphics.rectangle("fill", xx, yy, 1, 1)
        end
    end

    -- a few drifting clouds high in the sky
    pixelCloud(sx + sceneW * 0.24, sy + sceneH * 0.14, sceneW * 0.12)
    pixelCloud(sx + sceneW * 0.55, sy + sceneH * 0.08, sceneW * 0.08)

    -- sun (upper right) with a soft layered glow
    local sunX, sunY = sx + sceneW * 0.81, sy + sceneH * 0.18
    local sunR = math.floor(sceneH * 0.075)
    love.graphics.setColor(1, 0.95, 0.7, 0.12); love.graphics.circle("fill", sunX, sunY, sunR * 2.2)
    love.graphics.setColor(1, 0.96, 0.76, 0.22); love.graphics.circle("fill", sunX, sunY, sunR * 1.5)
    pixelDisc(sunX, sunY, sunR, { 1.0, 0.93, 0.62 })
    pixelDisc(sunX - sunR * 0.28, sunY - sunR * 0.28, sunR * 0.5, { 1.0, 0.98, 0.82 })

    -- shimmering sun reflection straight down onto the water
    for i = 0, 22 do
        local ry = horizonY + i * (sceneH * 0.018)
        if ry < seaBottom then
            local w = sunR * (0.5 + i * 0.05)
            love.graphics.setColor(1, 0.95, 0.7, 0.20 * (1 - i / 24))
            love.graphics.rectangle("fill", sunX - w / 2, ry, w, 1)
        end
    end

    -- islands on the horizon (grass crest over a sandy beach base)
    local grass, gdk = config.colors.grass.top, config.colors.grass.lip
    local sand = config.colors.sand.top
    local function island(cx, halfW, height)
        pixelHill(cx, horizonY + math.floor(sceneH * 0.01), halfW, math.floor(height * 0.35), sand, sand)
        pixelHill(cx, horizonY, halfW * 0.84, height, gdk, grass)
    end
    island(sx + sceneW * 0.17, sceneW * 0.11, sceneH * 0.15)
    island(sx + sceneW * 0.46, sceneW * 0.07, sceneH * 0.09)
    island(sx + sceneW * 0.90, sceneW * 0.12, sceneH * 0.19)

    -- a little lighthouse standing ON the left island's crest
    local lhX = sx + sceneW * 0.21
    local lhBase = horizonY - math.floor(sceneH * 0.10)
    local lhW = math.max(2, math.floor(sceneW * 0.012))
    local lhH = math.floor(sceneH * 0.12)
    local stripe = math.max(2, math.floor(lhH / 6))
    for k = 0, math.floor(lhH / stripe) - 1 do
        love.graphics.setColor(k % 2 == 0 and { 0.88, 0.32, 0.28 } or { 0.94, 0.92, 0.88 })
        love.graphics.rectangle("fill", lhX - lhW / 2, lhBase - (k + 1) * stripe, lhW, stripe)
    end
    love.graphics.setColor(0.30, 0.26, 0.22)            -- lantern housing
    love.graphics.rectangle("fill", lhX - lhW * 0.7, lhBase - lhH - stripe, lhW * 1.4, stripe)
    love.graphics.setColor(0.99, 0.90, 0.5)             -- lamp glow
    love.graphics.rectangle("fill", lhX - lhW * 0.4, lhBase - lhH - stripe * 0.7, lhW * 0.8, stripe * 0.5)

    love.graphics.setCanvas()
    love.graphics.setColor(1, 1, 1, 1)
    -- scene rect in screen coords (the animated layer draws at full res)
    self.bgScaleX, self.bgScaleY = sx_s, sy_s
    self.scene = {
        x = sx * sx_s, y = sy * sy_s, w = sceneW * sx_s, h = sceneH * sy_s,
        horizon = horizonY * sy_s, blk = math.max(2, sy_s),
    }
    return cv
end

-- A burst of water droplets + foam erupting from the middle of the screen.
function Menu:spawnSplash()
    local cx = love.graphics.getWidth() / 2
    local cy = love.graphics.getHeight() * 0.40
    for i = 1, 140 do
        local ang = -math.pi / 2 + (love.math.random() - 0.5) * 2.4  -- mostly upward
        local spd = love.math.random(220, 720)
        local kind = love.math.random()
        self.splash[i] = {
            x = cx + (love.math.random() - 0.5) * 60,
            y = cy,
            vx = math.cos(ang) * spd,
            vy = math.sin(ang) * spd,
            life = 0,
            ttl = love.math.random(0.7, 1.6),
            r = love.math.random(2, 6),
            -- mostly water-blue, some white foam, a few gold sparkles
            foam = kind > 0.65,
            gold = kind > 0.92,
        }
    end
end

function Menu:update(dt)
    self.t = self.t + dt
    local w = love.graphics.getWidth()
    for _, b in ipairs(self.boats) do
        b.x = b.x + b.speed * dt
        if b.x > w + 30 then b.x = -30 end
    end

    -- The big hero boat sails across and wraps back around.
    if self.hero then
        self.hero.x = self.hero.x + self.hero.speed * dt
        if self.hero.x - self.hero.w > w then self.hero.x = -self.hero.w end
    end

    -- The shark glides the other way (right to left) and wraps back around.
    if self.shark then
        self.shark.x = self.shark.x - self.shark.speed * dt
        if self.shark.x + self.shark.w < 0 then self.shark.x = w + self.shark.w end
    end

    -- The helicopter waits off-screen, then flies in (chopper sound on arrival)
    -- and buzzes left-to-right, wrapping back around and sounding again each lap.
    if self.heli then
        if not self.heli.flying then
            if self.t >= self.heli.startAt then
                self.heli.flying = true
                Assets.playSfx("chopper", 1.0)
            end
        else
            self.heli.x = self.heli.x + self.heli.speed * dt
            if self.heli.x - self.heli.w > w then
                self.heli.x = -self.heli.w
                Assets.playSfx("chopper", 1.0)   -- here it comes again
            end
        end
    end

    -- After the voice finishes: erupt the splash + crash, restore the music.
    if not self.splashFired and self.t >= self.splashAt then
        self.splashFired = true
        self:spawnSplash()
        Assets.playSfx("wave_crash")
        Assets.setMusicVolume(1.0)
    end

    -- Splash droplets: arc out under gravity, then fade.
    for _, p in ipairs(self.splash) do
        p.life = p.life + dt
        p.vy = p.vy + 1400 * dt          -- gravity
        p.x = p.x + p.vx * dt
        p.y = p.y + p.vy * dt
    end
end

-- The sign's plank rectangle, also the click hit-box. The sway is tiny enough
-- that testing the un-swayed rect is plenty accurate.
function Menu:buttonRect()
    local sw, sh = love.graphics.getWidth(), love.graphics.getHeight()
    local bw = math.min(math.floor(sw * 0.44), 600)   -- wide enough for the longer label
    local bh = math.floor(bw * 0.22)
    return sw / 2 - bw / 2, math.floor(sh * 0.66), bw, bh
end

-- Draw a string letter-by-letter, each letter springing in (elastic bounce)
-- with a staggered delay and a gentle ongoing wobble. Centered on cx.
function Menu:bouncyText(font, text, chars, cx, baselineY, startDelay, hueBase)
    love.graphics.setFont(font)
    local total = font:getWidth(text)
    local x = cx - total / 2
    local perLetter = 0.06           -- stagger between letters
    for i = 1, #chars do
        local ch = chars[i]
        local cw = font:getWidth(ch)
        if ch ~= " " then
            local appear = (self.t - startDelay - (i - 1) * perLetter)
            local p = clamp01(appear / 0.7)
            local e = easeOutElastic(p)
            -- Bounce is a vertical drop-in plus a gentle bob; letters stay full
            -- size so they can never end up shrunken.
            local dropY = (1 - e) * -font:getHeight() * 0.6
            local settle = clamp01(appear)
            local bob = math.sin(self.t * 3 + i * 0.5) * 8 * settle
            -- cheerful shifting colors
            local hue = hueBase + i * 0.7 + self.t * 1.5
            local r = 0.6 + 0.4 * math.sin(hue)
            local g = 0.6 + 0.4 * math.sin(hue + 2.1)
            local bl = 0.6 + 0.4 * math.sin(hue + 4.2)
            local lx = x + cw / 2
            local ly = baselineY + dropY + bob
            local ox, oy = cw / 2, font:getHeight() / 2
            -- soft drop shadow for depth
            love.graphics.setColor(0, 0, 0, 0.35)
            love.graphics.print(ch, lx + 6, ly + 8, 0, 1, 1, ox, oy)
            -- dark outline: a tight ring of copies (small radius reads as a
            -- solid stroke, not separate ghost letters)
            local ow = math.max(2, font:getHeight() * 0.018)
            love.graphics.setColor(0.04, 0.06, 0.10)
            for k = 0, 11 do
                local a = k / 12 * TAU
                love.graphics.print(ch, lx + math.cos(a) * ow, ly + math.sin(a) * ow,
                    0, 1, 1, ox, oy)
            end
            -- bright cheerful letter on top
            love.graphics.setColor(r, g, bl)
            love.graphics.print(ch, lx, ly, 0, 1, 1, ox, oy)
        end
        x = x + cw
    end
end

-- A small pixel sailboat (hull + single sail) for the distant drifting boats.
local function miniBoat(x, y, s, col)
    love.graphics.setColor(1, 1, 1, 0.35)
    love.graphics.ellipse("fill", x, y + 7 * s, 16 * s, 3 * s)            -- reflection
    love.graphics.setColor(0.97, 0.96, 0.92)
    love.graphics.polygon("fill", x, y - 16 * s, x, y + 2 * s, x + 11 * s, y + 2 * s) -- sail
    love.graphics.setColor(0.30, 0.24, 0.18)
    love.graphics.rectangle("fill", x - 0.8 * s, y - 16 * s, 1.6 * s, 18 * s)        -- mast
    love.graphics.setColor(col)
    love.graphics.polygon("fill", x - 13 * s, y + 2 * s, x + 13 * s, y + 2 * s,
        x + 8 * s, y + 8 * s, x - 8 * s, y + 8 * s)                       -- hull
end

-- Cheap, busy-looking main rotor: a short mast, a faint swept disc, then a few
-- motion-blur "ghosts" of two blades sweeping a flattened (side-on) ellipse, and
-- a hub cap. halfW is the blade reach; the y-squash makes it read as a top rotor
-- seen almost edge-on.
function Menu:drawRotor(cx, cy, halfW)
    local squash = 0.16
    love.graphics.setColor(0.15, 0.15, 0.17)              -- short mast up to the hub
    love.graphics.setLineWidth(3)
    love.graphics.line(cx, cy + halfW * squash + 4, cx, cy)
    love.graphics.setColor(0.90, 0.92, 0.95, 0.16)        -- faint swept disc
    love.graphics.ellipse("fill", cx, cy, halfW, halfW * squash)
    local spin = self.t * 18
    for k = 0, 2 do                                        -- 3 ghosts = motion blur
        love.graphics.setColor(0.10, 0.10, 0.12, 0.55 - k * 0.16)
        love.graphics.setLineWidth(3)
        local a = spin - k * 0.45
        for b = 0, 1 do
            local ang = a + b * math.pi
            love.graphics.line(cx, cy, cx + math.cos(ang) * halfW, cy + math.sin(ang) * halfW * squash)
        end
    end
    love.graphics.setColor(0.20, 0.20, 0.22); love.graphics.circle("fill", cx, cy, 3)
    love.graphics.setLineWidth(1); love.graphics.setColor(1, 1, 1)
end

-- The tail rotor, seen face-on from the side: a small spinning disc of blades.
function Menu:drawTailRotor(cx, cy, r)
    love.graphics.setColor(0.85, 0.88, 0.92, 0.15)
    love.graphics.circle("fill", cx, cy, r)
    local spin = self.t * 24
    for k = 0, 2 do
        love.graphics.setColor(0.10, 0.10, 0.12, 0.5 - k * 0.15)
        love.graphics.setLineWidth(2)
        local a = spin - k * 0.5
        for b = 0, 1 do
            local ang = a + b * math.pi
            love.graphics.line(cx, cy, cx + math.cos(ang) * r, cy + math.sin(ang) * r)
        end
    end
    love.graphics.setLineWidth(1); love.graphics.setColor(1, 1, 1)
end

function Menu:draw()
    local c = config.colors
    local sw, sh = love.graphics.getWidth(), love.graphics.getHeight()

    -- (Re)bake the static framed background if missing or the window resized.
    if not self.bg or self.bgW ~= sw or self.bgH ~= sh then
        self.bg, self.bgW, self.bgH = self:buildBackground(sw, sh), sw, sh
    end
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(self.bg, 0, 0, 0, self.bgScaleX, self.bgScaleY)   -- upscale VGA canvas

    -- Everything that moves is clipped to the inner scene (so it never spills
    -- over the wooden frame).
    local S = self.scene
    love.graphics.setScissor(S.x, S.y, S.w, S.h)

    -- gently rolling foam wave-rows over the sea
    for r = 1, 6 do
        local wy = S.horizon + (S.h - (S.horizon - S.y)) * (r / 8)
        local spacing = S.w * 0.09
        local off = (self.t * (18 + r * 6)) % spacing
        love.graphics.setColor(c.foam[1], c.foam[2], c.foam[3], 0.10 + r * 0.015)
        for x = S.x - spacing, S.x + S.w, spacing do
            local dx = x + off + (r % 2) * spacing * 0.5
            love.graphics.rectangle("fill", dx, wy, spacing * 0.5, math.max(2, S.blk * 0.6))
        end
    end

    -- distant drifting pixel sailboats
    for _, b in ipairs(self.boats) do
        miniBoat(b.x, b.y, b.scale, b.color)
    end

    -- The big hero boat (real photo) gliding across the sea.
    local boatImg = Assets.image("boats/boat1.png")
    if boatImg and self.hero then
        boatImg:setFilter("linear", "linear")           -- smooth (it's a photo)
        local scale = self.hero.w / boatImg:getWidth()
        local bob = math.sin(self.t * 1.4) * 8
        local hx, hy = self.hero.x, self.hero.y + bob
        -- soft shadow + a little wake behind it
        love.graphics.setColor(0, 0, 0, 0.14)
        love.graphics.ellipse("fill", hx, hy + 4, self.hero.w * 0.45, self.hero.w * 0.07)
        love.graphics.setColor(1, 1, 1, 0.5)
        for k = 1, 5 do
            love.graphics.ellipse("fill", hx - self.hero.w * (0.45 + k * 0.06), hy + 4, 6, 3)
        end
        love.graphics.setColor(1, 1, 1)
        love.graphics.draw(boatImg, hx, hy, 0, scale, scale,
            boatImg:getWidth() / 2, boatImg:getHeight() * 0.85)
    end

    -- The chomping shark, low in the foreground water (drawn over the boat so it
    -- reads as nearer the viewer). It already faces left, which is the way it
    -- swims, so no flip is needed.
    if self.shark then
        local frame = self.shark.frames[math.floor(self.t / self.shark.frameDur) % #self.shark.frames + 1]
        local img = self.sharkFrames[frame]
        if img then
            local scale = self.shark.w / img:getWidth()
            local ih = img:getHeight() * scale
            local bob = math.sin(self.t * 1.3) * 6
            local pitch = math.sin(self.t * 1.6) * 0.03         -- gentle swim wobble
            local sx, sy = self.shark.x, self.shark.y + bob
            -- soft shadow + a few ripples trailing behind the tail (to the right)
            love.graphics.setColor(0, 0, 0, 0.12)
            love.graphics.ellipse("fill", sx, sy + ih * 0.30, self.shark.w * 0.42, ih * 0.10)
            love.graphics.setColor(1, 1, 1, 0.45)
            for k = 1, 4 do
                love.graphics.ellipse("fill", sx + self.shark.w * (0.45 + k * 0.05), sy, 5, 2.5)
            end
            love.graphics.setColor(1, 1, 1)
            love.graphics.draw(img, sx, sy, pitch, scale, scale,
                img:getWidth() / 2, img:getHeight() / 2)
        end
    end

    -- The Coast Guard helicopter crossing the sky, rotors spinning (drawn in
    -- code). It faces right, the way it flies, so no flip is needed. Only once it
    -- has flown in (after the initial wait).
    if self.heli and self.heli.flying then
        local img = Assets.image("menu/helicopter.png")
        if img then
            local scale = self.heli.w / img:getWidth()
            local ih = img:getHeight() * scale
            local bob = math.sin(self.t * 2.4) * 4
            local hx, hy = self.heli.x, self.heli.y + bob
            love.graphics.setColor(1, 1, 1)
            love.graphics.draw(img, hx, hy, 0, scale, scale,
                img:getWidth() / 2, img:getHeight() / 2)
            -- main rotor on top (hub just above the cabin roof) + small tail rotor
            self:drawRotor(hx - self.heli.w * 0.02, hy - ih * 0.5 - ih * 0.05, self.heli.w * 0.46)
            self:drawTailRotor(hx - self.heli.w * 0.46, hy - ih * 0.12, ih * 0.18)
        end
    end

    -- Passenger figures peeking up from the bottom edge (clipped by the scissor,
    -- so they rise out of the waterline and duck back down with a little wobble).
    local baseY = S.y + S.h
    for _, p in ipairs(self.peekers) do
        local cyc = (self.t + p.offset) % p.period
        local up = (cyc < p.peekDur) and math.sin(cyc / p.peekDur * math.pi) or 0
        if up > 0.01 then
            local img = self.passengerImgs[p.fig]
            local scale = (sw * 0.05) / img:getWidth()
            local show = img:getHeight() * scale * 0.62        -- how much shows at full peek
            local sway = math.sin(self.t * 3 + p.sway) * 0.05 * up
            love.graphics.setColor(1, 1, 1)
            love.graphics.draw(img, p.x, baseY - show * up, sway, scale, scale, img:getWidth() / 2, 0)
        end
    end

    -- splash droplets
    for _, p in ipairs(self.splash) do
        local a = clamp01(1 - p.life / p.ttl)
        if a > 0 then
            if p.gold then
                love.graphics.setColor(c.gold[1], c.gold[2], c.gold[3], a)
            elseif p.foam then
                love.graphics.setColor(1, 1, 1, a)
            else
                love.graphics.setColor(c.wave[1], c.wave[2], c.wave[3], a)
            end
            love.graphics.circle("fill", p.x, p.y, p.r)
        end
    end

    love.graphics.setScissor()

    -- the two big bouncing title lines, over the scene
    self:bouncyText(self.welcomeFont, self.welcomeText, self.welcomeChars, sw / 2, sh * 0.16, 0.10, 0.0)
    self:bouncyText(self.titleFont,   self.titleText,   self.titleChars,   sw / 2, sh * 0.42, 0.55, 3.0)

    -- wooden sign button (appears once the welcome has bounced in)
    local btnIn = clamp01((self.t - 1.6) / 0.5)
    if btnIn > 0 then self:drawSign(btnIn) end

    -- footer hint
    love.graphics.setFont(self.game.fonts.small)
    love.graphics.setColor(WOOD.text)
    local hint = "Trykk ENTER eller klikk for å starte   •   F11 = fullskjerm"
    love.graphics.print(hint, sw / 2 - self.game.fonts.small:getWidth(hint) / 2, sh * 0.93)

    self:drawArtist(sw, sh)   -- Finn-Erik, the game's artist, in the corner

    -- TEMPORARY preview button (see previewBtnRect)
    do
        local bx, by, bw, bh, label = self:previewBtnRect()
        local hover = self:pointInPreview(love.mouse.getPosition())
        Retro.bevel(bx, by, bw, bh, hover and WOOD.hi or WOOD.face, WOOD.hi, WOOD.lo, 3, true)
        love.graphics.setFont(self.game.fonts.small)
        love.graphics.setColor(WOOD.text)
        love.graphics.print(label, bx + (bw - self.game.fonts.small:getWidth(label)) / 2,
            by + (bh - self.game.fonts.small:getHeight()) / 2)
    end

    love.graphics.setColor(1, 1, 1)
end

function Menu:pointInPreview(mx, my)
    local bx, by, bw, bh = self:previewBtnRect()
    return mx >= bx and mx <= bx + bw and my >= by and my <= by + bh
end

-- Credit my boy Finn-Erik (the artist) peeking up from the bottom-right corner.
function Menu:drawArtist(sw, sh)
    if not config.SHOW_ARTIST_PHOTO then return end
    local img = self.artist
    if not img then return end
    local ih = sh * 0.34
    local scale = ih / img:getHeight()
    local iw = img:getWidth() * scale
    local x = sw - sw * 0.015 - iw            -- left edge (anchored to the right)
    local by = sh * 0.99                       -- his bottom near the screen bottom
    local y = by - ih
    local bob = math.sin(self.t * 1.6) * 4     -- gentle life

    love.graphics.setColor(0, 0, 0, 0.16)
    love.graphics.ellipse("fill", x + iw / 2, by - 2, iw * 0.40, 7)   -- soft shadow
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(img, x, y + bob, 0, scale, scale)

    -- "Spillkunstner / Finn-Erik" credit above his head
    local cx = x + iw / 2
    local fs, fn = self.game.fonts.small, self.game.fonts.normal
    local function center(font, txt, yy, col)
        love.graphics.setFont(font)
        local w = font:getWidth(txt)
        love.graphics.setColor(0, 0, 0, 0.5); love.graphics.print(txt, cx - w / 2 + 1, yy + 1)
        love.graphics.setColor(col);          love.graphics.print(txt, cx - w / 2, yy)
    end
    local ly2 = (y + bob) - fn:getHeight() - 4
    center(fs, "Spillkunstner", ly2 - fs:getHeight() - 1, WOOD.accent)
    center(fn, "Finn-Erik (5)", ly2,                      WOOD.text)
    love.graphics.setColor(1, 1, 1)
end

-- The carved wooden sign hanging from two ropes, swaying gently from a pivot
-- above. Brightens and sways a touch more on hover.
function Menu:drawSign(pop)
    local bx, by, bw, bh = self:buttonRect()
    local cx = bx + bw / 2
    local hover = self:pointInButton(love.mouse.getPosition())
    local t = math.max(2, math.floor(bh / 14))          -- bevel thickness
    local beamY = by - bh * 0.62                          -- rope pivot above plank
    local sway = math.sin(self.t * 1.1) * (hover and 0.045 or 0.022)

    love.graphics.push()
    love.graphics.translate(cx, beamY)
    love.graphics.rotate(sway)
    love.graphics.scale(pop, pop)                         -- pop-in when appearing
    love.graphics.translate(-cx, -beamY)

    -- two ropes from rings down to the plank's top corners
    local lx, rx = bx + bw * 0.16, bx + bw * 0.84
    love.graphics.setColor(0.62, 0.50, 0.30)
    love.graphics.setLineWidth(math.max(2, bh * 0.05))
    love.graphics.line(lx, beamY + bh * 0.10, lx, by)
    love.graphics.line(rx, beamY + bh * 0.10, rx, by)
    love.graphics.setLineWidth(1)
    love.graphics.setColor(0.20, 0.16, 0.12)              -- iron rings
    love.graphics.circle("line", lx, beamY + bh * 0.10, bh * 0.07)
    love.graphics.circle("line", rx, beamY + bh * 0.10, bh * 0.07)

    -- the plank: raised wood, with a sunken carved inner panel
    local face = hover and WOOD.hi or WOOD.face
    Retro.bevel(bx, by, bw, bh, face, WOOD.hi, WOOD.lo, t, true)
    Retro.bevel(bx + t * 2, by + t * 2, bw - t * 4, bh - t * 4, WOOD.deep, WOOD.hi, WOOD.lo, t, false)

    -- carved label: light highlight underneath + dark engraved text on top
    love.graphics.setFont(self.signFont)
    local label = "Klar til å sette seil"
    local tw, th = self.signFont:getWidth(label), self.signFont:getHeight()
    local tx, ty = cx - tw / 2, by + bh / 2 - th / 2
    love.graphics.setColor(WOOD.hi[1], WOOD.hi[2], WOOD.hi[3], 0.8)
    love.graphics.print(label, tx + 1, ty + 2)
    love.graphics.setColor(hover and WOOD.accent or WOOD.text)
    love.graphics.print(label, tx, ty)

    love.graphics.pop()
end

function Menu:pointInButton(mx, my)
    local bx, by, bw, bh = self:buttonRect()
    return mx >= bx and mx <= bx + bw and my >= by and my <= by + bh
end

-- TEMPORARY: a tiny dev button (bottom-left) that jumps straight to the all-found
-- finale, so the win screen can be previewed without playing through. Remove this
-- (and its draw + click handling + World:load's game.previewWin hook) later.
function Menu:previewBtnRect()
    local sh = love.graphics.getHeight()
    local f  = self.game.fonts.small
    local label = "Se finale (TEST)"
    local pad = 10
    return 16, sh - (f:getHeight() + pad) - 14, f:getWidth(label) + pad * 2, f:getHeight() + pad, label
end

-- Restore volume (it may have been ducked under the voice) and go via the
-- loading screen so the world build happens behind a "Laster…".
function Menu:start()
    Assets.setMusicVolume(1.0)
    self.game:setScene("loading")
end

function Menu:keypressed(key)
    if key == "return" or key == "space" or key == "kpenter" then
        self:start()
    end
end

function Menu:mousepressed(x, y, button)
    if button ~= 1 then return end
    if self:pointInPreview(x, y) then          -- TEMPORARY: jump to the finale
        self.game.previewWin = true
        self.game:setScene("loading")
    elseif self:pointInButton(x, y) then
        self:start()
    end
end

return Menu
