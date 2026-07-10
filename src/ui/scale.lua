-- src/ui/scale.lua
-- THE one place that turns a design size (px at the 1280x800 design window)
-- into an on-screen size. Every UI element belongs to one of two categories —
-- pick consciously (the rule lives in CLAUDE.md, "Cross-platform UI sizing"):
--
--   Scale.ui(px)       anything READ or TAPPED: text, buttons, icons, crates,
--                      thumbnails, badges. Window-proportional, and BOOSTED on
--                      phones (config.PHONE.UI_BOOST) — pure proportionality
--                      makes these physically tiny on a small screen.
--
--   Scale.overlay(px)  world-anchored decor: pointer arrows, pulse rings, name
--                      tags, wakes. Purely window-proportional, NEVER boosted —
--                      boosting these makes them swallow a phone screen.
--
-- Never write `love.graphics.getHeight() / 800` (or a bare pixel size) in UI
-- code again; route it through here so phones/tablets/desktop can't drift
-- apart. Game:load sets `phone`; values track the live window size.

local config = require("src.config")

local Scale = { phone = false }

function Scale.k()                       -- raw proportional factor (rarely right alone)
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

return Scale
