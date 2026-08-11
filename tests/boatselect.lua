-- tests/boatselect.lua
-- The boat screen's geometry: the on-screen ÆØÅ keyboard (BoatSelect:keyLayout)
-- and the name row (BoatSelect:layout) in src/scenes/boatselect.lua.
--
-- Worth a test file because the failure it pins was a HARD LOCK on every iPhone,
-- and it was invisible on the iPad the screen was laid out on. The keyboard's
-- four rows are sized by Scale.ui -- h/800 * PHONE.UI_BOOST -- so on a phone they
-- grow 1.6x faster than the screen they were anchored in at a fixed fraction of
-- sh. The bottom row went off the bottom: Slett, Mellomrom and Ferdig, measured
-- 57..118 px past the edge from an iPhone SE to a 17 Pro Max.
--
-- "Ferdig" is not one button among four. It is the ONLY exit from editing on a
-- touch device: mousepressed tests the key rects and returns, love.keypressed
-- can't fire on iOS, and there is no Tilbake key while editing. Off screen, it
-- meant tapping the name box trapped the player until they force-quit the app --
-- on the second screen of the game, in front of a five-year-old. So this file
-- pins, at every shape the game ships in:
--
--   * every key is fully on screen, Ferdig called out by name
--   * keys clear config.TOUCH_MIN -- a child taps these, so they are CONTROLS
--   * the name being typed never sits under the top key row
--   * the not-editing name box and "Nytt navn" also clear TOUCH_MIN, and the
--     Sett seil! key below them doesn't ride up over them
--   * a tap on nothing leaves editing -- the safety net, so the next layout
--     regression costs a mis-sized key and not a locked app
--
-- Plus the ÆØÅ name handling around it (insert/backspace/MAXLEN), since a name
-- that silently loses its last letter is the same kind of quiet bug.
--
-- Runs WITHOUT LÖVE, from the project root:
--     luajit tests/boatselect.lua
-- Exit code 0 = all green.

package.path = "./?.lua;" .. package.path
local H = require("tests.harness")
H.installLove()
H.installUtf8()

local Scale      = require("src.ui.scale")
local config     = require("src.config")
local BoatSelect = require("src.scenes.boatselect")
local boats      = require("src.data.boats")
local Game       = require("src.game")
local check, eq  = H.check, H.eq

-- The two boat lists the chooser ships with. The short one is what a hand-out
-- .love shows on an engine with no live 3D (Game.visibleBoats) -- and it is a
-- DIFFERENT branch of the strip geometry, not merely a smaller one: with nb = 2
-- `thumbW = min(sw * 0.86 / nb, 150 * k)` stops being the width term and pins to
-- the cap on every screen, which feeds thumbH, sx0 and the whole flow below it.
-- Built from the real predicate rather than by hand, so the test can't pin a
-- list the game never produces.
local LISTS = {
    { name = "alle båter",   boats = boats },
    { name = "uten 3D",      boats = (Game.visibleBoats(boats, false, false)) },
}
check(#LISTS[2].boats < #LISTS[1].boats,
    "the no-3D list is actually shorter -- otherwise this file tests one list twice")

-- Every shape the game ships in, plus two cruel ones. The iPhones are the point:
-- landscape-locked (ios/love-ios.plist), so the SHORT side is the height and it
-- is 375..440 pt while an iPad has 820..1024.
local SCREENS = {
    { name = "iPhone SE 667x375",     w = 667,  h = 375  },
    { name = "iPhone 14 Pro 852x393", w = 852,  h = 393  },
    { name = "iPhone 17 Pro 874x402", w = 874,  h = 402  },
    { name = "iPhone 17 PM 956x440",  w = 956,  h = 440  },
    { name = "iPad 1180x820",         w = 1180, h = 820  },
    { name = "iPad 13 1366x1024",     w = 1366, h = 1024 },
    { name = "desktop 1280x800",      w = 1280, h = 800  },
    { name = "tiny 640x360",          w = 640,  h = 360  },
    { name = "portrait 768x1024",     w = 768,  h = 1024 },
}

-- A stand-in for the scene: layout() and keyLayout() only read `editing` and the
-- boat list, so this is everything they touch.
local function scene(editing, list)
    return setmetatable({
        t = 0, index = 1, editing = editing, name = "Skvulpen", edited = true,
        game = {
            data  = { boats = list or boats },
            state = { selectedBoat = "starter_boat", boatNames = {} },
            boatDisplayName = function() return "Skvulpen" end,
            ownsBoat        = function() return true end,
            isPremium       = function() return false end,
            save            = function() end,
        },
    }, { __index = BoatSelect })
end

local function inside(r, w, h)
    return r.x >= 0 and r.y >= 0 and r.x + r.w <= w and r.y + r.h <= h
end

local function overlaps(a, b)
    return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

for _, s in ipairs(SCREENS) do
    Scale.phone = H.setScreen(s.w, s.h)
    local n = s.name

    -- ── editing: the keyboard ────────────────────────────────────────────────
    local ed   = scene(true)
    local keys = ed:keyLayout()
    local L    = ed:layout()

    check(#keys == 29 + 3, n .. ": 29 letters plus Slett/Mellomrom/Ferdig")

    local lowest, done = 0, nil
    for _, key in ipairs(keys) do
        check(inside(key, s.w, s.h),
            n .. ": key '" .. tostring(key.label) .. "' is on screen"
            .. (" (%d,%d %dx%d in %dx%d)"):format(key.x, key.y, key.w, key.h, s.w, s.h))
        check(key.h >= config.TOUCH_MIN,
            n .. ": key '" .. tostring(key.label) .. "' meets TOUCH_MIN ("
            .. math.floor(key.h) .. " >= " .. config.TOUCH_MIN .. ")")
        check(key.w >= config.TOUCH_MIN,
            n .. ": key '" .. tostring(key.label) .. "' is wide enough")
        lowest = math.max(lowest, key.y + key.h)
        if key.kind == "done" then done = key end
    end

    -- Called out on its own: it is the only way out of editing on a touch screen.
    check(done ~= nil, n .. ": there IS a Ferdig key")
    if done then
        check(inside(done, s.w, s.h),
            n .. ": Ferdig -- the ONLY exit from editing on touch -- is on screen")
    end
    check(lowest <= s.h,
        n .. (": the keyboard's bottom row ends at %d, screen is %d"):format(lowest, s.h))

    -- ── editing: the name being typed sits clear of the keys ─────────────────
    local top = math.huge
    for _, key in ipairs(keys) do top = math.min(top, key.y) end
    check(not overlaps(L.editBox, { x = 0, y = top, w = s.w, h = s.h - top }),
        n .. (": the name box (%d..%d) clears the top key row (%d)")
            :format(L.editBox.y, L.editBox.y + L.editBox.h, top))
    check(inside(L.editBox, s.w, s.h), n .. ": the name box is on screen")

    -- ── not editing: the name row and the keys around it ─────────────────────
    -- Run for BOTH boat lists: the strip is the top of a flow (statsY and nameY
    -- hang off stripY + thumbH), so a different boat count moves every row under
    -- it. This is the screen that already shipped a layout bug which trapped the
    -- player, and this loop is the control that catches the next one.
    for _, list in ipairs(LISTS) do
    local n = s.name .. " / " .. list.name
    Scale.phone = H.setScreen(s.w, s.h)
    local sel = scene(false, list.boats)
    local L2  = sel:layout()

    for _, part in ipairs({ "nameBox", "nytt", "sail", "back" }) do
        check(inside(L2[part], s.w, s.h), n .. ": " .. part .. " is on screen")
    end
    -- Tapped, so they are CONTROLS: the name box opens the keyboard and Nytt navn
    -- rolls a name. Same rule the shelf's treasure slot is held to.
    check(L2.nameBox.h >= config.TOUCH_MIN,
        n .. (": the name box meets TOUCH_MIN (%d >= %d)")
            :format(math.floor(L2.nameBox.h), config.TOUCH_MIN))
    check(L2.nytt.h >= config.TOUCH_MIN,
        n .. (": Nytt navn meets TOUCH_MIN (%d >= %d)")
            :format(math.floor(L2.nytt.h), config.TOUCH_MIN))
    check(L2.back.h >= config.TOUCH_MIN,
        n .. (": Tilbake meets TOUCH_MIN (%d >= %d)")
            :format(math.floor(L2.back.h), config.TOUCH_MIN))
    check(L2.sail.h >= config.TOUCH_MIN, n .. ": Sett seil! meets TOUCH_MIN")

    check(not overlaps(L2.nameBox, L2.sail), n .. ": Sett seil! clears the name box")
    check(not overlaps(L2.nameBox, L2.nytt), n .. ": Nytt navn sits beside the name box")
    eq(#L2.strip, #list.boats, n .. ": one thumbnail per boat, no more and no fewer")
    for i, r in ipairs(L2.strip) do
        check(inside(r, s.w, s.h), n .. ": boat thumbnail " .. i .. " is on screen")
        check(not overlaps(r, L2.nameBox), n .. ": thumbnail " .. i .. " clears the name row")
        if i > 1 then
            check(not overlaps(L2.strip[i - 1], r),
                n .. ": thumbnail " .. i .. " clears its neighbour")
        end
    end
    end
end

-- ── the safety net: a tap on nothing leaves editing ─────────────────────────
-- Not a nicety. It is the reason a future mis-sized keyboard costs a mis-sized
-- keyboard, instead of an app a child cannot get out of.
Scale.phone = H.setScreen(874, 402)
local ed = scene(true)
ed.name, ed.edited = "Skvulpen", true
local keys = ed:keyLayout()
local far = { x = 0, y = 0 }                     -- top-left corner: title area
for _, key in ipairs(keys) do
    check(not (far.x >= key.x and far.x <= key.x + key.w
           and far.y >= key.y and far.y <= key.y + key.h), "the corner tap hits no key")
end
ed:mousepressed(far.x, far.y, 1)
eq(ed.editing, false, "a tap outside the keyboard leaves editing")
eq(ed.game.state.boatNames["nasse_noff"], "Skvulpen", "...and commits the name on the way out")

-- a tap ON a letter must still type, not escape
local ed2 = scene(true)
ed2.name, ed2.edited = "", true
local a
for _, key in ipairs(ed2:keyLayout()) do if key.label == "A" then a = key end end
ed2:mousepressed(a.x + a.w / 2, a.y + a.h / 2, 1)
eq(ed2.editing, true, "tapping a letter stays in editing")
eq(ed2.name, "a", "...and types it")

-- ── ÆØÅ name handling ───────────────────────────────────────────────────────
local nm = scene(true)
nm.name, nm.edited = "", true
for _, ch in ipairs({ "S", "J", "Ø", "O", "R", "M", "E", "N" }) do nm:insert(ch) end
eq(nm.name, "sjøormen", "insert lowercases, ÆØÅ included")
eq(nm:displayName(), "Sjøormen", "upperFirst capitalises a multibyte first letter")

nm:backspace()
eq(nm.name, "sjøorme", "backspace drops one character")
nm.name = "sjø"
nm:backspace()
eq(nm.name, "sj", "backspace drops a whole multibyte character, not one byte")
nm.name = ""
nm:backspace()
eq(nm.name, "", "backspace on an empty name is a no-op, not an error")

-- MAXLEN counts CHARACTERS, so a name of Ø's fits as many as a name of O's
local mx = scene(true)
mx.name, mx.edited = "", true
for _ = 1, 40 do mx:insert("Ø") end
local utf8 = require("utf8")
eq(utf8.len(mx.name), 14, "MAXLEN caps at 14 characters, not 14 bytes")

H.report()
