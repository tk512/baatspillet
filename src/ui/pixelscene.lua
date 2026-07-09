-- src/ui/pixelscene.lua
-- Shared early-90s pixel-scene primitives (Bayer-dithered gradients, discs,
-- hills, clouds, sun, mini sailboats) used by the title screen and the boat
-- chooser backdrop. Everything except miniBoat is meant for BAKE time: draw
-- once onto a nearest-filtered virtual-res canvas and upscale -- never call
-- the per-pixel fills in a per-frame path.

local Scene = {}

Scene.VRES_H = 540   -- virtual scanlines (between VGA 480 and SVGA 600)

-- Bayer 4x4 ordered-dither matrix (0..15), for the crosshatched VGA gradients.
Scene.BAYER = {
    { 0, 8, 2, 10 }, { 12, 4, 14, 6 }, { 3, 11, 1, 9 }, { 15, 7, 13, 5 },
}

local BAYER = Scene.BAYER
local function lerp(a, b, t) return a + (b - a) * t end

-- Vertical colour gradient quantized into `levels` bands and crosshatched with
-- the Bayer matrix -- the classic VGA sky/sea fill.
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

-- A clean pixel disc (every virtual pixel inside the radius), filled at vres.
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

-- A smooth pixel hill (parabola), lighter band along the grassy top.
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

-- A soft pixel cloud: a few overlapping discs with a dithered flat bottom.
function Scene.cloud(cx, cy, w)
    local white = { 0.97, 0.98, 1.0 }
    Scene.disc(cx, cy, w * 0.5, white)
    Scene.disc(cx - w * 0.5, cy + w * 0.12, w * 0.34, white)
    Scene.disc(cx + w * 0.55, cy + w * 0.10, w * 0.38, white)
    Scene.disc(cx + w * 0.12, cy - w * 0.18, w * 0.30, white)
    love.graphics.setColor(0.86, 0.90, 0.96)            -- soft underside shadow
    love.graphics.rectangle("fill", cx - w * 0.8, cy + w * 0.30, w * 1.6, 1)
end

-- Sun with a soft layered glow and a bright highlight.
function Scene.sun(cx, cy, r)
    love.graphics.setColor(1, 0.95, 0.7, 0.12); love.graphics.circle("fill", cx, cy, r * 2.2)
    love.graphics.setColor(1, 0.96, 0.76, 0.22); love.graphics.circle("fill", cx, cy, r * 1.5)
    Scene.disc(cx, cy, r, { 1.0, 0.93, 0.62 })
    Scene.disc(cx - r * 0.28, cy - r * 0.28, r * 0.5, { 1.0, 0.98, 0.82 })
end

-- Shimmering reflection straight down from the sun onto the water.
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

-- A tiny sailboat silhouette drifting on the horizon (cheap: fine per frame).
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
