-- Scene manager plus global state (coins, unlocks, fog), save/load, fonts and
-- the dev hotkeys. Scenes are plain modules exposing load/update/draw/keypressed
-- (+ optional mouse handlers); `game` is passed into load so they can reach
-- state/data/fonts without a circular require.

local config = require("src.config")
local Assets = require("src.assets")
local json   = require("src.json")

local Game = {}

Game.SAVE_FILE = "savegame.json"

local function defaultState()
    return {
        coins            = 0,
        unlockedBoats    = { "starter_boat" },
        discoveredIslands = {},
        owned            = {},   -- one-time upgrades, e.g. owned.cannon = true
        food             = {},   -- consumable provisions, e.g. food.brod = 3
    }
end

function Game:load()
    love.graphics.setDefaultFilter("nearest", "nearest")
    self:buildFonts()

    self:loadData()
    Assets.loadSounds()
    self:loadSave()

    if config.START_FULLSCREEN then
        love.window.setFullscreen(true, "desktop")
    end

    self.scenes = {
        menu    = require("src.scenes.menu"),
        loading = require("src.scenes.loading"),
        world   = require("src.scenes.world"),
    }

    Assets.startMusic()
    self:setScene("menu")
end

function Game:update(dt)
    -- Cap dt so a hitch (e.g. window drag) never teleports the boat.
    if dt > 0.05 then dt = 0.05 end
    if self.scene and self.scene.update then self.scene:update(dt) end
end

function Game:draw()
    if self.scene and self.scene.draw then self.scene:draw() end
end

function Game:setScene(name)
    assert(self.scenes[name], "unknown scene: " .. tostring(name))
    self.sceneName = name
    self.scene = self.scenes[name]
    if self.scene.load then self.scene:load(self) end
end

function Game:reloadScene()
    if self.scene and self.scene.load then
        self.scene:load(self)   -- re-run setup; global state (coins) persists
    end
end

-- Fonts scale with the window; 800 is the design height.
function Game:buildFonts()
    local s = love.graphics.getHeight() / 800
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
        ports = require("src.data.ports"),
        shop  = require("src.data.shop"),
    }
end

-- F6: re-read the data files from disk without restarting the game.
function Game:reloadData()
    package.loaded["src.data.boats"] = nil
    package.loaded["src.data.ports"] = nil
    package.loaded["src.data.shop"]  = nil
    self:loadData()
    self:reloadScene()
end

-- Look up a boat definition by id; falls back to the first boat.
function Game:getBoatDef(id)
    for _, b in ipairs(self.data.boats) do
        if b.id == id then return b end
    end
    return self.data.boats[1]
end

function Game:loadSave()
    self.state = defaultState()
    if love.filesystem.getInfo(self.SAVE_FILE) then
        local contents = love.filesystem.read(self.SAVE_FILE)
        local data = contents and json.decode(contents)
        if type(data) == "table" then
            -- Merge defensively so an old/partial save still loads.
            self.state.coins = data.coins or self.state.coins
            self.state.unlockedBoats = data.unlockedBoats or self.state.unlockedBoats
            self.state.discoveredIslands = data.discoveredIslands or self.state.discoveredIslands
            self.state.fog = data.fog or self.state.fog
            self.state.owned = data.owned or self.state.owned
            self.state.food = data.food or self.state.food
        end
    end
end

function Game:save()
    local ok, encoded = pcall(json.encode, self.state)
    if ok then
        love.filesystem.write(self.SAVE_FILE, encoded)
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

function Game:totalFood()
    local n = 0
    if self.state.food then for _, c in pairs(self.state.food) do n = n + c end end
    return n
end

function Game:buyFood(id, price)
    if self.state.coins < price then return false end
    self.state.coins = self.state.coins - price
    self.state.food = self.state.food or {}
    self.state.food[id] = (self.state.food[id] or 0) + 1
    self:save()
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
    elseif key == "f5" then
        self:reloadScene(); return
    elseif key == "f6" then
        self:reloadData(); return
    elseif key == "m" then
        config.AUDIO_ON = not config.AUDIO_ON
        Assets.refreshAudio(); return
    elseif key == "escape" then
        if self.sceneName == "world" then
            if self.scene.flushFog then self.scene:flushFog() end  -- persist exploration
            self:save()
            self:setScene("menu")
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
    local isFs = love.window.getFullscreen()
    love.window.setFullscreen(not isFs, "desktop")
    self:resize(love.graphics.getWidth(), love.graphics.getHeight())
end

function Game:mousepressed(x, y, button)
    if self.scene and self.scene.mousepressed then self.scene:mousepressed(x, y, button) end
end

function Game:mousereleased(x, y, button)
    if self.scene and self.scene.mousereleased then self.scene:mousereleased(x, y, button) end
end

function Game:mousemoved(x, y, dx, dy)
    if self.scene and self.scene.mousemoved then self.scene:mousemoved(x, y, dx, dy) end
end

function Game:wheelmoved(dx, dy)
    if self.scene and self.scene.wheelmoved then self.scene:wheelmoved(dx, dy) end
end

function Game:resize(w, h)
    self:buildFonts()
    if self.scene and self.scene.resize then self.scene:resize(w, h) end
end

function Game:quit()
    self:save()
    return false  -- allow the quit
end

return Game
