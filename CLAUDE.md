# Båtspillet — project guide

A gentle isometric boat game for my 5-year-old son Finn-Erik. Sail between
Norwegian towns, carry passengers and fish, earn gold, find treasure — and watch
out for the occasional pirate. Relaxed, exploration-focused, no real failure.
Retro SimCity-2000 / Colonization look.

**All player-facing text and voice is Norwegian and stays that way.** The voice
clips are recordings of my son. The player cannot read.

Since the code comments are deliberately terse, **this file owns the "why"**.
If a rule here is violated the game breaks in a way tests won't catch.

## Run / build

- **Engine: LÖVE 12-dev, vendored at `./engine`** (Metal; pinned commit in
  `engine/VENDORED.md`). Our changes carry BATSPILLET markers in the pbxproj
  (the `BA0B1AF0…` id prefix): bundle id `skep.batspillet`, the StoreKit bridge
  `ios/storekit/bt_iap.m`, and `Båtspillet.love` as real target members — on
  **both** `love-ios` and `love-macosx`, so every build style (CLI, Xcode GUI,
  device, archive) links them. Plist edits live in `ios/love-ios.plist` and
  `mac/love-macosx.plist` and are synced in each build; never edit the engine's
  copies.
- Desktop: `love .`, pointed at the engine app from `./bygg.sh setup`. That
  product is **`Båtspillet.app`** now, not `love.app` — the Mac App Store bundle
  name is what a Mac owner reads in /Applications — so `setup` leaves a
  `love.app` symlink beside it and the old path keeps working. It also **strips
  the fused `.love` out of the dev app**, which is not tidying: `love.cpp`
  inserts a `Resources/*.love` at argv[1], *before* any path you pass, and adds
  `--fused`. A dev app with the game inside silently runs a stale snapshot —
  `love .` ignored, edits ignored, F5/F6 dead, and nothing on screen saying so.
  `setup` builds the ENGINE; the game is packaged in by `dmg` and by `mac`.
  Device-shaped dev windows: `BATSIM=ipad|ipad13|iphone love .` — real iPad and
  iPhone point sizes plus the touch camera and phone UI mode.
- **`./bygg.sh` is the ONE build script**, every target. Bare = interactive menu
  in a terminal, or the iPad sim when non-TTY. The menu is grouped
  UTGIVELSE / PRØVE UT / ÉN OM GANGEN with the release first, because the thing
  you do twice a year is the thing you forget how to do.
  - `utgivelse` — **the whole release, both platforms, one keypress.** Bumps the
    version ONCE and exports it, so `archive` and `mac` inherit the same number
    and can't drift apart through a forgotten flag. Signing for BOTH platforms is
    checked before anything builds (`signing_preflight`) — the iOS archive alone
    is ten minutes, and a missing Mac certificate discovered afterwards is the
    worst possible moment. `BT_RELEASE=1` suppresses the children's individual
    Transporter prompts so it asks once, at the end, with both files — and then
    prints the App Store Connect steps, because a checklist that only exists in
    someone's head is the part that rots.
  - `ipad` / `iphone` — simulators (`SIM_NAME` / `PHONE_SIM_NAME` override)
  - `device` — build + install on a plugged-in iPad/iPhone
  - `archive` — App Store .ipa, then offers Transporter. The marketing version
    auto-bumps from `ios/VERSION` (commit it with the release; `APP_VERSION=1.1`
    for a deliberate minor). It **hard-fails if the `bt_iap_*` symbols aren't
    exported** — StoreKit IAP dies silently in a stripped binary, hence
    `STRIP_STYLE=non-global`.
  - `love` — just the `.love`, which every other target packages. **Its
    exclusion list is the answer to "what ships?"**: `assets/icon/` and `raw/`
    are build-time art the game never loads, and leaving them in cost 2.7 MB of
    an 8.6 MB download. **The file is `batspillet.love`, ASCII, and that is not
    cosmetic** — see the Mac App Store landmines below.
  - `dmg` — Båtspillet.app + .dmg to hand out (run `setup` first; it packages
    that love.app). Unsigned, so recipients strip quarantine — or set `SIGN_ID`
    + `NOTARY_PROFILE` for a notarized build that just opens.
  - `mac` — Mac App Store `.pkg`, then offers Transporter. **Same bundle id and
    the SAME App Store Connect record as iOS**, which is what Universal Purchase
    means — and why Kaptein-pakken took no work: an IAP belongs to the app, not
    to a platform, so the product the iPad sells is the product the Mac sells.
    The bridge compiles for macOS unchanged because its one UIKit call (haptics)
    is already behind `TARGET_OS_IOS`. Same `bt_iap_*` export guard as `archive`,
    plus one for the `.love` actually being inside — a Mac build with no game
    passes review and boots to LÖVE's no-game screen.
  - `test` — the headless suite (menu item 9). **`utgivelse` runs it first and
    refuses to build if anything fails**; see Tests below for why that gate is
    where it is.
  - `setup` (macOS engine app, once) · `xcode`.
  - `love` and `dmg` are the only commands that run without the vendored Xcode
    project — `need_engine` guards the rest — so a .dmg can still be built
    against a downloaded LÖVE via `LOVE_UNIVERSAL`.
- **The Mac App Store's landmines**, each of which cost a failed build:
  - **NEVER give the fused `.love` a non-ASCII name.** `productbuild`, which
    builds the `.pkg`, writes a resource named `Båtspillet.love` into the
    package's BOM and then **leaves it out of the payload archive**. Nothing
    fails: the export says SUCCEEDED, the .pkg is signed and valid, and it
    installs an app whose Resources contain no game and whose code signature
    seals a file that isn't there. It was caught by 5 MB of missing weight.
    Renaming it `batspillet.love` fixes it completely — verified three ways: the
    å name drops, `game.love` (same extension, ASCII) survives, and
    `Båtspillet.dat` (neutral extension, still å) drops, so it is the name and
    not the `.love` UTI. Both platforms find the fused game by *extension*
    (`getLoveInResources` in `ios.mm`/`macos.mm`), never by name, so the name is
    free — it just has to be ASCII. `do_mac` now checks the **payload**, not the
    archive: the archive had the game every time.
  - **Every embedded framework needs a bundle identifier and versions Apple can
    parse**, and several of LÖVE's prebuilt ones don't have them: freetype had
    no identifier and no version keys at all, harfbuzz no identifier, theora
    "1.0d6"/"1.1alpha1svn" where at most three integers are allowed, and
    love.framework no `CFBundleVersion` (fixed in `mac/liblove-macosx.plist`).
    Nothing local complains — the build, the export and the signature are all
    clean, and it fails at **Transporter delivery** with a 409. `stamp_frameworks`
    fills only what is missing or invalid (idempotent, so re-vendoring the engine
    can't silently undo it), and `verify_bundles` re-checks the archived app
    before export so the next such gap costs seconds instead of an upload.
  - **A framework's code-signature identifier must equal its bundle
    identifier**, and fixing the plist does NOT fix the signature: `codesign`
    reuses the identifier from the previous signature, so a framework once
    signed while it had no `CFBundleIdentifier` keeps a synthesized
    `libmodplug-<sha>` for ever — straight through Xcode's re-sign on copy. Three
    of them were wrong (`libmodplug-<sha>`, `libluajit.so`,
    `libopenal.1.24.3.dylib`) and Apple reports **one per upload**, so they would
    have cost three round trips. `stamp_frameworks` re-signs ad-hoc with
    `--identifier` spelled out; the archive's re-sign then carries it.
  - **Two certificates, not interchangeable.** `Apple Distribution` signs the
    .app, `3rd Party Mac Developer Installer` (Xcode's Manage Certificates calls
    it *Mac Installer Distribution*) signs the .pkg. macOS uploads are .pkg
    only, so the second one is load-bearing and is the one nobody has. `do_mac`
    preflights both plus the profile, and names the exact fix for each.
  - **The provisioning profile lives on the target, in the pbxproj** — never on
    the xcodebuild command line, where it also lands on `liblove-macosx` and
    fails with "does not support provisioning profiles". It can't be dropped
    from the archive either: the entitlements request IAP, and Xcode then
    demands a profile that grants it. Same trap as `CODE_SIGN_ENTITLEMENTS`,
    which is why entitlements are *synced as a file* rather than passed as a
    setting — a framework carrying an app's entitlements fails notarization.
  - **Two entitlements files, and swapping them is not optional.**
    `mac/love-appstore.entitlements` is sandboxed (mandatory) and names the
    app-identifier; `mac/love-dev.entitlements` is the engine's own set.
    Signing the handed-out .dmg with the App Store set makes an app that
    **refuses to launch** — a sandboxed bundle needs a profile to back its
    app-identifier, and the .dmg has none. `do_mac` puts the App Store set in
    place and `cleanup` always puts the dev set back, however the build ended.
    Both keep `allow-jit`: LÖVE embeds LuaJIT, and a hardened runtime with no
    JIT entitlement dies the moment Lua runs — which is also why `sign_app`
    passes `--entitlements` on the Developer ID path.
  - **`PRODUCT_NAME` is Båtspillet, `EXECUTABLE_NAME` stays `love`.** Unlike
    iOS, the bundle's file name is what a Mac owner reads in /Applications, so
    it carries the game's name — while the binary inside stays what the plist's
    `CFBundleExecutable` and every engine build phase expect. `resolve_love`
    therefore takes either name, since a downloaded LÖVE is still `love.app`.
  - Two smaller ones: the build is **universal** (`x86_64 arm64`) because an
    arm64-only slice silently drops every Intel Mac and the vendored frameworks
    are universal already, so it is free; and **`mac` follows `ios/VERSION`
    without bumping it** — the Mac release is the same game as the last iOS
    release, App Store Connect versions each platform separately, and the
    listing's macOS version must read the same string or the upload has nothing
    to attach to. `APP_VERSION=1.0.5 ./bygg.sh mac` for a Mac-only fix.
- **High-DPI is `t.highdpi`, top level in `conf.lua` — never `t.window.highdpi`.**
  LÖVE 12 moved it, and the old field prints a deprecation notice over the
  bottom-left of the running game whenever it is merely PRESENT, `false`
  included. So it can't be left set to a harmless default; it has to be absent.
  On means iOS (or it renders at 1x and looks blurry) and `BATSHOT=retina`.
- **App icon: ONE master**, `assets/icon/icon-1024.png`, full-bleed square with
  no rounded corners of its own (Apple masks it).
  `python3 tools/make_icon.py [new-master.png]` installs it into both
  appiconsets in the vendored engine: iOS gets the 1024 flattened to RGB — **an
  alpha channel fails upload with ITMS-90717 even when fully opaque** — and
  Xcode derives the rest; macOS gets the 16…1024 ladder in the Dock shape
  (824/1024 squircle on a transparent canvas). A new icon on the **Mac** side
  needs `./bygg.sh setup` re-run; iOS just rebuilds. Verify without launching
  anything via `xcrun actool --app-icon "iOS AppIcon" --compile …`.
- **Dev mode** is `config.DEV`, true only with `BATDEV`/`BATSIM` set — which
  cannot happen inside an app bundle. It gates the dev hotkeys, the 4-finger
  profiler toggle and the IAP pretend-stub. In production the cheats are dead
  and a missing bridge makes purchases **fail closed**.
- **Parental gate** (`config.PREMIUM.PARENTAL_GATE`): the buy button opens a
  6×6..9×9 question first. **Six** answers, not three — a child who just taps
  gets through a three-way choice one time in three, which is no gate. The wrong
  answers are plausible near-misses (off by a row, a column, one), so none can
  be dismissed at a glance, and a wrong answer re-rolls with **fresh numbers** so
  it can't be solved by elimination. `GATE_TRIES` then closes it. Two lines of
  copy on purpose: "Spør en voksen!" for the child, and a small line telling the
  grown-up who arrives what they're approving. iOS's own Face ID still guards the
  payment — this exists so a five-year-old can't summon the sheet over and over.
- **Saves are crash-safe.** `Game:save` rotates the last good save to
  `savegame.json.bak` before overwriting; `loadSave` falls back to it.
  `Game:onBlur` flushes fog and save when iOS backgrounds the app — it kills
  suspended apps without calling `love.quit`.
- Dev keys: **F5** reload scene · **F6** reload `src/data/*` · **F3** profiler
  overlay · **F4** record `profile.csv` to the save dir (F4 again flushes; the
  path prints) · **F10** store screenshot · **F11** fullscreen · **M** mute ·
  **ESC** pause in the world, "Vil du avslutte?" on the title, back from the help
  page, quit elsewhere (`onEscape`) · **B** album · dev-only **G** +50 gold,
  **P** summon a pirate, **K** reveal all maps.
- **Store screenshots: `BATSHOT=retina love .`, then F10.** The App Store takes
  ONLY 1280x800, 1440x900, 2560x1600 or 2880x1800 for macOS and resizes nothing,
  so the shot has to leave the game at exactly that size — which a grab of the
  fullscreen window cannot be, and which cropping only makes wrong differently.
  `BATSHOT` therefore sizes the window itself (bare = 1280x800, or `WxH`), keeps
  it windowed, and turns on `config.DEV` so F10 exists. F10 captures the
  BACKBUFFER, so there is no cursor, no menu bar and no window chrome — all
  three disqualify a shot taken with the system grabber. `retina` is the one to
  use: 1440x900 points at 2x is a 2880x1800 capture, the sharpest size the store
  accepts, from a window that still fits on a laptop screen. Files land in the
  save dir and the path prints.
- **Profiling** (`src/systems/profiler.lua`): F4 logs per-frame dt, update/draw
  ms, per-zone ms, draw calls, texture and Lua memory, **`gc_freed_kb`**, object
  and ship counts and the boat's position — so a spike traces to both a phase and
  a place ("it stutters off New York"). A GC hiccup is a `dt_ms` spike on a row
  with a large `gc_freed_kb`.
- Store docs: **`docs/personvern.md` (the privacy policy the App Store listing
  links to) and `docs/store-metadata.md` were deleted in `988a645`** and `docs/`
  is now gitignored. Recover with
  `git show 8c10290:docs/personvern.md > docs/personvern.md` if that wasn't
  deliberate — the listing needs a reachable privacy URL.
- **Parked, do NOT build unless asked**: `docs/sjoroverkongen.md` — a
  Sjørøverkongen boss finale and a "Båtløp" race mode. Read it before ideating
  in that space so the reasoning isn't re-derived.

## Tests

Only where a silent bug costs real progress; the rest is feel, and feel is
tested by playing.

**`./bygg.sh test` runs all of them**, headless, in under a second — or
`luajit tests/<name>.lua` from the repo root for one. It **globs `tests/*.lua`**,
so a new file is picked up by existing; and it spawns one interpreter PER FILE,
because each test mutates the global `love` and `H.report()` ends in
`os.exit(1)`, so the isolation is necessary and free. **`utgivelse` gates on it**
before it builds anything, beside `signing_preflight` and for the same reason:
the archive is ten minutes and this is a second. Until 2026-08 the release path
checked two certificates, a provisioning profile, the `bt_iap_*` exports and the
`.love`'s presence in the Mac payload — and never ran one assertion.

The LÖVE stub and assert helpers are in `tests/harness.lua` — a new test is
`require("tests.harness")`, `H.installLove()`, `H.report()`. Add
`H.installUtf8()` for a scene that needs `utf8` (boatselect, minimap), and
`H.setScreen(w, h)` to walk device shapes — it returns the phone flag from
`Game:load`'s own `min(w,h) < 500` rule rather than restating it.

- `save_state` — round-trip, migration, corrupt-file recovery, gold/food/ammo.
- `cannon` — `Boat:tapFire`: range, ammo and cooldown gates, aim invariants.
- `profiler` — the CSV's shape; a ragged file is only noticed ten minutes in.
- `shelf` — `Shelf.build`, **the cache signature**, and the see-through frame. An
  input the build branches on but `signature()` forgets leaves the shelf stale
  until something unrelated bumps the number: intermittent and unreproducible.
  `Retro.plaqueGlass` is pinned too: its pieces must TILE the plaque, no overlap
  and no gaps. Collapsing it back to `Retro.plaque`-style stacked fills looks
  like a tidy-up and silently breaks the transparency — see "The shelf is
  SEE-THROUGH" below.
- `pointer` — `Pointer.layout` at eight bearings, plus `Pointer.draw`, chiefly
  that **the badge never rotates**; a chest inside the arrow's rotation hangs
  upside-down every time the boat sails west, and half of all playtests never
  notice. `draw` is tested too because there are now two badged markers and the
  badge is what the invariant protects — the test records the transform depth at
  the moment the badge is asked to draw, so a badge that creeps inside the
  push/rotate fails immediately.
- `treasure` — `Treasure.mapDue`. The one number that can be wrong for weeks
  while nothing looks broken. It has been, twice.
- `pirate` — `Pirate.stationOffset`, the standoff steering. A pirate that closes
  to zero parks inside your hull and clips through the sprite, which reads as a
  drawing bug rather than a steering one and gets blamed on the art.
- `announce` — the marker-flourish curves, chiefly that the entrance **overshoots
  past full size**. If it degrades to a polite ease the flourish still runs on
  every frame counter and stops doing the one thing it exists for, and "something
  did flash" is not a bug anyone files. Plus `fit`, which keeps the long treasure
  line on screen.
- `info` — `Info.layout`, the help page's geometry. The page has a fixed row
  count and **no scrolling**, so on a short screen the last row is simply gone —
  and it is gone on the phone while looking perfect on the iPad it was written
  on. Nothing errors and nothing logs; the page just stops early. Checked at
  every shape the game ships in, plus that the huddle solved from
  `Icons.clusterWidth` really fits the column it's drawn in.
- `boatselect` — the ÆØÅ keyboard's and the name row's geometry at nine device
  shapes. It exists because the bug it pins **shipped**: four `Scale.ui`-sized
  rows anchored at `sh * 0.50` put Slett/Mellomrom/**Ferdig** 57–118 px off the
  bottom of every iPhone, and Ferdig is the only exit from editing on touch — so
  tapping the name box trapped the player until they force-quit. It failed 77
  checks before the fix. Also pins the tap-outside escape (the thing that turns
  the next such slip back into a cosmetic bug), `TOUCH_MIN` on everything tapped,
  and the ÆØÅ name handling, where a `utf8.offset` slip silently eats a letter.
- `icons` — the goods huddle. `clusterWidth` must equal what `cluster` actually
  draws: the mission banner reserves space with one and fills it with the other,
  so a mismatch overlaps the town name for *some counts only* — fine with 1 fish,
  wrong with 4 passengers. Same failure `sectionExtent` protects the shelf from.

Anything pulling in `src/ui/minimap.lua` can't load headlessly: it needs `utf8`,
which LÖVE has and bare luajit doesn't.

## Layout

- `main.lua` / `conf.lua` — entry and window config.
- `src/game.lua` — scene manager, global state, save/load, fonts, dev keys.
- `src/config.lua` — every tuning number and the palette. **Edit here to change
  feel.**
- `src/scenes/` — `menu`, `info` ("Slik spiller du"), `boatselect`, `mapselect`,
  `loading` (builds the world in a coroutine), `world` (the game).
- `src/entities/` — `boat`, `port`, `pirate`, `shark`, `dolphins`. Plain tables
  with methods, no inheritance.
- `src/systems/` — `terrain`, `objects` (sprite/placeholder layer), `fleet`
  (ambient ships + skerries), `treasure`, `camera`, `iso`, `cargo`, `fog`,
  `model3d`, `profiler`, `iap`, `haptics`, `loader`.
- `src/ui/` — `hud`, `shelf` (the one "what do I have" panel), `portscreen`
  (dock + shop), `minimap`, `album`, `winscreen`, `mapreveal`, `pointer` (the
  one "go THAT way" marker), `announce` (the flourish that introduces a new goal
  on a marker), `icons`, `retro` (shared bevel look), `dialog` (the one modal
  ask), `scale`, `pixelscene`, `harbormark`, `flags`, `shipinfo`, `pausemenu`.
- `src/data/` — `boats`, `ports`, `ports_amerika`, `ships`, `ships_amerika`,
  `maps`, `shop`. The content; safe for non-coders to edit, F6 reloads.
- `src/json.lua` — vendored, do not touch.
- `assets/` — drop real art/audio here to replace code placeholders.

Scene flow: menu → boatselect → mapselect → loading → world.
Side trip: menu → info → menu.

**One backdrop, three screens.** The boat, map and info screens each baked the
same sky/sea/haze/islands/sun onto a virtual-res canvas with different constants.
That is now `Scene.backdrop` / `Scene.drawBackdrop` (`src/ui/pixelscene.lua`) and
the constants are a `BACKDROP` table per scene, so a fourth chooser is a table
rather than a copy. **The title screen keeps its own bake on purpose** — it has
the lighthouse and a full-bleed geometry the choosers don't share.

## The title screen

Two carved discs hang where the sign's rope-end doubloons used to be
(`assets/menu/questionmark.png`, `exit.png`; `Menu:discSide` / `Menu:drawDisc`).
They were the only dead wood on the screen, and they are the natural home for
the only two things a grown-up ever wants at a title screen.

- **They are PINS BOLTED TO THE SCREEN, not ornaments on the sign.** They were
  first drawn inside the sign's sway, hanging with it, and that was wrong twice
  over: the art is carved wood, so its grain slides against itself under any
  small continuous motion and the disc reads as a smeared texture rather than a
  solid object — and a button that will not hold still is a worse button.
  `Menu:drawSign` therefore hangs the **ropes** from these fixed points and sways
  only what is below them, computing the plank's swung top corner by hand
  (`swayed`) so the rope lands where the plank actually drew. Fixed pins are also
  the honest reading: rings don't swing, ropes do. **Keep the discs still.**
- Size is `DISC_H` (0.66 of the plank height), nearly twice the old doubloon
  across, floored at `config.TOUCH_MIN` — these are CONTROLS, and 21pt of
  doubloon on a phone was a decoration. **One number to tune if they want to be
  bigger still.** One rect function feeds both the drawing and the hit test.
- **No quit disc on iOS** (`Menu:hasQuitDisc`): apps there leave by the home
  gesture and Apple rejects an in-app quit button. That rope keeps its doubloon —
  **sized from `discSide` rather than re-derived**, so the two pins stay a matched
  pair and a tune to `DISC_H` can't move only one of them. The old bottom-right
  "Avslutt" text button is gone — it quit on the spot, and two exits where one
  asks first is worse than either.
- **The exit disc asks first** (`Menu:askQuit`, `src/ui/dialog.lua`): one stray
  tap on a screen a five-year-old is allowed to bash would otherwise end the
  game. Both answers are safe, green "Nei, spill videre!" first. Finn-Erik's own
  recording plays with it (`voice/nei_spill_videre.ogg` — *"Nei, du må spille
  videre!"*), which is the joke and also, for him, the label. **ESC now opens the
  same ask** rather than quitting behind the button's back — see `onEscape` below.
- The **help page** ("Sånn spiller du") is `src/scenes/info.lua`. It is the ONE
  screen aimed past the child, so the pre-reader rule is bent, not broken: every
  line is anchored to the symbol it explains, drawn in the colours he meets at
  sea — which is why the arrow row draws the **real** `Pointer.MISSION` (moved
  out of `world.lua` into `src/ui/pointer.lua` for exactly this; a second
  hand-drawn arrow on the page would teach the wrong symbol). Voice hook:
  `sann_spiller_du`. **The copy is HIS, not mine** — "Sånn", not "Slik";
  "pilen"/"kisten", not "pila"/"kista". Norwegian on any new screen goes past
  him before it ships; see also the tone note in memory.
  `Info.layout` is pure and **shrinks the rows to fit rather than scrolling** —
  a scrollbar is one more thing to discover, and a row pushed off the bottom is
  invisible on the iPad it was written on and obvious on the phone he plays on.
  `tests/info.lua` pins that at every shape the game ships in.
- **Coming back from the help page is quiet** (`game.menuQuiet`): the welcome
  shout and the splash are for walking in the door, and replaying them each time
  he closes a page he opened himself reads as a stutter.
- **`Menu:onEscape` / `Info:onEscape`.** `Game:keypressed` routes ESC to a
  scene's `onEscape` when it has one, so there is one way out per screen instead
  of a key that quits behind the button that asks first. Everything else still
  quits on ESC, as before.

## Conventions (keep these)

- **Isometric rule.** All gameplay — movement, collision, distance — is in a FLAT
  ground plane; only drawing knows iso (`Iso.project`). Terrain elevation is
  **visual only**: the boat always sails at z = 0.
- **Determinism.** Worldgen is seeded (`config.WORLD_SEED`); same seed → same
  map, and F6 must reproduce it. Anything scattered per tile hashes the tile
  coords rather than calling random at build time.
  - **`love.math.random` is NEVER seeded** — LÖVE takes it from the clock — so it
    is the *gameplay* stream: where a pirate appears, fireworks, the dolphins,
    things that should differ every time. Worldgen must not touch it.
  - `src/systems/fleet.lua` therefore owns `self.rng`, its own generator seeded
    from `config.WORLD_SEED`. It used to use the global one, and the whole sea
    silently moved on every load: a platform sailed out to yesterday was
    somewhere else today, skerries wandered, ambient ships respawned elsewhere.
    Worse for debugging, checking a position in one run said **nothing** about
    the next — a rig verified as sitting off Frekhaug simply wasn't there when
    the game was next opened. Anything new that PLACES something in the world
    goes on `self.rng`; anything that happens *during play* stays on the global
    one.
- **Performance.** No per-frame allocations in hot paths. Static geometry
  (terrain, coast, roads) bakes once into a `love.graphics.Mesh`. Per-tile
  closures, tables and sorts are what cause the GC pauses that read as sailing
  stutter — `drawFog` once allocated 25 closures per boundary tile per frame.
  - **"Hot path" means the world scene and anything drawn over it**: `terrain`,
    `objects`, `fleet`, `fog`, `boat`/`pirate`/`shark`/`dolphins`, and the panels
    that sit on the sea all game — `hud`, `shelf`, `minimap`, `pointer`. The cost
    there scales with tiles or with objects, and the profiler's `gc_freed_kb`
    column exists to catch it.
  - **The chooser and modal screens are NOT hot paths** — `menu`, `boatselect`,
    `mapselect`, `info`, `portscreen`, `album`, `winscreen`. No world, no meshes,
    no per-tile anything; the frame budget is nearly empty and a few dozen rects
    per frame is free. So **recompute layout every frame there and don't cache
    it**: `BoatSelect:keyLayout` builds 32 key rects per frame and calls
    `kbMetrics` two or three times, and that is the right trade. A cache would buy
    nothing measurable and cost an invalidation signature that has to know about
    resize, `editing` flipping and `Scale.phone` — which is the exact class of bug
    `tests/shelf.lua` was written for. The shelf earned that complexity by being
    drawn over the world every frame of every voyage. A menu has not.
- **Cross-platform UI sizing — don't regress this.** Never write
  `love.graphics.getHeight()/800` or a bare pixel size in UI code. Everything
  goes through `src/ui/scale.lua`:
  - `Scale.ui(px)` — anything **read or tapped** (text, buttons, icons, crates).
    Phone-boosted via `config.PHONE.UI_BOOST`, because pure proportionality makes
    these physically tiny on a small screen.
  - `Scale.overlay(px)` — **world-anchored decor** (arrows, rings, tags).
    Proportional only, never boosted, or it swallows a phone screen.
  - `Scale.marker(px)` — world-anchored **and recognition-dependent**; today only
    the treasure chest over the boat. Partially boosted (`config.PHONE.MARKER_BOOST`): proportional shrink
    turns a chest into a brown blob at 402pt, while the full UI boost makes
    something hovering over the boat swallow the sea.
  - **Admission rule for `marker`** — a third category is exactly what becomes a
    dumping ground. It must be both anchored in the world *and* carry its meaning
    through a silhouette the player identifies. An abstract arrow is not
    recognition-dependent: that stays `overlay` — which is why the *ring* on the
    destination town is `overlay` while the badge on the same marker is not.
  - Device flags: `Game.mobile` (any iOS), `Game.phone` (small screen → boost +
    `config.PHONE.CAMERA_ZOOM`), `Game.touchCamera` (glide-follow, no
    edge-scroll). Check UI work in `BATSIM=iphone` **and** `BATSIM=ipad` before
    calling it done.
  - **Never anchor `Scale.ui`-sized content at a fixed fraction of the window.**
    This is the one combination that breaks on phones ONLY, and it breaks
    silently — nothing errors, nothing logs. `Scale.ui` is `h/800 × UI_BOOST`, so
    on a phone the content is ~1.6× bigger *relative to the screen* than on the
    iPad it was laid out on, while `sh * 0.5` stays put. It grows into whatever is
    below it and then off the edge.
    - The worked example is the boat screen's ÆØÅ keyboard. Four rows sized by
      `Scale.ui`, anchored at `sh * 0.50`, ended **57–118 px past the bottom of
      every iPhone** — SE through 17 Pro Max, worse the bigger the phone. The row
      that fell off was Slett / Mellomrom / **Ferdig**, and Ferdig is the only way
      out of editing on a touch device (`mousepressed` tested the key rects and
      returned; `keypressed` can't fire on iOS; there is no Tilbake while
      editing). So tapping the name box **trapped the player until they
      force-quit the app**, on the second screen of the game. It shipped, and it
      was invisible on the iPad.
    - Two fixes, and the second one is the important one. `BoatSelect:kbMetrics`
      is now the single source for the keyboard's geometry — `keyLayout` builds
      the rects from it and `layout` hangs the editing name box above it, so they
      cannot disagree — and it is anchored to the **bottom** of the screen with
      its size clamped by width *and* height. Separately, **a tap on nothing now
      leaves editing**: one small exit is what turned a layout slip into a locked
      app, so the escape hatch matters more than the geometry.
    - A width term must count the **gaps**. `(sw * 0.92) / 10` forgot the nine
      inter-key gaps and put an iPhone SE's outer keys at `x = -3`.
    - Anything both tapped and phone-sized needs `math.max(px * k,
      config.TOUCH_MIN)`. The name box, Nytt navn and Tilbake were 34–42 pt.
    - `tests/boatselect.lua` pins all of it at nine shapes (it failed 77 checks
      before the fix), the way `tests/info.lua` pins the help page. **A new screen
      with rows or a grid gets a layout test**; that is the only control that
      actually caught this. `H.installUtf8()` / `H.setScreen()` in the harness are
      what let a scene load headlessly — `setScreen` derives the phone flag with
      `Game:load`'s own `min(w,h) < 500` rule so the two can't drift.
    - **Still open, deliberately:** the hero preview is centred at `sh * 0.32`
      while `previewW` resolves to `≈0.64 × h` on any landscape phone, so its
      nominal box reaches ~24 px into the boat strip at `sh * 0.42` on every
      iPhone. The three draw paths (`drawModel3D`, `drawBoatFrames`, photo sprite)
      have very different real extents, so whether it visibly collides depends on
      which boat is selected — which is why it reproduces for one person and not
      another. Not reshaped: measuring it needs a device, not a headless box.
- **Pre-reader UX.** State is carried by shape, colour and VOICE, never text
  alone. Locked premium boats stay full-colour behind a rope and gold padlock —
  grey reads as "broken" to a kid — and the action button is green + sail when
  sailable, gold + padlock when locked. Voice hooks: `laast`, `spor_en_voksen`.
- **HAVE vs DO — the HUD rule. Pick a side for anything new.**
  - *HAVE* — gold, cargo aboard, gear, treasures — lives in ONE compact shelf on
    the left (`src/ui/shelf.lua`), in one grammar: a sunken slot with an icon and
    an `xN` badge, sections split by a thin rule and **no text headers**. Before
    this, possessions were spread over four grammars and counts were written three
    ways; now he learns a slot once.
  - *DO* — the top-centre mission banner plus the world marker. **Never more than
    one thing to follow at a time.**
  - **A new goal is ANNOUNCED, in words, then the marker is left alone**
    (`src/ui/announce.lua`, `config.MARKER_ANNOUNCE`). One line springs up over
    the marker, overshooting so it lands with a bump, breathes, and fades — 2.8 s
    all in. The mission marker shipped as a bare gold arrow on the theory that an
    arrow is self-explanatory; a playtester took his first cargo, got the arrow
    and had no idea what it was for. An arrow says "that way" and never "that way
    to *what*", so the WHAT is said loudly at the moment it changes and then gets
    out of the way. Both markers use the one module, so the two announcements are
    the same gesture and he learns it once.
    - Mission (`World:onCargoTaken` → `missionAnnounceDelay` → `missionAnnounce`):
      "Pilen viser vei", **once ever** (`hintFollowArrow`). The line teaches the
      ARROW — it never names the town — so it's a tutorial line, and a tutorial
      line repeated every voyage is a nag. It ran every pickup at first, on the
      reasoning that the destination changes each time; that reasoning belongs to
      a line that says *which* town, and this one doesn't. Delayed 3.5 s: fired as
      the dock closed it landed while the player was still finding the boat.
      Voice: `pilen_viser_vei`.
    - Treasure (`World:closeMapReveal` → `treasureAnnounceDelay` →
      `treasureAnnounce`): "Pilen viser vei til skatten!" a few seconds after the
      card clears — same hold as the mission line, so it lands once you're
      sailing — tying the thing the card was about to the thing to follow. Never on load — a saved hunt is
      already under way. It also gets `World:drawTreasureHint`: a big bobbing
      chest pinned to the screen EDGE in the treasure's direction, because the
      chest is off screen at the start of every hunt, which is exactly when
      "which way?" is hardest and the little arrow over the boat easiest to miss.
      It leaves with the words. Same gesture as `drawPirateIndicator` pointed at
      the opposite feeling; both go through `Pointer.edge`.
    - **A badge was tried on the mission arrow and taken off** — the destination
      town's harbour mark on a disc in its colour, arriving huge and shrinking
      away. It answered "to what" with a second symbol the child then has to
      learn, and it sat over the boat all voyage still answering a question asked
      once. Words and voice do it in one go; the sea stays clear. Don't re-add it.
      (The treasure chest badge is different and stays: it's the hunt indicator,
      and it's what the heat and the heartbeat act on.)
    - **`Announce.fit` is load-bearing.** "Pilen viser vei til skatten!" is nearly
      twice the mission line and an iPhone is 874pt wide, with the entrance
      overshooting on top. A clipped caption is invisible on the iPad it's written
      on and obvious on the phone he plays it on.
  - **The active destination shows on the minimap even under fog.** The
    harbourmaster named the town; a pip on the chart is what being told a name
    means. Without it the first delivery of a new world points at nothing visible
    anywhere on screen — and you cannot learn what a pointer means when the
    pointed-at thing isn't there. Terrain fog is untouched: one town, the one you
    were just sent to.
  - **Counts are SHOWN, not written** (`Icons.cluster`). Four passengers stand in
    a huddle — first one whole, the rest peeking out from behind, each a step over
    and a touch higher — instead of one passenger and "×4". He can't read "×4"; he
    can count heads. Same reasoning as the treasure tally's rising gold. They
    *overlap* on purpose: spaced evenly they read as four separate errands, while
    shoulder to shoulder they read as one group going one place, which is what a
    job actually is. Used by the mission banner and the dock screens. The shelf's
    remaining `xN` badges (gear, food, ammo) stay: a slot is ~44pt and a huddle in
    one is mush, and a stack of bread is a quantity, not a group going anywhere.
  - **Cargo is NOT on the shelf.** Once the banner drew the goods themselves, and
    given a harbour won't hand out a second job while one is aboard, HAVE and DO
    held the identical fact in two grammars — a countable picture up top and a box
    with "x4" on the left. That's the exact failure the shelf was built to end, so
    the shelf gave it up. It also means cargo is invisible during a treasure hunt
    (the banner hides then, by design: one thing to follow). Note the signature
    rule runs BOTH ways — cargo left `Shelf.build`, so it had to leave
    `signature()` too, or every pickup rebuilds the shelf to produce identical
    output. `tests/shelf.lua` pins both directions.
  - **Never draw the player's stuff on the boat.** It crowds the thing the child
    is steering; a deck-cargo experiment was removed for exactly this.
  - **The shelf is SEE-THROUGH** (`config.SHELF`, `Retro.plaqueGlass`). It sits on
    the sea for the whole game and most of what it covers is padding, so the frame
    and the recessed backing give way and the water shows through them — the
    minimap's idea, one panel over, but less faint (0.66/0.40 against the
    minimap's 0.10 well, which is a touch too transparent). **Only the wood gives
    way**: the coin, the gold, every slot and its icon, the badges and the pause
    key stay at full strength, because they are the whole reason the panel exists.
    - **`Retro.plaqueGlass` is not `Retro.plaque` with an alpha, and cannot be.**
      The plaque fills the whole rect with plank and lays the well on top; give
      those two an alpha and the middle darkens twice while the well shows
      through onto the PLANK rather than the sea, which looks exactly like being
      see-through onto nothing. It is the identical bug the minimap's wooden
      surround was rewritten as a real ring to fix. The glass version paints every
      pixel EXACTLY ONCE — three disjoint zones, and `ringBands` for the two
      frames because `Retro.bevel`'s bands overlap at the corners. `tests/shelf.lua`
      pins that the pieces tile the plaque with no overlap and no gaps, and it
      fails loudly if anyone collapses it back into stacked fills.
    - The gold number is the one thing with no slot behind it, so it gained a drop
      shadow — gold lettering on open water otherwise. Both layouts go through the
      one `goldLine`, like `sectionExtent`: these two have drifted before.
  - **Nothing floats loose on the sea.** Pause is a key at the end of the shelf's
    gold row (`Shelf.draw`'s `key` argument, drawn by `HUD.drawPauseKey`) — inside
    the panel the player already reads, and **only the key itself is tappable**.
    It has had four homes: the whole inventory plaque *was* the button, so tapping
    your own bread paused the game; bottom-left was unfindable; above the shelf it
    ate a band of the left edge; under the minimap it read as an orphaned square
    in the water.
  - Shelf taps never fall through to the world — poking your own stuff must never
    act on what's behind it.
  - **Phones flow the shelf sideways.** An iPhone is 874×402: width is plentiful,
    height is what the sea needs, so a column growing downward fights the wrong
    axis (it reached ~47% of the screen). On `Scale.phone` the shelf packs whole
    sections per row — 13% of the screen for one row, 21% worst case, with
    *bigger* slots. Nothing is hidden from the small screen; it's laid out
    differently, not cut down. Both layouts measure through the one shared
    `sectionExtent`, so they can't drift apart.
  - **Only CONTROLS are held to Apple's 44pt** (`config.TOUCH_MIN`, via
    `HUD.keySize`): status is read, never tapped, so it's free to be smaller. That
    split is the whole trick — with one deliberate exception, the treasure slot,
    which IS tapped (it opens the album), so it alone among the shelf's slots
    meets the minimum. Being visibly the biggest slot also does the wordless job
    of saying "this one does something".
  - **The treasure tally is ONE slot, not one per chest.** It fills with gold from
    the bottom (`Shelf.progressSlot`) with a small `2/4` badge for the grown-up.
    **The fill is the load-bearing signal** — he cannot read a fraction — and the
    badge must never become the only one. Four wells cost four slots of the panel
    we most want small and said what a rising line says in one. The slot appears
    once the hunt has been *introduced* (`world.huntSeen`, which **latches**: a
    pirate stealing your chest un-maps it, and a tally vanishing at that moment
    would read as "the pirate took my treasures too").
- **Buttons press in, fire on release.** Every button uses the Retro protocol
  (`src/ui/retro.lua`): `Retro.press(id, rect, x, y[, ox, oy])` in mousepressed,
  `Retro.isDown(id)` (or `Retro.button`) while drawing, `Retro.released(id, x, y)`
  in mousereleased. Sunken bevel while held, slide-off cancels, gold burst on
  fire. **Never make a new button act on mousepressed.**
- **Placeholder-first art.** Everything draws a code placeholder, and the matching
  PNG replaces it if present (`Objects.draw`, `Terrain:drawSprite`): so art drops
  in with zero code — `assets/tiles/`, `props/`, `boats/`, `ports/portraits/`,
  `icons/`, `models/`. **The game must always run with no art.**
- **The harbour town is CODE-DRAWN and stays that way** (`Port:drawPlaceholder`).
  Baking it to a pixel image was tried and reverted (2026-07): at a texel density
  matching the OpenGFX blocks it renders identically by construction, so it bought
  nothing, while adding a visible pop as each bake landed. Lowering the density
  enough to look chunky loses the detail. If you want chunky harbours the answer
  is real pixel art in `assets/ports/<id>.png`, which the placeholder path already
  picks up.
- **Trees are never pixel art.** They are 3D models baked ONCE to smooth sprites
  (`assets/models/trees.obj`); the code-drawn tree is the fallback. Pixelised
  trees were the one thing the actual player disliked.
- **Data-driven content.** Add a boat or port by editing `src/data/*` — no logic
  changes. Boats are free or `premium = true`. **GOLD NEVER BUYS BOATS**: gold is
  for provisions, cannon and ammo; boats are the Kaptein-pakken's whole value.
- **Harbourmaster portraits.** `python3 tools/make_portrait.py <photo.png> <id>`
  → `assets/ports/portraits/<id>.png`. It renders ~370px and quantizes to 24
  colours **without dithering**: the well is ~492×576pt on a 13" iPad, and the old
  130px dithered portraits blew up ~5× in device pixels, where magnified
  Floyd-Steinberg reads as dirt on a face. Chunky is the look;
  dithered-and-magnified was the bug. Override with
  `PORTRAIT_WIDTH`/`PORTRAIT_COLORS`/`PORTRAIT_DITHER`.
- **Audio overrides.** Synth SFX and voice are replaced by files when present:
  `assets/sfx/<name>.ogg`, `assets/voice/<name>.ogg`. Convert via ffmpeg →
  `oggenc` (Vorbis).
  - **A clip that sounds quiet is usually quiet, not mixed wrong.**
    `playNamedVoice` already plays at 1.0 and LÖVE won't go above it, so the fix
    is the file. Check before touching code:
    `ffmpeg -i clip.ogg -af volumedetect -f null - 2>&1 | grep volume` — the voice
    clips sit around **−15 dB mean**; `finn_en_havn` was −19 and was lifted to
    match (`volume=4.2dB,alimiter=limit=0.97`, then re-encoded at its own 44.1 kHz
    rather than the README's 22050, so a lossy generation isn't also downsampled).
  - The **harbour horn is 0.55** (`HORN_VOL` in `portscreen.lua`): it fires on
    arrival and on casting off, right next to a spoken line. The player's own horn
    stays 1.0 — that one is the child pressing a button, and it should be the
    loudest thing he can make happen.
  - **`leave.ogg` is ~14 dB hotter (≈5×) than the synth effects** — −8 dB mean
    against −22 — so its call-site volumes look absurdly small and are correct:
    0.42 on casting off is *above* the 0.6 baseline in the ear, not below it. All
    five uses (world cast-off, boatselect ×2, pausemenu, mapselect) sit at
    0.20–0.42 and should move together. Measure before tuning:
    `ffmpeg -i clip.ogg -af volumedetect -f null - 2>&1 | grep mean_volume`.
  - **Do NOT normalise `leave.ogg` down to match the others.** It was tried and
    reverted. `Source:setVolume` clamps at **1.0**, and this clip is wanted at
    roughly twice the baseline — so once the file is quietened, that level is
    simply unreachable and no call-site number can get it back. A file being
    louder than its neighbours is only a problem if the call sites pretend
    otherwise; the fix is this note, not a re-encode. (A clip that is too *quiet*
    is the opposite case and does want the file fixed — see `finn_en_havn` above,
    where 1.0 was already maxed out and the recording had to come up.)
  - Note the cast-off sound is a *different* one from the harbour horn above —
    both fire around leaving, so confirm which you're hearing before turning a knob.
  - **Discovering an island is silent** (`World:checkIslandDiscovery` still
    records it). A 19-island map meant 19 toasts and 19 chimes for something the
    player didn't choose to do and can't act on, and the fog opening up says "new
    place" better than a word he can't read.
- **Child-friendly.** The boat accelerates gently, never sinks, bounces softly.
  Docking is automatic. Big clear cues, voice prompts, no real failure. The pirate
  is slow and dodge-able, and harbours are always safe.

## Sea furniture, channels, and checking a map is sailable

Per-map, from a map's `sea` and `channels` entries in `src/data/maps.lua`.
Tuning lives in `config.SEA` and `config.CHANNELS`.

- **Oil rigs** (`assets/props/rig/rig.png`). Both maps — Norge's four are as
  Norwegian as the fjord they are nowhere near; Amerika has six. Solid, with a
  generous bump circle, because the point of a structure in open water is that
  you sail *around* it.
  - **A map's `rigs` is a LIST OF COORDINATES, and shipped maps keep it that
    way.** The same spots on every device and every launch, inspectable, and any
    one of them nudged by hand without touching a rule. Procedural placement
    moves the moment the terrain, a channel or a tuning number changes, and then
    every position has to be re-checked — which is not a thing anyone does.
    Setting `rigs = <count>` re-scatters instead, and in dev prints a paste-ready
    list, so a NEW map is scattered once, looked at, and then frozen.
  - Dev warns when an authored rig is not in open water, or stands on a chest.
    Both have caught real mistakes.
  - **The scatter's placement is an ANNULUS round the towns**, and both bounds
    were learned by getting it wrong. `fromPort` alone means "far from every harbour", which on
    Norge (towns only span x 3500..9000) is the same place as "off the edge of
    the game" — the first pair went to the far east and the north-west corner and
    were never seen. `nearPort` is the upper bound that keeps them in the water
    the player crosses. Selection inside the ring is **farthest-point** (each rig
    goes to whichever candidate is furthest from those already standing), because
    plain rejection sampling clustered all six of Amerika's into a row along the
    southern edge — but farthest-point *alone* drives everything into the corners,
    which is what the annulus holds back.
  - Rigs also keep off the **map border**: `openSea` samples through
    `tileIndexAt`, which CLAMPS, so a point hard against the edge reads as having
    open water on that side. One came out at y = 26.
  - **`Fleet:unblockTreasures` withdraws any rig standing on a chest.** Rigs are
    placed in `populate()`, which runs *before* `Treasure.build`, so a platform
    can land on a sandbank a chest later appears on — and its bump circle then
    makes that chest unreachable, which is a hunt with no way out of it. Losing
    one platform of six is invisible; that is not. It fires on real worlds.
- **Buoys** (`Fleet:layBuoys`) — Amerika only. A row leading out of each harbour
  mouth along the bearing with the most open water, which is the approach channel
  by definition. **Not solid**: bumping off the thing you were told to follow
  teaches the wrong lesson. A pre-reader cannot read a town name but can follow
  four red markers. (Norwegian, if it ever needs a label: a **bøye**; the class of
  thing is a **sjømerke**. A **livbøye** is the rescue ring — a different object.)
- **`channels`** (`Terrain:carveChannels`) — authored waterways, forced open on
  the corner grid right after the island masks and noise, before anything
  downstream reads it. Carving later gives a channel you can sail through that
  still *draws* as land. A band of width W leaves roughly `(W-128)/2` of real
  clearance, because the carve runs on the 64-unit grid and a tile needs all four
  corners clear.
- **Checking a map: `BATNAV=1 love .` then `python3 tools/navcheck.py`**
  (`World:dumpNavGrid`, dev only). "There is water there" and "you can sail
  there" are different questions, and Amerika read fine by eye while **a third of
  its sea was unreachable**. The tool splits the sea into BASINS of water with
  enough clearance to steer in and reports everything outside the basin the boat
  starts in, plus the shortest carve that would join each one back — which is
  what goes in `channels`. **A gap the boat can *just* thread is worse than
  none**: the auto-steer bounces off one shore, turns, bounces off the other, and
  ping-pongs there for ever. Amerika's middle strait was 8 units of clearance
  against a boat of radius 20. Re-run after touching `ISLANDS`, `LAND_THRESH` or
  `channels`.

## Maps and world generation

A **map is data** (`src/data/maps.lua`): a seed, authored island anchors, and
which ports/ships files populate it. `Game:applyMap()` installs the seed and
islands into config's live slots, so terrain and treasure read one place. A paid
map pack is a new entry with its own product id and state flag — **not** the
Kaptein-pakken `premium` flag.

**Adding a town to a SHIPPED map is safe; adding an ISLAND is where saves
break.** Nothing in the save file mentions ports, so a new entry in
`src/data/ports.lua` simply appears for a player mid-game — the terrain is
regenerated from the seed at load, never stored. Islands are the opposite:
`discoveredIslands` holds `"island"..i` and `treasuresFound`/`treasuresMapped`
hold `"treasure"..islandIndex`, both **positional**. So:
- **Append to `islands`, never insert.** Inserting renumbers everything after it
  and the saved ids quietly start naming different places.
- **Keep a new Norge island under radius 1820.** `Treasure.pickIslands` takes the
  `COUNT` biggest, currently Bergen 2520 (#1), Oslo 2520 (#7), Skiparviken 1960
  (#3), Lerøy 1820 (#5) → chests `treasure1/3/5/7`. Anything 1820 or over
  displaces Lerøy: a found chest's id stops existing, the tally drops from 3/4
  back to 2/4, and since `good` is handed out by PICK ORDER the album's stickers
  reshuffle too. Equal is not safe either — `table.sort` is unstable on ties.
- `tests/treasure.lua` pins the pick set and the 1820 margin, because all three
  mistakes look completely innocent in a diff and nothing errors or logs.
- Putting the town on an existing island sidesteps all of it. **Frekhaug** is the
  worked example: a second harbour on Bergen's island, NE shore, ~2800 units off
  Bergen (a `large` town spreads ~1100 and flattening reaches ~450).

**Biomes carry more than colour now** (`config.BIOMES`): `palms` puts palm
sprites among a biome's plants — Los Angeles' desert gets a third of them, Miami
is a `tropical` island where every forest tree is one. That is the ONE place the
"trees are never pixel art" rule bends, and it survives because a palm is a
*silhouette* — bare trunk, crown on top — which is not what the original
objection was about. `houses` is the countryside density (1 tile in N, default
13). **Biomes that set `houses` get first refusal on their tiles**, before woods
and scrub: with vegetation first the setting did nothing at all, because
tropical's forests and desert's scrub claim almost every grass tile before the
house branch is reached. Norge is untouched — `green` sets no `houses`, so it
still falls through to the bottom.

Per-island fields: `biome` (`config.BIOMES`) and `remote = true`, which grows no
countryside houses, so the island stays forest, rock and coast — and since roads
link neighbouring houses, no roads either. **Mixing packed islands with empty
ones is what makes a big map feel travelled**; Amerika marks 6 of 19 remote.
Lookups go through `Terrain:islandAt` (`biomeAt` / `isRemoteAt` both read it).

A port can take `landmarks = {"airport"}` (`LANDMARKS` in `world.lua`): a named
cluster — control tower, terminal, hangar — on consecutive tiles just past the
built-up edge, so it reads as one installation and stays out of the downtown
core. Both Amerika metropolises have one; a control tower says "big foreign city"
to a five-year-old far more loudly than any change of housing style. Downtown art
is per-map (`BLOCK_SETS` in `world.lua`): Norge the modest `block_*.png`, Amerika
the `us_*.png` high-rises. **Never merge them — glass towers in a fjord are
wrong.**

Generation: value-noise fBm masked by radial island gradients, thresholded for
coastlines and quantized into terraced plateaus, baked to meshes. Towns snap to
the nearest coast. The beach's sand→grass edge is a dithered band driven by a
corner-grid shore-distance field (`Terrain:isBeach`, `config.BEACH`) shared by
both ground meshes, so it never traces the tile diamonds. Between the towns,
**farm districts**: a coarse 4×4 hash (`FARM_CELL`/`FARM_ODDS` in `world.lua`)
makes every countryside building in one cell in five draw from the farm set, so a
farm arrives as a CLUSTER — farmhouse, barn, silo, pig pen — rather than a lone
barn in a field. Dirt **country roads** link neighbouring countryside houses
(`Terrain:buildRoadMesh`, `config.ROADS`), dropped where they'd cross water, pads
or high ground. All baked static.

## Save

`savegame.json` in LÖVE's save dir (identity `batspillet`), plus the `.bak`.

Global: `coins`, `unlockedBoats`, `selectedBoat`, `selectedMap`, `boatNames`,
`premium`, `owned` (one-time upgrades), `food`, `ammo`, `cannons`,
`hintFindPort`.

**Per-world under `maps[mapId]`** (via `Game:mapState`): `fog`,
`discoveredIslands`, `treasuresFound`, `treasuresMapped`. Exploration belongs to
a world, not the player, and must never leak between maps. `Game:mapState`
backfills missing lists, because `loadSave` takes `data.maps` wholesale and an
older or truncated save hands back a bucket with only some keys.

`Game:newGame` ("Spill igjen") resets progress but **NEVER** premium,
unlockedBoats, boatNames or the boat/map selection. It must never cost a family
their purchase.

## World map + treasure hunt

The **minimap** (`src/ui/minimap.lua`) is a fog-grid texture repainted only as
cells reveal, with port pips, the boat, the camera viewport and treasure X's.
**The unexplored dark is semi-transparent** (`config.MINIMAP`), and it alone: the
map covers a corner of the sea, and the part of it covering the most screen is the
part with the least to say. Revealed terrain stays solid and every pip, X, boat
and viewport line draws over the top at full strength. Two things had to give way
for that to be visible at all, and **both are easy to reintroduce**: the well
behind the map is a faint wash rather than opaque, and the wooden surround is
drawn as a genuine RING — four trapezoids between matching `outer`/`inner`
vertices. It used to be `polygon("fill", outer)` with the well laid over it, and
since `outer` *contains* `inner`, that quietly painted an opaque plank across the
whole map: every bit of alpha underneath was see-through onto wood, which looks
exactly like being see-through onto nothing.

**It is drawn in the SAME iso projection as the world**, so it's a 2:1 diamond,
not a rectangle — don't "fix" that. Drawn top-down it disagreed with the view by
up to 63°, so a child who read the map and sailed that way went somewhere else.
Everything routes through `Iso.project`, including the viewport, which unprojects
the four *screen* corners and re-projects them so it traces the true view rather
than an over-large bounding diamond.

**The hunt** (`src/systems/treasure.lua`, `config.TREASURE`): chests rest on
seeded sandbanks in open water off the biggest islands — `Treasure.sandbankNear`
picks a tile with water all around, so the pathfinding-less boat pulls right up.

A harbourmaster hands out a map **on a successful delivery** with no hunt active
(`World:revealTreasureMap`, one at a time). The rule itself is `Treasure.mapDue`
— pure and tested — with the first map guaranteed, since a pre-reader can't be
told the mechanic exists and has to be handed it. **The cadence is
`MAP_COOLDOWN - 1 + 1/MAP_CHANCE` deliveries between hunts**, currently ~4.2, and
it is the rhythm of the whole game: the delivery loop is the spine, hunts are the
punctuation. **Spend tuning on the FLOOR, not the chance** — a lower chance buys
the same average with more variance, and a drought reads to a five-year-old as
"the treasure game stopped". Deliveries made *during* a hunt deliberately don't
tick the floor; when they did, one mid-hunt delivery ate the whole breather and
maps arrived ~45% more often than `config.TREASURE` claimed.

When granted, the "Finn skatten!" card pops once the dock closes
(`src/ui/mapreveal.lua`, deferred via `pendingMapReveal`), and the handoff gets
its own screen first (`PortScreen:drawMapHandoff`). As the card clears, the chest
marker **announces itself** over the boat (`World:closeMapReveal`; see "A new
goal is ANNOUNCED on the marker" above), so the thing the card was about and the
thing to follow are visibly the same object. Getting a map sends you straight
into the hunt; the post-delivery oppdrag is skipped. While a chest is
active **harbours give no new oppdrag** — "Finn skatten først!" (`openDock`
forces `mode = "findfirst"`) — though cargo already aboard still gets delivered.

As you close in **a pirate races you** (`World:updateRace`/`spawnRacer`: a
goal-driven `Pirate` via its `goal` field, slightly slower than you). Reach it
first and it's yours, **no cannon needed**; the player is checked first so a tie
goes to you. If the pirate wins it steals the chest and the X vanishes — no
deadlock circling it — and the chest returns to the pool for a future map.

**Treasure-seeking mode** (`config.TREASURE_MODE`): while a map is live the whole
game changes character, because a pre-reader can't be *told* he's on a hunt — he
has to feel it. It all runs off one number, `World:treasureHeat()` (0 far → 1
nearly on it), so nothing can disagree: the chest marker grows, bobs faster and
BEATS, the ring on the chest pulses faster (warmer/colder, the oldest children's
game there is, and wordless), and `World:drawHuntOverlay` washes the sea in
old-map parchment with a deepening vignette. `World:drawMissionPointer` bows out,
so there is only ever ONE thing to follow.

**There is deliberately no "Finn skatten!" banner and no map slot in the shelf.**
Both existed and both were removed for the same reason: the top-centre band and
the left shelf are the two most expensive strips of screen on an iPhone, and a
chest hovering over the boat — where the child is already looking — says
"treasure!" more loudly than a word he can't read. Don't re-add either; if the
hunt needs to say more, say it on the marker.

Each chest yields one collectible (`config.TREASURE_GOODS`) for the **album**
(`src/ui/album.lua`), a sticker page opened by the **B** key or the shelf's
treasure slot. Finding **all** chests triggers the finale
(`src/ui/winscreen.lua`): fireworks, coins piling up along the bottom, the open
chest with every sticker, and Finn-Erik the pirate. Its "Spill igjen" wipes to
defaults and returns to the title screen — the hook to rotate `WORLD_SEED` for a
different map each finish is noted there.

## Shop, pirate, and little joys

The dock screen's **Butikk** button opens a full-screen store
(`src/ui/portscreen.lua`) — a rusty trading post showing a grid of wooden crates.
Items are data in `src/data/shop.lua`. Unaffordable ones dim with a red price and
show "Spar X til!", which is the subtraction the store exists to teach.

- **Kanon** (100 g) is re-buyable (`stack = true`): the first unlocks the
  auto-cannon, each extra fires the battery `config.CANNON.EXTRA_RATE` faster,
  capped at `MAX_RATE`.
- **Food** (Brød, Saft, Sitroner, Epler, Ost) is re-buyable provisions with a
  stock badge. Crew and passengers eat one every `config.EAT_DISTANCE` with a
  "Nam nam nam!", so a long voyage is a reason to stock up.
- **Kanonkuler** (`ammo = N`) refills the locker. It stays **last** in the list:
  it's the only crate that can be hidden (no cannon yet), and as the tail item its
  coming and going never shifts the others around the grid.

**The pirate appears just past the edge of what you can SEE, ahead of you**
(`World:spawnPirate` / `viewRadius`): angles are tried in order of how close they
are to straight ahead, at a distance just beyond the unprojected screen corners,
so it sails into view within a second or two. It used to take any of twelve
angles at up to 1350 units, which on a wide screen is often behind you and out of
sight — the chant went up, the music changed, and there was nothing there. A
threat you can hear but not find reads to a five-year-old as the game being
broken. The old all-round sweep survives as a fallback for when there's no open
water ahead at all.

**It fights from a standoff** (`config.PIRATE.STANDOFF`, `Pirate.stationOffset`):
one continuous rule — far out it aims at you, on station it aims across you and
circles, inside it aims away and peels off. It used to steer straight at you and
close to nothing, which clipped a galleon through the player's sprite and made a
duel unreadable at the exact moment it mattered. A state machine would judder
along its own boundaries; the single curve can't. Its shots are also **aimed from
the muzzle, not the hull centre** — the ball leaves ~83 units up a long bow, which
is a rounding error at range and the whole shot at close quarters, and is why a
pirate sitting on top of you never used to land anything.

The auto-cannon fires wild — no leading, random `SPREAD` — so most shots miss,
and a hit **scares the pirate off** rather than sinking it. **Tapping the pirate
fires a shot you aimed yourself** (`Boat:tapFire`), the one trigger in the game,
added because every older child who playtested reached for one. The automatic
battery is untouched, so a small child who never taps plays exactly as before.
The aimed shot is far more accurate — that accuracy IS the reward — but still
costs a ball and runs on its own cooldown, so tapping never waits on the battery.
Only while the pirate is chasing; out of range or with no cannon the tap falls
through to sailing, so tapping a distant pirate simply steers you toward it.

**Ammo is what balances this, not a slow trigger.** The trigger is deliberately
fast, so `START_AMMO` (40) and the 25-ball crate (20 g ≈ one delivery) are sized
for ~2 balls a second of hammering. An empty locker always answers a TAP with a
dry click and repeats the spoken warning on a cooldown; the automatic battery
going quiet says its piece once per encounter, so it never nags.

**Driving the pirate off pays** (`World:pirateDropsGold`, `DROP_GOLD` = 25 ≈ a
delivery). **Don't remove this**: the kanonkuler spent in a fight cost real gold,
so with no prize the correct play is always to run away — the wrong lesson for
the one part of the game the older playtesters asked for.

**Little joys.** Space, or tapping your own boat, toots the **horn** — capped at
~1s, with smoke puffs, and the nearest ship within earshot answers back deeper a
beat later (`World:soundHorn`). A **dolphin pod** joins when you hold full sail a
moment (`src/entities/dolphins.lua`). A **friendly shark** wanders the sea, the
pirate's opposite: it bumps softly and never chases. Every delivery ends with
**mini fireworks** over the town as you sail off (`World:startFireworks`,
deferred until the dock closes like the map card).

**Ambient ships** (`src/data/ships.lua`) live in `src/systems/fleet.lua`: a
`home` boat runs a two-stop ferry route around its island (`buildFerryRoute`), a
`visits` liner periodically steers to an anchorage off a listed city
(`findAnchorage`), and a `submarine` cruises invisible underwater, surfacing now
and then with bubbles and a "blubb" (`Fleet:updateDive`) — not solid or tappable
while under. It stays up **26–42 s** (`config.SUBMARINE`), long enough to be a
sighting: at 10–18 s it was gone before you could steer over to look, and the
rarest thing in the sea read as a glitch rather than a lucky catch. Anchorages and stops always stay outside the docking approach, so a
vessel can never steal the harbour tap. Far-off ships tick their AI in batched
steps (`config.AMBIENT_LOD`), so adding boats costs ~nothing per frame.

## Roadmap

More towns and harbourmasters, bigger islands with more on them (villages,
landmarks, lakes), real pixel-art tiles and props to replace placeholders, more
of Finn-Erik's own artwork and voice. Possible later: Bluetooth multiplayer (real
`love.thread` for networking; meshes stay main-thread).
