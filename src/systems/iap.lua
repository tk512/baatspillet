-- src/systems/iap.lua
-- In-app purchases, kept to the ONE product this game sells: Kaptein-pakken
-- (a non-consumable; see config.PREMIUM and the monetization rule: one pack,
-- no per-item purchases, no ads). This module is the seam between the game
-- and the platform store:
--
--   IAP.buy(cb)       start the purchase; cb(ok, errMsg) when it settles
--   IAP.restore(cb)   re-grant an earlier purchase (Apple REQUIRES this path)
--   IAP.price()       localized display price (store) or config fallback
--   IAP.busy()        true while a transaction is in flight (disable buttons)
--   IAP.update(dt)    pump; call each frame while store UI is up
--
-- Backends:
--  * native — ios/storekit/bt_iap.m, a source member of the vendored engine's
--    love-ios target (every build style links it), reached via LuaJIT FFI.
--    Poll-based: the ObjC side queues event strings, we drain one per frame:
--    "purchased" | "restored" | "restoredone" | "failed:<msg>" |
--    "restorefailed:<msg>". Restore succeeds iff a "restored" event arrives
--    before "restoredone" (that's how SKPaymentQueue reports "nothing found").
--  * stub — dev only (config.DEV): settles successfully after a pretend delay
--    so the whole flow is testable anywhere. A NON-dev build without the
--    bridge FAILS CLOSED — pretending success would give the pack away free.

local config = require("src.config")

local C, ffi = nil, nil   -- FFI namespace + module when the bridge is linked in
do
    local ok, f = pcall(require, "ffi")
    if ok then
        f.cdef([[
            void bt_iap_init(const char *productId);
            void bt_iap_buy(void);
            void bt_iap_restore(void);
            const char *bt_iap_poll(void);
            const char *bt_iap_price(void);
        ]])
        -- Symbol lookup throws when the bridge isn't linked in (desktop) —
        -- that's our backend detection.
        if pcall(function() return f.C.bt_iap_init end) then
            C, ffi = f.C, f
            C.bt_iap_init(config.PREMIUM.PRODUCT_ID)
        end
    end
end

local IAP = {
    _cb        = nil,     -- pending callback
    _t         = 0,       -- stub timer
    _restoring = false,   -- native: current transaction is a restore
    _restored  = false,   -- native: saw a "restored" before "restoredone"
}

function IAP.busy() return IAP._cb ~= nil end

-- Localized display price ("kr 19,00", "€1,99"…) from the store when the
-- bridge has fetched the product; config's string is the stub/offline
-- fallback. The real price is an App Store Connect price point, never code.
function IAP.price()
    if C then
        local p = C.bt_iap_price()
        if p ~= nil then return ffi.string(p) end
    end
    return config.PREMIUM.price
end

function IAP.buy(cb)
    if IAP._cb then return end
    IAP._cb, IAP._restoring = cb, false
    if C then C.bt_iap_buy() else IAP._t = 1.2 end
end

function IAP.restore(cb)
    if IAP._cb then return end
    IAP._cb, IAP._restoring, IAP._restored = cb, true, false
    if C then C.bt_iap_restore() else IAP._t = 1.2 end
end

local function settle(ok, msg)
    local cb = IAP._cb
    IAP._cb = nil
    if cb then cb(ok, msg) end
end

function IAP.update(dt)
    if not IAP._cb then return end

    if not C then
        IAP._t = IAP._t - dt
        if IAP._t <= 0 then
            if config.DEV then settle(true)          -- dev stub: pretend success
            else settle(false, "Kjøp er ikke tilgjengelig her") end  -- fail CLOSED
        end
        return
    end

    local raw = C.bt_iap_poll()
    if raw == nil then return end
    local ev = ffi.string(raw)

    if ev == "purchased" then
        settle(true)
    elseif ev == "restored" then
        IAP._restored = true            -- success confirmed at "restoredone"
    elseif ev == "restoredone" then
        if IAP._restored then settle(true)
        else settle(false, "Fant ingen tidligere kjøp") end
    elseif ev:find("^failed:") then
        local msg = ev:sub(#"failed:" + 1)
        settle(false, msg ~= "" and msg or "Kjøpet ble avbrutt")
    elseif ev:find("^restorefailed:") then
        local msg = ev:sub(#"restorefailed:" + 1)
        settle(false, msg ~= "" and msg or "Kunne ikke gjenopprette")
    end
end

return IAP
