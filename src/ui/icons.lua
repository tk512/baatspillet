-- src/ui/icons.lua
-- One place to draw the little game symbols (cargo, treats, the cannon) so the
-- HUD and the shop never duplicate icon art. Each is drawn centred at (x, y) and
-- roughly `s` wide.
--
-- Placeholder-first: if assets/icons/<kind>.png exists it's drawn instead of the
-- code shape, so Finn-Erik's own drawings drop in later with zero code changes.

local Assets = require("src.assets")

local Icons = {}

-- THE gold coin, used everywhere gold shows (HUD, prices, coin rains).
-- Placeholder-first: assets/icons/gull.png (the engraved doubloon) when
-- present, else the classic gold disc. `rot` (optional) flips the coin
-- edge-on like it's spinning — image and fallback both support it.
-- Perf note: many image coins batch on one texture — cheaper than circles.
function Icons.coin(x, y, r, rot)
    local img = Assets.image("icons/gull.png")
    if img then
        if img:getFilter() ~= "linear" then img:setFilter("linear", "linear") end
        local sc = (r * 2) / math.max(img:getWidth(), img:getHeight())
        local sx = sc
        if rot then sx = sc * math.max(0.15, math.abs(math.cos(rot))) end
        love.graphics.setColor(1, 1, 1)
        love.graphics.draw(img, x, y, 0, sx, sc, img:getWidth() / 2, img:getHeight() / 2)
        return
    end
    local w = rot and (math.abs(math.cos(rot)) * r + r * 0.15) or r
    love.graphics.setColor(0.62, 0.46, 0.08)
    love.graphics.ellipse("fill", x, y, w + 1, r + 1)
    love.graphics.setColor(0.95, 0.80, 0.30)
    love.graphics.ellipse("fill", x, y, w, r)
    love.graphics.setColor(1, 1, 1, 0.5)
    love.graphics.ellipse("fill", x - w * 0.3, y - r * 0.3, w * 0.25, r * 0.25)
end

-- Draw `kind` centred at (x, y), CONTAINED in a `size`×`size` box: the photo's
-- longest side is scaled to exactly `size`, so the whole product is visible.
-- The Butikk's square display windows use this.
function Icons.drawBox(kind, x, y, size, alpha)
    local img = Assets.image("icons/" .. tostring(kind) .. ".png")
    if img then
        if img:getFilter() ~= "linear" then img:setFilter("linear", "linear") end
        local scale = size / math.max(img:getWidth(), img:getHeight())
        love.graphics.setColor(1, 1, 1, alpha or 1)
        love.graphics.draw(img, x, y, 0, scale, scale, img:getWidth() / 2, img:getHeight() / 2)
        love.graphics.setColor(1, 1, 1)
        return
    end
    Icons.draw(kind, x, y, size)   -- glyphs span roughly one `s` already
end

-- Draw `kind` centred at (x, y), about `s` across. Unknown kinds fall back to a
-- generic crate.
function Icons.draw(kind, x, y, s)
    local img = Assets.image("icons/" .. tostring(kind) .. ".png")
    if img then
        -- linear: these are downscaled photos (like the boat), so smooth-shrink
        -- them rather than crunch to hard pixels
        if img:getFilter() ~= "linear" then img:setFilter("linear", "linear") end
        local scale = (s * 1.5) / math.max(img:getWidth(), img:getHeight())
        love.graphics.setColor(1, 1, 1)
        love.graphics.draw(img, x, y, 0, scale, scale, img:getWidth() / 2, img:getHeight() / 2)
        return
    end

    if kind == "smile" or (type(kind) == "string" and kind:match("^passenger")) then
        love.graphics.setColor(0.95, 0.80, 0.55)
        love.graphics.rectangle("fill", x - s * 0.22, y - s * 0.55, s * 0.44, s * 0.44)  -- head
        love.graphics.setColor(0.30, 0.45, 0.70)
        love.graphics.rectangle("fill", x - s * 0.40, y - s * 0.10, s * 0.80, s * 0.55)  -- body

    elseif kind == "fish" then
        love.graphics.setColor(0.55, 0.68, 0.82)
        love.graphics.rectangle("fill", x - s * 0.45, y - s * 0.22, s * 0.7, s * 0.44)   -- body
        love.graphics.polygon("fill", x + s * 0.25, y, x + s * 0.5, y - s * 0.3, x + s * 0.5, y + s * 0.3)
        love.graphics.setColor(0.12, 0.14, 0.18)
        love.graphics.rectangle("fill", x - s * 0.32, y - s * 0.08, s * 0.12, s * 0.12)  -- eye

    elseif kind == "apple" then
        love.graphics.setColor(0.82, 0.24, 0.20)
        love.graphics.circle("fill", x, y + s * 0.05, s * 0.40)
        love.graphics.setColor(0.45, 0.30, 0.16)                                          -- stem
        love.graphics.rectangle("fill", x - s * 0.04, y - s * 0.45, s * 0.08, s * 0.22)
        love.graphics.setColor(0.35, 0.55, 0.24)                                          -- leaf
        love.graphics.ellipse("fill", x + s * 0.16, y - s * 0.34, s * 0.16, s * 0.09)

    elseif kind == "lemon" then
        love.graphics.setColor(0.93, 0.82, 0.18)
        love.graphics.ellipse("fill", x, y, s * 0.42, s * 0.32)
        love.graphics.setColor(0.84, 0.72, 0.12)                                          -- nub
        love.graphics.ellipse("fill", x + s * 0.40, y, s * 0.08, s * 0.07)
        love.graphics.setColor(0.35, 0.52, 0.22)                                          -- leaf
        love.graphics.ellipse("fill", x - s * 0.22, y - s * 0.28, s * 0.16, s * 0.08)

    elseif kind == "bread" then
        love.graphics.setColor(0.74, 0.52, 0.28)                                          -- loaf top
        love.graphics.ellipse("fill", x, y - s * 0.02, s * 0.46, s * 0.30)
        love.graphics.setColor(0.62, 0.42, 0.22)                                          -- base
        love.graphics.rectangle("fill", x - s * 0.46, y - s * 0.02, s * 0.92, s * 0.18)
        love.graphics.setColor(0.50, 0.33, 0.16)                                          -- slashes
        for i = -1, 1 do
            love.graphics.rectangle("fill", x + i * s * 0.20 - s * 0.02, y - s * 0.20, s * 0.04, s * 0.16)
        end

    elseif kind == "juice" then
        love.graphics.setColor(0.32, 0.55, 0.72)                                          -- bottle glass
        love.graphics.rectangle("fill", x - s * 0.20, y - s * 0.34, s * 0.40, s * 0.66)
        love.graphics.rectangle("fill", x - s * 0.08, y - s * 0.48, s * 0.16, s * 0.16)  -- neck
        love.graphics.setColor(0.86, 0.34, 0.26)                                          -- red juice
        love.graphics.rectangle("fill", x - s * 0.16, y - s * 0.06, s * 0.32, s * 0.34)

    elseif kind == "cheese" then
        love.graphics.setColor(0.92, 0.76, 0.26)                                          -- wedge
        love.graphics.polygon("fill", x - s * 0.42, y + s * 0.26, x + s * 0.42, y + s * 0.26, x + s * 0.42, y - s * 0.22)
        love.graphics.setColor(0.80, 0.64, 0.16)                                          -- holes
        love.graphics.circle("fill", x + s * 0.10, y + s * 0.08, s * 0.07)
        love.graphics.circle("fill", x + s * 0.26, y + s * 0.16, s * 0.05)

    elseif kind == "cannon" then
        love.graphics.setColor(0.20, 0.20, 0.23)                                          -- barrel
        love.graphics.rectangle("fill", x - s * 0.5, y - s * 0.18, s * 0.85, s * 0.34)
        love.graphics.setColor(0.12, 0.12, 0.14)                                          -- wheels
        love.graphics.circle("fill", x - s * 0.34, y + s * 0.24, s * 0.18)
        love.graphics.circle("fill", x + s * 0.06, y + s * 0.24, s * 0.18)
        love.graphics.setColor(0.05, 0.05, 0.06)                                          -- ball at muzzle
        love.graphics.circle("fill", x + s * 0.52, y - s * 0.01, s * 0.17)

    elseif kind == "kanonkuler" then
        love.graphics.setColor(0.20, 0.20, 0.23)                                          -- small cannon behind
        love.graphics.rectangle("fill", x - s * 0.52, y - s * 0.30, s * 0.55, s * 0.22)
        love.graphics.setColor(0.12, 0.12, 0.14)
        love.graphics.circle("fill", x - s * 0.30, y - s * 0.04, s * 0.12)
        love.graphics.setColor(0.05, 0.05, 0.06)                                          -- pyramid of balls
        love.graphics.circle("fill", x + s * 0.02, y + s * 0.26, s * 0.16)
        love.graphics.circle("fill", x + s * 0.34, y + s * 0.26, s * 0.16)
        love.graphics.circle("fill", x + s * 0.18, y - s * 0.02, s * 0.16)
        love.graphics.setColor(0.35, 0.36, 0.40)                                          -- glints
        love.graphics.circle("fill", x + s * 0.13, y - s * 0.07, s * 0.04)
        love.graphics.circle("fill", x - s * 0.03, y + s * 0.21, s * 0.04)

    elseif kind == "shell" then
        love.graphics.setColor(0.94, 0.80, 0.72)                                          -- fan shell
        love.graphics.polygon("fill", x, y + s * 0.36, x - s * 0.42, y - s * 0.18, x - s * 0.14, y - s * 0.30,
            x, y - s * 0.34, x + s * 0.14, y - s * 0.30, x + s * 0.42, y - s * 0.18)
        love.graphics.setColor(0.82, 0.60, 0.55)                                          -- ribs
        love.graphics.setLineWidth(1)
        for i = -2, 2 do love.graphics.line(x, y + s * 0.34, x + i * s * 0.13, y - s * 0.24) end

    elseif kind == "starfish" then
        love.graphics.setColor(0.96, 0.62, 0.26)
        local arms = {}
        for i = 0, 4 do
            local a = -math.pi / 2 + i * (2 * math.pi / 5)
            arms[#arms + 1] = x + math.cos(a) * s * 0.46
            arms[#arms + 1] = y + math.sin(a) * s * 0.46
            local a2 = a + math.pi / 5
            arms[#arms + 1] = x + math.cos(a2) * s * 0.18
            arms[#arms + 1] = y + math.sin(a2) * s * 0.18
        end
        love.graphics.polygon("fill", arms)
        love.graphics.setColor(0.85, 0.50, 0.18)
        love.graphics.circle("fill", x, y, s * 0.10)

    elseif kind == "gem" then
        love.graphics.setColor(0.36, 0.78, 0.82)                                          -- facets
        love.graphics.polygon("fill", x, y - s * 0.36, x + s * 0.34, y - s * 0.08,
            x, y + s * 0.40, x - s * 0.34, y - s * 0.08)
        love.graphics.setColor(0.62, 0.92, 0.95)                                          -- top highlight
        love.graphics.polygon("fill", x, y - s * 0.36, x + s * 0.34, y - s * 0.08, x, y - s * 0.04, x - s * 0.34, y - s * 0.08)
        love.graphics.setColor(0.24, 0.58, 0.64)
        love.graphics.line(x, y - s * 0.04, x, y + s * 0.40)

    elseif kind == "pearl" then
        love.graphics.setColor(0.86, 0.78, 0.66)                                          -- open clam
        love.graphics.arc("fill", x, y + s * 0.06, s * 0.44, math.pi, 2 * math.pi)
        love.graphics.setColor(0.92, 0.86, 0.74)
        love.graphics.arc("fill", x, y + s * 0.10, s * 0.40, 0, math.pi)
        love.graphics.setColor(0.97, 0.96, 0.98)                                          -- the pearl
        love.graphics.circle("fill", x, y - s * 0.02, s * 0.16)
        love.graphics.setColor(1, 1, 1, 0.8)
        love.graphics.circle("fill", x - s * 0.05, y - s * 0.07, s * 0.05)

    elseif kind == "chest" then
        love.graphics.setColor(0.50, 0.33, 0.16)                                          -- box
        love.graphics.rectangle("fill", x - s * 0.42, y - s * 0.08, s * 0.84, s * 0.42)
        love.graphics.setColor(0.40, 0.26, 0.12)                                          -- lid
        love.graphics.arc("fill", x, y - s * 0.08, s * 0.42, math.pi, 2 * math.pi)
        love.graphics.setColor(0.85, 0.68, 0.28)                                          -- gold bands
        love.graphics.rectangle("fill", x - s * 0.42, y - s * 0.02, s * 0.84, s * 0.07)
        love.graphics.rectangle("fill", x - s * 0.05, y - s * 0.10, s * 0.10, s * 0.44)
        love.graphics.setColor(0.95, 0.82, 0.36)                                          -- lock
        love.graphics.rectangle("fill", x - s * 0.06, y + s * 0.06, s * 0.12, s * 0.12)

    elseif kind == "book" then
        -- An OPEN book with a gold star on the page. Drawn closed (a rectangle
        -- inside a rectangle) it read as a plain box at button size -- one
        -- playtester took it for a treasure chest. The open silhouette is
        -- unmistakable even at 27px, and the star says "the things I've found"
        -- to someone who can't read the word "album".
        love.graphics.setColor(0.50, 0.24, 0.19)                                          -- cover, peeking out
        love.graphics.polygon("fill", x - s * 0.48, y - s * 0.14, x, y - s * 0.26,
            x + s * 0.48, y - s * 0.14, x + s * 0.48, y + s * 0.34,
            x, y + s * 0.26, x - s * 0.48, y + s * 0.34)
        love.graphics.setColor(0.95, 0.92, 0.83)                                          -- left page
        love.graphics.polygon("fill", x - s * 0.44, y - s * 0.13, x - s * 0.03, y - s * 0.24,
            x - s * 0.03, y + s * 0.20, x - s * 0.44, y + s * 0.28)
        love.graphics.setColor(0.88, 0.85, 0.75)                                          -- right page (shaded)
        love.graphics.polygon("fill", x + s * 0.03, y - s * 0.24, x + s * 0.44, y - s * 0.13,
            x + s * 0.44, y + s * 0.28, x + s * 0.03, y + s * 0.20)
        love.graphics.setColor(0.40, 0.19, 0.14)                                          -- spine
        love.graphics.setLineWidth(math.max(1, s * 0.05))
        love.graphics.line(x, y - s * 0.25, x, y + s * 0.24)
        love.graphics.setLineWidth(1)
        love.graphics.setColor(0.95, 0.78, 0.28)                                          -- the sticker: a gold star
        local star = {}
        for i = 0, 9 do
            local a = -math.pi / 2 + i * (math.pi / 5)
            local rr = (i % 2 == 0) and s * 0.17 or s * 0.07
            star[#star + 1] = x - s * 0.23 + math.cos(a) * rr
            star[#star + 1] = y + s * 0.02 + math.sin(a) * rr
        end
        love.graphics.polygon("fill", star)

    elseif kind == "map" then
        -- The treasure map: aged parchment with a curled edge and a red X. Shown
        -- in the shelf while a hunt is live. Real art: assets/icons/map.png
        -- (assets/ui/treasuremap.png is the big reveal card, a different thing).
        love.graphics.setColor(0.86, 0.76, 0.53)
        love.graphics.rectangle("fill", x - s * 0.40, y - s * 0.34, s * 0.80, s * 0.68, 2, 2)
        love.graphics.setColor(0.72, 0.61, 0.40)                                          -- curled top edge
        love.graphics.rectangle("fill", x - s * 0.40, y - s * 0.34, s * 0.80, s * 0.10)
        love.graphics.setColor(0.60, 0.50, 0.32)                                          -- dashed route
        for i = -2, 1 do
            love.graphics.rectangle("fill", x + i * s * 0.16, y + s * 0.06, s * 0.08, s * 0.035)
        end
        love.graphics.setColor(0.76, 0.20, 0.16)                                          -- the X
        love.graphics.setLineWidth(math.max(2, s * 0.07))
        love.graphics.line(x + s * 0.10, y - s * 0.14, x + s * 0.30, y + s * 0.04)
        love.graphics.line(x + s * 0.30, y - s * 0.14, x + s * 0.10, y + s * 0.04)
        love.graphics.setLineWidth(1)

    elseif kind == "container" then
        -- Two stacked shipping containers. Deliberately NOT the wooden crate and
        -- NOT the treasure chest: New York ships containers, and borrowing the
        -- chest made its cargo look like treasure. Ribbed sides + a flat top so
        -- it reads as steel at a glance. Real art: assets/icons/container.png.
        local function box(by, col, dark)
            love.graphics.setColor(col)
            love.graphics.rectangle("fill", x - s * 0.44, by, s * 0.88, s * 0.30)
            love.graphics.setColor(dark)
            for i = -3, 3 do                                                              -- corrugated ribs
                love.graphics.rectangle("fill", x + i * s * 0.12 - s * 0.015, by + s * 0.04,
                    s * 0.03, s * 0.22)
            end
            love.graphics.rectangle("fill", x - s * 0.44, by, s * 0.88, s * 0.035)         -- top rail
            love.graphics.rectangle("fill", x - s * 0.44, by + s * 0.265, s * 0.88, s * 0.035)
        end
        box(y + s * 0.06, { 0.72, 0.34, 0.28 }, { 0.48, 0.20, 0.16 })                     -- lower: red
        box(y - s * 0.30, { 0.30, 0.48, 0.66 }, { 0.18, 0.30, 0.44 })                     -- upper: blue

    else                                                                                  -- generic crate
        love.graphics.setColor(0.60, 0.45, 0.28)
        love.graphics.rectangle("fill", x - s * 0.4, y - s * 0.4, s * 0.8, s * 0.8)
        love.graphics.setColor(0.40, 0.30, 0.20)
        love.graphics.rectangle("fill", x - s * 0.4, y - s * 0.05, s * 0.8, s * 0.1)
    end
    love.graphics.setColor(1, 1, 1)
end

return Icons
