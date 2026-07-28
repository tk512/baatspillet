-- The treasure album: one big chest per treasure, golden when found, dimmed
-- under a "?" when not. Tapping a found chest fires the gold party; anywhere
-- else closes. A modal owned by the world scene.

local config = require("src.config")
local Assets = require("src.assets")
local Retro  = require("src.ui.retro")
local Icons  = require("src.ui.icons")

local WOOD = Retro.WOOD

local Album = {}
Album.__index = Album

local PARTY_TIME  = 3.0     -- seconds of coin cannonade per tap (taps stack)
local PARTY_RATE  = 70      -- coins per second while the party runs
local PARTY_MAX   = 450     -- live-coin cap (perf guard; it still looks insane)

function Album.new(world)
    return setmetatable({ world = world, t = 0, coins = {}, party = 0, clinkT = 0 }, Album)
end

-- geometry shared by draw and the tap test
function Album:layout()
    local sw, sh = love.graphics.getDimensions()
    local fonts  = self.world.game.fonts
    local list   = self.world.treasures or {}
    local t  = math.max(3, math.floor(fonts.small:getHeight() * 0.22))
    local pw = math.min(sw * 0.8, 820)
    local ph = math.min(sh * 0.8, 560)
    local px = (sw - pw) / 2
    local py = (sh - ph) / 2
    local ix, iy = px + t * 2, py + t * 2
    local iw, ih = pw - t * 4, ph - t * 4
    local n    = math.max(1, #list)
    local cols = math.min(n, 4)
    local rows = math.ceil(n / cols)
    local top  = iy + 24 + fonts.big:getHeight() + fonts.normal:getHeight()
    local areaH = (iy + ih) - top - 16
    local cell  = math.min(iw / cols, areaH / rows) * 0.82
    local gridW = cols * cell
    local gx0   = ix + (iw - gridW) / 2
    local gy0   = top + (areaH - rows * cell) / 2
    local slots = {}
    for k = 1, #list do
        local c = (k - 1) % cols
        local r = math.floor((k - 1) / cols)
        slots[k] = { x = gx0 + c * cell, y = gy0 + r * cell, w = cell, h = cell,
                     cx = gx0 + c * cell + cell / 2, cy = gy0 + r * cell + cell / 2 }
    end
    return { t = t, px = px, py = py, pw = pw, ph = ph,
             ix = ix, iy = iy, iw = iw, ih = ih, cell = cell, slots = slots }
end

function Album:burst()
    self.party = PARTY_TIME + (self.party > 0 and 0.8 or 0)   -- re-taps stack
    local sw, sh = love.graphics.getDimensions()
    for _ = 1, 50 do self:spawnCoin(sw, sh) end               -- opening salvo
    Assets.playPitched("coin_clink", 0.9, 0.8 + love.math.random() * 0.6)
    -- once per party: looping du_vant is the finale's privilege alone
    if not (self.song and self.song:isPlaying()) then
        local src = Assets.namedVoice("du_vant")
        if src then
            src:stop(); src:setLooping(false); src:setPitch(1.12); src:setVolume(1.0)
            src:play()
            self.song = src
        end
    end
end

function Album:spawnCoin(sw, sh)
    if #self.coins >= PARTY_MAX then return end
    local k = sh / 800
    -- emitters: four corners plus mid-edges
    local ex, ey
    local e = love.math.random(7)
    if     e == 1 then ex, ey = 0, 0
    elseif e == 2 then ex, ey = sw, 0
    elseif e == 3 then ex, ey = 0, sh
    elseif e == 4 then ex, ey = sw, sh
    elseif e == 5 then ex, ey = sw / 2, -20
    elseif e == 6 then ex, ey = -20, sh / 2
    else               ex, ey = sw + 20, sh / 2 end
    -- aim mid-screen, generous spread
    local tx = sw * (0.25 + love.math.random() * 0.5)
    local ty = sh * (0.15 + love.math.random() * 0.5)
    local ang = math.atan2(ty - ey, tx - ex) + (love.math.random() - 0.5) * 0.7
    local sp = (400 + love.math.random() * 520) * k
    self.coins[#self.coins + 1] = {
        x = ex, y = ey,
        vx = math.cos(ang) * sp, vy = math.sin(ang) * sp,
        r = (16 + love.math.random() * 18) * k,
        rot = love.math.random() * math.pi,
        vr = (love.math.random() - 0.5) * 10,
    }
end

function Album:update(dt)
    self.t = self.t + dt
    if self.party > 0 then
        self.party = self.party - dt
        local sw, sh = love.graphics.getDimensions()
        for _ = 1, math.max(1, math.floor(PARTY_RATE * dt + 0.5)) do
            self:spawnCoin(sw, sh)
        end
        self.clinkT = self.clinkT - dt
        if self.clinkT <= 0 then
            self.clinkT = 0.09
            Assets.playPitched("coin_clink", 0.5, 0.7 + love.math.random() * 0.9)
        end
    end
    local sh = love.graphics.getHeight()
    local g = 950 * (sh / 800)
    for i = #self.coins, 1, -1 do
        local c = self.coins[i]
        c.vy = c.vy + g * dt
        c.x = c.x + c.vx * dt
        c.y = c.y + c.vy * dt
        c.rot = c.rot + c.vr * dt
        if c.y > sh + 80 and c.vy > 0 then table.remove(self.coins, i) end
    end
end

-- tap a found chest = party, anywhere else = close
function Album:mousepressed(x, y, button)
    if button ~= 1 then return end
    local L = self:layout()
    local list = self.world.treasures or {}
    for k, tr in ipairs(list) do
        local s = L.slots[k]
        if s and tr.found and x >= s.x and x <= s.x + s.w and y >= s.y and y <= s.y + s.h then
            self:burst()
            return
        end
    end
    self.world:closeAlbum()
end

function Album:keypressed(key)
    if key == "escape" or key == "b" or key == "return" or key == "space" then
        self.world:closeAlbum()
    end
end

local function drawCoin(x, y, r, rot) Icons.coin(x, y, r, rot) end

function Album:draw()
    local sw, sh = love.graphics.getDimensions()
    local fonts  = self.world.game.fonts
    local list   = self.world.treasures or {}
    local found  = 0
    for _, tr in ipairs(list) do if tr.found then found = found + 1 end end
    local complete = (#list > 0 and found == #list)
    local L = self:layout()

    -- dim the frozen world
    love.graphics.setColor(0, 0, 0, 0.62)
    love.graphics.rectangle("fill", 0, 0, sw, sh)
    Retro.plaque(L.px, L.py, L.pw, L.ph, L.t)
    local ix, iy, iw, ih = L.ix, L.iy, L.iw, L.ih

    -- title + count
    love.graphics.setFont(fonts.big)
    local title = "Skattekiste"
    love.graphics.setColor(0, 0, 0, 0.5)
    love.graphics.print(title, ix + (iw - fonts.big:getWidth(title)) / 2 + 2, iy + 10 + 2)
    love.graphics.setColor(WOOD.accent)
    love.graphics.print(title, ix + (iw - fonts.big:getWidth(title)) / 2, iy + 10)
    love.graphics.setFont(fonts.normal)
    local cnt = found .. " / " .. #list
    love.graphics.setColor(WOOD.text)
    love.graphics.print(cnt, ix + (iw - fonts.normal:getWidth(cnt)) / 2,
        iy + 12 + fonts.big:getHeight())

    -- the chests: BIG, one per treasure
    for k, tr in ipairs(list) do
        local s = L.slots[k]
        local cell = L.cell
        Retro.bevel(s.x + cell * 0.08, s.y + cell * 0.08, cell * 0.84, cell * 0.84,
            WOOD.deep, WOOD.hi, WOOD.lo, math.max(2, math.floor(L.t * 0.6)), false)

        if tr.found then
            Icons.draw(tr.good, s.cx, s.cy - cell * 0.20, cell * 0.32)
            Icons.draw("chest", s.cx, s.cy + cell * 0.14, cell * 0.60)
            -- golden = yours: frame + corner glints
            love.graphics.setColor(WOOD.accent)
            love.graphics.setLineWidth(math.max(2, cell * 0.02))
            love.graphics.rectangle("line", s.x + cell * 0.08, s.y + cell * 0.08,
                cell * 0.84, cell * 0.84)
            love.graphics.setLineWidth(1)
            for i = 0, 2 do
                local a = math.sin(self.t * (1.4 + i * 0.5) + i * 2 + k)
                if a > 0.45 then
                    local f = (a - 0.45) / 0.55
                    local gx = s.x + cell * (0.14 + i * 0.36)
                    local gy = s.y + cell * (0.12 + (i % 2) * 0.72)
                    local r2 = cell * 0.05 * f
                    love.graphics.setColor(1, 0.97, 0.8, f)
                    love.graphics.line(gx - r2, gy, gx + r2, gy)
                    love.graphics.line(gx, gy - r2, gx, gy + r2)
                end
            end
        else
            Icons.draw("chest", s.cx, s.cy + cell * 0.08, cell * 0.60)
            love.graphics.setColor(0, 0, 0, 0.45)
            love.graphics.rectangle("fill", s.x + cell * 0.08, s.y + cell * 0.08,
                cell * 0.84, cell * 0.84)
            love.graphics.setFont(fonts.big)
            love.graphics.setColor(WOOD.hi[1], WOOD.hi[2], WOOD.hi[3], 0.75)
            local q = "?"
            love.graphics.print(q, s.cx - fonts.big:getWidth(q) / 2,
                s.cy - fonts.big:getHeight() / 2)
        end
    end

    -- footer
    love.graphics.setFont(fonts.normal)
    if complete then
        local msg = "Alle skatter funnet!"
        local pulse = 0.7 + 0.3 * math.sin(self.t * 6)
        love.graphics.setColor(config.colors.gold[1], config.colors.gold[2],
            config.colors.gold[3], pulse)
        love.graphics.print(msg, ix + (iw - fonts.normal:getWidth(msg)) / 2,
            iy + ih - fonts.normal:getHeight() - 8)
    else
        love.graphics.setFont(fonts.small)
        local hint = "Klikk for å lukke"
        love.graphics.setColor(WOOD.text[1], WOOD.text[2], WOOD.text[3], 0.7)
        love.graphics.print(hint, ix + (iw - fonts.small:getWidth(hint)) / 2,
            iy + ih - fonts.small:getHeight() - 8)
    end

    -- the party draws over everything
    for _, c in ipairs(self.coins) do drawCoin(c.x, c.y, c.r, c.rot) end
    love.graphics.setColor(1, 1, 1)
end

return Album
