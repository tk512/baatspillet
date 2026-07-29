-- LÖVE window/module config, read once at startup. Starts windowed; fullscreen
-- is decided at runtime (config.START_FULLSCREEN) off the monitor's resolution.

function love.conf(t)
    t.identity = "batspillet"          -- save folder name
    t.version  = love._version         -- fused: the version nag would be noise
    t.console  = false                 -- set true on Windows for a debug console

    t.window.title      = "Båtspillet"
    t.window.width      = 1280
    t.window.height     = 800
    -- device-shaped windows for layout testing: `BATSIM=ipad love .`
    local sim = os.getenv("BATSIM")
    if sim == "ipad"   then t.window.width, t.window.height = 1194, 834 end -- iPad Pro 11" (points)
    if sim == "ipad13" then t.window.width, t.window.height = 1376, 1032 end -- iPad Pro 13"
    if sim == "iphone" then t.window.width, t.window.height = 874, 402 end -- iPhone 16 Pro landscape
    -- App Store screenshots: `BATSHOT=1 love .` (or BATSHOT=1440x900). The store
    -- takes ONLY 1280x800, 1440x900, 2560x1600 or 2880x1800 for macOS and won't
    -- resize for you, so the window is sized exactly and F10 grabs the
    -- backbuffer — a cropped fullscreen grab is the wrong size by definition.
    local shot = os.getenv("BATSHOT")
    if shot then
        local w, h = shot:match("^(%d+)x(%d+)$")
        t.window.width  = tonumber(w) or 1280
        t.window.height = tonumber(h) or 800
        -- `BATSHOT=retina`: 1440x900 POINTS drawn at 2x is a 2880x1800 capture —
        -- the sharpest size the store accepts, from a window that still fits on
        -- a laptop screen. Asking for 2880x1800 directly would want a window
        -- bigger than the display, since highdpi is otherwise off on macOS.
        -- (highdpi itself is set below, where the normal rule lives.)
        if shot == "retina" then
            t.window.width, t.window.height = 1440, 900
        end
    end
    t.window.resizable  = true
    t.window.fullscreen = false
    t.window.vsync      = 1
    t.window.minwidth   = 640
    t.window.minheight  = 480
    -- Off on Retina Macs avoids pushing 4x the pixels; iOS needs it ON or
    -- everything renders at 1x and looks blurry.
    -- LÖVE 12 moved this from t.window.highdpi to the TOP LEVEL. The old field
    -- still works, but merely being present — even set to false — prints a
    -- deprecation notice over the bottom-left of the running game, so it must be
    -- left unset rather than set to a default.
    t.highdpi           = (love._os == "iOS") or shot == "retina"

    -- dropped to stay light on old Macs
    t.modules.joystick = false
    t.modules.physics  = false         -- movement is hand-rolled, no Box2D
end
