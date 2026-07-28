-- The flourish that introduces a new goal: a single line of text springs up over
-- the marker, holds long enough to be noticed, and fades. That is all it is.
--
-- It had a badge too -- the destination town's mark, arriving huge and shrinking
-- away. It went because the badge was answering a question the arrow had already
-- raised, and answering it with a second symbol the child also has to learn. The
-- words do the job in one go for whoever is sitting next to him, the voice does
-- it for him, and the arrow is left alone on the sea where it belongs.
--
-- Shared by the mission arrow and the treasure marker, so both announcements are
-- the same gesture and he learns it once. The caller owns the countdown (seconds
-- remaining) and everything here is a pure function of it, so the entrance, the
-- breathing and the fade cannot drift apart -- the same reason
-- World:treasureHeat() is one number.

local Announce = {}

-- 1 the instant it fires, 0 once it's over. Everything else reads this.
function Announce.phase(left, dur)
    if not left or left <= 0 or not dur or dur <= 0 then return 0 end
    return math.min(1, left / dur)
end

-- The entrance: springs from nothing to full size over the first `span` of the
-- phase, overshooting a little on the way so it lands with a bump rather than
-- easing politely in. Politeness is the enemy here -- the whole job of this thing
-- is to pull a five-year-old's eye off the sea. Holds at 1 afterwards.
local BACK = 1.70158                                    -- the classic ease-out-back constant
function Announce.pop(p, span, over)
    if p <= 0 then return 1 end
    local u = (1 - p) / (span or 0.25)                  -- 0 as it fires -> 1 in place
    if u >= 1 then return 1 end
    if u <= 0 then return 0 end
    local s = BACK * (over or 1)
    local q = u - 1
    return 1 + (s + 1) * q * q * q + s * q * q
end

-- Fades over the LAST `fade` of the phase, so the line is solid while it's being
-- read and gone before the marker is left to itself. p counts DOWN, hence p < fade.
function Announce.alpha(p, fade)
    if p <= 0 then return 0 end
    if not fade or fade <= 0 or p >= fade then return 1 end
    return p / fade
end

-- A small breathing while it's up. Movement is what makes a child look. Driven by
-- absolute time, not the phase, so it doesn't slow to a crawl as the line fades.
function Announce.pulse(t, amt)
    return 1 + amt * math.sin(t * 6.5)
end

-- Shrinks the scale so the line never runs off the sides. Load-bearing, not
-- defensive: "Pilen viser vei til skatten!" is nearly twice the mission line and
-- an iPhone is 874pt wide, and the entrance overshoots on top of that. A caption
-- that clips is the one failure mode that would be invisible on the iPad it's
-- written on and obvious on the phone he actually plays it on.
function Announce.fit(scale, textW, maxW)
    if textW <= 0 or maxW <= 0 or textW * scale <= maxW then return scale end
    return maxW / textW
end

-- Outline offsets, file scope: this runs per frame while a flourish is up.
local OUTLINE = { { -2, 0 }, { 2, 0 }, { 0, -2 }, { 0, 2 } }

-- The line, centred on cx with its BASELINE at cy -- it sits above the marker, so
-- it grows upward -- scaled about its own centre so the entrance doesn't drag it
-- sideways. Outlined, because it hangs over open water.
--
-- The words are for whichever grown-up is watching. The child gets the size, the
-- movement and the voice, which is why this may NEVER be the only thing that
-- says it: see CLAUDE.md, "Pre-reader UX".
function Announce.caption(text, cx, cy, font, alpha, scale)
    if not text or alpha <= 0.01 or scale <= 0.01 then return end
    love.graphics.setFont(font)
    local w, h = font:getWidth(text), font:getHeight()
    scale = Announce.fit(scale, w, love.graphics.getWidth() * 0.88)

    love.graphics.push()
    love.graphics.translate(cx, cy - h / 2)
    love.graphics.scale(scale, scale)
    love.graphics.setColor(0.10, 0.07, 0.04, 0.65 * alpha)
    for i = 1, #OUTLINE do
        love.graphics.print(text, -w / 2 + OUTLINE[i][1], -h / 2 + OUTLINE[i][2])
    end
    love.graphics.setColor(1, 0.87, 0.38, alpha)
    love.graphics.print(text, -w / 2, -h / 2)
    love.graphics.pop()
    love.graphics.setColor(1, 1, 1)
end

return Announce
