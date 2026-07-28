-- Scene manager plus global state (coins, unlocks, fog), save/load, fonts and
-- the dev hotkeys. Scenes are plain modules exposing load/update/draw/keypressed
-- (+ optional mouse handlers); `game` is passed into load so they can reach
-- state/data/fonts without a circular require.

local config = require("src.config")
local Assets = require("src.assets")
local json   = require("src.json")
local Scale  = require("src.ui.scale")
local Retro  = require("src.ui.retro")
local Profiler = require("src.systems.profiler")

local Game = {}

Game.SAVE_FILE = "savegame.json"
Game.SAVE_BAK  = "savegame.json.bak"   -- last-known-good copy (crash safety)

local function defaultState()
    return {
        coins            = 0,
        unlockedBoats    = { "nasse_noff" },
        selectedBoat     = "nasse_noff",    -- the default boat (boats.lua's first entry)
        selectedMap      = "norge",         -- world chosen on the map screen
        boatNames        = {},              -- player's name per boat id (absent = the boat's own)
        premium          = false,           -- the one "Kaptein-pakken" unlock (all premium content)
        owned            = {},   -- one-time upgrades, e.g. owned.cannon = true
        food             = {},   -- consumable provisions, e.g. food.brod = 3
        ammo             = 0,    -- cannonballs left (the cannon comes with some)
        cannons          = 0,    -- cannons bought; extras fire a bit faster
        hintFindPort     = false,           -- one-time "Finn en havn!" shown?
        -- Per-WORLD progress (fog, discovered islands, treasures) lives under
        -- maps[mapId] — switching maps must never leak exploration between
        -- worlds. See Game:mapState().
        maps             = {},
    }
end

function Game:load()
    love.graphics.setDefaultFilter("nearest", "nearest")

    -- Device class, needed before fonts. mobile = any iOS device; phone = small
    -- logical screen (iPhone) → boosted UI + wider zoom (config.PHONE). BATSIM
    -- dev windows on a Mac count too, so both modes are testable without a device.
    self.mobile = (love.system.getOS() == "iOS")
    self.touchCamera = self.mobile or (os.getenv("BATSIM") ~= nil)
    self.phone = self.touchCamera
        and math.min(love.graphics.getWidth(), love.graphics.getHeight()) < 500
    Scale.phone = self.phone

    self:buildFonts()

    self:loadData()
    Assets.loadSounds()
    self:loadSave()
    self:applyMap(self.state.selectedMap)

    -- iOS/iPadOS is always fullscreen at the device's native size; forcing a
    -- mode switch there is pointless and can reset the GL context.
    if config.START_FULLSCREEN and not self.mobile and not os.getenv("BATSIM") then
        love.window.setFullscreen(true, "desktop")
    end

    self.scenes = {
        menu      = require("src.scenes.menu"),
        boatselect = require("src.scenes.boatselect"),
        mapselect  = require("src.scenes.mapselect"),
        loading   = require("src.scenes.loading"),
        world     = require("src.scenes.world"),
    }

    -- Dev profiler overlay (F3): rolling update/draw timings + FPS + draw stats.
    self.profile = { on = false, upd = 0, drw = 0 }

    Assets.startMusic()
    self:setScene("menu")
end

function Game:update(dt)
    -- Cap dt so a hitch (e.g. window drag) never teleports the boat.
    if dt > 0.05 then dt = 0.05 end
    local p = self.profile
    -- Time the scene when EITHER the on-screen overlay (F3) or the CSV
    -- recorder (F4) wants it; otherwise skip the clock reads entirely.
    local t0 = ((p and p.on) or Profiler.on) and love.timer.getTime() or nil
    if self.scene and self.scene.update then self.scene:update(dt) end
    if t0 then
        local ms = (love.timer.getTime() - t0) * 1000
        self._updMs, self._dt = ms, dt
        if p and p.on then p.upd = p.upd * 0.9 + ms * 0.1 end   -- smoothed, for the overlay
    end
    Retro.updateFx(dt)   -- button star-bursts live above scenes
end

function Game:draw()
    local p = self.profile
    local t0 = ((p and p.on) or Profiler.on) and love.timer.getTime() or nil
    if self.scene and self.scene.draw then self.scene:draw() end
    if t0 then
        local ms = (love.timer.getTime() - t0) * 1000
        self._drawMs = ms
        if p and p.on then p.drw = p.drw * 0.9 + ms * 0.1 end
    end
    if p and p.on then self:drawProfiler() end
    Retro.drawFx()
    -- One CSV row per frame, last thing, so getStats() covers the whole frame.
    Profiler.frame(self._dt or 0, self._updMs or 0, self._drawMs or 0,
        (self.sceneName == "world") and self.scene or nil)
end

-- Compact dev overlay. Draw timings are CPU submit time (not GPU); FPS reflects
-- real frame pacing, so if FPS sits at the vsync cap (e.g. 60) while scrolling,
-- the bottleneck is elsewhere (vsync / scroll speed), not the frame budget.
function Game:drawProfiler()
    local f = (self.fonts and self.fonts.small) or love.graphics.getFont()
    love.graphics.setFont(f)
    local st  = love.graphics.getStats()
    local lines = {
        string.format("FPS %d    frame %.1f ms", love.timer.getFPS(),
            love.timer.getAverageDelta() * 1000),
        string.format("update %.2f ms   draw %.2f ms", self.profile.upd, self.profile.drw),
        string.format("drawcalls %d  (batched %d)", st.drawcalls, st.drawcallsbatched),
        string.format("tex %.1f MB   lua %.1f MB",
            st.texturememory / 1048576, collectgarbage("count") / 1024),
    }
    local pad, lh, w = 8, f:getHeight() + 2, 0
    for _, l in ipairs(lines) do w = math.max(w, f:getWidth(l)) end
    local x, y = 14, love.graphics.getHeight() - (#lines * lh + pad * 2) - 40
    love.graphics.setColor(0, 0, 0, 0.72)
    love.graphics.rectangle("fill", x - pad, y - pad, w + pad * 2, #lines * lh + pad * 2, 4, 4)
    love.graphics.setColor(0.45, 1.0, 0.55)
    for i, l in ipairs(lines) do love.graphics.print(l, x, y + (i - 1) * lh) end
    love.graphics.setColor(1, 1, 1)
end

function Game:setScene(name)
    assert(self.scenes[name], "unknown scene: " .. tostring(name))
    self.sceneName = name
    self.scene = self.scenes[name]
    if self.scene.load then self.scene:load(self) end
    Retro.cancelPress()
    -- Clicks queued up while a scene transition hitched would otherwise fire
    -- on the NEW scene (double-clicking a laggy "Gå ut" used to start a whole
    -- new voyage from the menu). Swallow input for a beat after any switch.
    self._sceneSwitchT = love.timer.getTime()
end

function Game:reloadScene()
    if self.scene and self.scene.load then
        self.scene:load(self)   -- re-run setup; global state (coins) persists
    end
end

-- Start a brand-new playthrough: wipe PROGRESS back to the first state (map
-- re-discovered, gold re-earned, cannon re-bought, treasures re-found) — but
-- NEVER the things that aren't progress: the PAID Kaptein-pakken entitlement,
-- gold-unlocked boats, the boats' names and the boat/map choice. "Spill igjen"
-- must never cost a family their purchase. Used by the win screen.
-- FUTURE: rotate the map here for variety (new WORLD_SEED per finish).
function Game:newGame()
    local keep = {
        premium       = self.state.premium,
        unlockedBoats = self.state.unlockedBoats,
        boatNames     = self.state.boatNames,
        selectedBoat  = self.state.selectedBoat,
        selectedMap   = self.state.selectedMap,
    }
    self.state = defaultState()
    for k, v in pairs(keep) do self.state[k] = v end
    self:save()
    if self.scenes then
        self:setScene("menu")   -- back to the title; "set sail" loads fresh
    end
end

-- Fonts scale via Scale.ui (window-proportional + phone boost); see
-- src/ui/scale.lua for the sizing rule.
function Game:buildFonts()
    local s = Scale.ui(1)
    self.fonts = {
        small  = love.graphics.newFont(math.floor(15 * s)),
        normal = love.graphics.newFont(math.floor(21 * s)),
        big    = love.graphics.newFont(math.floor(40 * s)),
        title  = love.graphics.newFont(math.floor(64 * s)),
    }
end

function Game:loadData()
    self.data = {
        boats = require("src.data.boats"),
        maps  = require("src.data.maps"),
        ports = require("src.data.ports"),
        shop  = require("src.data.shop"),
        ships = require("src.data.ships"),
    }
end

-- F6: re-read the data files from disk without restarting the game.
function Game:reloadData()
    package.loaded["src.data.boats"] = nil
    package.loaded["src.data.maps"]  = nil
    package.loaded["src.data.ports"] = nil
    package.loaded["src.data.ports_amerika"] = nil
    package.loaded["src.data.ships_amerika"] = nil
    package.loaded["src.data.shop"]  = nil
    package.loaded["src.data.ships"] = nil
    self:loadData()
    self:reloadScene()
end

-- Per-world progress bucket for a map id (default: the selected map).
-- Fog, discovered islands and treasure progress belong to a WORLD, not the
-- player; gold/boats/premium stay global.
function Game:mapState(id)
    id = id or self.state.selectedMap or "norge"
    self.state.maps = self.state.maps or {}
    local ms = self.state.maps[id]
    if not ms then
        ms = { fog = nil, discoveredIslands = {}, treasuresFound = {}, treasuresMapped = {} }
        self.state.maps[id] = ms
    end
    -- A bucket that came off disk can be missing its lists entirely: loadSave
    -- takes `data.maps` wholesale, so a save written by an older build (or one
    -- hand-edited, or truncated) hands us a table with only some keys. Backfill
    -- here, in the one place every caller goes through, rather than let the
    -- first `ipairs(ms.treasuresMapped)` in World:load crash on a nil.
    ms.discoveredIslands = ms.discoveredIslands or {}
    ms.treasuresFound    = ms.treasuresFound    or {}
    ms.treasuresMapped   = ms.treasuresMapped   or {}
    return ms
end

-- The player's name for a boat (falls back to the boat's own).
function Game:boatDisplayName(id)
    return (self.state.boatNames and self.state.boatNames[id]) or self:getBoatDef(id).name
end

-- Look up a map definition by id; falls back to the first (free) map.
function Game:getMapDef(id)
    for _, m in ipairs(self.data.maps) do
        if m.id == id then return m end
    end
    return self.data.maps[1]
end

-- Install a map as THE world: copy its seed/islands into config's live slots
-- (terrain + treasure read those) and load its ports/ships files. Worldgen is
-- seeded, so the same map always builds the identical world. Called by the map
-- selector before "loading", and at startup for the saved selection.
function Game:applyMap(id)
    local m = self:getMapDef(id)
    if m.comingSoon then m = self.data.maps[1] end
    if m.premium and not self:isPremium() then m = self.data.maps[1] end
    self.state.selectedMap = m.id
    config.WORLD_SEED = m.seed
    config.ISLANDS    = m.islands
    self.data.ports   = require(m.ports)
    self.data.ships   = require(m.ships)
    return m
end

-- Look up a boat definition by id; falls back to the first boat.
function Game:getBoatDef(id)
    for _, b in ipairs(self.data.boats) do
        if b.id == id then return b end
    end
    return self.data.boats[1]
end

-- Has the player bought the single premium pack (Kaptein-pakken)?
-- Development always owns it (no clicking through the pretend purchase):
-- either dev env vars (BATSIM/BATDEV) or running UNFUSED — i.e. `love .`
-- straight from the source tree. Shipped builds (iOS app, Mac dmg) are fused,
-- so they are never affected. Runtime-only; nothing is written to the save.
function Game:isPremium()
    if config.DEV then return true end
    if love.filesystem.isFused and not love.filesystem.isFused() then return true end
    return self.state.premium == true
end

-- Do we own this boat? Free boats always; premium boats are all unlocked together
-- by the one pack -- never bought individually.
-- Own a boat when it's free, or premium with the pack bought. Gold NEVER buys
-- boats — boats are the Kaptein-pakken's whole value (per Torbjørn).
function Game:ownsBoat(id)
    local def = self:getBoatDef(id)
    if not def.premium then return true end
    return self:isPremium()
end

-- Unlock the whole premium pack. PRETEND purchase for now (just flips the flag).
-- TODO(IAP): replace with a real App Store / Google Play non-consumable purchase
-- (and a "restore purchases"); call this only once the OS confirms it. Everything
-- premium already keys off Game:isPremium(), so one unlock opens it all.
function Game:unlockPremium()
    self.state.premium = true
    self:save()
end

-- Load the save, falling back to the .bak when the main file is corrupt
-- (an iOS app kill mid-write truncates it — the backup means "lose a few
-- seconds", never "lose the child's whole world").
-- Validate a string as UTF-8; if invalid, re-encode it as Latin-1 -> UTF-8
-- (the one corruption our old JSON decoder produced). Pure Lua: also runs
-- under plain luajit in the tests.
function Game.repairUtf8(s)
    if type(s) ~= "string" then return s end
    local i, n, valid = 1, #s, true
    while i <= n do
        local b = s:byte(i)
        if b < 0x80 then
            i = i + 1
        elseif b >= 0xC2 and b <= 0xDF then
            local b2 = s:byte(i + 1)
            if b2 and b2 >= 0x80 and b2 <= 0xBF then i = i + 2 else valid = false; break end
        elseif b >= 0xE0 and b <= 0xEF then
            local b2, b3 = s:byte(i + 1), s:byte(i + 2)
            if b2 and b3 and b2 >= 0x80 and b2 <= 0xBF and b3 >= 0x80 and b3 <= 0xBF then
                i = i + 3
            else valid = false; break end
        elseif b >= 0xF0 and b <= 0xF4 then
            local b2, b3, b4 = s:byte(i + 1), s:byte(i + 2), s:byte(i + 3)
            if b2 and b3 and b4 and b2 >= 0x80 and b2 <= 0xBF and b3 >= 0x80 and b3 <= 0xBF
               and b4 >= 0x80 and b4 <= 0xBF then
                i = i + 4
            else valid = false; break end
        else
            valid = false; break
        end
    end
    if valid then return s end
    local out = {}
    for j = 1, n do
        local b = s:byte(j)
        if b < 0x80 then
            out[#out + 1] = string.char(b)
        else
            out[#out + 1] = string.char(0xC0 + math.floor(b / 0x40), 0x80 + b % 0x40)
        end
    end
    return table.concat(out)
end

function Game:loadSave()
    self.state = defaultState()
    local contents, data
    for _, f in ipairs({ self.SAVE_FILE, self.SAVE_BAK }) do
        if love.filesystem.getInfo(f) then
            contents = love.filesystem.read(f)
            data = contents and json.decode(contents)
            if type(data) == "table" then
                self._lastGood = contents      -- seeds the .bak rotation
                break
            end
            data = nil                          -- corrupt: try the backup
        end
    end
    do
        if type(data) == "table" then
            -- Merge defensively so an old/partial save still loads.
            self.state.coins = data.coins or self.state.coins
            self.state.unlockedBoats = data.unlockedBoats or self.state.unlockedBoats
            self.state.maps = data.maps or self.state.maps
            self.state.owned = data.owned or self.state.owned
            self.state.food = data.food or self.state.food
            self.state.ammo = data.ammo or self.state.ammo
            self.state.cannons = data.cannons or self.state.cannons
            -- Saves from before cannonballs/multi-cannon: a cannon owner starts
            -- fully loaded, with that one cannon counted.
            if data.ammo == nil and data.owned and data.owned.cannon then
                self.state.ammo = config.CANNON.START_AMMO
            end
            if data.cannons == nil and data.owned and data.owned.cannon then
                self.state.cannons = 1
            end
            -- Pre-maps saves kept world progress at the top level: it all
            -- belonged to the one world that existed — Norge.
            if not data.maps and (data.fog or data.discoveredIslands
                    or data.treasuresFound or data.treasuresMapped) then
                local ms = self:mapState(data.selectedMap or "norge")
                ms.fog = data.fog
                ms.discoveredIslands = data.discoveredIslands or {}
                ms.treasuresFound = data.treasuresFound or {}
                ms.treasuresMapped = data.treasuresMapped or {}
            end
            self.state.selectedBoat = data.selectedBoat or self.state.selectedBoat
            self.state.selectedMap = data.selectedMap or self.state.selectedMap
            -- Names are per boat; old saves had ONE boatName — it belonged to
            -- the boat that was selected at the time.
            self.state.boatNames = data.boatNames or self.state.boatNames
            if data.boatName and not data.boatNames then
                self.state.boatNames[self.state.selectedBoat] = data.boatName
            end
            -- Repair names saved by the old \uXXXX decoder, which wrote
            -- Latin-1 bytes ("T\xF8ffe") -- invalid UTF-8 that crashes text
            -- drawing the moment the name is shown.
            for id, nm in pairs(self.state.boatNames) do
                self.state.boatNames[id] = Game.repairUtf8(nm)
            end
            if data.premium ~= nil then self.state.premium = data.premium end
            if data.hintFindPort ~= nil then self.state.hintFindPort = data.hintFindPort end
        end
    end
end

-- Save with backup rotation: keep the previous good save as .bak BEFORE
-- overwriting the real file, so a write interrupted by an app kill can always
-- be recovered by loadSave. (love.filesystem has no atomic rename; this is
-- the next-best guarantee.)
function Game:save()
    local ok, encoded = pcall(json.encode, self.state)
    if not ok then return end
    if self._lastGood and self._lastGood ~= encoded then
        love.filesystem.write(self.SAVE_BAK, self._lastGood)
    end
    if love.filesystem.write(self.SAVE_FILE, encoded) then
        self._lastGood = encoded
    end
end

function Game:addCoins(n)
    self.state.coins = self.state.coins + n
    self:save()
end

-- Shop ownership: owns() checks a purchase, buyUpgrade() spends gold to acquire
-- one (only if you can afford it). Both persist via the save.
function Game:owns(id)
    return self.state.owned and self.state.owned[id] == true
end

function Game:buyUpgrade(id, price)
    if self.state.coins < price then return false end
    self.state.coins = self.state.coins - price
    self.state.owned = self.state.owned or {}
    self.state.owned[id] = true
    self:save()
    return true
end

-- Food provisions: bought repeatedly (a stock count), eaten on voyages.
function Game:foodCount(id)
    return (self.state.food and self.state.food[id]) or 0
end

function Game:buyFood(id, price)
    if self.state.coins < price then return false end
    self.state.coins = self.state.coins - price
    self.state.food = self.state.food or {}
    self.state.food[id] = (self.state.food[id] or 0) + 1
    self:save()
    return true
end

-- Cannons: the first purchase unlocks the auto-cannon (owned.cannon, which all
-- the gating checks keep using); every further cannon fires the battery a bit
-- faster (config.CANNON.EXTRA_RATE per extra, capped at MAX_RATE).
function Game:cannonCount()
    return self.state.cannons or (self:owns("cannon") and 1 or 0)
end

function Game:cannonRate()
    local n = self:cannonCount()
    if n < 1 then return 1 end
    return math.min(1 + (n - 1) * config.CANNON.EXTRA_RATE, config.CANNON.MAX_RATE)
end

function Game:buyCannon(price)
    if self.state.coins < price then return false end
    self.state.coins = self.state.coins - price
    self.state.owned = self.state.owned or {}
    self.state.owned.cannon = true
    self.state.cannons = self:cannonCount() + 1
    self:save()
    return true
end

-- Cannonballs: a stock like food, but spent by the auto-cannon (one per shot).
-- Buy packs in the Butikk; each cannon comes with a starting stock.
function Game:ammoCount()
    return self.state.ammo or 0
end

function Game:addAmmo(n)
    self.state.ammo = (self.state.ammo or 0) + n
    self:save()
end

function Game:buyAmmo(price, n)
    if self.state.coins < price then return false end
    self.state.coins = self.state.coins - price
    self:addAmmo(n)
    return true
end

-- Spend one ball; false when the locker is empty (the cannon stays quiet).
function Game:useAmmo()
    if (self.state.ammo or 0) <= 0 then return false end
    self.state.ammo = self.state.ammo - 1
    -- No save() here: the auto-cannon fires ~1/s in a fight and re-encoding
    -- the whole state (fog blob included) each shot caused combat hitches.
    -- The count rides along on the next natural save (delivery, dock, blur).
    return true
end

-- Eat one unit of any food aboard (prefers the largest stock so it lasts).
-- Returns the eaten food's id, or nil if there's nothing to eat.
function Game:eatFood()
    if not self.state.food then return nil end
    local best, bestN = nil, 0
    for id, c in pairs(self.state.food) do
        if c > bestN then best, bestN = id, c end
    end
    if not best then return nil end
    self.state.food[best] = self.state.food[best] - 1
    if self.state.food[best] <= 0 then self.state.food[best] = nil end
    self:save()
    return best
end

-- Dev hotkeys + ESC, then forward to the active scene.
function Game:keypressed(key, scancode, isrepeat)
    if key == "f11" then
        self:toggleFullscreen(); return
    elseif config.DEV and key == "f5" then
        self:reloadScene(); return
    elseif config.DEV and key == "f6" then
        self:reloadData(); return
    elseif config.DEV and key == "f3" then
        self.profile.on = not self.profile.on; return   -- toggle dev profiler
    elseif config.DEV and key == "f4" then
        -- Record every frame to profile.csv in the save dir (F4 again to stop
        -- and flush). Play normally while it runs, then analyse the file.
        local path = Profiler.toggle()
        print(path and ("profiling -> " .. path) or "profiling stopped (flushed)")
        return
    elseif key == "m" then
        config.AUDIO_ON = not config.AUDIO_ON
        Assets.refreshAudio(); return
    elseif key == "escape" then
        -- In the world, ESC opens the pause/menu overlay (which has its own
        -- "Hovedmeny" to save + leave). Elsewhere it quits.
        if self.sceneName == "world" and self.scene.togglePause then
            self.scene:togglePause()
        else
            love.event.quit()
        end
        return
    end

    if self.scene and self.scene.keypressed then
        self.scene:keypressed(key, scancode, isrepeat)
    end
end

function Game:toggleFullscreen()
    if self.mobile then return end
    local isFs = love.window.getFullscreen()
    love.window.setFullscreen(not isFs, "desktop")
    self:resize(love.graphics.getWidth(), love.graphics.getHeight())
end

function Game:textinput(t)
    if self.scene and self.scene.textinput then self.scene:textinput(t) end
end

function Game:mousepressed(x, y, button)
    if self._sceneSwitchT and love.timer.getTime() - self._sceneSwitchT < 0.35 then
        return   -- stale click from before/during the scene switch
    end
    if self.scene and self.scene.mousepressed then self.scene:mousepressed(x, y, button) end
end

function Game:mousereleased(x, y, button)
    if self.scene and self.scene.mousereleased then self.scene:mousereleased(x, y, button) end
    Retro.cancelPress()   -- a release always ends the press, even off-button
end

function Game:mousemoved(x, y, dx, dy)
    if self.scene and self.scene.mousemoved then self.scene:mousemoved(x, y, dx, dy) end
end

function Game:resize(w, h)
    self:buildFonts()
    if self.scene and self.scene.resize then self.scene:resize(w, h) end
end

-- App losing focus (backgrounded, phone call): persist everything now —
-- on iOS this may be our last breath. Fog flush includes a save. On mobile
-- also pause ALL audio (music kept playing over the home screen otherwise);
-- desktop keeps playing when you merely switch windows.
function Game:onBlur()
    if self.sceneName == "world" and self.scene and self.scene.flushFog then
        pcall(function() self.scene:flushFog() end)
    end
    self:save()
    if self.mobile then
        self._pausedAudio = love.audio.pause()
    end
end

function Game:onFocus()
    if self._pausedAudio then
        love.audio.play(self._pausedAudio)
        self._pausedAudio = nil
    end
end

function Game:quit()
    Profiler.stop()   -- flush whatever hasn't been written yet
    self:save()
    return false  -- allow the quit
end

return Game
