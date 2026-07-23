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

    -- HUD strings + inventory list are CACHED and rebuilt only when the values
    -- behind them change: building them fresh every frame is steady garbage
    -- feeding the GC (micro-stutter while sailing).
    local hc = world._hudCache
    if not hc then hc = { owned = {}, pool = {} }; world._hudCache = hc end
    local game = world.game
    if hc.coins ~= game.state.coins then
        hc.coins = game.state.coins
        hc.goldStr = tostring(hc.coins) .. " gull"
    end
    -- Just the gold (+ the bought-goods symbols below): boat name and cargo
    -- count used to have rows here, but the name is on the boat-select screen
    -- and the cargo is already visible on the Oppdrag panel — a shorter plaque
    -- covers less sea.
    local goldStr = hc.goldStr

    -- Bought goods (the "inventory") shown under the boat/cargo rows as a row of
    -- symbols only -- no text -- so a non-reader recognises them at a glance (and
    -- so Finn-Erik's drawings can replace them later via assets/icons/<icon>.png).
    -- A numeric signature of all the counts decides when the list is rebuilt.
    local sig = 0
    for _, it in ipairs(game.data.shop) do
        local n = (it.food and game:foodCount(it.id)) or (it.ammo and game:ammoCount())
            or (it.stack and game:cannonCount()) or (game:owns(it.id) and 1) or 0
        sig = sig * 61 + n
    end
    local owned = hc.owned
    if hc.invSig ~= sig then
        hc.invSig = sig
        for k = #owned, 1, -1 do owned[k] = nil end
        for _, it in ipairs(game.data.shop) do
            local n
            if it.food then n = game:foodCount(it.id)
            elseif it.ammo then n = game:ammoCount()
            elseif it.stack then n = game:cannonCount()
            elseif game:owns(it.id) then n = 1 end
            if n and n > 0 then
                local e = hc.pool[#owned + 1]
                if not e then e = {}; hc.pool[#owned + 1] = e end
                e.it = it
                e.count = (it.food or it.ammo or it.stack) and n or nil
                e.lbl = (e.count and e.count > 1) and ("x" .. e.count) or nil
                owned[#owned + 1] = e
            end
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
    local contentW = math.max(row1W, invW) + pauseKey + pad
    local pw = contentW + (pad + t * 2) * 2
    local ph = (pad + t * 2) * 2 + nmH
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
        -- red = the universal "stop" (user-group: make pause obviously pause)
        Retro.bevel(kx, ky, pauseKey, pauseKey, { 0.64, 0.24, 0.19 },
            { 0.80, 0.40, 0.33 }, { 0.36, 0.12, 0.09 },
            math.max(2, math.floor(pauseKey * 0.10)), not down)
        local off = down and math.max(1, math.floor(pauseKey * 0.08)) or 0
        love.graphics.setColor(0.99, 0.93, 0.85)
        local bw = pauseKey * 0.14
        local by, bh = ky + pauseKey * 0.28 + off, pauseKey * 0.44
        love.graphics.rectangle("fill", kx + pauseKey * 0.34 - bw / 2 + off, by, bw, bh, 1, 1)
        love.graphics.rectangle("fill", kx + pauseKey * 0.66 - bw / 2 + off, by, bw, bh, 1, 1)
        local r = world._pauseBtnRect
        if not r then r = {}; world._pauseBtnRect = r end
        r.x, r.y, r.w, r.h = leftX, 16, pw, ph
    end

    -- row 1: coin + gold count
    coin(ix + pad + cr, iy + pad + nmH * 0.5, cr)
    love.graphics.setFont(fonts.normal)
    love.graphics.setColor(c.gold)
    love.graphics.print(goldStr, ix + pad + cr * 2 + gap, iy + pad)

    -- inventory: "Kjøpt:" header then a wrapped row of symbols only
    if #owned > 0 then
        local oy = iy + pad + nmH + gap
        love.graphics.setFont(fonts.small)
        love.graphics.setColor(WOOD.accent)
        love.graphics.print("Kjøpt:", ix + pad, oy)
        local startY = oy + smH + gap
        for k, e in ipairs(owned) do
            local col, row = (k - 1) % invPer, math.floor((k - 1) / invPer)
            local cxk = ix + pad + col * (invIcon + invGap) + invIcon * 0.5
            local cyk = startY + row * (invIcon + invGap) + invIcon * 0.5
            Icons.draw(e.it.icon, cxk, cyk, invIcon)
            if e.lbl then                          -- food stock: "xN" badge (cached)
                love.graphics.setFont(fonts.small)
                local lbl = e.lbl
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
    local sr = world._skatterRect                            -- click target -> album
    if not sr then sr = {}; world._skatterRect = sr end
    sr.x, sr.y, sr.w, sr.h = x, y, pw, ph

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
