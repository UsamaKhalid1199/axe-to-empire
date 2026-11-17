# Axe to Empire

3D arcade-idle game for Android (portrait). Chop trees, stack logs, cook, serve guests, hire a crew,
then unlock the next venue and grow a six-venue Timber Empire. Prestige ("New Empire") restarts with +50% income.

Godot 4.7.2, GDScript, `gl_compatibility` renderer. Tuned for low-end phones (PowerVR GE8320, ~3 GB RAM).

## The game loop

1. Chop trees (stand next to one; the axe/chainsaw comes out only near trees). Stumps regrow after 45 s,
   and only once you've walked away, so you keep moving through the forest. The harvester (top tool) is ridden
   only in the forest: you climb in past the tree line and step out at the camp edge (it stays parked there),
   so building, cooking and serving are always on foot.
2. Stack logs by the cooker, carry food to the counter, serve the queue, collect cash (green banknotes, `$`).
3. Build pads (tables, tool shed, crew cabin, second cooker), buy tool/bag/boots at the shop.
4. Hire lumberjacks, waiters and cooks. The crew is slower and carries less than you, and lumberjacks never sell
   wood: when the pile is full they rest. Serving the line yourself pays a +SERVICE bonus.
5. Follow the **job card** (top left): a 13-step task chain per chapter with a cash reward per step.
6. Upgrade the five stations (kitchen, menu, dining, sign, signature station) from Lv 1 to 25 in **UPGRADE**.
   Shown levels 5/10/15/20/25 are timed renovations (finish early with cash).
7. When every pad is built, start the chapter's **Big Day** at the gate: serve the goal within 180 s without
   too many walkouts. Winning opens the gate and earns the first star; more stars (served 2x the gate goal at
   rating 4.5+, a clean Big Day with all stations Lv 15+) raise income.
8. Use **MAP** to travel. Background venues earn at a reduced rate; away earnings are capped at 1-4 h depending
   on unlocked venues and need a crew. The game really pauses (tree + audio) when the phone locks.

Guests have moods (happy / impatient / angry faces): happy guests pay +20%; past their patience they walk out,
annoying the two guests behind them. When the line is full, passers-by walk on ("TOO BUSY!") and the sale is lost.
Groups arrive in bursts, and a golden tree sometimes appears for a big cash reward.

The story (`data/story.json`, design in `docs/DESIGN.md`): Old Mags and her ally in each chapter against the
Grayline chain, told through story cards with portraits. The **ME** button opens the character screen (gear and a
19-piece wardrobe from `data/outfits.json`), and Settings has sound, vibration, story cards, FPS, graphics, how to
play, stats, story replay, reset and credits.

| # | Venue | Product | Cooker | Signature station (new mechanic) | Cost scale |
|---|---|---|---|---|---|
| 1 | Forest Camp | Grilled corn | Firepit | (none: learn the basic loop) | x1 |
| 2 | Roadside Shack | Burgers | Grill | **Drive-thru window**: cars queue on the road, hand dishes through the window, they pay 1.5x by card | x4 |
| 3 | Lakeside Diner | Fish & chips | Fryer | **Timber raft**: load logs, it sails to the sawmill and pays 3x the truck price | x14 |
| 4 | Mountain Lodge | Pizza | Oven | **Lodge fireplace**: burns a log every 6 s; while lit, guests pay +50% and wait longer | x45 |
| 5 | Autumn Smokehouse | Ribs | Smoker | **Fair bell**: ring it for a 30 s rush (3x guests, 2x prices), then a 75 s cooldown | x140 |
| 6 | Grand Timber Hotel | Steak | Grill | **Room-service van**: load dishes, it delivers them for 2x; ~1 in 6 guests is a VIP (bigger order, 3x pay, less patient) | x420 |

The signature station is an extra build pad (base cost 350 x chapter scale) and the gate needs it. Crews use it
too (waiters fill the drive-thru/van, lumberjacks feed the fireplace and send surplus wood on the raft), and a
built station raises that venue's crew income (+25-40%), including in the background. Each chapter also has its
own theme (sky, sun, grass, foliage season, building colours, a lake for chapter 3) and props (tent, gas pump,
rowboat, snowman and skis, hay and pumpkins, hotel planters) plus a road sign with the venue name.

Layouts differ per chapter too (`chapters.json`): `forest` shapes the choppable forest (a meadow at the Shack,
a forest thinning toward the lakeshore, sparse mountain woods with two meadows, straight orchard rows at the
Smokehouse, a long open avenue at the Hotel), `dining` picks the furniture (picnic tables, parasols at table ends,
lodge lanterns, round clothed hotel tables with stools) and `ground_patches` adds worn ground (Shack car park,
Hotel plaza, station yards).

Arriving at a new venue for the first time, the crew you bring sets up the cooker, one lumberjack comes along and
there are 12 logs on the pile. Tools, bag and boots carry over between venues; buildings, kitchen and crew are per venue.

## Layout

| Path | What it is |
|---|---|
| `data/game.json` | Base numbers: builds, upgrades, crew, menu, gate, trees. Tune here. |
| `data/chapters.json` | Chapter names, products, build names, themes, crowd tuning, Big Day goals and the growth multipliers |
| `data/story.json` | Characters, story beats and the per-chapter task chain |
| `data/outfits.json` | Wardrobe items (shirts, hats, pants), prices and star gates |
| `docs/DESIGN.md` | Game design: story, loop, moods, crew vs player, stations, stars, roadmap |
| `scripts/core/game_state.gd` | Autoload `Game`: economy, chapter config scaling, per-venue state, empire income, prestige, save/load + migration, offline earnings, jobs |
| `scripts/main.gd` | Boot, threaded preloading, staged venue build behind the loading screen, travel, graphics quality + auto downgrade |
| `scripts/world/` | World build, player, crew/customers, trees, procedural art, character rig (two-hand chainsaw IK), `specials.gd` (each chapter's signature station) |
| `scripts/ui/` | HUD, modals (shop, crew, gate, chapter complete, empire map, settings), loading screen, UI shapes |
| `shaders/` | Ground, foliage (+ see-through variant for trees covering the player), UI |
| `tests/` | Headless and rendered test scripts (below) |
| `legacy/` | The earlier grey-box logic prototype (ignored by Godot) |

## Tests

```sh
G=E:/Work/tools/godot/Godot_v4.7.2-stable_win64_console.exe
$G --headless --path . --script res://tests/flowtest.gd             # A-Z empire flow: gate, travel, save/load, prestige (20 checks)
$G --headless --path . --script res://tests/autoplay.gd -- 8 60 0   # bot plays chapter 0 at 8x and prints pacing
$G --headless --path . --script res://tests/lumbertest.gd           # lumberjacks stack logs and rest (never sell)
$G --headless --path . --script res://tests/wardrobetest.gd         # wardrobe buy/equip/persist
$G --headless --path . --script res://tests/regrowtest.gd           # stumps wait until the player leaves
$G --headless --path . --script res://tests/harvtest.gd             # ride the harvester in the forest, walk in camp
$G --headless --path . --script res://tests/specialtest.gd -- 1     # signature station of chapter 1..5 (player + crew)
$G --headless --path . --script res://tests/crewzone.gd -- 2        # crew zone opens its menu in chapter 2
$G --path . --resolution 720x1280 --script res://tests/uishot2.gd -- <outdir>   # empire / gate / complete modals
$G --path . --resolution 540x960 --script res://tests/chaptershot.gd -- <out.png> <chapter> sp   # frame a chapter's station
```

Bot pacing (chapter finished including the Big Day): chapter 1 ~32 min. The bot also buys station upgrades
along the way, so a focused player is faster.

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
