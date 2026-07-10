-- Central place to tune numbers and colors. Safe to edit by hand.

local config = {}

-- True launches fullscreen (for play); false gives a resizable dev window.
config.START_FULLSCREEN = true

-- Developer mode: dev hotkeys (F5/F6/F3, G/P/K), the touch profiler toggle and
-- the pretend-purchase stub only exist when this is true. NEVER true in a
-- shipped build: it's driven purely by the BATDEV/BATSIM env vars, which don't
-- exist inside an iOS/macOS app bundle.
config.DEV = (os.getenv("BATDEV") ~= nil) or (os.getenv("BATSIM") ~= nil)

-- Temporary show/hide toggles (flip back to true to restore).
config.SHOW_CLOUDS       = false  -- mountain-peak clouds in the world
config.SHOW_ARTIST_PHOTO = true   -- Finn-Erik's photo on the title screen

config.WORLD_WIDTH  = 12000  -- sailable ocean width, in ground units
config.WORLD_HEIGHT = 8000

-- Flat 2:1 iso tile map (water/sand/grass/rock). TILE = one tile in ground units.
-- Optional pixel tileset goes in assets/tiles/<type>.png.
config.TILE       = 64

-- Procedural terrain: layered noise height field shaped by the island masks,
-- then terraced into flat bands with slope transitions (SimCity-2000 look).
-- WORLD_SEED and ISLANDS are LIVE SLOTS: Game:applyMap() installs the selected
-- map's values here (src/data/maps.lua) so terrain/treasure code reads one
-- place. The literals below are the "Norge" defaults (dev reload / tests).
config.WORLD_SEED   = 1337   -- change for a different map (F6 regenerates)
config.LAND_THRESH  = 0.42   -- island mask + edge noise above this = land
config.COAST_SCALE  = 520    -- coastline wiggle scale (bigger = smoother)
config.COAST_NOISE  = 0.22   -- how much noise frays the coastline
config.COVER_SCALE  = 720    -- scale of grass-vs-rock cover patches
config.ROCK_THRESH  = 0.62   -- cover noise above this becomes rocky ground

-- Coastal tiles are filled at sub-pixel resolution so the shoreline is a jagged
-- pixel line, not a single diamond. Higher = finer but more to draw.
config.COAST_PIXELS = 10
config.COAST_JAGGED = 0.6    -- shoreline fray (0 = clean steps)

-- The sand→grass edge of every beach: instead of tracing the tile diamonds,
-- grass takes over through a speckled per-pixel dither band (the same trick the
-- waterline uses). Distances are in corner steps inland (~1 = one tile).
config.BEACH = {
    INNER  = 1.1,   -- solid sand until this far inland...
    OUTER  = 1.7,   -- ...solid grass from here on; dithered mix in between
    WOBBLE = 0.7,   -- the band wanders by about +/- half this (no neat rings)
}

config.FOREST_SCALE   = 360    -- bigger = larger forests
config.FOREST_THRESH  = 0.54   -- lower = more / bigger forests
config.FOREST_DENSITY = 6      -- trees drawn per forest tile

-- Where land sits and how big each island is. Each roughly hosts the matching
-- port in src/data/ports.lua. Spread far apart for open ocean between them.
config.ISLANDS = {
    { x = 2600, y = 2600, radius = 2520 },  -- Bergen   (huge, NW)
    { x = 6200, y = 2200, radius = 1540 },  -- Alversund (N-mid)
    { x = 9600, y = 2600, radius = 1960 },  -- Florø    (NE)
    { x = 7800, y = 4400, radius = 1260 },  -- Hjellestad (center-E)
    { x = 2600, y = 6000, radius = 1820 },  -- Lerøy    (SW)
    { x = 5200, y = 6200, radius = 1050 },  -- Klokkarvik (tiny, S-mid)
    { x = 10000,y = 6200, radius = 2520 },  -- Oslo     (huge, SE)
    { x = 5100, y = 4300, radius = 1260 },  -- Florida  (big, central sea)
}

-- Visual island height only — the sea stays flat (boat sails at z=0). Each land
-- tile gets an integer elevation level (low at coasts, higher inland); tiles
-- bridging two levels become shaded slope tiles. Baked into the static land mesh.
config.MOUNTAINS = {
    MAX_LEVEL      = 8,    -- number of elevation steps
    STEP           = 15,   -- world-units rise per level
    NOISE_SCALE    = 460,  -- terrace patch size (a few tiles across)
    SNOW_LEVEL     = 7,    -- flat tops at/above this level are snow
    TREELINE_LEVEL = 4,    -- at/above this: no forests/houses
    FLATTEN_R      = 7,    -- tile radius flattened around each town
    SUBPIX         = 6,    -- pixels per tile side (granular surface)
}

-- Fog of war: the map starts dark and is revealed (and saved) as the boat sails.
config.FOG_CELL        = 192   -- reveal granularity in ground units (3 tiles)
config.FOG_REVEAL      = 1150  -- reveal radius around the boat (see far enough not
                               -- to sail straight past an undiscovered island)

-- Maps each port `size` to how many houses to scatter and how far they spread.
config.CITY_SIZES = {
    tiny   = { houses = 4,  spread = 4  },
    small  = { houses = 9,  spread = 6  },
    medium = { houses = 18, spread = 9  },
    large  = { houses = 40, spread = 15 },
}

-- The one zoom the world runs at. Wheel zoom was removed on purpose: the kid
-- kept zooming all the way out and losing the boat.
config.CAMERA_DEFAULT_ZOOM = 1.4
-- The camera does not follow the boat. Scroll with the mouse at the screen edges
-- (or right-drag); press C to recenter on the boat.
config.EDGE_SCROLL_MARGIN = 38  -- px from an edge that triggers scrolling
config.EDGE_SCROLL_SPEED  = 950 -- scroll speed (screen px / second)
-- Edge-scrolling stops once the boat would leave the central band, so the kid
-- can't lose it off-screen. Max boat offset from centre, as a screen fraction.
config.EDGE_SCROLL_KEEP   = 0.34
-- Follow camera: the boat sailing toward a screen edge pans the map to keep it in
-- the central band (touch / iPad friendly). It still leaves room to look around
-- (mouse edge / drag) within that band; press C to recentre.
config.FOLLOW_CAMERA      = true
-- Touch devices (and BATSIM dev windows): edge-scroll is a mouse-hover concept,
-- so it's off there. Instead the camera GLIDES after the boat: no map movement
-- while the boat is inside a tight central band, then an eased catch-up — never
-- a jump. KEEP = max boat offset from centre (screen fraction, tighter than
-- EDGE_SCROLL_KEEP); LERP = catch-up rate per second (higher = snappier).
config.TOUCH_FOLLOW_KEEP  = 0.10  -- tight: panning starts almost immediately
config.TOUCH_FOLLOW_LERP  = 4.0
config.TOUCH_FOLLOW_LEAD  = 0.45  -- aim this many seconds ahead of the boat's
                                  -- motion, so the map pans toward where the
                                  -- kid is going, not where the boat has been
-- Phones (small logical screens, e.g. iPhone landscape ≈ 874x402 points): text
-- scaled purely by window height comes out physically tiny, and the desktop zoom
-- shows too little sea to plan a route. Boost fonts and zoom out. Tablets and
-- desktop are untouched (Game.phone is false there).
config.PHONE = {
    UI_BOOST    = 1.6,   -- multiplies Scale.ui sizes (text/buttons/icons)
    CAMERA_ZOOM = 1.1,   -- world zoom on phones: a touch wider than the desktop
                         -- 1.4, enough to see neighbouring ports, not map-like
}
-- Touch tap-to-sail momentum: the boat sails to EXACTLY the tapped point, but
-- doesn't brake there — it glides through at speed and coasts onward, tapering
-- off over COAST_TIME. Taps chain into continuous sailing instead of
-- tap-tap-tap. Desktop clicks keep the precise stop.
config.TOUCH_COAST_TIME = 2.5

-- Gameplay feel — kept gentle on purpose (see CLAUDE.md "child-friendly").
config.PICKUP_RADIUS  = 95    -- docking distance, from the dock point in the water
config.BOAT_SPRITE_WIDTH = 140 -- on-screen boat width (~2 tiles)
config.BOUNCE_DAMPING = 0.45  -- collision softness (0 = dead stop, 1 = bouncy)

-- Pirate ship: a rare black-sailed hunter that appears while you sail with gold.
-- It's slower than you and docking is always safe, so it's dodge-able.
config.PIRATE = {
    SPEED_FRAC    = 0.78,   -- top speed as a fraction of YOUR boat's
    LENGTH        = 2.6,    -- length vs a normal ship (a long galleon)
    WIDTH         = 1.45,   -- beam
    SPAWN_GRACE   = 30,     -- seconds of sailing before the first can appear
    SPAWN_MEAN    = 70,     -- avg seconds between spawn rolls (higher = rarer)
    RESPAWN_GRACE = 25,     -- quiet time after one leaves
    FIRE_RANGE    = 720,    -- only fires within this distance (ground units)
    FIRE_INTERVAL = 2.8,    -- seconds between shots
    BALL_SPEED    = 250,    -- cannonball speed (slow + telegraphed)
    BALL_RADIUS   = 15,     -- cannonball hit radius
    HIT_GOLD      = 5,      -- gold lost per hit
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
    SCARE_HITS    = 3,     -- hits needed to drive the pirate off (so it really chases
                           -- + shoots you first; 1 would scare it away too quickly)
    START_AMMO    = 15,    -- balls included with each cannon; more via the Butikk's
                           -- Kanonkuler pack (shop.lua `ammo = N`)
    EXTRA_RATE    = 0.2,   -- each cannon beyond the first fires 20% faster...
    MAX_RATE      = 1.8,   -- ...capped here, so a pile of cannons stays gentle
}

-- Treasure hunt: a few chests rest on sandbanks (shallow water) off the coasts.
-- Harbourmasters hand out the maps on deliveries; sail up to the X and the chest
-- is yours -- no cannon needed. But a pirate RACES you to it: get there first and
-- it's yours; dawdle and the (slightly slower) pirate grabs it and you try again.
config.TREASURE = {
    COUNT        = 4,    -- how many chests (placed off the 4 biggest islands)
    MAP_CHANCE   = 0.5,  -- chance a delivery hands you a map (first one guaranteed)
    REACH        = 140,  -- sail this close to the X to grab the chest
    GOLD         = 40,   -- gold reward for a chest
    RACE_TRIGGER = 1600, -- a pirate joins the race once you're this close to the chest
}
-- One collectible per chest, in placement order (sticker for the album).
config.TREASURE_GOODS = { "shell", "starfish", "gem", "pearl" }

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
config.DOLPHINS = {
    TRIGGER_FRAC = 0.75, -- they come when you sail faster than this × top speed
    PLAY_TIME    = 14,   -- how long they frolic alongside (s)
    COOLDOWN_MIN = 240,  -- RARE on purpose: minutes of quiet sea between visits,
    COOLDOWN_MAX = 540,  -- so a pod showing up stays a real event
    FIRST_WAIT   = 90,   -- ...including a good wait before the first one
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
    SUBMERGED_MIN = 45,   -- stays under this long (s)... (rare = special)
    SUBMERGED_MAX = 100,
    SURFACE_MIN   = 10,   -- ...then cruises surfaced this long, then dives away
    SURFACE_MAX   = 18,
    TRANSITION    = 2.2,  -- seconds to rise / sink through the waterline
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
    -- The extra maths-question gate before buying. Off: the card itself says
    -- "ask mamma/pappa" and iOS's own purchase sheet (Face ID / Ask to Buy)
    -- guards the payment. If Kids-category review insists on an app-side gate,
    -- flip this to true — the gate screen is still wired.
    PARENTAL_GATE = false,
    -- Must match the non-consumable product id in App Store Connect (and the
    -- .storekit test file) exactly. Product ids are only scoped to the app,
    -- so short is fine.
    PRODUCT_ID = "skep.batspillet.kapteinpakken",
    -- Kaptein-pakken = the SHIPS (all premium boats, incl. future ones).
    -- Future map packs (Amerika, Asia …) will be their own products — so don't
    -- promise maps here; early buyers must get everything this card lists.
    perks = {
        "Alle de fine båtene",
        "Nye båter som kommer!",
    },
}

return config
