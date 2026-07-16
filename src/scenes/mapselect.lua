-- src/scenes/mapselect.lua
-- "Velg kart": pick the world to sail, right after choosing a boat. Maps are
-- pure data (src/data/maps.lua); each card draws its islands as a miniature
-- sea chart straight from the map's island anchors — so the choice reads
-- without reading. `comingSoon` maps show as quiet teaser cards (dimmed, a big
-- "?", no padlock — they're not buyable yet, just "later"), per the
-- no-purchase-pressure rule. Voice hook: velg_kart.

local config = require("src.config")
local Assets = require("src.assets")
local Retro  = require("src.ui.retro")
local Scale  = require("src.ui.scale")
local Scene  = require("src.ui.pixelscene")
local Flags  = require("src.ui.flags")

local W = Retro.WOOD
local MapSelect = {}

-- A flag WAVING in the wind, centre of the map preview: the image is drawn in
-- vertical slices riding a travelling sine (hoist edge steady, fly end waving)
-- with a light shimmer rolling along the cloth. Quads are cached per image.
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

-- Sky + sea backdrop in the title screen's pixel language, baked once.
function MapSelect:drawBackground(sw, sh)
    if not self.bg or self.bgW ~= sw or self.bgH ~= sh then
        local VH = Scene.VRES_H
        local scale = sh / VH
        local VW = math.max(4, math.floor(sw / scale + 0.5))
        local horizon = math.floor(VH * 0.26)
        local cv = love.graphics.newCanvas(VW, VH)
        cv:setFilter("nearest", "nearest")
        love.graphics.setCanvas(cv)
        Scene.dithGradient(0, 0, VW, horizon, { 0.36, 0.60, 0.88 }, { 0.82, 0.90, 0.96 }, 10)
        Scene.dithGradient(0, horizon, VW, VH - horizon,
            config.colors.water_top, config.colors.water_deep, 8)
        Scene.sun(VW * 0.88, VH * 0.10, math.floor(VH * 0.055))
        Scene.cloud(VW * 0.25, VH * 0.09, VW * 0.06)
        love.graphics.setCanvas()
        self.bg, self.bgW, self.bgH, self.bgScale = cv, sw, sh, scale
    end
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(self.bg, 0, 0, 0, self.bgScale, self.bgScale)
end

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

-- One map card: wooden frame around a mini sea chart drawn from the map's own
-- island anchors (sand halo under a grass blob per island).
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

    -- Placeholder-first: a real picture (assets/maps/<id>.png, any aspect —
    -- cover-fit + scissored) replaces the generated island blobs.
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
        -- islands to scale: sand halo + grass blob (a generated kid's chart)
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

    -- TWINKLE: little four-point stars glinting across a pickable chart, each
    -- on its own rhythm (pure functions of time — nothing allocated per frame).
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

    -- premium map without the pack: roped off behind a padlock (the same
    -- "for later" language as the locked boats)
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
    self:drawBackground(sw, sh)

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
    if def.comingSoon then Assets.playSfx("leave", 0.3); return end
    if def.premium and not self.game:isPremium() then
        Assets.playNamedVoice("spor_en_voksen")
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
