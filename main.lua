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

-- Dev: no F3 key on iOS — four fingers down together toggles the profiler
-- overlay instead (config.DEV builds only; a kid's palm-mash must never
-- summon debug stats in production). Single touches already arrive as mouse
-- events.
function love.touchpressed()
    local config = require("src.config")
    if config.DEV and Game.profile and #love.touch.getTouches() >= 4 then
        Game.profile.on = not Game.profile.on
    end
end

function love.resize(w, h)
    Game:resize(w, h)
end

-- iOS kills suspended apps without calling love.quit — losing focus is the
-- last reliable moment to persist. Flush exploration + save there.
function love.focus(focused)
    if not focused then Game:onBlur() end
end

function love.quit()
    Game:quit()
end
