extends SceneTree
## A-Z empire flow: gate -> unlock -> travel -> state isolation -> empire income -> save/load -> travel back -> prestige.
var fails := 0
func ok(c: bool, msg: String) -> void:
	print(("PASS " if c else "FAIL ") + msg)
	if not c: fails += 1
func _initialize() -> void:
	_run.call_deferred()
func _ready_scene() -> void:
	while current_scene == null or current_scene.get("hud") == null or current_scene.get_node_or_null("LoadingScreen") != null or current_scene.get("crossing"):
		await process_frame
func _run() -> void:
	var g = root.get_node("Game")
	g.saving_enabled = true
	g.offline_reward = 0
	g.coins = 0; g.served = 0; g.built = {}; g.pad_paid = {}; g.chapter_done = false
	g.venue = 0; g.unlocked = 1; g.venues = []; g.vserved = 0; g.prestige = 0; g.cfg = g.chapter_cfg(0)
	g.reno = {}; g.bigday = {}; g.seen = {}; g.task_i = 0; g.task_base = 0; g.golden_n = 0
	g.levels = {"tool": 0, "bag": 0, "boots": 0, "fire": 0, "menu": 0, "dining": 0, "sign": 0, "station": 0}
	g.settings.story = false
	change_scene_to_file("res://scenes/main.tscn")
	await _ready_scene()
	# --- chapter 1 completed state
	g.built = {"campfire": true, "tables_1": true, "shop": true, "crew_hut": true, "fire_2": true, "tables_2": true}
	g.crew = {"lumberjack": 2, "waiter": 1, "cook": 1}
	g.levels.fire = 2; g.levels.menu = 1
	g.vserved = 200; g.served = 200; g.rating_hist = [5.0, 5.0]
	g.coins = 5000
	ok(not g.gate_ready() and g.big_day_ready(), "gate waits for the Big Day once everything is built")
	ok(current_scene.world.start_big_day(), "Big Day starts")
	current_scene.world.bd_served = 999
	await create_timer(0.3).timeout
	ok(g.bigday.get("won", false) and not current_scene.world.bd_active, "Big Day won when the goal is served")
	ok(g.stars()[0], "first star for the Big Day")
	ok(g.gate_ready(), "gate ready with checklist done")
	g.open_next_venue()
	ok(g.coins == 5000, "gate keeps your savings (coins=%d)" % g.coins)
	ok(g.unlocked == 2, "chapter 2 unlocked")
	ok(g.chapter_done and g.built.has("gate"), "chapter 1 marked done")
	# --- travel to chapter 2
	current_scene.travel_to(1)
	for i in 5: await process_frame
	await _ready_scene()
	ok(g.venue == 1, "now at venue 2")
	ok(g.built.keys() == ["campfire"] and g.crew.lumberjack == 1 and g.woodpile >= 6, "chapter 2 head start: cooker + 1 lumberjack + firewood")
	ok(g.special_type() == "drive_thru" and g.build_def("special").cost == 1400, "chapter 2 has a drive-thru pad (cost x4)")
	ok("special" in g.build_def("gate").requires, "chapter 2 gate needs the drive-thru")
	ok(g.levels.fire == 0 and g.levels.menu == 0, "kitchen levels are per venue")
	ok(g.build_def("campfire").name == "Burger grill" and int(g.build_def("campfire").cost) == 96, "chapter 2 config themed + scaled (%s %s)" % [g.build_def("campfire").name, g.build_def("campfire").cost])
	ok(current_scene.world.theme == g.chapters[1].theme, "world uses chapter 2 theme")
	var r1: float = g.venue_rate(0)
	ok(r1 > 0.0, "chapter 1 crew earns in background (%.2f c/s)" % r1)
	var c0: int = g.coins
	var t0: int = g.till(0)
	await create_timer(4.0).timeout
	ok(g.till(0) > t0 and g.coins == c0, "chapter 1 cash piles up on its own counter, not in your pocket (%d -> %d)" % [t0, g.till(0)])
	ok(g.tills_waiting() == g.till(0), "waiting cash totals the other places")
	# --- save / load round trip
	g.coins = 777
	g.built = {"campfire": true}
	g.save_game()
	g.coins = 0; g.built = {}; g.venue = 0; g.venues = []; g.unlocked = 1
	g.load_game()
	g.cfg = g.chapter_cfg(g.venue)
	ok(g.venue == 1 and g.unlocked == 2, "save/load keeps venue + unlocks")
	ok(g.coins == 777 and g.built.has("campfire"), "save/load keeps venue 2 state")
	ok(g.venues[0].get("crew", {}).get("lumberjack", 0) == 2, "save/load keeps venue 1 crew")
	# --- travel back
	current_scene.travel_to(0)
	for i in 5: await process_frame
	await _ready_scene()
	ok(g.venue == 0 and g.built.has("tables_2") and g.crew.lumberjack == 2, "back at camp with its state")
	ok(g.levels.fire == 2 and g.levels.menu == 1, "camp kitchen levels restored")
	ok(g.venues[1].get("built", {}).has("campfire"), "venue 2 state stashed")
	# --- last chapter + prestige
	g.venue = 5; g.unlocked = 6; g.cfg = g.chapter_cfg(5); g.chapter_done = true
	ok(g.is_last_chapter(), "chapter 6 is last")
	g.start_new_empire()
	ok(g.prestige == 1 and g.venue == 0 and g.unlocked == 1 and g.coins == 0, "new empire resets with prestige 1")
	ok(absf(g.income_mult() - 1.5) < 0.01, "prestige income x1.5")
	g.coins = 0; g.venues = []; g.unlocked = 1; g.venue = 0; g.prestige = 0; g.built = {}; g.chapter_done = false
	g.save_game()
	print("FLOW RESULT fails=%d" % fails)
	quit()
