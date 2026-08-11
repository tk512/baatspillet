-- "Velg kart", straight after the boat chooser. Each card draws its islands as
-- a miniature sea chart from the map's own anchors, so the choice reads without
-- reading. `comingSoon` maps are dimmed teasers with a "?" and no padlock --
-- they aren't buyable, just later. Voice hook: velg_kart.

local config = require("src.config")
local Assets = require("src.assets")
local Retro  = require("src.ui.retro")
local Scale  = require("src.ui.scale")
local Scene  = require("src.ui.pixelscene")
local Flags  = require("src.ui.flags")

local W = Retro.WOOD
local MapSelect = {}

-- Waving flag: vertical slices riding a travelling sine, hoist steady and fly
-- end waving, with a shimmer rolling along the cloth. Quads cached per image.
local flagQuads = {}
local function wavingFlag(country, cx, cy, w, t)
    local code = Flags.CODES[country]
    local img = code and Assets.image("flags/" .. code .. ".png")
    if not img then
        Flags.draw(country, cx - w / 2, cy - w * 0.36, w, w * 0.72)
        return
    end
    if img:getFilter() ~= "linear" then img:setFilter("linear", "linear") end
    local iw, ih = img:getWidth(), img:getHeight()
    local n = 14
    local qs = flagQuads[img]
    if not qs then
        qs = {}
        for i = 1, n do
            qs[i] = love.graphics.newQuad(iw * (i - 1) / n, 0, iw / n + 1, ih, iw, ih)
        end
        flagQuads[img] = qs
    end
    local sc = w / iw
    local sliceW = iw / n * sc
    local h = ih * sc
    local x0 = cx - w / 2
    love.graphics.setColor(0, 0, 0, 0.28)                 -- soft shadow behind the cloth
    love.graphics.rectangle("fill", x0 + 3, cy - h / 2 + 5, w, h, 3, 3)
    for i = 1, n do
        local u = (i - 0.5) / n
        local ph = t * 3.0 - u * 4.6
        local wave = math.sin(ph) * w * 0.04 * u          -- ripple grows toward the fly end
        local shine = 1 + 0.16 * math.sin(ph + 0.7) * u   -- shimmer rides the wave
        love.graphics.setColor(shine, shine, shine)
        love.graphics.draw(img, qs[i], x0 + (i - 1) * sliceW, cy - h / 2 + wave, 0, sc, sc)
    end
    love.graphics.setColor(1, 1, 1)
end

local function hover(r)
    local mx, my = love.mouse.getPosition()
    return mx >= r.x and mx <= r.x + r.w and my >= r.y and my <= r.y + r.h
end

function MapSelect:load(game)
    self.game = game
    self.t = 0
    Assets.playNamedVoice("velg_kart")   -- optional clip ("Velg kart!")
end

function MapSelect:update(dt) self.t = self.t + dt end

-- title-screen pixel language, baked once. Treed islands at the EDGES only: the
-- middle has to stay clear behind the cards.
local BACKDROP = {
    horizon = 0.26,
    islands = { { x = 0.06, w = 0.08, h = 0.09 }, { x = 0.95, w = 0.09, h = 0.11 } },
    sun     = { x = 0.88, y = 0.10, r = 0.055 },
    clouds  = { { w = 0.06, yf = 0.09, speed = 7 }, { w = 0.045, yf = 0.05, speed = 5 } },
}

function MapSelect:layout()
    local sw, sh = love.graphics.getDimensions()
    local k = Scale.ui(1)
    local maps = self.game.data.maps
    local n = #maps
    local cw = math.min((sw * 0.88 - (n - 1) * 30 * k) / n, 430 * k)
    local ch = cw * 0.70
    local gap = 30 * k
    local total = n * cw + (n - 1) * gap
    local cards = {}
    for i = 1, n do
        cards[i] = { x = sw / 2 - total / 2 + (i - 1) * (cw + gap),
                     y = sh * 0.32, w = cw, h = ch, def = maps[i] }
    end
    return {
        k = k, cards = cards,
        back = { x = 20 * k, y = 20 * k, w = 130 * k, h = 52 * k },
    }
end

-- one card: wooden frame around a mini chart drawn from the island anchors
function MapSelect:drawCard(c)
    local def = c.def
    local t = math.max(2, math.floor(c.h * 0.05))
    local down = Retro.isDown("map:" .. def.id)
    local hov = hover(c) and not def.comingSoon and not down
    Retro.bevel(c.x, c.y, c.w, c.h, hov and W.hi or W.face, W.hi, W.lo, t, not down)

    -- chart area (the "paper"): calm sea
    local ix, iy = c.x + t * 2, c.y + t * 2
    local iw, ih = c.w - t * 4, c.h - t * 4 - c.h * 0.18
    local sea = config.colors.water_top
    love.graphics.setColor(sea[1], sea[2], sea[3])
    love.graphics.rectangle("fill", ix, iy, iw, ih)

    -- assets/maps/<id>.png (any aspect, cover-fit) replaces the blobs
    local img = not def.comingSoon and Assets.image("maps/" .. def.id .. ".png")
    if img then
        local sc = math.max(iw / img:getWidth(), ih / img:getHeight())
        love.graphics.setScissor(ix, iy, iw, ih)
        love.graphics.setColor(1, 1, 1)
        love.graphics.draw(img, ix + iw / 2, iy + ih / 2, 0, sc, sc,
            img:getWidth() / 2, img:getHeight() / 2)
        love.graphics.setScissor()
    elseif def.comingSoon then
        love.graphics.setColor(0, 0, 0, 0.30)
        love.graphics.rectangle("fill", ix, iy, iw, ih)
        local f = self.game.fonts.title
        love.graphics.setFont(f); love.graphics.setColor(1, 1, 1, 0.85)
        love.graphics.print("?", ix + iw / 2 - f:getWidth("?") / 2, iy + ih / 2 - f:getHeight() / 2)
    else
        -- islands to scale: sand halo + grass blob
        local sx, sy = iw / config.WORLD_WIDTH, ih / config.WORLD_HEIGHT
        for _, isl in ipairs(def.islands) do
            local px, py = ix + isl.x * sx, iy + isl.y * sy
            local pr = isl.radius * math.min(sx, sy) * 0.62
            local sand = config.colors.sand.top
            love.graphics.setColor(sand[1], sand[2], sand[3])
            love.graphics.circle("fill", px, py, pr * 1.22)
            local g = config.colors.grass.top
            love.graphics.setColor(g[1], g[2], g[3])
            love.graphics.circle("fill", px, py, pr)
        end
    end

    -- four-point stars, each on its own rhythm; pure functions of time
    if not def.comingSoon then
        for i = 1, 7 do
            local a = math.sin(self.t * (0.8 + (i % 3) * 0.37) + i * 1.9)
            if a > 0.35 then
                local f = (a - 0.35) / 0.65
                local px = ix + ((i * 0.381966 + 0.19) % 1) * iw
                local py = iy + ((i * 0.618034 + 0.33) % 1) * ih
                local r = c.h * (0.02 + (i % 3) * 0.012) * f
                love.graphics.setColor(1, 0.97, 0.78, 0.95 * f)
                love.graphics.setLineWidth(math.max(1, c.h * 0.008))
                love.graphics.line(px - r, py, px + r, py)
                love.graphics.line(px, py - r, px, py + r)
                love.graphics.circle("fill", px, py, r * 0.30)
                love.graphics.setLineWidth(1)
            end
        end
    end

    -- the country's flag waves proudly mid-preview
    if def.country and not def.comingSoon then
        wavingFlag(def.country, ix + iw / 2, iy + ih / 2, iw * 0.40, self.t)
    end

    -- premium without the pack: the same rope + padlock as the locked boats
    if def.premium and not self.game:isPremium() then
        local ry = iy + ih * 0.55
        Retro.ropeAcross(ix + 2, ix + iw - 2, ry, ih * 0.08, math.max(2, ih * 0.03))
        Retro.padlock(ix + iw / 2, ry + ih * 0.14, ih * 0.22)
    end

    -- name plank under the chart: just the name, big
    local f = self.game.fonts.big
    love.graphics.setFont(f)
    local label = def.comingSoon and (def.name .. " – kommer snart!") or def.name
    if def.comingSoon then f = self.game.fonts.normal; love.graphics.setFont(f) end
    local ly = iy + ih + (c.h * 0.18 - f:getHeight()) / 2 + t - 1   -- air above the name
    love.graphics.setColor(0, 0, 0, 0.4)
    love.graphics.print(label, c.x + c.w / 2 - f:getWidth(label) / 2 + 2, ly + 2)
    love.graphics.setColor(W.text)
    love.graphics.print(label, c.x + c.w / 2 - f:getWidth(label) / 2, ly)

    if hov then
        love.graphics.setColor(W.accent); love.graphics.setLineWidth(math.max(2, 3 * (c.h / 200)))
        love.graphics.rectangle("line", c.x, c.y, c.w, c.h); love.graphics.setLineWidth(1)
    end
end

function MapSelect:draw()
    local sw, sh = love.graphics.getDimensions()
    local fonts = self.game.fonts
    local L = self:layout()

    love.graphics.clear(config.colors.water_deep)
    Scene.drawBackdrop(self, sw, sh, BACKDROP, self.t)

    love.graphics.setFont(fonts.title)
    local title = "Velg kart"
    local tx = sw / 2 - fonts.title:getWidth(title) / 2
    local ty = math.floor(sh * 0.08)
    love.graphics.setColor(0.13, 0.11, 0.09, 0.5)
    love.graphics.print(title, tx + math.max(2, 3 * L.k), ty + math.max(2, 3 * L.k))
    love.graphics.setColor(W.text)
    love.graphics.print(title, tx, ty)

    for _, c in ipairs(L.cards) do self:drawCard(c) end

    -- Tilbake, same spot as the boat chooser's
    Retro.button("map.back", L.back, "Tilbake", fonts.small)
    love.graphics.setColor(1, 1, 1)
end

function MapSelect:pick(def)
    if def.comingSoon then Assets.playSfx("leave", 0.20); return end
    if def.premium and not self.game:isPremium() then
        Assets.playNamedVoice("spor_en_voksen")
        -- With the premium boats hidden the pack card has no showcase to draw,
        -- so it's suppressed -- and sending the player to the boat screen to
        -- meet no card would simply lose them. Say it out loud and stay put.
        if self.game.premiumHidden then return end
        self.game._openPackOffer = true
        self.game:setScene("boatselect")     -- the Kaptein-pakken card lives there
        return
    end
    self.game:applyMap(def.id)
    self.game:save()
    Assets.setMusicVolume(1.0)
    self.game:setScene("loading")
end

-- Press-in on touch, act on release (Retro press protocol).
function MapSelect:mousepressed(x, y, button)
    if button ~= 1 then return end
    local L = self:layout()
    for _, c in ipairs(L.cards) do
        if Retro.press("map:" .. c.def.id, c, x, y) then return end
    end
    Retro.press("map.back", L.back, x, y)
end

function MapSelect:mousereleased(x, y, button)
    if button ~= 1 then return end
    local L = self:layout()
    for _, c in ipairs(L.cards) do
        if Retro.released("map:" .. c.def.id, x, y) then self:pick(c.def); return end
    end
    if Retro.released("map.back", x, y) then self.game:setScene("boatselect") end
end

function MapSelect:keypressed(key)
    if key == "escape" then self.game:setScene("boatselect")
    elseif key == "return" or key == "kpenter" then
        self:pick(self.game.data.maps[1])
    end
end

return MapSelect
