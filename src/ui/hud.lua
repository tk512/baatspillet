-- src/ui/hud.lua
-- Heads-up display drawn in screen space: coins, boat + cargo, the active
-- mission, and short-lived toast messages. Laid out from measured text widths
-- so labels never collide whatever the font size or town-name length.

local config     = require("src.config")
local Retro      = require("src.ui.retro")
local Icons      = require("src.ui.icons")
local HarborMark = require("src.ui.harbormark")

local HUD = {}
local WOOD = Retro.WOOD

-- Wooden plaque (raised outer bevel + sunken inner well); shared via Retro.
local plaque = Retro.plaque

local function coin(x, y, r) Icons.coin(x, y, r) end

-- world exposes: game (coins + fonts), boat, cargoSystem, nearPort, toast.
function HUD.draw(world)
    local c     = config.colors
    local fonts = world.game.fonts
    local sw    = love.graphics.getWidth()
    local sh    = love.graphics.getHeight()
    local smH   = fonts.small:getHeight()
    local nmH   = fonts.normal:getHeight()
    local t     = math.max(2, math.floor(smH * 0.20))   -- bevel thickness (scaled)

    -- The pause key lives INSIDE the info plaque (right edge), so the corner
    -- holds exactly one panel and nothing else.
    local leftX = 16

    -- Top-left: gold + boat + cargo plaque
    local pad  = math.max(6, math.floor(smH * 0.55))
    local gap  = math.floor(smH * 0.32)
    local cr   = nmH * 0.54                               -- coin radius (doubloon-sized)
    local goldStr  = tostring(world.game.state.coins) .. " gull"
    local boatStr  = "Båt: " .. (world.boat.displayName or world.boat.def.name)
    local cargoStr = "Last: " .. world.boat:cargoCount() .. " / " .. world.boat.capacity

    -- Bought goods (the "inventory") shown under the boat/cargo rows as a row of
    -- symbols only -- no text -- so a non-reader recognises them at a glance (and
    -- so Finn-Erik's drawings can replace them later via assets/icons/<icon>.png).
    local owned = {}
    for _, it in ipairs(world.game.data.shop) do
        if it.food then
            local n = world.game:foodCount(it.id)
            if n > 0 then owned[#owned + 1] = { it = it, count = n } end
        elseif it.ammo then
            local n = world.game:ammoCount()
            if n > 0 then owned[#owned + 1] = { it = it, count = n } end
        elseif it.stack then
            local n = world.game:cannonCount()
            if n > 0 then owned[#owned + 1] = { it = it, count = n } end
        elseif world.game:owns(it.id) then
            owned[#owned + 1] = { it = it }
        end
    end
    local invIcon = nmH * 0.9                             -- inventory icon size
    local invGap  = math.floor(invIcon * 0.35)
    local invPer  = 5                                     -- icons per row before wrapping
    local invRows = (#owned > 0) and math.ceil(#owned / invPer) or 0
    local invCols = math.min(#owned, invPer)
    local invW = (#owned > 0) and (invCols * invIcon + (invCols - 1) * invGap) or 0
    if #owned > 0 then invW = math.max(invW, fonts.small:getWidth("Kjøpt:")) end

    local row1W = cr * 2 + gap + fonts.normal:getWidth(goldStr)
    -- a finger-sized pause key column reserved along the plaque's right edge
    local pauseKey = math.max(34, math.floor(nmH * 1.2))
    local contentW = math.max(row1W, fonts.small:getWidth(boatStr),
        fonts.small:getWidth(cargoStr), invW) + pauseKey + pad
    local pw = contentW + (pad + t * 2) * 2
    local ph = (pad + t * 2) * 2 + nmH + gap + smH + gap + smH
    if #owned > 0 then ph = ph + gap + smH + gap + invRows * (invIcon + invGap) end
    local ix, iy = plaque(leftX, 16, pw, ph, t)

    -- the pause key itself: a small wooden button with the universal ⏸ bars,
    -- vertically centred on the plaque (the one way to pause / exit)
    do
        local kx = leftX + pw - (pad + t * 2) - pauseKey + pad * 0.4
        local ky = 16 + math.floor((ph - pauseKey) / 2)
        -- the WHOLE plaque is the pause target (easy for little fingers); the
        -- key is the visual cue, sinking while the board is held anywhere
        local down = Retro.isDown("hud.pause")
        Retro.bevel(kx, ky, pauseKey, pauseKey, WOOD.face, WOOD.hi, WOOD.lo,
            math.max(2, math.floor(pauseKey * 0.10)), not down)
        local off = down and math.max(1, math.floor(pauseKey * 0.08)) or 0
        love.graphics.setColor(WOOD.accent)
        local bw = pauseKey * 0.14
        local by, bh = ky + pauseKey * 0.28 + off, pauseKey * 0.44
        love.graphics.rectangle("fill", kx + pauseKey * 0.34 - bw / 2 + off, by, bw, bh, 1, 1)
        love.graphics.rectangle("fill", kx + pauseKey * 0.66 - bw / 2 + off, by, bw, bh, 1, 1)
        world._pauseBtnRect = { x = leftX, y = 16, w = pw, h = ph }
    end

    -- row 1: coin + gold count
    coin(ix + pad + cr, iy + pad + nmH * 0.5, cr)
    love.graphics.setFont(fonts.normal)
    love.graphics.setColor(c.gold)
    love.graphics.print(goldStr, ix + pad + cr * 2 + gap, iy + pad)
    -- rows 2 & 3: boat + cargo
    love.graphics.setFont(fonts.small)
    love.graphics.setColor(WOOD.text)
    local ry = iy + pad + nmH + gap
    love.graphics.print(boatStr, ix + pad, ry)
    love.graphics.print(cargoStr, ix + pad, ry + smH + gap)

    -- inventory: "Kjøpt:" header then a wrapped row of symbols only
    if #owned > 0 then
        local oy = ry + (smH + gap) * 2
        love.graphics.setFont(fonts.small)
        love.graphics.setColor(WOOD.accent)
        love.graphics.print("Kjøpt:", ix + pad, oy)
        local startY = oy + smH + gap
        for k, e in ipairs(owned) do
            local col, row = (k - 1) % invPer, math.floor((k - 1) / invPer)
            local cxk = ix + pad + col * (invIcon + invGap) + invIcon * 0.5
            local cyk = startY + row * (invIcon + invGap) + invIcon * 0.5
            Icons.draw(e.it.icon, cxk, cyk, invIcon)
            if e.count and e.count > 1 then        -- food stock: "xN" badge
                love.graphics.setFont(fonts.small)
                local lbl = "x" .. e.count
                love.graphics.setColor(0, 0, 0, 0.55)
                love.graphics.print(lbl, cxk + invIcon * 0.5 - fonts.small:getWidth(lbl) + 1, cyk + invIcon * 0.3 + 1)
                love.graphics.setColor(WOOD.text)
                love.graphics.print(lbl, cxk + invIcon * 0.5 - fonts.small:getWidth(lbl), cyk + invIcon * 0.3)
            end
        end
    end

    -- Treasure tally on the side, under the gold plaque, once the hunt is in play
    -- (cannon owned or a chest already found): filled / empty slots, like an album.
    if world.treasures and #world.treasures > 0 then
        local anyFound = false
        for _, tr in ipairs(world.treasures) do if tr.found then anyFound = true; break end end
        if world.game:owns("cannon") or anyFound then
            HUD.drawTreasureBar(world, leftX, 16 + ph + math.floor(gap * 1.5), t)
        end
    end

    -- Top-centre: current mission banner
    if world.boat.cargo[1] then
        HUD.drawMission(world, sw, c, fonts, smH, nmH, t)
    end

    if world.toast and world.toast.timer > 0 then
        HUD.drawToast(world, sw, sh, c, fonts)
    end

    love.graphics.setColor(1, 1, 1)
end

-- Side inventory of treasure chests: one slot per chest, the collectible sticker
-- once dug up, an empty sunken slot until then. A quick at-a-glance "how many
-- have I found" without opening the full album.
function HUD.drawTreasureBar(world, x, y, t)
    local fonts = world.game.fonts
    local smH   = fonts.small:getHeight()
    local pad   = math.max(6, math.floor(smH * 0.5))
    local slot  = smH * 1.5
    local gapi  = math.floor(slot * 0.22)
    local list  = world.treasures
    local n     = #list

    local rowW     = n * slot + (n - 1) * gapi
    local contentW = math.max(rowW, fonts.small:getWidth("Skatter"))
    local pw = contentW + (pad + t * 2) * 2
    local ph = (pad + t * 2) * 2 + smH + gapi + slot
    local ix, iy = plaque(x, y, pw, ph, t)
    world._skatterRect = { x = x, y = y, w = pw, h = ph }   -- click target -> album

    love.graphics.setFont(fonts.small)
    love.graphics.setColor(WOOD.accent)
    love.graphics.print("Skatter", ix + pad, iy + pad)

    local sy = iy + pad + smH + gapi
    local st = math.max(1, math.floor(t * 0.5))
    for k, tr in ipairs(list) do
        local sx = ix + pad + (k - 1) * (slot + gapi)
        Retro.bevel(sx, sy, slot, slot, WOOD.deep, WOOD.hi, WOOD.lo, st, false)  -- sunken slot
        if tr.found then
            Icons.draw("chest", sx + slot / 2, sy + slot / 2, slot * 0.86)       -- the chest image
        end
    end
    love.graphics.setColor(1, 1, 1)
end

-- Top-centre banner: "Oppdrag <icon>×N ▮ <BY>", destination in its town colour.
function HUD.drawMission(world, sw, c, fonts, smH, nmH, t)
    local m = world.boat.cargo[1]
    local pad  = math.max(8, math.floor(smH * 0.7))
    local gap  = math.floor(nmH * 0.55)
    local s    = nmH * 0.9                                 -- icon size
    local markW, markH = nmH * 1.05, nmH * 0.95            -- harbour badge (Bryggen emblem)
    local dest = m.toName
    local countStr = "×" .. m.count

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
