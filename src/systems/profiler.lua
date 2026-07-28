-- Per-frame CSV profiling (F4 in dev builds), written to LÖVE's save dir as
-- profile.csv. The F3 overlay says a frame was slow; this says which ones, where
-- the boat was, and whether the GC did it.
-- Samples go into a preallocated flat array and are formatted only at flush: a
-- profiler that builds a string per frame manufactures the hiccups it hunts.
-- Zones cost nothing when off:
--     local t0 = Profiler.mark()      -- nil unless recording
--     ...work...
--     Profiler.zone("world", t0)

local Profiler = {}

Profiler.on = false

-- column order == CSV header order, keep in sync
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
            row[c] = (v % 1 == 0) and string.format("%d", v) or string.format("%.3f", v)
        end
        parts[#parts + 1] = table.concat(row, ",")
    end
    -- say so on failure: a silent one means an empty file after ten minutes
    local ok, err = pcall(love.filesystem.append, PATH, table.concat(parts, "\n") .. "\n")
    if not ok and not Profiler._warned then
        Profiler._warned = true
        print("profiler: could not write " .. PATH .. ": " .. tostring(err))
    end
    nFrames = 0
end

-- truncates any previous file and writes the header
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

-- One row, once per frame after drawing. `world` is optional -- outside the
-- world scene its columns log zeros.
function Profiler.frame(dt, updMs, drawMs, world)
    if not Profiler.on then return end
    local st  = love.graphics.getStats()
    local lua = collectgarbage("count")

    -- A drop in Lua memory means a collection ran: a GC hiccup is a dt_ms spike
    -- on a row with a large gc_freed_kb.
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
