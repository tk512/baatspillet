-- src/systems/loader.lua
-- Cooperative chunked loading: the world build is heavy, so running it in a
-- coroutine and calling Loader.tick() inside the big loops time-slices it and
-- lets the loading screen animate.
--
-- The loading scene sets Loader.deadline = now + budget before each resume;
-- tick() yields once that budget is used up. Outside a coroutine (e.g. an F5
-- synchronous load) deadline stays math.huge, so tick() is a no-op.

local Loader = { deadline = math.huge }

function Loader.tick()
    if Loader.deadline ~= math.huge
        and coroutine.running()
        and love.timer.getTime() >= Loader.deadline then
        coroutine.yield()
    end
end

return Loader
