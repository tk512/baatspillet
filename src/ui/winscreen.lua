-- src/ui/winscreen.lua
-- The grand finale: shown when every treasure chest has been found. A full-screen
-- party -- rotating golden light rays, layered fireworks, jewels raining down and
-- a never-ending shower of gold coins that PILE UP along the bottom (each landing
-- with a random-pitched clink), the open chest with all the collected stickers
-- fanned above it, Finn-Erik the pirate cheering, and a big rainbow "HURRA!!".
-- A modal owned by the world scene (freezes the world). A click dismisses it.
-- Voice can be added later (hook "du_vant").

local config = require("src.config")
local Assets = require("src.assets")

local WinScreen = {}
WinScreen.__index = WinScreen

local FW_COLORS = {
    { 1.0, 0.85, 0.3 }, { 1.0, 0.4, 0.4 }, { 0.5, 0.8, 1.0 },
    { 0.6, 1.0, 0.6 }, { 1.0, 0.6, 0.9 }, { 0.7, 0.6, 1.0 },
}
-- mostly coins, plus treasure chests (the real chest.png sprite) and a few jewels
-- raining down for "gold + treasure". Coins are drawn specially; everything else
-- goes through Icons.draw, so "chest" uses assets/icons/chest.png.
local FALL_KINDS = { "coin", "coin", "coin", "coin", "coin", "chest", "chest", "gem", "pearl" }

local BINW = 18          -- width of a coin-stacking column
local PILE_CAP = 520     -- max landed coins (big coins fill fast; caps draw cost)

function WinScreen.new(world)
    return setmetatable({
        world = world, t = 0, items = {}, spawnAcc = 0,
        landed = {}, pile = {}, clinkT = 0, fwT = 0.2, full = false,
    }, WinScreen)
end

function WinScreen:update(dt)
    self.t = self.t + dt
    local sw, sh = love.graphics.getDimensions()
    self.clinkT = self.clinkT - dt

    -- a steady volley of firework booms (random pitch) -- bababa-baaaaa-boom!
    self.fwT = self.fwT - dt
    if self.fwT <= 0 then
        self.fwT = 0.45 + love.math.random() * 0.6
        Assets.playPitched("firework", 0.45, 0.92 + love.math.random() * 0.2)   -- random fw clip
    end

    -- rain new coins/jewels from the top (stops once the heap is capped) -- big,
    -- fast and plentiful for a proper crazy gold storm
    self.spawnAcc = self.spawnAcc + dt * (self.full and 0 or 70)
    while self.spawnAcc >= 1 and #self.items < 150 do
        self.spawnAcc = self.spawnAcc - 1
        self.items[#self.items + 1] = {
            x    = love.math.random() * sw,
            y    = -20 - love.math.random() * 90,
            vy   = 220 + love.math.random() * 320,
            rot  = love.math.random() * 6.28,
            rotV = (love.math.random() - 0.5) * 8,
            kind = FALL_KINDS[love.math.random(#FALL_KINDS)],
            size = 30 + love.math.random() * 36,            -- big coins (30..66)
            sway = love.math.random() * 6.28,
        }
    end

    for i = #self.items, 1, -1 do
        local it = self.items[i]
        it.y   = it.y + it.vy * dt
        it.rot = it.rot + it.rotV * dt
        local r = it.size * 0.5
        if it.kind == "coin" then
            -- land + stack when it reaches the top of its column's pile
            local bin   = math.floor(it.x / BINW)
            local pile  = self.pile[bin] or 0
            local restY = sh - pile - r
            if it.y >= restY then
                table.remove(self.items, i)
                if #self.landed < PILE_CAP then
                    self.landed[#self.landed + 1] = { x = it.x, y = restY, r = r, rot = it.rot }
                    self.pile[bin] = pile + r * 0.8
                    if self.clinkT <= 0 then          -- throttle + vary pitch -> "clirr klank"
                        self.clinkT = 0.03 + love.math.random() * 0.06
                        Assets.playPitched("coin_clink", 0.6, 0.7 + love.math.random() * 0.8)
                    end
                else
                    self.full = true
                end
            end
        elseif it.y > sh + 40 then
            table.remove(self.items, i)              -- jewels just fall on through
        end
    end
end

-- A short delay so an in-flight click (the one that dug up the last chest) does
-- not skip the celebration instantly.
function WinScreen:mousepressed(_, _, button)
    if button == 1 and self.t > 0.6 then self.world:closeWinScreen() end
end

function WinScreen:keypressed(key)
    if self.t > 0.6 and (key == "return" or key == "space" or key == "escape") then
        self.world:closeWinScreen()
    end
end

-- A spinning coin: the ellipse width oscillates with rotation to fake a 3D flip.
local function drawCoin(x, y, r, rot)
    local w = math.abs(math.cos(rot)) * r + r * 0.15
    love.graphics.setColor(0.62, 0.46, 0.08)
    love.graphics.ellipse("fill", x, y, w + 1, r + 1)
    love.graphics.setColor(0.95, 0.80, 0.30)
    love.graphics.ellipse("fill", x, y, w, r)
    love.graphics.setColor(1, 1, 1, 0.5)
    love.graphics.ellipse("fill", x - w * 0.3, y - r * 0.3, w * 0.25, r * 0.25)
end


function WinScreen:draw()
    local sw, sh = love.graphics.getDimensions()
    local fonts  = self.world.game.fonts
    local Icons  = require("src.ui.icons")
    local t      = self.t
    local cx, cy = sw / 2, sh * 0.52

    -- background: night, then a warm gold radial glow from the centre
    love.graphics.setColor(0.06, 0.05, 0.12)
    love.graphics.rectangle("fill", 0, 0, sw, sh)
    for i = 8, 1, -1 do
        love.graphics.setColor(0.9, 0.7, 0.25, 0.05 * (i / 8))
        love.graphics.circle("fill", cx, cy, (i / 8) * math.max(sw, sh) * 0.62)
    end

    -- slow rotating light rays
    love.graphics.push()
    love.graphics.translate(cx, cy)
    love.graphics.rotate(t * 0.2)
    local L = math.max(sw, sh)
    for k = 0, 11 do
        local a = k * (math.pi * 2 / 12)
        love.graphics.setColor(1, 0.9, 0.4, 0.05)
        love.graphics.polygon("fill", 0, 0,
            math.cos(a - 0.08) * L, math.sin(a - 0.08) * L,
            math.cos(a + 0.08) * L, math.sin(a + 0.08) * L)
    end
    love.graphics.pop()

    -- layered, staggered fireworks
    for b = 1, 12 do
        local bt = t - b * 0.27
        if bt > 0 then
            local p   = (bt % 1.5) / 1.5
            local fx  = sw * (0.1 + 0.8 * ((b * 0.37) % 1))
            local fy  = sh * (0.08 + 0.42 * ((b * 0.61) % 1))
            local rad = p * 150
            local col = FW_COLORS[((b - 1) % #FW_COLORS) + 1]
            for kk = 1, 16 do
                local a = (kk / 16) * math.pi * 2
                love.graphics.setColor(col[1], col[2], col[3], 1 - p)
                love.graphics.circle("fill", fx + math.cos(a) * rad, fy + math.sin(a) * rad, 3 * (1 - p) + 1)
            end
        end
    end

    -- the open chest with every collected sticker fanned in an arc above it
    local chestS = math.min(sw, sh) * 0.17
    Icons.draw("chest", cx, cy + chestS * 0.35 + math.sin(t * 3) * 5, chestS)
    local list = self.world.treasures or {}
    local n = #list
    for k, tr in ipairs(list) do
        if tr.found then
            local frac = (n > 1) and (k - 1) / (n - 1) or 0.5
            local a    = math.pi * (0.82 - 0.64 * frac)
            local rr   = chestS * 1.25
            local ix   = cx + math.cos(a) * rr
            local iy   = cy - chestS * 0.25 - math.sin(a) * rr * 0.5 + math.sin(t * 4 + k) * 4
            Icons.draw(tr.good, ix, iy, chestS * 0.5)
        end
    end

    -- the accumulated gold heap along the bottom (drawn before the falling ones)
    for _, c in ipairs(self.landed) do drawCoin(c.x, c.y, c.r, c.rot) end

    -- still-falling coins + jewels, over the heap
    for _, it in ipairs(self.items) do
        if it.kind == "coin" then
            drawCoin(it.x, it.y, it.size * 0.5, it.rot)
        else
            local x = it.x + math.sin(t * 1.5 + it.sway) * 8
            love.graphics.push(); love.graphics.translate(x, it.y); love.graphics.rotate(it.rot * 0.3)
            Icons.draw(it.kind, 0, 0, it.size)
            love.graphics.pop()
        end
    end

    -- big rainbow title, pulsing
    love.graphics.setFont(fonts.title)
    local title = "HURRA!!"
    local sc    = 1 + 0.08 * math.sin(t * 5)
    local tw    = fonts.title:getWidth(title)
    love.graphics.push(); love.graphics.translate(cx, sh * 0.16); love.graphics.scale(sc, sc)
    love.graphics.setColor(0, 0, 0, 0.4); love.graphics.print(title, -tw / 2 + 3, -fonts.title:getHeight() / 2 + 3)
    love.graphics.setColor(0.6 + 0.4 * math.sin(t * 2), 0.6 + 0.4 * math.sin(t * 2 + 2), 0.6 + 0.4 * math.sin(t * 2 + 4))
    love.graphics.print(title, -tw / 2, -fonts.title:getHeight() / 2)
    love.graphics.pop()

    -- subtitle
    love.graphics.setFont(fonts.big)
    local sub = "Du fant alle skattene!"
    love.graphics.setColor(0, 0, 0, 0.4); love.graphics.print(sub, cx - fonts.big:getWidth(sub) / 2 + 2, sh * 0.29 + 2)
    love.graphics.setColor(config.colors.gold); love.graphics.print(sub, cx - fonts.big:getWidth(sub) / 2, sh * 0.29)

    -- keep-playing hint, after a beat
    if t > 1.0 then
        love.graphics.setFont(fonts.normal)
        local hint = "Klikk for å spille igjen"
        love.graphics.setColor(1, 1, 1, 0.6 + 0.4 * math.sin(t * 3))
        love.graphics.print(hint, cx - fonts.normal:getWidth(hint) / 2, sh * 0.9)
    end
    love.graphics.setColor(1, 1, 1)
end

return WinScreen
