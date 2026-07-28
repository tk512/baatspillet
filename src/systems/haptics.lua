-- Taptic buzz for buttons, via the native bridge's bt_haptic() over FFI like the
-- IAP bridge. iPhone-only by hardware; iPads no-op, and on desktop the symbol is
-- missing so these are no-ops -- callers never check the platform.

local Haptics = {}

local C
do
    local ok, f = pcall(require, "ffi")
    if ok then
        f.cdef([[ void bt_haptic(int kind); ]])
        if pcall(function() return f.C.bt_haptic end) then C = f.C end
    end
end

function Haptics.tap()   if C then C.bt_haptic(0) end end   -- button pressed in
function Haptics.thump() if C then C.bt_haptic(1) end end   -- button fired

return Haptics
