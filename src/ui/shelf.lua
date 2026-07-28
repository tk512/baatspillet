-- The "what do I have" surface: one plaque on the left holding everything the
-- player owns, in ONE grammar -- a sunken slot with an icon and an xN badge.
-- This is the HAVE side of the HUD split (see CLAUDE.md, "HAVE vs DO").
-- Sections are split by a thin rule with NO text headers, since the player
-- can't read them, and run most-changing first: gold, cargo, gear, treasure.

local config = require("src.config")
local Retro = require("src.ui.retro")
local Icons = require("src.ui.icons")
local Scale = require("src.ui.scale")

local Shelf = {}
local WOOD = Retro.WOOD

Shelf.PER_ROW = 4        -- slots before wrapping (keeps the plaque narrow)

-- shared by both slot kinds, so they can't drift apart in look
local function well(x, y, s, t)
    local st = math.max(1, math.floor(t * 0.5))
    Retro.bevel(x, y, s, s, WOOD.deep, WOOD.hi, WOOD.lo, st, false)
    return st
end

local function badge(x, y, s, st, lbl, font)
    love.graphics.setFont(font)
    local lw = font:getWidth(lbl)
    local bx, by = x + s - lw - st, y + s - font:getHeight() - st * 0.5
    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.print(lbl, bx + 1, by + 1)
    love.graphics.setColor(WOOD.text)
    love.graphics.print(lbl, bx, by)
end

-- sunken well, optional icon, optional xN badge
function Shelf.slot(x, y, s, icon, count, font, t)
    local st = well(x, y, s, t)
    if icon then Icons.draw(icon, x + s * 0.5, y + s * 0.5, s * 0.84) end
    if count and count > 1 then badge(x, y, s, st, "x" .. count, font) end
end

-- The treasure tally: ONE well filling with gold from the bottom, not one well
-- per chest. The gold HEIGHT is the message -- he can't read a fraction, so the
-- numerals ride along for the grown-up and must never be the only signal.
-- Static on purpose: `frac` and `label` come from Shelf.build, not per frame.
function Shelf.progressSlot(x, y, s, icon, frac, label, font, t)
    local st = well(x, y, s, t)
    -- plain rectangle anchored to the well's bottom: the well is a rectangle,
    -- so there's nothing to clip -- no stencil pass, no scissor
    local inner = s - st * 2
    local fh = math.floor(inner * math.max(0, math.min(1, frac)))
    if fh > 0 then
        love.graphics.setColor(0.85, 0.68, 0.28, 0.55)
        love.graphics.rectangle("fill", x + st, y + st + inner - fh, inner, fh)
    end
    -- icon sits high in the well so the fill has room to read underneath it
    if icon then Icons.draw(icon, x + s * 0.5, y + s * 0.44, s * 0.66) end
    if label then badge(x, y, s, st, label, font) end
end

-- the one place deciding a section's slot kind, so the layouts can't disagree
function Shelf.drawEntry(sec, e, x, y, s, font, t)
    if sec.progress then
        Shelf.progressSlot(x, y, s, e.icon, e.frac, e.label, font, t)
    else
        Shelf.slot(x, y, s, e.icon, e.count, font, t)
    end
end

-- Room a section needs, in its own slot size. One definition for both layouts:
-- when the phone flow and the desktop column each derived it, they had to agree
-- numerically or the plaque drew wrong on one device class. Multiple returns,
-- not a table -- this runs per section per frame.
local function sectionExtent(sec, gapi, perRow)
    local n = #sec
    if n == 0 then return 0, 0 end
    local s = sec.slot
    local cols = perRow and math.min(n, perRow) or n
    local rows = perRow and math.ceil(n / perRow) or 1
    return cols * s + (cols - 1) * gapi, rows * s + (rows - 1) * gapi
end

-- Rebuilds only when something behind it changed; entries are pooled, since
-- building tables per frame is steady GC garbage and micro-stutter.
-- Mixed with a MODULO, not a running product: a plain `sig = sig * k + v` chain
-- overflows a double's 53 exact bits after a dozen inputs, and it's the
-- EARLIEST ones that fall off -- gold is mixed first, so it would stop
-- invalidating the cache at all. Under 2^31 every mix stays exact.
local function mix(h, v)
    return (h * 31 + v) % 2147483647
end

-- EVERY input the build reads must be mixed in here. One that build branches on
-- but this ignores leaves the shelf stale until something unrelated bumps the
-- number: intermittent and unreproducible. See tests/shelf.lua.
local function signature(world)
    local game = world.game
    local sig = mix(0, game.state.coins)
    for _, job in ipairs(world.boat.cargo) do
        sig = mix(sig, job.count or 1)
    end
    sig = mix(sig, #world.boat.cargo)
    for _, it in ipairs(game.data.shop) do
        local n = (it.food and game:foodCount(it.id)) or (it.ammo and game:ammoCount())
            or (it.stack and game:cannonCount()) or (game:owns(it.id) and 1) or 0
        sig = mix(sig, n)
    end
    -- the tally's two inputs: hunt introduced at all, and chests dug up
    sig = mix(sig, world.huntSeen and 1 or 0)
    if world.treasures then
        for _, tr in ipairs(world.treasures) do sig = mix(sig, tr.found and 1 or 0) end
    end
    return sig
end

-- pooled, so a rebuild allocates nothing after the first
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
        -- slot size is per-section, not global: the tally is the only TAPPABLE
        -- slot and has to meet the touch minimum
        sh.treas.progress = true
        world._shelf = sh
    end
    local sig = signature(world)
    if sh.sig == sig then return sh end
    sh.sig = sig

    local game = world.game

    -- No treasure-MAP slot on purpose: the chest marker hovers over the boat
    -- for exactly as long as the hunt lasts, so a map icon would say the same
    -- thing twice and cost a slot on the panel we're trying to keep small.

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

    -- Skatter: ONE slot for the whole hunt, filled with gold in proportion to
    -- how many chests are dug up (Shelf.progressSlot).
    --
    -- It appears once the hunt has been INTRODUCED -- world.huntSeen, which
    -- latches on the first map -- and not before, so a player who has never seen
    -- a treasure map doesn't carry an empty well around. The old gate was
    -- `owns("cannon") or anyFound`, which was a leftover from when this row was
    -- four mystery holes; a cannon has nothing to do with treasure (you never
    -- needed one to grab a chest).
    for k = #sh.treas, 1, -1 do sh.treas[k] = nil end
    local total = (world.treasures and #world.treasures) or 0
    if total > 0 and world.huntSeen then
        local done = 0
        for _, tr in ipairs(world.treasures) do
            if tr.found then done = done + 1 end
        end
        local e = push(sh.treas, sh.pools[3], "chest", nil)
        e.frac  = done / total
        -- built HERE, not in the draw call: a "2/4" concatenated every frame is
        -- steady garbage, and this only changes when the signature does
        e.label = done .. "/" .. total
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
-- (No `slot` parameter: every section carries its own size now, sh.<sec>.slot.)
local function drawFlow(world, x, y, t, sh, fonts, nmH, pad, gapi, coinR, key)
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

    -- Pack: gold, then each non-empty section, wrapping whole sections.
    -- Row heights are measured PER ROW rather than assumed uniform: sections no
    -- longer share one slot size, because the treasure tally is bigger (it's the
    -- one slot the player taps). Pooled tables -- no per-frame allocation.
    local rows = sh.rows
    if not rows then rows = {}; sh.rows = rows end
    local rowH = sh.rowH
    if not rowH then rowH = {}; sh.rowH = rowH end
    for i = 1, #rowH do rowH[i] = nil end

    local row, used, widest, nrows = 1, goldW, goldW, 1
    rowH[1] = math.max(nmH, key)               -- row 1 carries the gold line + pause key
    for si, sec in ipairs(sections) do
        local w, h = sectionExtent(sec, gapi)
        if w > 0 then
            w = w + gapi * 3                                    -- + divider space
            if used + w > maxW and used > 0 then
                row, used = row + 1, 0
                nrows, rowH[row] = row, 0
            end
            rows[si] = row
            rowH[row] = math.max(rowH[row] or 0, h)
            used = used + w
            widest = math.max(widest, used)
        else
            rows[si] = nil
        end
    end

    -- where each row starts, accumulated from the measured heights
    local tops = sh.tops
    if not tops then tops = {}; sh.tops = tops end
    local acc = 0
    for r = 1, nrows do
        tops[r] = acc
        acc = acc + rowH[r] + gapi
    end

    local pw = widest + (pad + t * 2) * 2
    local ph = acc - gapi + (pad + t * 2) * 2
    local ix, iy = Retro.plaque(x, y, pw, ph, t)

    local rects = world._shelfRects
    if not rects then rects = {}; world._shelfRects = rects end

    -- gold first, on row 1
    local row1H = rowH[1]
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
            local rh = rowH[cr]
            local cy = iy + pad + tops[cr]
            -- vertical rule between groups: grouping without a word to read
            love.graphics.setColor(WOOD.lo[1], WOOD.lo[2], WOOD.lo[3], 0.7)
            love.graphics.rectangle("fill", cx + gapi, cy + 2, 1, rh - 4)
            cx = cx + gapi * 3

            local left, ss = cx, sec.slot
            for _, e in ipairs(sec) do
                Shelf.drawEntry(sec, e, cx, cy + (rh - ss) * 0.5, ss, fonts.small, t)
                cx = cx + ss + gapi
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

    -- PER-SECTION slot sizes. Everything is one size except the treasure tally,
    -- which is held to the touch minimum because it is the one slot in the whole
    -- shelf you can TAP (it opens the album -- see World:mousepressed).
    --
    -- The rest of the shelf is status: read, never touched, so it's free to be
    -- smaller (HUD.keySize's note). That split is what keeps the panel compact.
    -- Being the biggest slot also does a second job for a child who can't read:
    -- it is visibly not like the others, which is the wordless way of saying
    -- "this one does something when you poke it".
    sh.cargo.slot = slot
    sh.gear.slot  = slot
    sh.treas.slot = math.max(slot, key > 0 and key or config.TOUCH_MIN)

    if Scale.phone then
        return drawFlow(world, x, y, t, sh, fonts, nmH, pad, gapi, coinR, key)
    end

    local sections = { sh.cargo, sh.gear, sh.treas }

    -- width: the gold row (coin + number + pause key), or the widest section
    -- row, whichever needs more
    local goldStr = tostring(world.game.state.coins)
    local goldW = coinR * 2 + gapi + fonts.normal:getWidth(goldStr)
                  + (key > 0 and (gapi * 2 + key) or 0)
    local goldH = math.max(nmH, key)

    -- width and height both come from sectionExtent -- the same measurement the
    -- phone flow uses, so the two layouts can't drift apart numerically.
    local contentW = goldW
    local h = goldH
    for _, sec in ipairs(sections) do
        local w, secH = sectionExtent(sec, gapi, Shelf.PER_ROW)
        if w > 0 then
            contentW = math.max(contentW, w)
            h = h + gapi * 2 + secH       -- a divider's worth of space, then the rows
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

            local top, ss = cy, sec.slot
            local _, secH = sectionExtent(sec, gapi, Shelf.PER_ROW)
            for k, e in ipairs(sec) do
                local col = (k - 1) % Shelf.PER_ROW
                local row = math.floor((k - 1) / Shelf.PER_ROW)
                Shelf.drawEntry(sec, e, ix + pad + col * (ss + gapi),
                    cy + row * (ss + gapi), ss, fonts.small, t)
            end
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
