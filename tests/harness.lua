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

-- LÖVE ships the Lua 5.3 `utf8` library; bare luajit does not, so any module
-- that requires it can't load headlessly (boatselect, minimap). This installs a
-- faithful stand-in for the two functions the game uses -- faithful on purpose:
-- a sloppy `offset` would let a real ÆØÅ bug pass, which is the one class of bug
-- this shim is standing in for.
function H.installUtf8()
    local u = { charpattern = "[%z\1-\127\194-\244][\128-\191]*" }

    -- byte index of every character start, plus the one-past-the-end position
    -- Lua's own utf8.offset returns for n == len + 1
    local function starts(s)
        local idx, i = {}, 1
        while i <= #s do
            idx[#idx + 1] = i
            local c = s:byte(i)
            i = i + ((c < 0x80) and 1 or (c < 0xE0) and 2 or (c < 0xF0) and 3 or 4)
        end
        idx[#idx + 1] = #s + 1
        return idx
    end

    function u.len(s) return #starts(s) - 1 end

    -- n > 0: the n-th character from the start. n < 0: the n-th from the end,
    -- so offset(s, -1) is the first byte of the last character. nil when there
    -- is no such position -- which is what boatselect's `if off then` guards on.
    function u.offset(s, n)
        local idx = starts(s)
        if n > 0 then return idx[n] end
        return idx[#idx + n]
    end

    package.preload["utf8"] = function() return u end
    return u
end

-- Screen-size stub. UI layout code reads the window through love.graphics, so a
-- test that walks device shapes sets them here. Mirrors Game:load's own rule for
-- the phone flag (min side < 500) rather than restating it per device, so the two
-- can't disagree about what counts as a phone.
function H.setScreen(w, h)
    love.graphics.getDimensions = function() return w, h end
    love.graphics.getWidth      = function() return w end
    love.graphics.getHeight     = function() return h end
    return math.min(w, h) < 500
end

function H.report()
    print(string.format("%d passed, %d failed", H.passed, H.failed))
    if H.failed > 0 then os.exit(1) end
end

return H
