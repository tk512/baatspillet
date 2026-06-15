-- src/systems/fog.lua
-- Fog of war / exploration. The world starts as dark "unknown" cells; sailing
-- near a cell reveals it permanently (the reveal grid is saved), so uncovering
-- the map is a surprise. Coarse cells (config.FOG_CELL) keep it cheap to store
-- and give a chunky, Civ-like reveal.
--
-- Persistence format (game.state.fog):
--   { w=<cols>, h=<rows>, cell=<px>, rows = { "010..", "110..", ... } }
-- one string per column, one char ('0'/'1') per row.

local config = require("src.config")

local Fog = {}
Fog.__index = Fog

function Fog.new(saved)
    local self = setmetatable({}, Fog)
    self.cell = config.FOG_CELL
    self.w = math.ceil(config.WORLD_WIDTH  / self.cell)
    self.h = math.ceil(config.WORLD_HEIGHT / self.cell)
    self.grid = {}
    for cx = 0, self.w - 1 do self.grid[cx] = {} end

    -- Restore a saved reveal grid if it matches the current world dimensions.
    if type(saved) == "table" and saved.w == self.w and saved.h == self.h
       and type(saved.rows) == "table" then
        for cx = 0, self.w - 1 do
            local row = saved.rows[cx + 1]
            if type(row) == "string" then
                for cy = 0, self.h - 1 do
                    if row:sub(cy + 1, cy + 1) == "1" then self.grid[cx][cy] = true end
                end
            end
        end
    end
    return self
end

function Fog:cellOf(x, y)
    local cx = math.floor(x / self.cell)
    local cy = math.floor(y / self.cell)
    if cx < 0 then cx = 0 elseif cx > self.w - 1 then cx = self.w - 1 end
    if cy < 0 then cy = 0 elseif cy > self.h - 1 then cy = self.h - 1 end
    return cx, cy
end

function Fog:pointRevealed(x, y)
    local cx, cy = self:cellOf(x, y)
    return self.grid[cx][cy] == true
end

-- Reveal every cell whose center is within `radius` of (x, y). Returns true if
-- at least one NEW cell was lit (so the caller knows to re-save).
function Fog:revealAround(x, y, radius)
    local new = false
    local r = math.ceil(radius / self.cell)
    local ccx, ccy = self:cellOf(x, y)
    local r2 = radius * radius
    for cx = ccx - r, ccx + r do
        if cx >= 0 and cx < self.w then
            for cy = ccy - r, ccy + r do
                if cy >= 0 and cy < self.h and not self.grid[cx][cy] then
                    local px = (cx + 0.5) * self.cell
                    local py = (cy + 0.5) * self.cell
                    local dx, dy = px - x, py - y
                    if dx * dx + dy * dy <= r2 then
                        self.grid[cx][cy] = true
                        new = true
                    end
                end
            end
        end
    end
    return new
end

function Fog:serialize()
    local rows = {}
    for cx = 0, self.w - 1 do
        local cols = {}
        for cy = 0, self.h - 1 do
            cols[cy + 1] = self.grid[cx][cy] and "1" or "0"
        end
        rows[cx + 1] = table.concat(cols)
    end
    return { w = self.w, h = self.h, cell = self.cell, rows = rows }
end

return Fog
