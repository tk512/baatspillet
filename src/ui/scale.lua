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
--   Scale.marker(px)   world-anchored AND recognition-dependent: something that
--                      hovers in the world but whose whole job is to be
--                      RECOGNISED as a specific object — today, the treasure
--                      chest above the boat. Partially boosted on phones
--                      (config.PHONE.MARKER_BOOST, between 1.0 and UI_BOOST).
--
-- ADMISSION RULE for that third category, because a third category is exactly
-- the kind of thing that becomes a dumping ground: it must be BOTH anchored to
-- the world (so `ui` is wrong — it would swallow a small screen) AND carry its
-- meaning through a silhouette the player has to identify (so `overlay` is
-- wrong — proportional shrink turns a chest into a brown blob at 402pt). An
-- abstract arrow is NOT recognition-dependent: it stays `overlay`. If you can't
-- say which specific object the player must recognise, you want `overlay`.
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

function Scale.marker(px)
    local s = Scale.k()
    if Scale.phone then s = s * config.PHONE.MARKER_BOOST end
    return px * s
end

return Scale
