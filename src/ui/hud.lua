-- Heads-up display, drawn in screen space. Split along one line that new HUD
-- features must pick a side of -- HAVE (the shelf, left) vs DO (mission banner,
-- top centre, plus the world pointers). See CLAUDE.md, "HAVE vs DO".
-- Laid out from measured text widths, so labels never collide.

local config     = require("src.config")
local Retro      = require("src.ui.retro")
local Icons      = require("src.ui.icons")
local Shelf      = require("src.ui.shelf")
local HarborMark = require("src.ui.harbormark")

local HUD = {}
local WOOD = Retro.WOOD

local plaque = Retro.plaque

-- world exposes: game (coins + fonts), boat, cargoSystem, nearPort, toast.
function HUD.draw(world)
    local c     = config.colors
    local fonts = world.game.fonts
    local sw    = love.graphics.getWidth()
    local sh    = love.graphics.getHeight()
    local smH   = fonts.small:getHeight()
    local nmH   = fonts.normal:getHeight()
    local t     = math.max(2, math.floor(smH * 0.20))   -- bevel thickness (scaled)

    -- everything the player HAS, plus the pause key riding at the end of the
    -- gold row -- only the key itself is tappable
    Shelf.draw(world, 16, 16, t, HUD.keySize(nmH))
    if world._shelfKeyRect then
        local k = world._shelfKeyRect
        HUD.drawPauseKey(world, k.x, k.y, nmH)
    end

    -- During a hunt the banner stays away: the chest marker over the boat is the
    -- job, and a destination town with no arrow pointing at it just confuses.
    if world.boat.cargo[1] and not (world.activeTreasure and world:activeTreasure()) then
        HUD.drawMission(world, sw, c, fonts, smH, nmH, t)
    end

    if world.toast and world.toast.timer > 0 then
        HUD.drawToast(world, sw, sh, c, fonts)
    end

    love.graphics.setColor(1, 1, 1)
end

-- Controls are the only HUD parts that get HIT, so they alone are held to
-- Apple's 44pt minimum; the shelf is read, not tapped, and may be smaller.
function HUD.keySize(nmH)
    return math.max(config.TOUCH_MIN, math.floor(nmH * 1.2))
end

-- Red for "stop", finger-sized because a five-year-old is aiming at it.
function HUD.drawPauseKey(world, x, y, nmH)
    local key  = HUD.keySize(nmH)
    local down = Retro.isDown("hud.pause")
    Retro.bevel(x, y, key, key, { 0.64, 0.24, 0.19 },
        { 0.80, 0.40, 0.33 }, { 0.36, 0.12, 0.09 },
        math.max(2, math.floor(key * 0.10)), not down)
    local off = down and math.max(1, math.floor(key * 0.08)) or 0
    love.graphics.setColor(0.99, 0.93, 0.85)
    local bw = key * 0.14
    local by, bh = y + key * 0.28 + off, key * 0.44
    love.graphics.rectangle("fill", x + key * 0.34 - bw / 2 + off, by, bw, bh, 1, 1)
    love.graphics.rectangle("fill", x + key * 0.66 - bw / 2 + off, by, bw, bh, 1, 1)
    local r = world._pauseBtnRect
    if not r then r = {}; world._pauseBtnRect = r end
    r.x, r.y, r.w, r.h = x, y, key, key
    love.graphics.setColor(1, 1, 1)
end

-- "Oppdrag <huddle of goods> <badge> <BY>". Only the FIRST job -- this is the
-- "do" side; what's aboard is on the shelf. The count is SHOWN, not written:
-- four passengers standing together say "four" to someone who can't read "x4"
-- (see Icons.cluster).
function HUD.drawMission(world, sw, c, fonts, smH, nmH, t)
    local m = world.boat.cargo[1]
    local pad  = math.max(8, math.floor(smH * 0.7))
    local gap  = math.floor(nmH * 0.55)
    local s    = nmH * 0.9                                 -- one item's size
    local markW, markH = nmH * 1.05, nmH * 0.95            -- harbour badge
    local dest = m.toName
    local wGoods = Icons.clusterWidth(m.count, s)

    local wLabel = fonts.normal:getWidth("Oppdrag")
    local wDest  = fonts.normal:getWidth(dest)
    local content = wLabel + gap + wGoods + gap
                    + markW + gap * 0.5 + wDest

    local ph = nmH + (pad + t * 2)
    local pw = content + (pad + t * 2) * 2
    local px = math.floor(sw / 2 - pw / 2)
    local ix, iy, _, ih = plaque(px, 14, pw, ph, t)
    local cy = iy + ih / 2
    local function ty(fontH) return cy - fontH / 2 end

    local cx = ix + pad
    love.graphics.setFont(fonts.normal)

    love.graphics.setColor(WOOD.accent)
    love.graphics.print("Oppdrag", cx, ty(nmH)); cx = cx + wLabel + gap

    Icons.cluster(m.figures or m.icon, m.count, cx + wGoods / 2, cy, s)
    cx = cx + wGoods + gap

    -- the town badge IS the "to" marker: an arrow glyph rendered as tofu
    HarborMark.draw(cx, cy - markH / 2, markW, markH, m.color or WOOD.text)
    cx = cx + markW + gap * 0.5
    love.graphics.setColor(m.color or WOOD.text)
    love.graphics.print(dest, cx, ty(nmH))

    love.graphics.setColor(1, 1, 1)
end

function HUD.drawToast(world, sw, sh, c, fonts)
    local t = world.toast
    local alpha = math.min(1, t.timer)  -- fades out in the last second
    love.graphics.setFont(fonts.big)
    local w = fonts.big:getWidth(t.text)
    local x = sw / 2 - w / 2
    local y = sh * 0.30 - t.rise        -- floats up as it fades

    love.graphics.setColor(0, 0, 0, 0.4 * alpha)
    love.graphics.print(t.text, x + 2, y + 2)
    love.graphics.setColor(c.gold[1], c.gold[2], c.gold[3], alpha)
    love.graphics.print(t.text, x, y)
end

return HUD
