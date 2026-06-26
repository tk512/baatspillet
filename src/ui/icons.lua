-- src/ui/icons.lua
-- One place to draw the little game symbols (cargo, treats, the cannon) so the
-- HUD and the shop never duplicate icon art. Each is drawn centred at (x, y) and
-- roughly `s` wide.
--
-- Placeholder-first: if assets/icons/<kind>.png exists it's drawn instead of the
-- code shape, so Finn-Erik's own drawings drop in later with zero code changes.

local Assets = require("src.assets")

local Icons = {}

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
        love.graphics.setColor(0.62, 0.30, 0.24)                                          -- cover
        love.graphics.rectangle("fill", x - s * 0.36, y - s * 0.42, s * 0.72, s * 0.84, 2, 2)
        love.graphics.setColor(0.94, 0.90, 0.80)                                          -- pages
        love.graphics.rectangle("fill", x - s * 0.28, y - s * 0.34, s * 0.60, s * 0.68)
        love.graphics.setColor(0.85, 0.68, 0.28)                                          -- spine + star
        love.graphics.rectangle("fill", x - s * 0.36, y - s * 0.42, s * 0.10, s * 0.84)
        love.graphics.setColor(0.80, 0.55, 0.20)
        for i = -1, 1 do love.graphics.line(x - s * 0.20, y + i * s * 0.16, x + s * 0.26, y + i * s * 0.16) end

    else                                                                                  -- generic crate
        love.graphics.setColor(0.60, 0.45, 0.28)
        love.graphics.rectangle("fill", x - s * 0.4, y - s * 0.4, s * 0.8, s * 0.8)
        love.graphics.setColor(0.40, 0.30, 0.20)
        love.graphics.rectangle("fill", x - s * 0.4, y - s * 0.05, s * 0.8, s * 0.1)
    end
    love.graphics.setColor(1, 1, 1)
end

return Icons
