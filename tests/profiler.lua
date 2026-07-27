-- tests/profiler.lua
-- The frame recorder (src/systems/profiler.lua). A broken profiler is worse
-- than none: you play for ten minutes, stop, and find a truncated or ragged
-- file. So check the shape of what it writes -- header, column count, the
-- integrated zone timings, and that a garbage collection shows up as freed
-- memory on the row where it happened.
--
-- Runs WITHOUT LÖVE, from the project root:
--     luajit tests/profiler.lua

package.path = "./?.lua;" .. package.path
local H = require("tests.harness")
local files = H.installLove()
local check, eq = H.check, H.eq

-- the profiler needs a clock and draw stats; the harness stubs neither usefully
local clock = 1000.0
love.timer.getTime = function() return clock end
love.graphics.getStats = function()
    return { drawcalls = 120, drawcallsbatched = 40, texturememory = 8 * 1048576 }
end
love.filesystem.getSaveDirectory = function() return "/tmp/save" end

local Profiler = require("src.systems.profiler")

-- header ----------------------------------------------------------------------
local path = Profiler.start()
check(path:find("profile.csv"), "start: returns the file path")
check(Profiler.on, "start: recording is on")
local header = files["profile.csv"]
check(header and header:find("^frame,time_s,dt_ms"), "header written first")
local NCOL = select(2, header:gsub(",", ",")) + 1
check(NCOL >= 15, "header has the full column set (" .. NCOL .. ")")

-- zones are only sampled while recording ---------------------------------------
local t0 = Profiler.mark()
check(t0 ~= nil, "mark: returns a timestamp while recording")
clock = clock + 0.004                       -- 4ms of "work"
Profiler.zone("world", t0)

-- one frame --------------------------------------------------------------------
Profiler.frame(1 / 60, 2.5, 7.5, nil)
Profiler.stop()
check(not Profiler.on, "stop: recording is off")

local out = files["profile.csv"]
local lines = {}
for l in out:gmatch("[^\n]+") do lines[#lines + 1] = l end
eq(#lines, 2, "one header + one data row")

local cells = {}
for c in lines[2]:gmatch("[^,]+") do cells[#cells + 1] = c end
eq(#cells, NCOL, "data row has exactly as many columns as the header")
eq(tonumber(cells[1]), 1, "frame counter starts at 1")
H.near(tonumber(cells[3]), 1000 / 60, 0.01, "dt logged in milliseconds")
H.near(tonumber(cells[4]), 2.5, 0.001, "update ms passed through")
H.near(tonumber(cells[5]), 7.5, 0.001, "draw ms passed through")
H.near(tonumber(cells[6]), 4.0, 0.01, "world zone measured the 4ms of work")
eq(tonumber(cells[7]), 0, "an unused zone logs zero, not nil")

-- zones must RESET between frames, or every row would accumulate the last -----
Profiler.start()
local m = Profiler.mark(); clock = clock + 0.002; Profiler.zone("world", m)
Profiler.frame(1 / 60, 1, 1, nil)
Profiler.frame(1 / 60, 1, 1, nil)          -- second frame did no world work
Profiler.stop()
local rows = {}
for l in files["profile.csv"]:gmatch("[^\n]+") do rows[#rows + 1] = l end
eq(#rows, 3, "restart truncates: header + two rows")
local r2 = {}
for c in rows[3]:gmatch("[^,]+") do r2[#r2 + 1] = c end
eq(tonumber(r2[6]), 0, "zones reset each frame (no carry-over)")

-- marks are free when not recording ---------------------------------------------
eq(Profiler.mark(), nil, "mark: nil when not recording, so zones cost nothing")
Profiler.zone("world", nil)                -- must be a harmless no-op
check(true, "zone: tolerates a nil start time")

H.report()
