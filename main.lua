local Game = require("src.game")

function love.load()
    Game:load()
end

function love.update(dt)
    Game:update(dt)
end

function love.draw()
    Game:draw()
end

function love.keypressed(key, scancode, isrepeat)
    Game:keypressed(key, scancode, isrepeat)
end

function love.textinput(t)
    Game:textinput(t)
end

function love.mousepressed(x, y, button)
    Game:mousepressed(x, y, button)
end

function love.mousereleased(x, y, button)
    Game:mousereleased(x, y, button)
end

function love.mousemoved(x, y, dx, dy)
    Game:mousemoved(x, y, dx, dy)
end

-- No F3 key on iOS: four fingers together toggles the profiler, dev builds only
-- so a palm-mash can't summon debug stats. Single touches arrive as mouse events.
function love.touchpressed()
    local config = require("src.config")
    if config.DEV and Game.profile and #love.touch.getTouches() >= 4 then
        Game.profile.on = not Game.profile.on
    end
end

function love.resize(w, h)
    Game:resize(w, h)
end

-- iOS kills suspended apps without calling love.quit, so losing focus is the
-- last reliable moment to persist.
function love.focus(focused)
    if focused then Game:onFocus() else Game:onBlur() end
end

function love.quit()
    Game:quit()
end
