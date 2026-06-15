-- LÖVE window/module config, read once at startup.
-- Starts windowed; fullscreen is decided at runtime (src/config.lua START_FULLSCREEN)
-- so we can pick the monitor's resolution dynamically.

function love.conf(t)
    t.identity = "batspillet"          -- save folder name
    t.version  = "11.3"
    t.console  = false                 -- set true on Windows for a debug console

    t.window.title      = "Båtspillet"
    t.window.width      = 1280
    t.window.height     = 800
    t.window.resizable  = true
    t.window.fullscreen = false
    t.window.vsync      = 1
    t.window.minwidth   = 640
    t.window.minheight  = 480
    -- Off on a Retina Mac avoids pushing 4x the pixels; a no-op on non-Retina.
    t.window.highdpi    = false

    -- Drop unused modules to stay light on old Macs.
    t.modules.joystick = false
    t.modules.physics  = false         -- movement is hand-rolled, no Box2D
end
