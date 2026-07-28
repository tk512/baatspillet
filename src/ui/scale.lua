-- Design px (at the 1280x800 design window) -> on-screen px. Every UI size goes
-- through here; never write love.graphics.getHeight() / 800 in UI code.
--   ui       read or tapped -- text, buttons, icons (phone-boosted)
--   overlay  world-anchored decor -- arrows, rings, tags (never boosted)
--   marker   world-anchored AND must be recognised (partly boosted)
-- Which one to use, and the admission test for `marker`, is in CLAUDE.md
-- ("Cross-platform UI sizing"). Game:load sets `phone`.

local config = require("src.config")

local Scale = { phone = false }

function Scale.k()                       -- raw proportional factor, rarely right alone
    return love.graphics.getHeight() / 800
end

function Scale.ui(px)
    local s = Scale.k()
    if Scale.phone then s = s * config.PHONE.UI_BOOST end
    return px * s
end

function Scale.overlay(px)
    return px * Scale.k()
end

function Scale.marker(px)
    local s = Scale.k()
    if Scale.phone then s = s * config.PHONE.MARKER_BOOST end
    return px * s
end

return Scale
