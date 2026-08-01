-- In-game pause overlay. The plaque, the buttons and the press handling are the
-- shared modal (src/ui/dialog.lua); this file is only what pause MEANS.

local Assets = require("src.assets")
local Dialog = require("src.ui.dialog")

local PauseMenu = {}

function PauseMenu.new(world)
    -- Two choices only. No Lyd toggle: the voice prompts ARE the pre-reader UI,
    -- so muting in-game is a footgun; volume is the platform's job (desktop
    -- keeps the M key for grown-ups).
    local function leave(action)
        return function() Assets.playSfx("leave", 0.30); action() end
    end
    return Dialog.new("pause", world.game.fonts, "Pause", {
        { label = "Fortsett", action = leave(function() world:closePause() end),
          face = Dialog.SAFE.face, hi = Dialog.SAFE.hi, lo = Dialog.SAFE.lo },
        { label = "Gå ut",    action = leave(function() world:exitToMenu() end) },
    }, function() world:closePause() end)   -- tap outside, or ESC = resume
end

return PauseMenu
