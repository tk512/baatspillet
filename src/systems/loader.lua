-- Time-slices the heavy world build: it runs in a coroutine, and Loader.tick()
-- inside the big loops yields once the frame's budget is spent so the loading
-- screen keeps animating. The loading scene sets `deadline` before each resume;
-- outside a coroutine (an F5 reload) it stays math.huge and tick() is a no-op.

local Loader = { deadline = math.huge }

function Loader.tick()
    if Loader.deadline ~= math.huge
        and coroutine.running()
        and love.timer.getTime() >= Loader.deadline then
        coroutine.yield()
    end
end

return Loader
