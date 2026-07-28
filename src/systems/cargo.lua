-- The delivery loop: a port offers a cargo bound for another port, the boat
-- carries it there for gold. No timer, no failure, several jobs at once.

local CargoSystem = {}
CargoSystem.__index = CargoSystem

function CargoSystem.new(ports)
    local self = setmetatable({}, CargoSystem)
    self.ports = ports
    self.offers = {}        -- portId -> offer, or nil if none right now
    for _, p in ipairs(ports) do
        self.offers[p.id] = self:makeOffer(p)
    end
    return self
end

function CargoSystem:makeOffer(port)
    if #self.ports < 2 then return nil end
    local dest
    repeat
        dest = self.ports[love.math.random(#self.ports)]
    until dest.id ~= port.id

    -- what the town sends; `produces` wins, old `cargo` is the fallback
    local prod = port.def.produces
    if not prod then
        local c = port.def.cargo or { label = "Last", icon = "box" }
        prod = { mode = "cargo", label = c.label, icon = c.icon }
    end

    local count = (prod.mode == "passengers") and love.math.random(1, 4)
                                              or  love.math.random(1, 3)
    local reward = count * love.math.random(6, 12)

    local offer = {
        mode   = prod.mode,            -- "passengers" | "cargo"
        type   = prod.label,
        icon   = prod.icon,
        count  = count,
        fromId = port.id,
        toId   = dest.id,
        toName = dest.name,
        color  = dest.color,           -- destination accent, used for the flag
        reward = reward,
    }

    -- Passengers are individuals: one action figure each, and `icon` becomes one
    -- of them so the single-icon mission banner shows a real passenger too.
    if prod.mode == "passengers" then
        offer.figures = {}
        for i = 1, count do
            offer.figures[i] = "passenger" .. love.math.random(4)
        end
        offer.icon = offer.figures[1]
    end

    return offer
end

function CargoSystem:offerAt(portId)
    return self.offers[portId]
end

-- Returns the picked-up offer, or nil if there is none or the boat is full.
function CargoSystem:tryPickup(boat, port)
    local offer = self.offers[port.id]
    if not offer then return nil end
    if not boat:hasRoom() then return nil end

    boat.cargo[#boat.cargo + 1] = offer
    self.offers[port.id] = self:makeOffer(port)  -- restocks immediately
    return offer
end

-- Delivers everything aboard bound for this port. Returns gold, item count.
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
