-- src/ui/album.lua
-- The treasure album: a full-screen wooden panel showing one slot per chest in
-- the world -- the collectible sticker once you've dug it up, a "?" until then.
-- Opened from the book button by the world map; a modal owned by the world scene
-- (while it's up the world is frozen, like the docking screen). Closing is a
-- click or Esc. When every chest is found it shows a little "all done" banner.

local config = require("src.config")
local Retro  = require("src.ui.retro")
local Icons  = require("src.ui.icons")

local WOOD = Retro.WOOD

local Album = {}
Album.__index = Album

function Album.new(world)
    return setmetatable({ world = world, t = 0 }, Album)
end

function Album:update(dt) self.t = self.t + dt end

-- Any click closes the album (it's just a viewer).
function Album:mousepressed(_, _, button)
    if button == 1 then self.world:closeAlbum() end
end

function Album:keypressed(key)
    if key == "escape" or key == "b" or key == "return" or key == "space" then
        self.world:closeAlbum()
    end
end

function Album:draw()
    local sw, sh = love.graphics.getDimensions()
    local fonts  = self.world.game.fonts
    local list   = self.world.treasures or {}
    local found  = 0
    for _, t in ipairs(list) do if t.found then found = found + 1 end end
    local complete = (#list > 0 and found == #list)

    -- dim the frozen world
    love.graphics.setColor(0, 0, 0, 0.62)
    love.graphics.rectangle("fill", 0, 0, sw, sh)

    -- panel sized to the screen
    local t  = math.max(3, math.floor(fonts.small:getHeight() * 0.22))
    local pw = math.min(sw * 0.8, 820)
    local ph = math.min(sh * 0.8, 560)
    local px = (sw - pw) / 2
    local py = (sh - ph) / 2
    local ix, iy, iw, ih = Retro.plaque(px, py, pw, ph, t)

    -- title
    love.graphics.setFont(fonts.big)
    local title = "Skattekiste"
    love.graphics.setColor(0, 0, 0, 0.5)
    love.graphics.print(title, ix + (iw - fonts.big:getWidth(title)) / 2 + 2, iy + 10 + 2)
    love.graphics.setColor(WOOD.accent)
    love.graphics.print(title, ix + (iw - fonts.big:getWidth(title)) / 2, iy + 10)

    -- count
    love.graphics.setFont(fonts.normal)
    local cnt = found .. " / " .. #list
    love.graphics.setColor(WOOD.text)
    love.graphics.print(cnt, ix + (iw - fonts.normal:getWidth(cnt)) / 2,
        iy + 12 + fonts.big:getHeight())

    -- grid of slots
    local n    = math.max(1, #list)
    local cols = math.min(n, 4)
    local rows = math.ceil(n / cols)
    local top  = iy + 24 + fonts.big:getHeight() + fonts.normal:getHeight()
    local areaH = (iy + ih) - top - 16
    local cell  = math.min(iw / cols, areaH / rows) * 0.82
    local gridW = cols * cell
    local gx0   = ix + (iw - gridW) / 2
    local gy0   = top + (areaH - rows * cell) / 2

    for k, tr in ipairs(list) do
        local c = (k - 1) % cols
        local r = math.floor((k - 1) / cols)
        local cx = gx0 + c * cell + cell / 2
        local cy = gy0 + r * cell + cell / 2
        local s  = cell * 0.72

        -- sunken slot
        Retro.bevel(cx - cell * 0.42, cy - cell * 0.42, cell * 0.84, cell * 0.84,
            WOOD.deep, WOOD.hi, WOOD.lo, math.max(2, math.floor(t * 0.6)), false)

        if tr.found then
            -- a gentle bob so the found stickers feel alive
            local bob = math.sin(self.t * 2 + k) * 2
            Icons.draw(tr.good, cx, cy + bob, s)
        else
            love.graphics.setFont(fonts.big)
            love.graphics.setColor(WOOD.hi[1], WOOD.hi[2], WOOD.hi[3], 0.55)
            local q = "?"
            love.graphics.print(q, cx - fonts.big:getWidth(q) / 2, cy - fonts.big:getHeight() / 2)
        end
    end

    -- footer: "all done" banner or a close hint
    love.graphics.setFont(fonts.normal)
    if complete then
        local msg = "Alle skatter funnet!"
        local pulse = 0.7 + 0.3 * math.sin(self.t * 6)
        love.graphics.setColor(config.colors.gold[1], config.colors.gold[2], config.colors.gold[3], pulse)
        love.graphics.print(msg, ix + (iw - fonts.normal:getWidth(msg)) / 2, iy + ih - fonts.normal:getHeight() - 8)
    else
        love.graphics.setFont(fonts.small)
        local hint = "Klikk for å lukke"
        love.graphics.setColor(WOOD.text[1], WOOD.text[2], WOOD.text[3], 0.7)
        love.graphics.print(hint, ix + (iw - fonts.small:getWidth(hint)) / 2, iy + ih - fonts.small:getHeight() - 8)
    end
    love.graphics.setColor(1, 1, 1)
end

return Album
