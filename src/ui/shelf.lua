-- src/ui/shelf.lua
-- THE "what do I have" surface. One compact plaque on the left edge holding
-- everything the player possesses, in ONE visual grammar: a sunken slot with an
-- icon in it, and a count badge when there's more than one.
--
-- The rule this enforces, and the reason the module exists:
--
--   HAVE  -> the shelf (gold, cargo aboard, gear, treasures)
--   DO    -> the mission banner, the gold arrow, the treasure arrow
--
-- Before this, possessions were spread over four different grammars (a text
-- "Kjøpt:" grid, a "Skatter" slot bar, the mission banner's ×N, and icons drawn
-- on the boat itself) and the counts were written three different ways. A child
-- who cannot read had to learn each one separately. Now he learns a slot once.
--
-- Sections are separated by a thin rule and carry NO text headers -- the player
-- can't read them. Order is most-changing first: gold, then what's aboard, then
-- gear, then the treasure tally.
--
-- Nothing is ever drawn on top of the boat: the boat is the thing the child is
-- steering and it must stay clean and legible.

local Retro = require("src.ui.retro")
local Icons = require("src.ui.icons")
local Scale = require("src.ui.scale")

local Shelf = {}
local WOOD = Retro.WOOD

Shelf.PER_ROW = 4        -- slots before wrapping (keeps the plaque narrow)

-- One slot: sunken well, optional icon, optional "xN" badge. An empty well is
-- how the treasure tally shows a chest you haven't found yet.
function Shelf.slot(x, y, s, icon, count, font, t)
    local st = math.max(1, math.floor(t * 0.5))
    Retro.bevel(x, y, s, s, WOOD.deep, WOOD.hi, WOOD.lo, st, false)
    if icon then Icons.draw(icon, x + s * 0.5, y + s * 0.5, s * 0.84) end
    if count and count > 1 then
        local lbl = "x" .. count
        love.graphics.setFont(font)
        local lw = font:getWidth(lbl)
        local bx, by = x + s - lw - st, y + s - font:getHeight() - st * 0.5
        love.graphics.setColor(0, 0, 0, 0.6)
        love.graphics.print(lbl, bx + 1, by + 1)
        love.graphics.setColor(WOOD.text)
        love.graphics.print(lbl, bx, by)
    end
end

-- Rebuild the section list only when something behind it actually changed.
-- Building tables every frame is steady garbage for the GC (micro-stutter while
-- sailing), so the slot entries are pooled and reused in place.
local function signature(world)
    local game = world.game
    local sig = game.state.coins
    for _, job in ipairs(world.boat.cargo) do
        sig = sig * 31 + (job.count or 1)
    end
    sig = sig * 17 + #world.boat.cargo
    for _, it in ipairs(game.data.shop) do
        local n = (it.food and game:foodCount(it.id)) or (it.ammo and game:ammoCount())
            or (it.stack and game:cannonCount()) or (game:owns(it.id) and 1) or 0
        sig = sig * 61 + n
    end
    if world.treasures then
        for _, tr in ipairs(world.treasures) do sig = sig * 3 + (tr.found and 1 or 0) end
    end
    return sig
end

-- A pooled slot entry, so a rebuild allocates nothing after the first time.
local function push(sec, pool, icon, count)
    local n = #sec + 1
    local e = pool[n]
    if not e then e = {}; pool[n] = e end
    e.icon, e.count = icon, count
    sec[n] = e
    return e
end

function Shelf.build(world)
    local sh = world._shelf
    if not sh then
        sh = { cargo = {}, gear = {}, treas = {}, pools = { {}, {}, {} } }
        world._shelf = sh
    end
    local sig = signature(world)
    if sh.sig == sig then return sh end
    sh.sig = sig

    local game = world.game

    -- NOTE: there is deliberately no treasure-map slot here. The big "Finn
    -- skatten!" banner is on screen for exactly as long as a hunt is active, so
    -- a map icon in the shelf would say the same thing twice and cost a row.

    -- Ombord: one slot per job aboard, its own count. This is what replaces
    -- drawing cargo on the boat -- and it's the only place that shows ALL of it
    -- (the mission banner only ever names the first job).
    for k = #sh.cargo, 1, -1 do sh.cargo[k] = nil end
    for _, job in ipairs(world.boat.cargo) do
        push(sh.cargo, sh.pools[1], job.icon or "box", job.count or 1)
    end

    -- Utstyr: everything bought in the Butikk that you still have.
    for k = #sh.gear, 1, -1 do sh.gear[k] = nil end
    for _, it in ipairs(game.data.shop) do
        local n
        if it.food then n = game:foodCount(it.id)
        elseif it.ammo then n = game:ammoCount()
        elseif it.stack then n = game:cannonCount()
        elseif game:owns(it.id) then n = 1 end
        if n and n > 0 then
            push(sh.gear, sh.pools[2], it.icon, (it.food or it.ammo or it.stack) and n or nil)
        end
    end

    -- Skatter: one slot per chest in the world, filled once dug up. Shown only
    -- once the hunt is actually in play, so it isn't a row of mystery holes.
    for k = #sh.treas, 1, -1 do sh.treas[k] = nil end
    if world.treasures and #world.treasures > 0 then
        local anyFound = false
        for _, tr in ipairs(world.treasures) do
            if tr.found then anyFound = true; break end
        end
        if game:owns("cannon") or anyFound then
            for _, tr in ipairs(world.treasures) do
                push(sh.treas, sh.pools[3], tr.found and "chest" or nil, nil)
            end
        end
    end
    return sh
end

local NAMES = { "cargo", "gear", "treasures" }

-- PHONE LAYOUT: flow the shelf ALONG THE WIDE AXIS.
--
-- An iPhone in landscape is 874x402: width is plentiful, height is the thing the
-- sea needs. The column layout below grows downward, which is exactly the wrong
-- axis -- a loaded shelf came to ~189pt, 47% of the screen. Flowed sideways the
-- same contents cost one slot's height, so NOTHING has to be hidden from the
-- small screen; it's laid out differently, not cut down.
--
-- Whole sections are packed per row rather than split mid-group, because a
-- section broken across two lines stops reading as one group.
local function drawFlow(world, x, y, t, sh, fonts, smH, nmH, pad, slot, gapi, coinR, key)
    local sections = { sh.cargo, sh.gear, sh.treas }
    local goldStr  = tostring(world.game.state.coins)
    -- the pause key rides at the end of the gold block, on the same line
    local goldW    = coinR * 2 + gapi + fonts.normal:getWidth(goldStr)
                     + (key > 0 and (gapi * 2 + key) or 0)

    -- room to the left of the minimap, minus the margins
    local maxW = love.graphics.getWidth() - x * 2
    if world.minimap then
        local mx = world.minimap:layout()
        maxW = mx - x - pad * 2
    end
    maxW = math.max(goldW, maxW - (pad + t * 2) * 2)

    -- pack: gold, then each non-empty section, wrapping whole sections
    local rows = sh.rows
    if not rows then rows = {}; sh.rows = rows end
    local row, used, widest, nrows = 1, goldW, goldW, 1
    for si, sec in ipairs(sections) do
        if #sec > 0 then
            local w = #sec * slot + (#sec - 1) * gapi + gapi * 3   -- + divider space
            if used + w > maxW and used > 0 then
                row, used = row + 1, 0
                nrows = row
            end
            rows[si] = row
            used = used + w
            widest = math.max(widest, used)
        else
            rows[si] = nil
        end
    end

    local rowH  = math.max(slot, nmH)
    local row1H = math.max(rowH, key)          -- row 1 also carries the pause key
    local pw = widest + (pad + t * 2) * 2
    local ph = row1H + (nrows - 1) * (rowH + gapi) + (pad + t * 2) * 2
    local ix, iy = Retro.plaque(x, y, pw, ph, t)

    local rects = world._shelfRects
    if not rects then rects = {}; world._shelfRects = rects end

    -- gold first, on row 1
    love.graphics.setFont(fonts.normal)
    Icons.coin(ix + pad + coinR, iy + pad + row1H * 0.5, coinR)
    love.graphics.setColor(WOOD.accent)
    love.graphics.print(goldStr, ix + pad + coinR * 2 + gapi,
        iy + pad + (row1H - nmH) * 0.5)
    if key > 0 then
        local kr = world._shelfKeyRect
        if not kr then kr = {}; world._shelfKeyRect = kr end
        kr.x = ix + pad + goldW - key
        kr.y = iy + pad + (row1H - key) * 0.5
        kr.w, kr.h = key, key
    end

    local cx, cr = ix + pad + goldW, 1
    for si, sec in ipairs(sections) do
        if #sec > 0 then
            if rows[si] ~= cr then                     -- wrapped: new line
                cr = rows[si]
                cx = ix + pad
            end
            -- row 1 is taller (it carries the pause key); later rows are plain
            local rh = (cr == 1) and row1H or rowH
            local cy = iy + pad + (cr > 1 and (row1H + gapi + (cr - 2) * (rowH + gapi)) or 0)
            -- vertical rule between groups: grouping without a word to read
            love.graphics.setColor(WOOD.lo[1], WOOD.lo[2], WOOD.lo[3], 0.7)
            love.graphics.rectangle("fill", cx + gapi, cy + 2, 1, rh - 4)
            cx = cx + gapi * 3

            local left = cx
            for _, e in ipairs(sec) do
                Shelf.slot(cx, cy + (rh - slot) * 0.5, slot, e.icon, e.count,
                    fonts.small, t)
                cx = cx + slot + gapi
            end
            local r = rects[NAMES[si]]
            if not r then r = {}; rects[NAMES[si]] = r end
            r.x, r.y, r.w, r.h = left, cy, cx - left, rh
        else
            rects[NAMES[si]] = nil
        end
    end

    love.graphics.setColor(1, 1, 1)
    return pw, ph
end

-- Lay the shelf out and draw it. Returns its width and height so the caller can
-- place anything below it. `rects` is filled with per-section hit boxes.
-- `key` is the size of the pause key, which lives at the end of the GOLD ROW --
-- the one row that always exists. It used to sit under the minimap, but that
-- left two orphaned squares floating in the sea; on the gold line it's part of
-- the panel the player already reads. Pass 0 to lay out without it.
function Shelf.draw(world, x, y, t, key)
    key = key or 0
    local fonts = world.game.fonts
    local smH   = fonts.small:getHeight()
    local nmH   = fonts.normal:getHeight()
    local sh    = Shelf.build(world)

    local pad  = math.max(5, math.floor(smH * 0.45))
    -- Phone slots are a touch larger: flowing sideways buys back so much height
    -- that legibility is worth more than the extra width.
    local slot = math.floor(smH * (Scale.phone and 1.9 or 1.55))
    local gapi = math.max(2, math.floor(slot * 0.16))
    local coinR = nmH * 0.46

    if Scale.phone then
        return drawFlow(world, x, y, t, sh, fonts, smH, nmH, pad, slot, gapi, coinR, key)
    end

    local sections = { sh.cargo, sh.gear, sh.treas }

    -- width: the gold row (coin + number + pause key), or the widest section
    -- row, whichever needs more
    local goldStr = tostring(world.game.state.coins)
    local goldW = coinR * 2 + gapi + fonts.normal:getWidth(goldStr)
                  + (key > 0 and (gapi * 2 + key) or 0)
    local goldH = math.max(nmH, key)
    local cols = 0
    for _, sec in ipairs(sections) do
        cols = math.max(cols, math.min(#sec, Shelf.PER_ROW))
    end
    local rowW = (cols > 0) and (cols * slot + (cols - 1) * gapi) or 0
    local contentW = math.max(goldW, rowW)

    -- height: gold row + a divider and rows for each non-empty section
    local h = goldH
    local shown = 0
    for _, sec in ipairs(sections) do
        if #sec > 0 then
            shown = shown + 1
            local rows = math.ceil(#sec / Shelf.PER_ROW)
            h = h + gapi * 2 + rows * slot + (rows - 1) * gapi
        end
    end

    local pw = contentW + (pad + t * 2) * 2
    local ph = h + (pad + t * 2) * 2
    local ix, iy = Retro.plaque(x, y, pw, ph, t)

    -- Gold reads as a NUMBER, not a slot: it's the one quantity worth counting,
    -- and a badge on a coin would bury it. It still lives inside the shelf so
    -- everything the player owns is one object on screen.
    Icons.coin(ix + pad + coinR, iy + pad + goldH * 0.5, coinR)
    love.graphics.setFont(fonts.normal)
    love.graphics.setColor(WOOD.accent)
    love.graphics.print(goldStr, ix + pad + coinR * 2 + gapi,
        iy + pad + (goldH - nmH) * 0.5)
    if key > 0 then
        local kr = world._shelfKeyRect
        if not kr then kr = {}; world._shelfKeyRect = kr end
        kr.x = ix + pad + goldW - key
        kr.y = iy + pad + (goldH - key) * 0.5
        kr.w, kr.h = key, key
    end

    local cy = iy + pad + goldH
    local rects = world._shelfRects
    if not rects then rects = {}; world._shelfRects = rects end
    local names = NAMES

    for si, sec in ipairs(sections) do
        if #sec > 0 then
            -- thin rule between groups: grouping without a word to read
            cy = cy + gapi
            love.graphics.setColor(WOOD.lo[1], WOOD.lo[2], WOOD.lo[3], 0.7)
            love.graphics.rectangle("fill", ix + pad, cy, contentW, 1)
            cy = cy + gapi

            local rows = math.ceil(#sec / Shelf.PER_ROW)
            local top = cy
            for k, e in ipairs(sec) do
                local col = (k - 1) % Shelf.PER_ROW
                local row = math.floor((k - 1) / Shelf.PER_ROW)
                Shelf.slot(ix + pad + col * (slot + gapi), cy + row * (slot + gapi),
                    slot, e.icon, e.count, fonts.small, t)
            end
            local secH = rows * slot + (rows - 1) * gapi
            local r = rects[names[si]]
            if not r then r = {}; rects[names[si]] = r end
            r.x, r.y, r.w, r.h = ix + pad, top, contentW, secH
            cy = cy + secH
        else
            rects[names[si]] = nil
        end
    end

    love.graphics.setColor(1, 1, 1)
    return pw, ph
end

return Shelf
