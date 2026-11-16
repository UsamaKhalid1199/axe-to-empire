# Axe to Empire

3D arcade-idle game for Android (portrait). Chop trees, stack logs, cook, serve guests, hire a crew,
then unlock the next venue and grow a six-venue Timber Empire. Prestige ("New Empire") restarts with +50% income.

Godot 4.7.2, GDScript, `gl_compatibility` renderer. Tuned for low-end phones (PowerVR GE8320, ~3 GB RAM).

## The game loop

1. Chop trees (stand next to one; the axe/chainsaw comes out only near trees). Stumps regrow after 45 s,
   and only once you've walked away, so you keep moving through the forest.
2. Stack logs by the cooker, carry food to the counter, serve the queue, collect coins.
3. Build pads (tables, tool shed, crew cabin, second cooker), buy tool/bag/boots and kitchen upgrades.
4. Hire lumberjacks (they sell surplus wood at the truck when the pile is full), waiters and cooks.
5. Meet the gate checklist (builds, guests served, rating, coins) to unlock the next venue. Use the **MAP**
   button to travel. Crews at venues you leave keep earning at 50%.

| # | Venue | Product | Cooker | Cost scale |
|---|---|---|---|---|
| 1 | Forest Camp | Grilled corn | Firepit | x1 |
| 2 | Roadside Shack | Burgers | Grill | x4 |
| 3 | Lakeside Diner | Fish & chips | Fryer | x14 |
| 4 | Mountain Lodge | Pizza | Oven | x45 |
| 5 | Autumn Smokehouse | Ribs | Smoker | x140 |
| 6 | Grand Timber Hotel | Steak | Grill | x420 |

Each chapter has its own theme (sky, sun, grass, foliage season, building colours, a lake for chapter 3).

## Layout

| Path | What it is |
|---|---|
| `data/game.json` | Base numbers: builds, upgrades, crew, menu, gate, trees. Tune here. |
| `data/chapters.json` | Chapter names, products, build names, themes and the growth multipliers |
| `scripts/core/game_state.gd` | Autoload `Game`: economy, chapter config scaling, per-venue state, empire income, prestige, save/load + migration, offline earnings, jobs |
| `scripts/main.gd` | Boot, threaded preloading, staged venue build behind the loading screen, travel, graphics quality + auto downgrade |
| `scripts/world/` | World build, player, crew/customers, trees, procedural art, character rig (two-hand chainsaw IK) |
| `scripts/ui/` | HUD, modals (shop, crew, gate, chapter complete, empire map, settings), loading screen, UI shapes |
| `shaders/` | Ground, foliage (+ see-through variant for trees covering the player), UI |
| `tests/` | Headless and rendered test scripts (below) |
| `legacy/` | The earlier grey-box logic prototype (ignored by Godot) |

## Tests

```sh
G=E:/Work/tools/godot/Godot_v4.7.2-stable_win64_console.exe
$G --headless --path . --script res://tests/flowtest.gd             # A-Z empire flow: gate, travel, save/load, prestige (20 checks)
$G --headless --path . --script res://tests/autoplay.gd -- 8 60 0   # bot plays chapter 0 at 8x and prints pacing
$G --headless --path . --script res://tests/lumbertest.gd           # lumberjacks sell surplus wood
$G --headless --path . --script res://tests/regrowtest.gd           # stumps wait until the player leaves
$G --headless --path . --script res://tests/crewzone.gd -- 2        # crew zone opens its menu in chapter 2
$G --path . --resolution 720x1280 --script res://tests/uishot2.gd -- <outdir>   # empire / gate / complete modals
```

Bot pacing (gate reached, game minutes at 8x): chapter 1 ~49, chapter 2 ~56, chapter 3 ~51. The bot buys every
upgrade before saving for the gate, so a focused player is faster.

## Build and run on a phone

```sh
$G --headless --path . --export-debug Android builds/AxeToEmpire-debug.apk
adb install -r builds/AxeToEmpire-debug.apk
adb shell am start -n com.bigosoft.axetoempire.proto/com.godot.game.GodotAppLauncher
adb logcat -s godot:I | grep PERFLOG      # debug builds log fps / frame timings every 5 s
```

Draw-call and skinning budget (on the test phone with a full camp: ~480 -> ~200 draw calls, ~17 -> ~24 fps):
- Characters use one baked, decimated skinned mesh per outfit variant (`assets/characters/pete/merged/`,
  made by `tests/bake_pete.gd`) instead of 8 skinned parts. The compatibility renderer skins every vertex.
- Resting stack items (logs, dishes, coins) are drawn by one MultiMesh per part per stack (`stack.gd`).
- Idle standing trees are drawn by one MultiMesh per pine variant; a tree gets its own mesh only while
  shaking, falling, regrowing or see-through (`world._batch_tree`).
- Debug builds: `adb shell run-as com.bigosoft.axetoempire.proto touch files/probe` makes the next launch cycle
  through ablations (no characters, no trees, ...) and log `PROBE <name> fps=` lines.

Mobile settings: 30 fps cap, 3D render scale per graphics level (Smooth 0.6 / Balanced 0.75 / Beautiful 0.9),
no MSAA, no realtime shadows or omni lights, vertex shading, 1K textures, arm64 only. If fps stays under 17 the
game drops one graphics level automatically (Settings > Graphics turns that off).
