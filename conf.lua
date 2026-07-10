-- LÖVE window/module config, read once at startup.
-- Starts windowed; fullscreen is decided at runtime (src/config.lua START_FULLSCREEN)
-- so we can pick the monitor's resolution dynamically.

function love.conf(t)
    t.identity = "batspillet"          -- save folder name
    -- Declare the running engine's own version: we ship fused (the engine and
    -- game travel together), so the "made for another version" warning is noise.
    t.version  = love._version
    t.console  = false                 -- set true on Windows for a debug console

    t.window.title      = "Båtspillet"
    t.window.width      = 1280
    t.window.height     = 800
    -- Dev: device-shaped windows for layout testing without the iOS simulator
    -- (Apple broke GLES in Apple-Silicon sims). `BATSIM=ipad love .` etc.
    local sim = os.getenv("BATSIM")
    if sim == "ipad"   then t.window.width, t.window.height = 1194, 834 end -- iPad Pro 11" (points)
    if sim == "ipad13" then t.window.width, t.window.height = 1376, 1032 end -- iPad Pro 13"
    if sim == "iphone" then t.window.width, t.window.height = 874, 402 end -- iPhone 16 Pro landscape
    t.window.resizable  = true
    t.window.fullscreen = false
    t.window.vsync      = 1
    t.window.minwidth   = 640
    t.window.minheight  = 480
    -- Off on a Retina Mac avoids pushing 4x the pixels; a no-op on non-Retina.
    -- On iOS/iPadOS it must be ON or everything renders at 1x and looks blurry
    -- (love._os is set by the C core before conf runs, so it's safe here).
    t.window.highdpi    = (love._os == "iOS")

    -- Drop unused modules to stay light on old Macs.
    t.modules.joystick = false
    t.modules.physics  = false         -- movement is hand-rolled, no Box2D
end
