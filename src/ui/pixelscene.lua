-- Early-90s pixel-scene primitives shared by the title, boat and map screens.
-- Everything except miniBoat and drawLive is BAKE time: draw once onto a
-- nearest-filtered virtual-res canvas and upscale. Never per frame.

local config = require("src.config")

local Scene = {}

Scene.VRES_H = 540   -- virtual scanlines (between VGA 480 and SVGA 600)

-- One sky, everywhere. The title, boat, map and info screens are meant to read
-- as the same afternoon.
Scene.SKY_TOP = { 0.36, 0.60, 0.88 }
Scene.SKY_LOW = { 0.82, 0.90, 0.96 }

-- Bayer 4x4 ordered-dither matrix, 0..15
Scene.BAYER = {
    { 0, 8, 2, 10 }, { 12, 4, 14, 6 }, { 3, 11, 1, 9 }, { 15, 7, 13, 5 },
}

local BAYER = Scene.BAYER
local function lerp(a, b, t) return a + (b - a) * t end

-- vertical gradient in `levels` bands, crosshatched: the VGA sky/sea fill
function Scene.dithGradient(x0, y0, w, h, cTop, cBottom, levels)
    for yy = y0, y0 + h - 1 do
        local f = (yy - y0) / math.max(1, h - 1)
        local fl = f * levels
        local idx = math.floor(fl)
        local frac = fl - idx
        local row = (yy % 4) + 1
        for xx = x0, x0 + w - 1 do
            local thresh = (BAYER[row][(xx % 4) + 1] + 0.5) / 16
            local m = math.min(1, (idx + (frac > thresh and 1 or 0)) / levels)
            love.graphics.setColor(lerp(cTop[1], cBottom[1], m), lerp(cTop[2], cBottom[2], m),
                lerp(cTop[3], cBottom[3], m))
            love.graphics.rectangle("fill", xx, yy, 1, 1)
        end
    end
end

-- clean pixel disc, filled at vres
function Scene.disc(cx, cy, r, col)
    love.graphics.setColor(col)
    local r2 = r * r
    for by = -r, r do
        local span = math.floor(math.sqrt(math.max(0, r2 - by * by)))
        if span > 0 then
            love.graphics.rectangle("fill", cx - span, cy + by, span * 2, 1)
        end
    end
end

-- parabolic hill, lighter band along the grassy top
function Scene.hill(cx, baseY, halfW, height, col, top)
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

-- overlapping discs with a dithered flat bottom
function Scene.cloud(cx, cy, w)
    local white = { 0.97, 0.98, 1.0 }
    Scene.disc(cx, cy, w * 0.5, white)
    Scene.disc(cx - w * 0.5, cy + w * 0.12, w * 0.34, white)
    Scene.disc(cx + w * 0.55, cy + w * 0.10, w * 0.38, white)
    Scene.disc(cx + w * 0.12, cy - w * 0.18, w * 0.30, white)
    love.graphics.setColor(0.86, 0.90, 0.96)            -- soft underside shadow
    love.graphics.rectangle("fill", cx - w * 0.8, cy + w * 0.30, w * 1.6, 1)
end

function Scene.sun(cx, cy, r)
    love.graphics.setColor(1, 0.95, 0.7, 0.12); love.graphics.circle("fill", cx, cy, r * 2.2)
    love.graphics.setColor(1, 0.96, 0.76, 0.22); love.graphics.circle("fill", cx, cy, r * 1.5)
    Scene.disc(cx, cy, r, { 1.0, 0.93, 0.62 })
    Scene.disc(cx - r * 0.28, cy - r * 0.28, r * 0.5, { 1.0, 0.98, 0.82 })
end

-- shimmering reflection straight down from the sun
function Scene.sunReflection(cx, fromY, toY, r, step)
    for i = 0, 22 do
        local ry = fromY + i * step
        if ry < toY then
            local w = r * (0.5 + i * 0.05)
            love.graphics.setColor(1, 0.95, 0.7, 0.20 * (1 - i / 24))
            love.graphics.rectangle("fill", cx - w / 2, ry, w, 1)
        end
    end
end

-- pale blue-grey back range: the cheap trick that gives a flat horizon depth
function Scene.hazeHills(x0, w, horizonY, sceneH)
    local haze = { 0.62, 0.72, 0.84 }
    Scene.hill(x0 + w * 0.30, horizonY, w * 0.16, sceneH * 0.10, haze, haze)
    Scene.hill(x0 + w * 0.63, horizonY, w * 0.13, sceneH * 0.13, haze, haze)
    Scene.hill(x0 + w * 0.04, horizonY, w * 0.10, sceneH * 0.07, haze, haze)
end

-- horizon island: grass crest, sandy base, deterministic tree tufts
function Scene.island(cx, horizonY, halfW, height, grass, gdk, sand)
    Scene.hill(cx, horizonY + math.max(2, math.floor(height * 0.09)), halfW,
        math.floor(height * 0.35), sand, sand)
    Scene.hill(cx, horizonY, halfW * 0.84, height, gdk, grass)
    love.graphics.setColor(0.16, 0.34, 0.18)
    for k = 1, 9 do
        local f = (k / 10 - 0.5) * 1.3
        local hh = math.floor(height * (1 - f * f) * 0.84)
        if hh > 2 then
            local tx = cx + math.floor(f * halfW * 0.84)
            local jig = math.floor((math.sin(k * 12.9898 + cx) * 0.5 + 0.5) * hh * 0.55)
            love.graphics.rectangle("fill", tx, horizonY - hh + jig, 2, 2)
        end
    end
end

-- Each cloud baked once onto its own tiny canvas at scene pixel density, then
-- drifted by drawLive. specs = { {w, yf, speed}, ... } as fractions of the
-- scene; positions come out in SCREEN coords.
function Scene.makeClouds(specs, sceneW, sy, sceneH, scale)
    local clouds = {}
    for i, spec in ipairs(specs) do
        local w = sceneW * spec.w
        local cv = love.graphics.newCanvas(math.ceil(w * 2.4), math.ceil(w * 1.5))
        cv:setFilter("nearest", "nearest")
        love.graphics.setCanvas(cv)
        love.graphics.clear(0, 0, 0, 0)
        Scene.cloud(w * 1.1, w * 0.6, w)
        love.graphics.setCanvas()
        clouds[i] = {
            cv = cv,
            y = (sy + sceneH * spec.yf) * scale,
            speed = spec.speed * scale,
            phase = i * 0.61,
        }
    end
    love.graphics.setColor(1, 1, 1, 1)
    return clouds
end

-- The live layer the pixel scenes share: sun halo and rays, glitter, drifting
-- clouds, gulls. Pure functions of t, no allocations. S = { x, y, w, h,
-- horizon, blk, scale, sun = {x,y,r}, clouds }, all in screen coords.
function Scene.drawLive(S, t)
    local sun = S.sun
    if sun then
        love.graphics.setBlendMode("add")
        local breathe = 1 + 0.04 * math.sin(t * 1.3)
        love.graphics.setColor(1, 0.93, 0.6, 0.05 + 0.03 * math.sin(t * 1.3))
        love.graphics.circle("fill", sun.x, sun.y, sun.r * 2.1 * breathe)
        love.graphics.push()
        love.graphics.translate(sun.x, sun.y)
        love.graphics.rotate(t * 0.12)
        for i = 1, 10 do
            love.graphics.rotate(math.pi / 5)
            local stretch = 1 + 0.18 * math.sin(t * 0.9 + i * 1.7)
            love.graphics.setColor(1, 0.95, 0.68, 0.06)
            love.graphics.polygon("fill", sun.r * 1.25, -sun.r * 0.16,
                sun.r * 2.6 * stretch, 0, sun.r * 1.25, sun.r * 0.16)
        end
        love.graphics.pop()

        -- glitter along the reflection column
        local seaB = S.y + S.h
        for i = 1, 16 do
            local fy = (i * 0.618) % 1
            local gy = S.horizon + fy * (seaB - S.horizon) * 0.8 + S.blk
            local spread = S.w * 0.02 + fy * S.w * 0.055
            local gx = sun.x + math.sin(i * 12.9898) * spread
            local tw = math.sin(t * (1.4 + (i % 5) * 0.33) + i * 2.4)
            if tw > 0 then
                local a = tw * tw * tw * 0.55
                local sr = (1.5 + fy * 2.5) * (S.blk * 0.5) * tw
                love.graphics.setColor(1, 0.97, 0.8, a)
                love.graphics.rectangle("fill", gx - sr, gy - S.blk * 0.3, sr * 2, S.blk * 0.6)
                love.graphics.rectangle("fill", gx - S.blk * 0.3, gy - sr, S.blk * 0.6, sr * 2)
            end
        end
        love.graphics.setBlendMode("alpha")
    end

    -- after the sun, so they pass in front of it
    for i, cl in ipairs(S.clouds or {}) do
        local cw = cl.cv:getWidth() * S.scale
        local span = S.w + cw * 2
        local cx = S.x - cw + ((cl.phase * span) + t * cl.speed) % span
        local bob = math.sin(t * 0.4 + i * 2.2) * S.blk
        love.graphics.setColor(1, 1, 1, 0.96)
        love.graphics.draw(cl.cv, cx, cl.y + bob, 0, S.scale, S.scale)
    end

    -- gulls, two flapping strokes each
    love.graphics.setLineWidth(math.max(1.5, S.blk * 0.5))
    for i = 1, 3 do
        local u = (t * (0.022 + i * 0.007) + i * 0.37) % 1.3 - 0.15
        local gx = S.x + u * S.w
        local gy = S.y + (S.horizon - S.y) * (0.34 + 0.16 * math.sin(u * 9 + i * 2))
        local wing = S.blk * (2.2 + i * 0.4)
        local flap = math.sin(t * 6 + i * 2.1) * wing * 0.55
        love.graphics.setColor(0.25, 0.30, 0.38, 0.75)
        love.graphics.line(gx - wing, gy - flap * 0.4, gx, gy + flap)
        love.graphics.line(gx, gy + flap, gx + wing, gy - flap * 0.4)
    end
    love.graphics.setLineWidth(1)
    love.graphics.setColor(1, 1, 1)
end

-- ── The chooser backdrop ─────────────────────────────────────────────────────
-- Sky, sea, haze range, islands and sun baked onto the virtual-res canvas, plus
-- the descriptor drawLive needs. The boat, map and info screens each had the
-- identical twenty lines with different constants, so the constants became the
-- argument -- and a fourth screen is now a table, not a copy.
--
-- `spec` is fractions of the virtual scene, so it is resolution-free:
--   { horizon = 0.30,
--     islands = { { x = 0.11, w = 0.085, h = 0.10 }, ... },   -- x/w of VW, h of VH
--     sun     = { x = 0.85, y = 0.115, r = 0.06 },
--     clouds  = { { w = 0.07, yf = 0.10, speed = 8 }, ... } }
-- The cache lands on `o` (the scene table): bg/bgW/bgH/bgScale/bgHorizon and
-- liveScene, so a caller that wants more (boatselect's glints) can read them.
--
-- The TITLE screen keeps its own bake on purpose: it has the lighthouse and a
-- full-bleed geometry the choosers don't share.
function Scene.backdrop(o, sw, sh, spec)
    local VH = Scene.VRES_H
    local scale = sh / VH
    local VW = math.max(4, math.floor(sw / scale + 0.5))
    local horizon = math.floor(VH * spec.horizon)

    local cv = love.graphics.newCanvas(VW, VH)
    cv:setFilter("nearest", "nearest")
    love.graphics.setCanvas(cv)
    love.graphics.clear(0, 0, 0, 0)

    Scene.dithGradient(0, 0, VW, horizon, Scene.SKY_TOP, Scene.SKY_LOW, 10)
    Scene.dithGradient(0, horizon, VW, VH - horizon,
        config.colors.water_top, config.colors.water_deep, 8)

    Scene.hazeHills(0, VW, horizon, VH)          -- depth behind the islands
    local grass, gdk = config.colors.grass.top, config.colors.grass.lip
    local sand = config.colors.sand.top
    for _, isl in ipairs(spec.islands) do
        Scene.island(VW * isl.x, horizon, VW * isl.w, VH * isl.h, grass, gdk, sand)
    end

    local sunX, sunY = VW * spec.sun.x, VH * spec.sun.y
    local sunR = math.floor(VH * spec.sun.r)
    Scene.sun(sunX, sunY, sunR)
    Scene.sunReflection(sunX, horizon, VH, sunR, VH * 0.016)

    love.graphics.setCanvas()
    love.graphics.setColor(1, 1, 1)

    o.bg, o.bgW, o.bgH = cv, sw, sh
    o.bgScale, o.bgHorizon = scale, horizon * scale
    o.liveScene = {
        x = 0, y = 0, w = sw, h = sh,
        horizon = horizon * scale, blk = math.max(2, scale), scale = scale,
        sun = { x = sunX * scale, y = sunY * scale, r = sunR * scale },
        clouds = Scene.makeClouds(spec.clouds, VW, 0, VH, scale),
    }
end

-- Bake on first use or after a resize, then draw the canvas and the live layer.
function Scene.drawBackdrop(o, sw, sh, spec, t)
    if not o.bg or o.bgW ~= sw or o.bgH ~= sh then Scene.backdrop(o, sw, sh, spec) end
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(o.bg, 0, 0, 0, o.bgScale, o.bgScale)
    Scene.drawLive(o.liveScene, t)
end

-- horizon sailboat; cheap enough for a per-frame path
function Scene.miniBoat(x, y, s, col)
    love.graphics.setColor(1, 1, 1, 0.35)
    love.graphics.ellipse("fill", x, y + 7 * s, 16 * s, 3 * s)            -- reflection
    love.graphics.setColor(0.97, 0.96, 0.92)
    love.graphics.polygon("fill", x, y - 16 * s, x, y + 2 * s, x + 11 * s, y + 2 * s) -- sail
    love.graphics.setColor(0.30, 0.24, 0.18)
    love.graphics.rectangle("fill", x - 0.8 * s, y - 16 * s, 1.6 * s, 18 * s)         -- mast
    love.graphics.setColor(col)
    love.graphics.polygon("fill", x - 13 * s, y + 2 * s, x + 13 * s, y + 2 * s,
        x + 8 * s, y + 8 * s, x - 8 * s, y + 8 * s)                       -- hull
end

return Scene
