-- Central place to tune numbers and colors. Safe to edit by hand.

local config = {}

-- false gives a resizable dev window
config.START_FULLSCREEN = true

-- Gates the dev hotkeys, the touch profiler and the pretend-purchase stub.
-- NEVER true in a shipped build: it reads only BATDEV/BATSIM, which don't exist
-- inside an app bundle.
config.DEV = (os.getenv("BATDEV") ~= nil) or (os.getenv("BATSIM") ~= nil)
             or (os.getenv("BATSHOT") ~= nil)

-- temporary show/hide toggles
config.SHOW_CLOUDS       = false  -- mountain-peak clouds in the world
config.SHOW_ARTIST_PHOTO = true   -- Finn-Erik's photo on the title screen

config.WORLD_WIDTH  = 12000  -- sailable ocean width, in ground units
config.WORLD_HEIGHT = 8000

-- flat 2:1 iso tile map; TILE is one tile in ground units
config.TILE       = 64

-- Layered noise shaped by the island masks, terraced into flat bands.
-- WORLD_SEED and ISLANDS are LIVE SLOTS: Game:applyMap() installs the selected
-- map's values here so terrain and treasure read one place. The literals below
-- are the Norge defaults, for dev reloads and tests.
config.WORLD_SEED   = 1337   -- change for a different map (F6 regenerates)
config.LAND_THRESH  = 0.42   -- island mask + edge noise above this = land
config.COAST_SCALE  = 520    -- coastline wiggle scale (bigger = smoother)
config.COAST_NOISE  = 0.22   -- how much noise frays the coastline
config.COVER_SCALE  = 720    -- scale of grass-vs-rock cover patches
config.ROCK_THRESH  = 0.62   -- cover noise above this becomes rocky ground

-- sub-pixel coastal fill, so the shoreline is jagged rather than one diamond;
-- higher = finer but more to draw
config.COAST_PIXELS = 10
config.COAST_JAGGED = 0.6    -- shoreline fray (0 = clean steps)

-- Grass takes over through a speckled dither band instead of tracing the tile
-- diamonds. Distances are corner steps inland, ~1 per tile.
config.BEACH = {
    INNER  = 1.1,   -- solid sand until this far inland...
    OUTER  = 1.7,   -- ...solid grass from here on; dithered mix in between
    WOBBLE = 0.7,   -- the band wanders by about +/- half this (no neat rings)
}

config.FOREST_SCALE   = 360    -- bigger = larger forests
config.FOREST_THRESH  = 0.54   -- lower = more / bigger forests
config.FOREST_DENSITY = 6      -- trees drawn per forest tile

-- Saguaro and low bushes, so desert coasts read as arid rather than bare.
-- SOFT code shapes, not pixel sprites -- the player dislikes pixelised trees.
config.SCRUB = {
    DENSITY   = 3,     -- plants per scrub tile (a third of a forest: it's a desert)
    CACTUS    = 0.45,  -- chance a plant is a saguaro rather than a bush
    ARM_ODDS  = 0.62,  -- chance a saguaro grows arms (the iconic silhouette)
}

-- where land sits and how big; each roughly hosts its port from ports.lua
config.ISLANDS = {
    { x = 2600, y = 2600, radius = 2520 },  -- Bergen   (huge, NW)
    { x = 6200, y = 2200, radius = 1540 },  -- Alversund (N-mid)
    { x = 9600, y = 2600, radius = 1960 },  -- Skiparviken (NE)
    { x = 7800, y = 4400, radius = 1260 },  -- Hjellestad (center-E)
    { x = 2600, y = 6000, radius = 1820 },  -- Lerøy    (SW)
    { x = 5200, y = 6200, radius = 1050 },  -- Klokkarvik (tiny, S-mid)
    { x = 10000,y = 6200, radius = 2520 },  -- Oslo     (huge, SE)
    { x = 5100, y = 4300, radius = 1260 },  -- Florida  (big, central sea)
}

-- Set per island in a map's `islands` list; omitted = "green", the Norge look.
-- Each overrides ground colours and forest behaviour, and snowAt pulls the
-- snowline down to (level * STEP).
config.BIOMES = {
    green  = {},                                            -- the Norge baseline
    lush   = { grass = { 0.33, 0.48, 0.22 },                -- deep eastern forest
               forest = -0.07 },                            -- denser woods
    desert = { grass = { 0.78, 0.63, 0.35 },                -- sun-baked ground
               rock  = { 0.66, 0.40, 0.24 },                -- red canyon stone
               sand  = { 0.85, 0.74, 0.52 },
               forest = 999, snowless = true,               -- no woods, never snow
               -- not bare though: cactus and scrub instead, see SCRUB
               scrub = -0.02 },
    snow   = { grass = { 0.82, 0.86, 0.92 },                -- frozen ground
               rock  = { 0.52, 0.58, 0.68 },                -- icy blue stone
               sand  = { 0.88, 0.90, 0.94 },                -- frosted shores
               forest = 0.08, snowAt = 2 },                 -- sparse woods, low snowline
}

-- Visual only: the boat always sails at z = 0. Each land tile takes an integer
-- level, and tiles bridging two become shaded slopes.
config.MOUNTAINS = {
    MAX_LEVEL      = 8,    -- number of elevation steps
    STEP           = 15,   -- world-units rise per level
    NOISE_SCALE    = 460,  -- terrace patch size (a few tiles across)
    SNOW_LEVEL     = 7,    -- flat tops at/above this level are snow
    TREELINE_LEVEL = 4,    -- at/above this: no forests/houses
    FLATTEN_R      = 7,    -- tile radius flattened around each town
    SUBPIX         = 6,    -- pixels per tile side (granular surface)
}

-- the map starts dark and is revealed, and saved, as the boat sails
config.FOG_CELL        = 192   -- reveal granularity in ground units (3 tiles)
config.FOG_REVEAL      = 1150  -- reveal radius around the boat (see far enough not
                               -- to sail straight past an undiscovered island)

-- port `size` -> how many houses and how far they spread
config.CITY_SIZES = {
    tiny       = { houses = 4,  spread = 4  },
    small      = { houses = 9,  spread = 6  },
    medium     = { houses = 18, spread = 9  },
    large      = { houses = 55, spread = 17 },
    -- Packed hard on purpose: Amerika swings between crowded cities and empty
    -- wilderness, and a metropolis only reads as huge next to an empty island.
    metropolis = { houses = 140, spread = 24 },
}

-- The one zoom the world runs at. Wheel zoom was removed on purpose: he kept
-- zooming out and losing the boat.
config.CAMERA_DEFAULT_ZOOM = 1.4
-- desktop: no following -- edge-scroll or right-drag, C recentres
config.EDGE_SCROLL_MARGIN = 38  -- px from an edge that triggers scrolling
config.EDGE_SCROLL_SPEED  = 950 -- scroll speed (screen px / second)
-- edge-scrolling stops once the boat would leave the central band; max offset
-- from centre, as a screen fraction
config.EDGE_SCROLL_KEEP   = 0.34
-- the boat nearing an edge pans the map to hold it in the central band
config.FOLLOW_CAMERA      = true
-- Edge-scroll is a mouse-hover concept, so touch glides instead: nothing moves
-- while the boat is inside a tight band, then an eased catch-up, never a jump.
-- KEEP = max offset from centre; LERP = catch-up rate per second.
config.TOUCH_FOLLOW_KEEP  = 0.10  -- tight: panning starts almost immediately
config.TOUCH_FOLLOW_LERP  = 4.0
config.TOUCH_FOLLOW_LEAD  = 0.45  -- aim this many seconds ahead of the boat's
                                  -- motion, so the map pans toward where the
                                  -- kid is going, not where the boat has been
-- On a small logical screen (iPhone landscape is ~874x402 points) text scaled
-- by window height alone is physically tiny, and the desktop zoom shows too
-- little sea to plan a route. Tablets and desktop are untouched.
config.PHONE = {
    UI_BOOST    = 1.6,   -- multiplies Scale.ui sizes (text/buttons/icons)
    -- Between 1.0 and UI_BOOST on purpose: pure proportionality shrinks a chest
    -- to a brown blob at 402pt, and the full boost makes something hovering over
    -- the boat swallow the sea. Admission rule in CLAUDE.md.
    MARKER_BOOST = 1.3,
    CAMERA_ZOOM = 1.1,   -- world zoom on phones: a touch wider than the desktop
                         -- 1.4, enough to see neighbouring ports, not map-like
}
-- Apple's minimum touch target, in points. CONTROLS meet it, status doesn't.
-- Here because two files need the number: the HUD's keys and the shelf's one
-- tappable slot.
config.TOUCH_MIN = 44
-- The boat sails to exactly the tapped point but doesn't brake there: it glides
-- through and coasts, tapering off over COAST_TIME, so taps chain into
-- continuous sailing. Desktop clicks keep the precise stop.
config.TOUCH_COAST_TIME = 2.5

-- Gameplay feel — kept gentle on purpose (see CLAUDE.md "child-friendly").
config.PICKUP_RADIUS  = 95    -- docking distance, from the dock point in the water
config.BOAT_SPRITE_WIDTH = 140 -- on-screen boat width (~2 tiles)
config.BOUNCE_DAMPING = 0.45  -- collision softness (0 = dead stop, 1 = bouncy)

-- a rare hunter, slower than you, and docking is always safe
config.PIRATE = {
    SPEED_FRAC    = 0.78,   -- top speed as a fraction of YOUR boat's
    LENGTH        = 2.6,    -- length vs a normal ship (a long galleon)
    WIDTH         = 1.45,   -- beam
    -- Shouted several times, not once: a single shout is lost under the sea and
    -- the music, while a chant announces an event.
    CRY_TIMES     = 3,      -- how many times the cry goes up on a spawn
    CRY_GAP       = 2.2,    -- seconds of quiet AFTER a shout finishes before the
                            -- next one. Measured from the END of the clip, not
                            -- its start -- timing from the start cut each shout
                            -- off partway through and it read as a stutter
                            -- rather than a chant.
    SPAWN_GRACE   = 30,     -- seconds of sailing before the first can appear
    SPAWN_MEAN    = 70,     -- avg seconds between spawn rolls (higher = rarer)
    RESPAWN_GRACE = 25,     -- quiet time after one leaves
    -- STANDOFF: the range the pirate tries to hold while attacking, rather than
    -- sailing right up your side. Two things were wrong with closing to zero: a
    -- galleon parked inside your hull clips straight through the sprite, and a
    -- duel where the enemy is ON you is not a duel a child can read at all -- you
    -- can't see who is where. Well inside FIRE_RANGE, so it can shoot from
    -- station, and well outside both hulls (26 + 20) so nothing ever overlaps.
    STANDOFF      = 430,
    FIRE_RANGE    = 720,    -- only fires within this distance (ground units)
    FIRE_INTERVAL = 2.8,    -- seconds between shots
    BALL_SPEED    = 250,    -- cannonball speed (slow + telegraphed)
    BALL_RADIUS   = 15,     -- cannonball hit radius
    HIT_GOLD      = 5,      -- gold lost per hit
    -- Driving the pirate off has to pay, or fighting is a pure loss and running
    -- is always correct -- the wrong lesson for the one part the older children
    -- asked for. Roughly a delivery's pay: a won battle buys its own crate.
    DROP_GOLD     = 25,     -- gold spilled when it's finally driven off
    GIVEUP_DIST   = 2100,   -- stay this far away...
    GIVEUP_TIME   = 9,      -- ...for this long and the pirate gives up
    DESPAWN_DIST  = 1800,   -- vanishes once this far away while retreating
    HUNT_TIME     = 60,     -- max seconds a robbery visit lasts before it gets bored
    RETREAT_MAX   = 25,     -- retreating pirate vanishes after this long no matter what
                            -- (covers being chased by the kid, or boxed in by a coast)
}

-- A friendly shark wandering the open sea -- the gentle opposite of the pirate.
-- It can't chase you (its cruise is far slower than your boat); it just gets
-- curious and ambles over, and if you bump it the boat softly bounces (same as
-- nudging an island) while it chomps and darts off. It dives away while a pirate
-- is hunting so the two never crowd the screen.
config.SHARK = {
    SPRITE_WIDTH = 72,     -- on-screen length -- about half the ferry (140), so it
                           -- reads as a little fish, not a sea monster
    SPEED        = 70,     -- gentle cruise -- well below the boat, so it's unhurried
    DART_SPEED   = 150,    -- quick scoot right after a bump
    TURN_RATE    = 1.2,    -- how briskly it swings toward a new heading
    RADIUS       = 18,     -- soft-bounce collision radius (sits inside the body)
    CURIOUS_DIST = 420,    -- ambles over to investigate within this range
    BUMP_COOLDOWN = 3.0,   -- keeps its distance this long after a bump (no pestering)
    DART_TIME    = 1.3,    -- how long it scoots away after a bump
    CHOMP_RATE   = 1.6,    -- idle jaw cycle speed
    DART_CHOMP   = 6.0,    -- faster, excited chomp while darting off
    DIVE_RATE    = 1.2,    -- how fast it dives under / resurfaces (per second)
    -- Mostly out of sight: it plays deep in the ocean and only pops up now and
    -- then to look around (and maybe get bumped), then dives again.
    SUBMERGED_MIN = 16,    -- stays under this long (s) between peeks...
    SUBMERGED_MAX = 36,
    SURFACE_MIN   = 7,     -- ...then surfaces to look around for this long
    SURFACE_MAX   = 13,
    SPAWN_MIN    = 600,    -- spawns this far from the boat...
    SPAWN_MAX    = 1500,   -- ...out to this far, on open water
}

-- The player's cannon (bought in a harbour's Butikk). It auto-fires at a hunting
-- pirate, but we're NOT professional gunners: shots are wild (SPREAD) and aimed
-- at where the pirate is now (no leading), so most miss a moving ship. You'll
-- take some hits and lose a little gold before you finally land one -- and a hit
-- doesn't sink the pirate, it just scares it off so it turns and sails away (and
-- can come back another day). Owning it tips the fight your way without trivialising it.
config.CANNON = {
    FIRE_RANGE    = 760,   -- about the pirate's own reach (720)
    FIRE_INTERVAL = 1.6,   -- a touch faster than the pirate's 2.8
    BALL_SPEED    = 300,   -- ball speed
    BALL_RADIUS   = 16,    -- ball size for hit-testing the pirate
    SPREAD        = 0.24,  -- random aim error in radians (bigger = wilder, more misses)
    -- TAPPING the pirate fires a shot you aimed yourself (World:mousepressed ->
    -- Boat:tapFire). The automatic battery above is unchanged, so a small child
    -- who never taps plays exactly the game he played before; this is the
    -- trigger for anyone who wants one. Because you pointed at it, the aim is
    -- far tighter than the wild auto shot -- that accuracy IS the reward. It
    -- still costs a cannonball, which is what keeps tapping from being free.
    -- Tapping is meant to be MAYHEM: a fast trigger you can hammer, fed by a
    -- deep locker, rather than a slow trigger rationed by a shallow one. So
    -- TAP_INTERVAL stays short and START_AMMO/the Kanonkuler crate carry the
    -- balance instead. Like the automatic battery, extra cannons make the
    -- tapped shot faster too (game:cannonRate) -- buying a second Kanon has to
    -- mean something to the child doing the shooting, not just to the autopilot.
    TAP_SPREAD    = 0.07,  -- aim error of a player-aimed shot (vs SPREAD's 0.24)
    TAP_INTERVAL  = 0.45,  -- min seconds between tapped shots, before cannonRate
    SCARE_HITS    = 3,     -- hits needed to drive the pirate off (so it really chases
                           -- + shoots you first; 1 would scare it away too quickly)
    START_AMMO    = 40,    -- balls included with each cannon; more via the Butikk's
                           -- Kanonkuler pack (shop.lua `ammo = N`). Deep on purpose:
                           -- a hammered trigger drains ~2 balls a second, and 15
                           -- balls (the old figure, sized for the automatic battery
                           -- alone) emptied in under seven seconds of tapping.
    EXTRA_RATE    = 0.2,   -- each cannon beyond the first fires 20% faster...
    MAX_RATE      = 1.8,   -- ...capped here, so a pile of cannons stays gentle
}

-- Treasure hunt: a few chests rest on sandbanks (shallow water) off the coasts.
-- Harbourmasters hand out the maps on deliveries; sail up to the X and the chest
-- is yours -- no cannon needed. But a pirate RACES you to it: get there first and
-- it's yours; dawdle and the (slightly slower) pirate grabs it and you try again.
config.TREASURE = {
    COUNT        = 4,    -- how many chests (placed off the 4 biggest islands)
    -- How often a delivery hands over a map. Two levers, because the average
    -- alone doesn't describe the feel: at 0.5 with no floor there was a 50%
    -- chance the very NEXT delivery after finishing a hunt started another one,
    -- and back-to-back hunts read as relentless -- a hunt also blocks new
    -- oppdrag, so the delivery loop never gets going in between.
    --
    -- The gap between hunts is `MAP_COOLDOWN - 1 + 1/MAP_CHANCE` deliveries:
    --   0.50, floor 0  ->  2.0, and half landed on the very next delivery
    --   0.45, floor 2  ->  3.2  (but see below -- it was really running at 2.2)
    --   0.45, floor 3  ->  4.2  <- here
    -- Four chests exist in the whole game, so this also sets how long the arc to
    -- the finale is: ~17 deliveries at the current numbers.
    --
    -- SPEND CHANGES ON THE FLOOR, NOT THE CHANCE. A bigger floor buys a
    -- guaranteed stretch of ordinary trading; a smaller chance buys the same
    -- average with more variance, and a drought reads to a five-year-old as
    -- "the treasure game stopped happening".
    --
    -- The floor only started working properly in 2026-07: deliveries made DURING
    -- a hunt (cargo you already carry still gets delivered) were ticking it down,
    -- so one mid-hunt delivery ate the whole breather and maps came ~45% more
    -- often than these numbers said. See World:openDock.
    MAP_CHANCE   = 0.45, -- chance per eligible delivery (the first is guaranteed)
    MAP_COOLDOWN = 3,    -- deliveries of NORMAL trading that must pass after a
                         -- map before another can be granted (1 is NOT enough:
                         -- it still allows the very next delivery to start a
                         -- second hunt)
    REACH        = 140,  -- sail this close to the X to grab the chest
    GOLD         = 40,   -- gold reward for a chest
    RACE_TRIGGER = 1600, -- a pirate joins the race once you're this close to the chest
}
-- One collectible per chest, in placement order (sticker for the album).
config.TREASURE_GOODS = { "shell", "starfish", "gem", "pearl" }

-- TREASURE-SEEKING MODE. While a map is live the whole game changes character,
-- because the child cannot read "you are now on a treasure hunt" -- he has to
-- FEEL it. Everything below is driven by one number, World:treasureHeat(): 0
-- when the chest is far, 1 when you're nearly on top of it. The banner, the
-- arrow and the wash over the sea all read from it, so they can never disagree.
-- "Warmer / colder" is the oldest children's game there is, and it needs no
-- words at all.
config.TREASURE_MODE = {
    NEAR       = 1800,  -- heat starts climbing inside this distance...
    HOT        = 320,   -- ...and is full from here in (about the REACH ring)
    -- The MARKER is the chest-with-an-arrow that hovers over the boat. It is
    -- the whole hunt indicator now (there is no "Finn skatten!" banner any
    -- more -- the top of the screen is the most expensive band on a phone), so
    -- it is bigger than the bare arrow it replaced. Tune these two together:
    -- GROW is on top of MARKER_BASE, and the chest also beats with the heat.
    MARKER_BASE = 0.68, -- marker scale when the chest is far away
    MARKER_GROW = 0.55, -- ...and this much bigger again at full heat
    BOB_COLD   = 2.6,   -- arrow bob speed when far off...
    BOB_HOT    = 9.0,   -- ...and when you're right on it (excited)
    RING_COLD  = 4.0,   -- chest ring pulse speed, cold -> hot
    RING_HOT   = 11.0,
    -- A parchment wash + vignette over the sea: the world goes slightly
    -- old-map-coloured while hunting. Kept LOW -- it must read as a mood, never
    -- as "something is wrong with the screen".
    TINT       = { 0.92, 0.74, 0.40 },
    TINT_MIN   = 0.045, -- wash strength when the hunt starts...
    TINT_MAX   = 0.13,  -- ...and when you're on top of the chest
    VIGNETTE   = 0.30,  -- corner darkening at full heat
    -- The hunt takes the same announce as the mission marker (MARKER_ANNOUNCE),
    -- plus an edge hint: while the words are up, a big bobbing chest is pinned to
    -- the screen edge in the treasure's direction. The chest is far off and off
    -- screen at the start of EVERY hunt, which is exactly when "which way?" is
    -- hardest and the little arrow over the boat easiest to miss. It leaves with
    -- the words; from then on the arrow is enough.
    TEXT        = "Pilen viser vei til skatten!",
    HINT_SIZE   = 84,   -- edge chest, design px
    HINT_MARGIN = 78,   -- ...and how far its centre stays off the screen edge
    -- Held back like the mission line, and for the same reason: fired as the card
    -- closed it landed before the player had started sailing.
    ANNOUNCE_DELAY = 3.5,
    -- How far the orange arrow rides out from the chest. At 30 the chest -- which
    -- Icons.draw paints at 1.5x its badgeSize, so ~81px across -- buried all but
    -- the last 15px of the arrow, and the one part carrying the DIRECTION was the
    -- part you couldn't see. The tail still tucks under the chest's edge, so the
    -- two read as one marker rather than two things that happen to be near.
    ARROW_ORBIT = 52,
}

-- THE MARKER ANNOUNCE -- the flourish that introduces a new goal, shared by the
-- mission arrow and the treasure marker (`src/ui/announce.lua`) so that both say
-- "here is the new thing to follow" with the SAME gesture: the badge arrives
-- huge with a caption over it, breathes, then settles onto the marker.
--
-- It exists because the mission arrow shipped bare, and a playtester took his
-- first cargo, got the arrow and had no idea what it meant. An arrow alone says
-- "that way" and never "that way to WHAT" -- so the WHAT is now said loudly at
-- the moment it changes, and then gets out of the way. ANNOUNCING rather than
-- permanently badging is what keeps the sea clear: the strip just above the boat
-- is where the child is already looking, which makes it worth a great deal for
-- three seconds and very little for the rest of the voyage.
config.MARKER_ANNOUNCE = {
    TIME  = 2.8,    -- how long the line is up, entrance and fade included
    POP   = 0.22,   -- it springs to full size over this much of the phase...
    OVER  = 1.0,    -- ...overshooting by this much on the way, so it lands with a bump
    FADE  = 0.34,   -- ...and fades over the last this much
    PULSE = 0.05,   -- breathing while it's up -- movement is what makes a kid look
    LIFT  = 26,     -- gap between the top of the marker and the line, design px
}

-- THE MISSION MARKER -- the gold arrow that hovers over the boat while cargo is
-- aboard. Counterpart to the treasure marker above; the two are sized to read as
-- one family. The arrow is alone up there on purpose: what it means is said in
-- words and voice when the destination changes (MARKER_ANNOUNCE), not carried
-- around all voyage as a second symbol.
config.MISSION_MARKER = {
    SCALE = 0.7,    -- marker scale (the treasure chest lives at 0.68..1.23)
    LIFT  = 64,     -- how far above the boat it floats
    -- Long enough to be out of the harbour and actually sailing. Fired the
    -- instant the dock closed, it landed while the player was still finding the
    -- boat, which is the one moment he is not looking for advice.
    ANNOUNCE_DELAY = 3.5,
    TEXT           = "Pilen viser vei",
}

-- THE MINIMAP's see-through dark. The map covers a corner of the sea, and the
-- part of it covering the most screen is the part with the least to say: the
-- unexplored dark. So that -- and only that -- gives way. Revealed terrain stays
-- solid, and the pips, X's, boat and viewport all draw over the top at full
-- strength, because they are the whole reason the map is there.
config.MINIMAP = {
    FOG_ALPHA  = 0.28,  -- unexplored cells; lower = more sea showing through
    WELL_ALPHA = 0.10,  -- the well behind the map (see the note in Minimap:draw)
}

-- Crew + passengers eat the food you've stocked as you sail: every EAT_DISTANCE
-- ground-units travelled, one food unit aboard is eaten (longer voyage = more
-- eaten). The eaten item drops with a "Nam nam nam!". Bigger = food lasts longer.
config.EAT_DISTANCE = 3500

-- Country roads: thin dirt paths connecting neighbouring countryside houses
-- (purely decorative; baked into a static mesh with the rest of the terrain).
config.ROADS = {
    MAX_LINK = 560,   -- only houses closer than this (ground units) get a path
    WIDTH    = 10,    -- road width in ground units (~a sixth of a tile)
    WOBBLE   = 40,    -- how far a path meanders off the straight line
    RING_IN  = 2.0,   -- the coast road hugs the shore this far inland
                      -- (in corner steps; the beach band ends ~1.7)
}

config.MUSIC_VOLUME = 0.35
config.SFX_VOLUME   = 0.6
config.AUDIO_ON     = true

-- Palette: muted retro VGA tones. {r,g,b} in 0..1. Land tiles use {top, lip, dot}
-- (lip = shaded coastal face, dot = dither texture).
config.colors = {
    water_top    = {0.31, 0.49, 0.60},  -- shallow / near land (muted teal-blue)
    water_deep   = {0.21, 0.37, 0.50},  -- open sea
    wave         = {0.52, 0.64, 0.70},  -- soft, not white
    foam         = {0.86, 0.90, 0.89},  -- surf at the waterline

    sand  = { top = {0.76, 0.69, 0.49}, lip = {0.60, 0.53, 0.36}, dot = {0.70, 0.63, 0.44} },
    grass = { top = {0.49, 0.55, 0.31}, lip = {0.36, 0.42, 0.22}, dot = {0.44, 0.50, 0.27} },
    rock  = { top = {0.56, 0.52, 0.45}, lip = {0.42, 0.39, 0.33}, dot = {0.51, 0.47, 0.41} },

    -- sprite-object placeholders (muted)
    lot          = {0.66, 0.62, 0.53},
    building_wall= {0.80, 0.74, 0.62},
    building_dk  = {0.60, 0.52, 0.43},
    road         = {0.46, 0.44, 0.40},
    dirt         = {0.64, 0.54, 0.37},  -- country-road fill (pale worn earth)
    dirt_edge    = {0.30, 0.24, 0.16},  -- trodden verge (drawn ~30% alpha, blends into grass)
    dock_top     = {0.55, 0.42, 0.28},
    dock_side    = {0.40, 0.30, 0.20},
    stone        = {0.56, 0.55, 0.50},
    tree_trunk   = {0.36, 0.27, 0.17},
    tree_leaf    = {0.28, 0.39, 0.21},
    tree_leaf_hi = {0.37, 0.47, 0.27},
    rock_light   = {0.56, 0.54, 0.49},
    rock_dark    = {0.40, 0.39, 0.35},

    -- boats / ships (muted)
    boat_hull    = {0.72, 0.32, 0.27},
    boat_hull_dk = {0.52, 0.22, 0.18},
    boat_deck    = {0.80, 0.70, 0.50},
    boat_cabin   = {0.86, 0.82, 0.72},

    -- ui
    text         = {0.96, 0.95, 0.90},
    text_dark    = {0.16, 0.16, 0.18},
    gold         = {0.88, 0.74, 0.34},
    panel        = {0.16, 0.18, 0.22},
}

-- Roof/wall accent colors for harbor building variety.
config.BUILDING_COLORS = {
    {0.64, 0.36, 0.30},  -- brick red
    {0.46, 0.48, 0.52},  -- slate
    {0.72, 0.64, 0.46},  -- tan
    {0.50, 0.52, 0.36},  -- olive
    {0.40, 0.46, 0.50},  -- blue-grey
    {0.66, 0.56, 0.40},  -- ochre
}

-- Accent colors for ambient/docked vessels (the code-drawn placeholder ships).
config.SHIP_COLORS = {
    {0.70, 0.34, 0.28}, {0.34, 0.46, 0.58}, {0.74, 0.62, 0.34},
    {0.42, 0.54, 0.40}, {0.62, 0.50, 0.56},
}

-- Sprite ships the ambient sea traffic is drawn from: OpenGFX 8-view art under
-- assets/ships/<name>/0..7.png (see tools/extract_opengfx_ships.py). Each ambient
-- boat picks one at random; if the art is missing it falls back to the volumetric
-- placeholder (Objects.drawShip), so the game still runs art-free.
config.AMBIENT_SHIPS = {
    "cargo_ship1", "cargo_ship2", "cargo_ship3", "cargo_ship4",
    "toyland_ship1", "toyland_ship2",
}
config.AMBIENT_SHIP_WIDTH = 180  -- on-screen width of an OpenGFX sprite ship at scale 1.0
config.AMBIENT_PHOTO_WIDTH = 115 -- on-screen width of a photo billboard ship (kept modest, ~Viking Sky size)
config.AMBIENT_SHIP_RADIUS_FRAC = 0.22  -- collision radius as a fraction of on-screen width
config.AMBIENT_SHIP_SPEED = 23   -- base speed of sailing ships (slow; the player boat does ~140)
config.AMBIENT_CRUISE_SPEED = 12 -- photo boats with cruise=true (extra slow, stately)
config.AMBIENT_CRUISE_LANE = 420 -- min open water either way along a cruise ship's
                                 -- spawn heading (so it patrols a lane, not a puddle)
config.AMBIENT_HOME_LANE = 220   -- shorter lane for boats tied to a home port
                                 -- (little Beffen shuttling just outside Bergen)
config.AMBIENT_HOME_MIN = 280    -- keep-out ring around the home pier: never closer
                                 -- than this (docking is PICKUP_RADIUS=95, so the
                                 -- quay stays clear), bounce back out if headed in
config.AMBIENT_HOME_LEASH = 600  -- how far a home-port boat may stray before it
                                 -- turns around and shuttles back
config.AMBIENT_HOME_DWELL = 15   -- a route ferry's pause at each of its stops

-- Ambient ships calling at harbours (ships.lua `visits = {...}`): every so often
-- a listed liner steers to an anchorage off one of its cities, lies still a
-- while, then sails on. The anchorage ring keeps the quay itself clear (player
-- docking triggers at PICKUP_RADIUS=95, and 560 is the tap-safety ring).
config.AMBIENT_VISIT = {
    INTERVAL_MIN = 70,   -- seconds of open-sea cruising between visits...
    INTERVAL_MAX = 160,  -- ...picked randomly in this range
    DWELL        = 30,   -- how long a visitor lies at anchor off the pier
    RING_MIN     = 330,  -- anchorage distance from the pier
    RING_MAX     = 520,
    TIMEOUT      = 240,  -- give up steering there after this long (odd geometry)
    TURN_RATE    = 0.6,  -- rad/s homing turn while steering to a goal
}

-- Dolphins! A little pod that joins the boat when it holds full sail for a
-- moment, porpoising alongside the bow, then diving away again. Pure ambient
-- joy: never solid, never blocking, only on open water. Voice hook:
-- assets/voice/delfiner.ogg plays as they arrive.
-- Boat wake (ALL player boats — photo, frames and live-3D): foam puffs and
-- ripple rings are dropped at the stern's WORLD position and stay where they
-- fell, so the trail traces the actual track (a turn leaves a curve, not a
-- swinging fan) and dissipates quickly.
config.WAKE = {
    SPACING  = 9,     -- ground px sailed between foam drops
    LIFE     = 1.4,   -- seconds before a drop fully dissipates
    DRIFT    = 7,     -- sideways spread speed of the foam (ground px/s)
    STERN    = 22,    -- ground px from boat centre back to the propeller
    MIN_SPD  = 0.08,  -- fraction of top speed before any foam appears
    RING_ODDS = 0.22, -- chance a drop is a ripple ring instead of a foam puff
}

config.DOLPHINS = {
    TRIGGER_FRAC = 0.75, -- they come when you sail faster than this × top speed
    PLAY_TIME    = 14,   -- how long they frolic alongside (s)
    -- Still rare enough to be an event, but the old 240-540s meant a 15-minute
    -- session might see one pod -- and the dolphins were singled out by the
    -- playtesters as a favourite. Roughly doubled the frequency.
    COOLDOWN_MIN = 120,  -- minutes of quiet sea between visits...
    COOLDOWN_MAX = 300,  -- ...so a pod showing up still feels special
    FIRST_WAIT   = 60,   -- ...including a wait before the first one
    JUMP_H       = 34,   -- leap height (world units)
    PERIOD       = 1.5,  -- one porpoise cycle (leap + glide) per dolphin
    SIDE         = 70,   -- how far off the boat's side the pod swims
    COUNT        = 3,
}

-- The submarine (ships.lua `submarine = true`): it cruises DEEP -- invisible,
-- never solid, not clickable -- and now and then rises through the waterline
-- (bubbles + a "blubb"), runs on the surface a while, and sinks away again.
-- In between it sails the same gentle ambient AI as every other ship, so each
-- surfacing happens somewhere new.
config.SUBMARINE = {
    -- There is exactly ONE submarine in each map's fleet, and it only counts as
    -- "seen" if it happens to surface near the player -- so the real sighting
    -- rate is a good deal lower than these numbers suggest. Trimmed the dive
    -- modestly (it should still feel like a lucky catch, not a scheduled event).
    SUBMERGED_MIN = 35,   -- stays under this long (s)... (rare = special)
    SUBMERGED_MAX = 75,
    -- Long enough to be a SIGHTING. The surfacing is the whole point of the
    -- submarine, and it was over before you could steer across to look at it:
    -- you get one glance, and then you want to sail over, and that has to fit in
    -- the window or the rarest thing in the sea reads as a glitch.
    SURFACE_MIN   = 26,   -- ...then cruises surfaced this long, then dives away
    SURFACE_MAX   = 42,
    TRANSITION    = 3.0,  -- seconds to rise / sink through the waterline
    FX_DIST       = 2400, -- bubbles + blubb only when this close to the player
}

-- Ambient-AI level of detail: ships far beyond any possible screen bank their
-- dt and tick in batched steps instead of every frame (see Fleet:update). Same
-- total sailing, a fraction of the water probes -- adding boats stays cheap.
config.AMBIENT_LOD = {
    FAR  = 3000,   -- ground-unit distance from the player past which a ship is "far"
                   -- (the widest view at min zoom reaches ~1400 + camera slack)
    STEP = 0.25,   -- far ships tick roughly every this many seconds
}

-- The single premium unlock ("one pack unlocks everything"): all the fancy boats,
-- map variations and future extras. One non-consumable App Store purchase later;
-- for now it's a pretend buy (Game:unlockPremium). Anything premium checks
-- Game:isPremium() -- never per-item purchases.
config.PREMIUM = {
    name  = "Kaptein-pakken",
    -- Fallback display price only (dev stub / store not reachable). The REAL
    -- price is the App Store Connect price point (aim: kr 19), fetched
    -- localized at runtime via IAP.price().
    price = "kr 19,-",
    -- The maths-question gate in front of the purchase (BoatSelect:openGate).
    -- iOS's own sheet (Face ID / Ask to Buy) already guards the actual payment,
    -- so this isn't about money — it's about a five-year-old not being able to
    -- summon a purchase sheet over and over on his own. Six answers to a
    -- 6x6..9x9 multiplication: trivial for the grown-up he fetches, and ~17%
    -- to a guesser, who then gets a fresh question rather than another go at
    -- the same one.
    PARENTAL_GATE = true,
    GATE_TRIES    = 3,     -- wrong answers before the gate gives up and closes
    -- Must match the non-consumable product id in App Store Connect (and the
    -- .storekit test file) exactly. Product ids are only scoped to the app,
    -- so short is fine.
    PRODUCT_ID = "skep.batspillet.kapteinpakken",
    -- Kaptein-pakken = all premium SHIPS (incl. future ones) + the Amerika
    -- map. Future EXTRA maps (Asia …) may be their own products — early
    -- buyers must get everything this card lists, so only promise what ships
    -- with the pack today.
    perks = {
        "Alle de fine båtene",
        "Amerika-kartet!",
        "Nye båter som kommer!",
    },
}

return config
