-- src/systems/cargo.lua
-- The little economy that drives the gameplay loop:
--   each port OFFERS a cargo bound for another port. The boat picks it up,
--   sails to the destination, and delivers it for GOLD.
--
-- Kept deliberately simple and forgiving: there is no timer, no failure
-- state, and the boat can carry several jobs at once (up to its capacity).

local CargoSystem = {}
CargoSystem.__index = CargoSystem

-- ports is the list of Port entities created by world.lua.
function CargoSystem.new(ports)
    local self = setmetatable({}, CargoSystem)
    self.ports = ports
    self.offers = {}        -- portId -> offer table (or nil if none right now)
    for _, p in ipairs(ports) do
        self.offers[p.id] = self:makeOffer(p)
    end
    return self
end

-- Build a new delivery job that starts at `port` and ends at another port.
function CargoSystem:makeOffer(port)
    if #self.ports < 2 then return nil end
    -- pick a random destination that isn't this port
    local dest
    repeat
        dest = self.ports[love.math.random(#self.ports)]
    until dest.id ~= port.id

    -- What this town sends. `produces` is preferred; fall back to old `cargo`.
    local prod = port.def.produces
    if not prod then
        local c = port.def.cargo or { label = "Last", icon = "box" }
        prod = { mode = "cargo", label = c.label, icon = c.icon }
    end

    local count = (prod.mode == "passengers") and love.math.random(1, 4)
                                              or  love.math.random(1, 3)
    local reward = count * love.math.random(6, 12)

    return {
        mode   = prod.mode,            -- "passengers" | "cargo"
        type   = prod.label,           -- shown in HUD / screen
        icon   = prod.icon,            -- passenger / fish / apple / flower / box
        count  = count,
        fromId = port.id,
        toId   = dest.id,
        toName = dest.name,
        color  = dest.color,           -- destination's accent color (for the flag)
        reward = reward,
    }
end

function CargoSystem:offerAt(portId)
    return self.offers[portId]
end

-- Try to load this port's offered cargo onto the boat.
-- Returns the picked-up offer, or nil (no offer / boat full).
function CargoSystem:tryPickup(boat, port)
    local offer = self.offers[port.id]
    if not offer then return nil end
    if not boat:hasRoom() then return nil end

    boat.cargo[#boat.cargo + 1] = offer
    self.offers[port.id] = self:makeOffer(port)  -- port restocks immediately
    return offer
end

-- Deliver any cargo aboard that is destined for this port.
-- Returns total gold earned and the number of items delivered.
function CargoSystem:tryDeliver(boat, port)
    local earned, count = 0, 0
    local kept = {}
    for _, item in ipairs(boat.cargo) do
        if item.toId == port.id then
            earned = earned + item.reward
            count = count + 1
        else
            kept[#kept + 1] = item
        end
    end
    boat.cargo = kept
    return earned, count
end

return CargoSystem
