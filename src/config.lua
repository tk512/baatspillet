-- Central place to tune numbers and colors. Safe to edit by hand.

local config = {}

-- True launches fullscreen (for play); false gives a resizable dev window.
config.START_FULLSCREEN = true

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

config.CAMERA_MIN_ZOOM = 0.55   -- furthest out (wheel down)
config.CAMERA_MAX_ZOOM = 3.2    -- closest in (wheel up)
config.CAMERA_DEFAULT_ZOOM = 1.4
-- The camera does not follow the boat. Scroll with the mouse at the screen edges
-- (or right-drag); press C to recenter on the boat.
config.EDGE_SCROLL_MARGIN = 38  -- px from an edge that triggers scrolling
config.EDGE_SCROLL_SPEED  = 950 -- scroll speed (screen px / second)
-- Edge-scrolling stops once the boat would leave the central band, so the kid
-- can't lose it off-screen. Max boat offset from centre, as a screen fraction.
config.EDGE_SCROLL_KEEP   = 0.34

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
}

-- Crew + passengers eat the food you've stocked as you sail: every EAT_DISTANCE
-- ground-units travelled, one food unit aboard is eaten (longer voyage = more
-- eaten). The eaten item drops with a "Nam nam nam!". Bigger = food lasts longer.
config.EAT_DISTANCE = 3500

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

-- Accent colors for ambient/docked vessels.
config.SHIP_COLORS = {
    {0.70, 0.34, 0.28}, {0.34, 0.46, 0.58}, {0.74, 0.62, 0.34},
    {0.42, 0.54, 0.40}, {0.62, 0.50, 0.56},
}

return config
