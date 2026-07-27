-- tests/harness.lua
-- Shared bits for the headless test files: the assertion counters and the
-- minimal LÖVE stub. Nothing here knows about the game -- each test file
-- requires this, adds whatever else it touches, and calls H.report() last.
--
-- Runs WITHOUT LÖVE (see the run command at the top of each test file).

local H = { passed = 0, failed = 0 }

function H.check(cond, msg)
    if cond then H.passed = H.passed + 1
    else H.failed = H.failed + 1; print("FAIL: " .. tostring(msg)) end
end

function H.eq(got, want, msg)
    H.check(got == want, string.format("%s (got %s, want %s)",
        tostring(msg), tostring(got), tostring(want)))
end

-- Floating point never lands on an exact value; angles and distances need slack.
function H.near(got, want, tol, msg)
    H.check(type(got) == "number" and math.abs(got - want) <= tol,
        string.format("%s (got %s, want %s +/- %s)",
            tostring(msg), tostring(got), tostring(want), tostring(tol)))
end

-- Install a LÖVE stub covering everything the game modules touch while being
-- required, plus an in-memory filesystem. `files` IS that filesystem, returned
-- so a test can seed it (a saved game) or inspect what was written.
function H.installLove(files)
    files = files or {}
    love = {
        filesystem = {
            getInfo = function(p) return files[p] ~= nil and { type = "file" } or nil end,
            read    = function(p) return files[p] end,
            write   = function(p, s) files[p] = s; return true end,
            append  = function(p, s) files[p] = (files[p] or "") .. s; return true end,
        },
        math   = { random = math.random, noise = function() return 0.5 end },
        timer  = { getTime = function() return 0 end },
        system = { getOS = function() return "OS X" end },
        -- Drawing and audio are never reached from a test; a no-op catch-all is
        -- enough to let the modules that mention them load.
        graphics = setmetatable({}, { __index = function() return function() end end }),
        audio    = setmetatable({}, { __index = function() return function() end end }),
    }
    return files
end

function H.report()
    print(string.format("%d passed, %d failed", H.passed, H.failed))
    if H.failed > 0 then os.exit(1) end
end

return H
