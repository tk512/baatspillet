-- In-app purchases for the one product this game sells, Kaptein-pakken
-- (non-consumable, config.PREMIUM).
--   IAP.buy(cb)       cb(ok, errMsg) when it settles
--   IAP.restore(cb)   Apple REQUIRES this path
--   IAP.price()       localized store price, or the config fallback
--   IAP.busy()        true mid-transaction (disable buttons)
--   IAP.update(dt)    pump; call each frame while store UI is up
-- Native backend: ios/storekit/bt_iap.m over FFI, polled one queued event per
-- frame -- "purchased" | "restored" | "restoredone" | "failed:<msg>" |
-- "restorefailed:<msg>". A restore succeeded iff "restored" arrives before
-- "restoredone", which is how SKPaymentQueue reports "nothing found".
-- Without the bridge: dev builds use a pretend stub, real builds FAIL CLOSED.

local config = require("src.config")

local C, ffi = nil, nil
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
        -- symbol lookup throws when the bridge isn't linked: that's the detection
        if pcall(function() return f.C.bt_iap_init end) then
            C, ffi = f.C, f
            C.bt_iap_init(config.PREMIUM.PRODUCT_ID)
        end
    end
end

local IAP = {
    _cb        = nil,     -- pending callback
    _t         = 0,       -- stub timer
    _restoring = false,
    _restored  = false,   -- saw "restored" before "restoredone"
}

function IAP.busy() return IAP._cb ~= nil end

-- The real price is an App Store Connect price point, never code; config's
-- string is only the stub/offline fallback.
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
            if config.DEV then settle(true)
            else settle(false, "Kjøp er ikke tilgjengelig her") end   -- fail closed
        end
        return
    end

    local raw = C.bt_iap_poll()
    if raw == nil then return end
    local ev = ffi.string(raw)

    if ev == "purchased" then
        settle(true)
    elseif ev == "restored" then
        IAP._restored = true            -- confirmed at "restoredone"
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
