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
    t.window.resizable  = true
    t.window.fullscreen = false
    t.window.vsync      = 1
    t.window.minwidth   = 640
    t.window.minheight  = 480
    -- Off on Retina Macs avoids pushing 4x the pixels; iOS needs it ON or
    -- everything renders at 1x and looks blurry.
    t.window.highdpi    = (love._os == "iOS")

    -- dropped to stay light on old Macs
    t.modules.joystick = false
    t.modules.physics  = false         -- movement is hand-rolled, no Box2D
end
