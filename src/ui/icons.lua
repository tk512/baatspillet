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

    else                                                                                  -- generic crate
        love.graphics.setColor(0.60, 0.45, 0.28)
        love.graphics.rectangle("fill", x - s * 0.4, y - s * 0.4, s * 0.8, s * 0.8)
        love.graphics.setColor(0.40, 0.30, 0.20)
        love.graphics.rectangle("fill", x - s * 0.4, y - s * 0.05, s * 0.8, s * 0.1)
    end
    love.graphics.setColor(1, 1, 1)
end

return Icons
