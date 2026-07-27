-- src/systems/profiler.lua
-- Frame-by-frame profiling to a CSV, for finding real hotspots in real play
-- (F4 in dev builds). The on-screen F3 overlay tells you *that* a frame was
-- slow; this tells you *which* ones, *where* you were standing, and whether the
-- garbage collector was the cause.
--
-- Written to LÖVE's save directory as profile.csv:
--   unfused (love .)  ~/Library/Application Support/LOVE/batspillet/profile.csv
--   fused (.app)      ~/Library/Application Support/batspillet/profile.csv
--
-- IT MUST NOT PERTURB WHAT IT MEASURES. A profiler that formats a string every
-- frame generates steady garbage and would manufacture the very GC hiccups
-- we're hunting. So samples go into a PREALLOCATED flat number array and are
-- formatted only at flush time, once every FLUSH_FRAMES.
--
-- Zones are opt-in and cost nothing when off:
--     local t0 = Profiler.mark()      -- nil unless recording
--     ...work...
--     Profiler.zone("world", t0)

local Profiler = {}

Profiler.on = false

-- Column order == CSV header order. Keep the two in sync.
local COLS = {
    "frame", "time_s", "dt_ms", "upd_ms", "draw_ms",
    "z_world", "z_fog", "z_hud", "z_minimap",
    "drawcalls", "batched", "tex_mb", "lua_kb", "gc_freed_kb",
    "objects", "ships", "boat_x", "boat_y",
}
local NCOL = #COLS
local FLUSH_FRAMES = 600            -- ~10s at 60fps between writes

local buf = {}                      -- flat: NCOL numbers per frame
for i = 1, FLUSH_FRAMES * NCOL do buf[i] = 0 end

local zones = { world = 0, fog = 0, hud = 0, minimap = 0 }
local nFrames, frameNo, lastLua, t0Session = 0, 0, 0, 0
local PATH = "profile.csv"

function Profiler.mark()
    if not Profiler.on then return nil end
    return love.timer.getTime()
end

function Profiler.zone(name, t0)
    if not t0 then return end
    zones[name] = (zones[name] or 0) + (love.timer.getTime() - t0) * 1000
end

local function flush()
    if nFrames == 0 then return end
    local parts = {}
    for f = 0, nFrames - 1 do
        local base, row = f * NCOL, {}
        for c = 1, NCOL do
            local v = buf[base + c]
            -- integers stay integers so the CSV is easy to eyeball
            row[c] = (v % 1 == 0) and string.format("%d", v) or string.format("%.3f", v)
        end
        parts[#parts + 1] = table.concat(row, ",")
    end
    -- Say so if the write fails. Swallowing it silently means playing for ten
    -- minutes and finding an empty file with no clue why.
    local ok, err = pcall(love.filesystem.append, PATH, table.concat(parts, "\n") .. "\n")
    if not ok and not Profiler._warned then
        Profiler._warned = true
        print("profiler: could not write " .. PATH .. ": " .. tostring(err))
    end
    nFrames = 0
end

-- Begin a fresh recording (truncates any previous file and writes the header).
function Profiler.start()
    pcall(love.filesystem.write, PATH, table.concat(COLS, ",") .. "\n")
    nFrames, frameNo = 0, 0
    lastLua = collectgarbage("count")
    t0Session = love.timer.getTime()
    Profiler.on = true
    return love.filesystem.getSaveDirectory() .. "/" .. PATH
end

function Profiler.stop()
    if not Profiler.on then return end
    Profiler.on = false
    flush()
end

function Profiler.toggle()
    if Profiler.on then Profiler.stop(); return nil end
    return Profiler.start()
end

-- One row. Call once per frame, after drawing. `world` is optional -- when the
-- active scene isn't the world we simply log zeros for its columns.
function Profiler.frame(dt, updMs, drawMs, world)
    if not Profiler.on then return end
    local st  = love.graphics.getStats()
    local lua = collectgarbage("count")

    -- A DROP in Lua memory means a collection ran this frame. Logging how much
    -- was freed alongside the frame time is what makes a GC hiccup visible:
    -- look for dt_ms spikes on rows where gc_freed_kb is large.
    local freed = lastLua - lua
    if freed < 0 then freed = 0 end
    lastLua = lua

    frameNo = frameNo + 1
    local base = nFrames * NCOL
    local i = base
    local function put(v) i = i + 1; buf[i] = v or 0 end

    put(frameNo)
    put(love.timer.getTime() - t0Session)
    put(dt * 1000)
    put(updMs)
    put(drawMs)
    put(zones.world)
    put(zones.fog)
    put(zones.hud)
    put(zones.minimap)
    put(st.drawcalls)
    put(st.drawcallsbatched)
    put(st.texturememory / 1048576)
    put(lua)
    put(freed)
    put(world and world.objects and #world.objects.list or 0)
    put(world and world.fleet and #world.fleet.ships or 0)
    put(world and world.boat and world.boat.x or 0)
    put(world and world.boat and world.boat.y or 0)

    zones.world, zones.fog, zones.hud, zones.minimap = 0, 0, 0, 0

    nFrames = nFrames + 1
    if nFrames >= FLUSH_FRAMES then flush() end
end

return Profiler
