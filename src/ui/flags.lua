-- Country flags for ship info and map cards, keyed by Norwegian country name.
-- Placeholder-first: assets/flags/<iso>.png, else the painted fallbacks below.
-- Aspect-fit with a hairline border so small flags stay crisp.

local Assets = require("src.assets")

local Flags = {}

-- country name -> ISO code, which is the image filename
local CODES = {
    ["Norge"]      = "no",
    ["Tyskland"]   = "de",
    ["Russland"]   = "ru",
    ["Amerika"]    = "us",
    ["Panama"]     = "pa",
    ["Sør-Afrika"] = "za",
}
Flags.CODES = CODES

function Flags.draw(country, x, y, w, h)
    local code = CODES[country]
    local img = code and Assets.image("flags/" .. code .. ".png")
    if img then
        if img:getFilter() ~= "linear" then img:setFilter("linear", "linear") end
        local sc = math.min(w / img:getWidth(), h / img:getHeight())
        local dw, dh = img:getWidth() * sc, img:getHeight() * sc
        local dx, dy = x + (w - dw) / 2, y + (h - dh) / 2
        love.graphics.setColor(1, 1, 1)
        love.graphics.draw(img, dx, dy, 0, sc, sc)
        love.graphics.setColor(0, 0, 0, 0.35)          -- hairline for crispness
        love.graphics.setLineWidth(1)
        love.graphics.rectangle("line", dx, dy, dw, dh)
        love.graphics.setColor(1, 1, 1)
        return
    end
    Flags.painted(country, x, y, w, h)
end

-- painted fallbacks, used when no image exists
function Flags.painted(country, x, y, w, h)
    local function band(n, i, r, g, b)        -- horizontal stripe i of n
        love.graphics.setColor(r, g, b)
        love.graphics.rectangle("fill", x, y + h * (i - 1) / n, w, h / n + 1)
    end
    if country == "Tyskland" then
        band(3, 1, 0.05, 0.05, 0.05); band(3, 2, 0.85, 0.10, 0.10); band(3, 3, 0.95, 0.78, 0.10)
    elseif country == "Russland" then
        band(3, 1, 0.97, 0.97, 0.99); band(3, 2, 0.10, 0.22, 0.65); band(3, 3, 0.80, 0.12, 0.14)
    elseif country == "Norge" then
        love.graphics.setColor(0.78, 0.10, 0.16); love.graphics.rectangle("fill", x, y, w, h)
        love.graphics.setColor(0.97, 0.97, 0.99)                       -- white cross
        love.graphics.rectangle("fill", x + w * 0.30, y, w * 0.16, h)
        love.graphics.rectangle("fill", x, y + h * 0.34, w, h * 0.30)
        love.graphics.setColor(0.10, 0.20, 0.55)                       -- blue cross
        love.graphics.rectangle("fill", x + w * 0.34, y, w * 0.08, h)
        love.graphics.rectangle("fill", x, y + h * 0.40, w, h * 0.18)
    elseif country == "Amerika" then
        for i = 1, 7, 2 do band(7, i, 0.80, 0.12, 0.14) end
        for i = 2, 6, 2 do band(7, i, 0.97, 0.97, 0.99) end
        love.graphics.setColor(0.10, 0.20, 0.55); love.graphics.rectangle("fill", x, y, w * 0.45, h * 0.55)
    elseif country == "Panama" then
        love.graphics.setColor(0.97, 0.97, 0.99); love.graphics.rectangle("fill", x, y, w, h)
        love.graphics.setColor(0.80, 0.12, 0.14); love.graphics.rectangle("fill", x + w / 2, y, w / 2, h / 2)
        love.graphics.setColor(0.10, 0.20, 0.55); love.graphics.rectangle("fill", x, y + h / 2, w / 2, h / 2)
    elseif country == "Sør-Afrika" then
        love.graphics.setColor(0.87, 0.11, 0.13); love.graphics.rectangle("fill", x, y, w, h / 2)
        love.graphics.setColor(0.00, 0.10, 0.53); love.graphics.rectangle("fill", x, y + h / 2, w, h / 2)
        local fx, fy = x + w * 0.45, y + h * 0.5
        love.graphics.setColor(0.97, 0.97, 0.99)
        love.graphics.setLineWidth(h * 0.40)
        love.graphics.line(x, y, fx, fy); love.graphics.line(x, y + h, fx, fy)
        love.graphics.line(fx, fy, x + w, fy)
        love.graphics.setColor(0.00, 0.47, 0.23)
        love.graphics.setLineWidth(h * 0.22)
        love.graphics.line(x, y, fx, fy); love.graphics.line(x, y + h, fx, fy)
        love.graphics.line(fx, fy, x + w, fy)
        love.graphics.setColor(0.99, 0.71, 0.08)
        love.graphics.polygon("fill", x, y + h * 0.06, x + w * 0.30, y + h * 0.5, x, y + h * 0.94)
        love.graphics.setColor(0.05, 0.05, 0.06)
        love.graphics.polygon("fill", x, y + h * 0.20, x + w * 0.21, y + h * 0.5, x, y + h * 0.80)
        love.graphics.setLineWidth(1)
    else
        -- unknown: a neutral pennant
        love.graphics.setColor(0.75, 0.73, 0.68)
        love.graphics.polygon("fill", x, y, x + w, y + h / 2, x, y + h)
    end
    love.graphics.setColor(1, 1, 1)
end

return Flags
