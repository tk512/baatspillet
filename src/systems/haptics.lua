-- src/systems/haptics.lua
-- Taptic buzz for buttons, iPhone-only by hardware: reaches the native
-- bridge's bt_haptic() (UIImpactFeedbackGenerator) via LuaJIT FFI, exactly
-- like the IAP bridge. iPads have no Taptic Engine and the generator no-ops
-- there; on desktop the symbol is absent and these are plain no-ops — callers
-- never need to check the platform.

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
