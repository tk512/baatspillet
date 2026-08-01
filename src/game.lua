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
        hintFollowArrow  = false,           -- one-time "Pilen viser vei" shown?
        -- Per-WORLD progress lives under maps[mapId]: switching maps must never
        -- leak exploration between worlds. See Game:mapState().
        maps             = {},
    }
end

function Game:load()
    love.graphics.setDefaultFilter("nearest", "nearest")

    -- Needed before fonts. mobile = any iOS; phone = small logical screen ->
    -- boosted UI and wider zoom. BATSIM dev windows count, so both are testable.
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

    -- iOS is always fullscreen natively; forcing a mode switch can reset the
    -- GL context
    if config.START_FULLSCREEN and not self.mobile and not os.getenv("BATSIM")
       and not os.getenv("BATSHOT") then
        love.window.setFullscreen(true, "desktop")
    end

    self.scenes = {
        menu      = require("src.scenes.menu"),
        info      = require("src.scenes.info"),      -- "Sånn spiller du", off the title
        boatselect = require("src.scenes.boatselect"),
        mapselect  = require("src.scenes.mapselect"),
        loading   = require("src.scenes.loading"),
        world     = require("src.scenes.world"),
    }

    -- F3 overlay: rolling update/draw timings, FPS, draw stats
    self.profile = { on = false, upd = 0, drw = 0 }

    Assets.startMusic()
    self:setScene("menu")
end

function Game:update(dt)
    -- cap dt so a hitch never teleports the boat
    if dt > 0.05 then dt = 0.05 end
    local p = self.profile
    -- only when F3 or F4 wants it; otherwise skip the clock reads
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
    -- last, so getStats() covers the whole frame
    Profiler.frame(self._dt or 0, self._updMs or 0, self._drawMs or 0,
        (self.sceneName == "world") and self.scene or nil)
end

-- Draw timings are CPU submit time, not GPU. FPS is real pacing, so FPS sitting
-- at the vsync cap while scrolling means the bottleneck is elsewhere.
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
    -- Clicks queued during a hitched transition would fire on the NEW scene --
    -- a double-tapped "Gå ut" once started a whole new voyage.
    self._sceneSwitchT = love.timer.getTime()
end

function Game:reloadScene()
    if self.scene and self.scene.load then
        self.scene:load(self)   -- re-run setup; global state (coins) persists
    end
end

-- Wipes PROGRESS back to the start -- map, gold, cannon, treasures -- but NEVER
-- what isn't progress: the paid entitlement, gold-unlocked boats, boat names and
-- the boat/map choice. "Spill igjen" must never cost a family their purchase.
-- FUTURE: rotate WORLD_SEED here so each finish gives a different map.
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

-- sized through Scale.ui; the rule is in src/ui/scale.lua
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

-- F6: re-read the data files without restarting
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

-- Fog, discovered islands and treasure belong to a WORLD, not the player;
-- gold, boats and premium stay global.
function Game:mapState(id)
    id = id or self.state.selectedMap or "norge"
    self.state.maps = self.state.maps or {}
    local ms = self.state.maps[id]
    if not ms then
        ms = { fog = nil, discoveredIslands = {}, treasuresFound = {}, treasuresMapped = {} }
        self.state.maps[id] = ms
    end
    -- loadSave takes `data.maps` wholesale, so an older or truncated save hands
    -- us a bucket with only some keys. Backfill here, the one place every caller
    -- goes through, rather than crash on a nil list in World:load.
    ms.discoveredIslands = ms.discoveredIslands or {}
    ms.treasuresFound    = ms.treasuresFound    or {}
    ms.treasuresMapped   = ms.treasuresMapped   or {}
    return ms
end

-- the player's name for a boat, else the boat's own
function Game:boatDisplayName(id)
    return (self.state.boatNames and self.state.boatNames[id]) or self:getBoatDef(id).name
end

-- by id, falling back to the first (free) map
function Game:getMapDef(id)
    for _, m in ipairs(self.data.maps) do
        if m.id == id then return m end
    end
    return self.data.maps[1]
end

-- Installs a map as THE world: its seed and islands go into config's live slots
-- (terrain and treasure read those) and its ports/ships files load. Worldgen is
-- seeded, so a map always builds the identical world.
function Game:applyMap(id)
    local m = self:getMapDef(id)
    if m.comingSoon then m = self.data.maps[1] end
    if m.premium and not self:isPremium() then m = self.data.maps[1] end
    self.state.selectedMap = m.id
    config.WORLD_SEED = m.seed
    config.ISLANDS    = m.islands
    config.CHANNELS   = m.channels or {}
    self.data.ports   = require(m.ports)
    self.data.ships   = require(m.ships)
    return m
end

-- by id, falling back to the first boat
function Game:getBoatDef(id)
    for _, b in ipairs(self.data.boats) do
        if b.id == id then return b end
    end
    return self.data.boats[1]
end

-- Development always owns the pack, so nobody clicks through a pretend purchase
-- every run: dev env vars, or running UNFUSED from the source tree. Shipped
-- builds are fused, so they're never affected. Nothing is written to the save.
function Game:isPremium()
    if config.DEV then return true end
    if love.filesystem.isFused and not love.filesystem.isFused() then return true end
    return self.state.premium == true
end

-- Free boats always; premium boats unlock together with the one pack, never
-- individually. Gold NEVER buys boats -- they are the pack's whole value.
function Game:ownsBoat(id)
    local def = self:getBoatDef(id)
    if not def.premium then return true end
    return self:isPremium()
end

-- Call only once the store confirms. Everything premium keys off isPremium(),
-- so one unlock opens it all.
function Game:unlockPremium()
    self.state.premium = true
    self:save()
end

-- Loads the save, falling back to the .bak when the main file is corrupt: an
-- iOS kill mid-write truncates it, and the backup makes that cost seconds
-- rather than the child's whole world.
-- Strings are validated as UTF-8 and re-encoded from Latin-1 when not -- the one
-- corruption the old JSON decoder produced. Pure Lua, so the tests can run it.
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
            -- merge defensively so an old or partial save still loads
            self.state.coins = data.coins or self.state.coins
            self.state.unlockedBoats = data.unlockedBoats or self.state.unlockedBoats
            self.state.maps = data.maps or self.state.maps
            self.state.owned = data.owned or self.state.owned
            self.state.food = data.food or self.state.food
            self.state.ammo = data.ammo or self.state.ammo
            self.state.cannons = data.cannons or self.state.cannons
            -- pre-ammo saves: a cannon owner starts loaded, that cannon counted
            if data.ammo == nil and data.owned and data.owned.cannon then
                self.state.ammo = config.CANNON.START_AMMO
            end
            if data.cannons == nil and data.owned and data.owned.cannon then
                self.state.cannons = 1
            end
            -- pre-maps saves kept world progress at the top level; it all
            -- belonged to Norge, the only world there was
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
            -- old saves had ONE boatName: it belonged to the selected boat
            self.state.boatNames = data.boatNames or self.state.boatNames
            if data.boatName and not data.boatNames then
                self.state.boatNames[self.state.selectedBoat] = data.boatName
            end
            -- repair names from the old decoder, which wrote Latin-1 bytes --
            -- invalid UTF-8 that crashes text drawing when the name is shown
            for id, nm in pairs(self.state.boatNames) do
                self.state.boatNames[id] = Game.repairUtf8(nm)
            end
            if data.premium ~= nil then self.state.premium = data.premium end
            if data.hintFindPort ~= nil then self.state.hintFindPort = data.hintFindPort end
            if data.hintFollowArrow ~= nil then self.state.hintFollowArrow = data.hintFollowArrow end
        end
    end
end

-- The previous good save is rotated to .bak BEFORE the real file is
-- overwritten, so a write killed mid-flight is recoverable. love.filesystem has
-- no atomic rename; this is the next best thing.
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

-- owns() checks a purchase, buyUpgrade() spends gold if you can afford it
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

-- bought repeatedly as a stock count, eaten on voyages
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

-- The first purchase unlocks the auto-cannon (owned.cannon, which every gating
-- check still reads); each further one speeds the battery up.
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

-- a stock like food, spent one per shot; each cannon ships with a starting one
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

-- false when the locker is empty, and the cannon stays quiet
function Game:useAmmo()
    if (self.state.ammo or 0) <= 0 then return false end
    self.state.ammo = self.state.ammo - 1
    -- No save() here: the cannon fires ~1/s in a fight and re-encoding
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
    elseif config.DEV and key == "f10" then
        -- Store screenshot: the backbuffer exactly as drawn, so it lands at the
        -- window's own size with no cursor, no menu bar and no window chrome —
        -- all three of which disqualify a shot taken with the system grabber.
        self.shotNo = (self.shotNo or 0) + 1
        local name = ("skjermbilde-%d-%dx%d.png")
            :format(self.shotNo, love.graphics.getWidth(), love.graphics.getHeight())
        love.graphics.captureScreenshot(name)
        print("screenshot -> " .. love.filesystem.getSaveDirectory() .. "/" .. name)
        return
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
        -- "Hovedmeny" to save + leave). A scene with its own idea of "back"
        -- (the title's quit ask, the help page) says so with onEscape, so
        -- there is ONE way out per screen rather than a key that quits behind
        -- the button that asks first. Everything else still quits.
        if self.sceneName == "world" and self.scene.togglePause then
            self.scene:togglePause()
        elseif self.scene and self.scene.onEscape then
            self.scene:onEscape()
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
