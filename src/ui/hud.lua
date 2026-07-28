-- src/ui/hud.lua
-- Heads-up display drawn in screen space. It is deliberately split along one
-- line, and new HUD features should pick a side and stay there:
--
--   HAVE -- what the player owns: gold, cargo aboard, gear, treasures.
--           ALL of it lives in the shelf on the left (src/ui/shelf.lua), in one
--           slot grammar, so a child who cannot read learns it once.
--   DO   -- what the player is meant to do next: the mission banner up top when
--           there's a delivery on, and (in world.lua, via src/ui/pointer.lua)
--           the gold mission arrow or the treasure-chest marker. Never both:
--           there is only ever ONE thing to follow.
--
-- Nothing belonging to the player is ever drawn on the boat itself: the boat is
-- the thing the child is steering and it stays clean.
--
-- Laid out from measured text widths so labels never collide whatever the font
-- size or town-name length.

local config     = require("src.config")
local Retro      = require("src.ui.retro")
local Icons      = require("src.ui.icons")
local Shelf      = require("src.ui.shelf")
local HarborMark = require("src.ui.harbormark")

local HUD = {}
local WOOD = Retro.WOOD

-- Wooden plaque (raised outer bevel + sunken inner well); shared via Retro.
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

    -- Everything the player HAS, as one compact object down the left edge --
    -- with the pause key riding at the end of the gold row (Shelf.draw).
    --
    -- Pause has had four homes and each earlier one was wrong: the WHOLE
    -- inventory plaque used to be the button, so tapping your own bread paused
    -- the game; bottom-left was unfindable; above the shelf it ate a band of
    -- the left edge; under the minimap it sat as an orphaned square in the sea.
    -- On the gold line it's inside the panel the player already reads, costs
    -- almost no extra space, and still only the KEY is tappable.
    Shelf.draw(world, 16, 16, t, HUD.keySize(nmH))
    if world._shelfKeyRect then
        local k = world._shelfKeyRect
        HUD.drawPauseKey(world, k.x, k.y, nmH)
    end

    -- Top-centre: what to do next -- and DURING A HUNT, nothing at all.
    --
    -- There used to be a "Finn skatten!" parchment banner here. It's gone: the
    -- chest-with-an-arrow that hovers over the boat (World:drawTreasurePointer)
    -- says the same thing in the place the child is already looking, and the
    -- top-centre band is the most expensive strip of screen on a phone. The
    -- delivery banner stays suppressed while hunting, exactly as it was when the
    -- hunt banner replaced it: there is only one job at a time, the harbours
    -- refuse to give another (World:openDock "findfirst"), and the gold mission
    -- arrow already bows out (World:drawMissionPointer). Showing a destination
    -- town with no arrow pointing at it would be the one confusing combination.
    if world.boat.cargo[1] and not (world.activeTreasure and world:activeTreasure()) then
        HUD.drawMission(world, sw, c, fonts, smH, nmH, t)
    end

    if world.toast and world.toast.timer > 0 then
        HUD.drawToast(world, sw, sh, c, fonts)
    end

    love.graphics.setColor(1, 1, 1)
end

-- CONTROLS are the only things on the HUD that must be HIT, so they alone are
-- held to Apple's 44pt minimum touch target. Status (the shelf) is read, never
-- tapped, and is free to be smaller -- that split is what lets the shelf stay
-- compact on a phone without making anything unhittable.
function HUD.keySize(nmH)
    return math.max(config.TOUCH_MIN, math.floor(nmH * 1.2))
end

-- The one way to pause / exit: a wooden key with the universal red ⏸ bars.
-- Red because it's the universal "stop" (user-group feedback: make pause
-- obviously pause), and finger-sized because a five-year-old is aiming it.
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

-- Top-centre banner: "Oppdrag <icon>×N ▮ <BY>", destination in its town colour.
-- Deliberately shows only the FIRST job: this is the "do" side, i.e. where to
-- steer next. Everything actually aboard is on the shelf.
function HUD.drawMission(world, sw, c, fonts, smH, nmH, t)
    local m = world.boat.cargo[1]
    local pad  = math.max(8, math.floor(smH * 0.7))
    local gap  = math.floor(nmH * 0.55)
    local s    = nmH * 0.9                                 -- icon size
    local markW, markH = nmH * 1.05, nmH * 0.95            -- harbour badge (Bryggen emblem)
    local dest = m.toName
    m._countStr = m._countStr or ("×" .. m.count)   -- count is fixed per mission
    local countStr = m._countStr

    local wLabel = fonts.normal:getWidth("Oppdrag")
    local wCount = fonts.normal:getWidth(countStr)
    local wDest  = fonts.normal:getWidth(dest)
    local content = wLabel + gap + s + gap * 0.4 + wCount + gap
                    + markW + gap * 0.5 + wDest

    local ph = nmH + (pad + t * 2)
    local pw = content + (pad + t * 2) * 2
    local px = math.floor(sw / 2 - pw / 2)
    local ix, iy, _, ih = plaque(px, 14, pw, ph, t)
    local cy = iy + ih / 2                                  -- vertical mid-line
    local function ty(fontH) return cy - fontH / 2 end

    local cx = ix + pad
    love.graphics.setFont(fonts.normal)

    -- label
    love.graphics.setColor(WOOD.accent)
    love.graphics.print("Oppdrag", cx, ty(nmH)); cx = cx + wLabel + gap

    -- icon ×N
    Icons.draw(m.icon, cx + s / 2, cy, s); cx = cx + s + gap * 0.4
    love.graphics.setColor(WOOD.text)
    love.graphics.print(countStr, cx, ty(nmH)); cx = cx + wCount + gap

    -- destination harbour badge + name in town colour (the town badge IS the
    -- "to" marker; the old "→" text rendered as a tofu box — no glyph)
    HarborMark.draw(cx, cy - markH / 2, markW, markH, m.color or WOOD.text)
    cx = cx + markW + gap * 0.5
    love.graphics.setColor(m.color or WOOD.text)
    love.graphics.print(dest, cx, ty(nmH))

    love.graphics.setColor(1, 1, 1)
end

function HUD.drawToast(world, sw, sh, c, fonts)
    local t = world.toast
    local alpha = math.min(1, t.timer)  -- fade out in the last second
    love.graphics.setFont(fonts.big)
    local w = fonts.big:getWidth(t.text)
    local x = sw / 2 - w / 2
    local y = sh * 0.30 - t.rise  -- floats upward as it fades

    love.graphics.setColor(0, 0, 0, 0.4 * alpha)
    love.graphics.print(t.text, x + 2, y + 2)
    love.graphics.setColor(c.gold[1], c.gold[2], c.gold[3], alpha)
    love.graphics.print(t.text, x, y)
end

return HUD
