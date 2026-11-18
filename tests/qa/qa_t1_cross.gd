extends SceneTree
## QA tester 1: money and carried items across walks along the road (real scene).
## Run: $G --headless --path . -s res://tests/qa/qa_t1_cross.gd
var fails := 0
var g


func ok(c: bool, msg: String) -> void:
	print(("PASS " if c else "FAIL ") + msg)
	if not c:
		fails += 1


func _initialize() -> void:
	_run.call_deferred()


func _wait(n: int) -> void:
	for i in n:
		await process_frame


func _secs(s: float) -> void:
	await create_timer(s).timeout


func _ready_scene() -> void:
	while current_scene == null or current_scene.get("hud") == null or current_scene.get_node_or_null("LoadingScreen") != null \
			or current_scene.get("crossing"):
		await process_frame


func _walk(dx: float, secs: float) -> bool:
	var v0: int = g.venue
	var t := 0.0
	while t < secs:
		var w = current_scene.world
		if w != null and is_instance_valid(w) and w.player != null and not current_scene.crossing:
			if g.venue != v0:
				break
			w.player.input_dir = Vector2(dx, 0)
		await physics_frame
		t += 1.0 / float(Engine.physics_ticks_per_second)
	await _ready_scene()
	await _wait(2)
	var w2 = current_scene.world
	if w2 and w2.player:
		w2.player.input_dir = Vector2.ZERO
	return g.venue != v0


func _place(x: float) -> void:
	var w = current_scene.world
	w.player.global_position = Vector3(x, 0, 11.5)
	w._cross_armed = true
	await _wait(3)


## Walk across: east (+1) means toward lower chapters.
func _cross(side: int) -> bool:
	var Plot = load("res://scripts/world/plot.gd")
	await _place(Plot.east(g.venue) - 2.7 if side > 0 else Plot.west(g.venue) + 2.7)
	return await _walk(float(side), 4.0)


func _full(k: int) -> Dictionary:
	var b := {"campfire": true, "tables_1": true, "shop": true, "crew_hut": true, "fire_2": true, "tables_2": true}
	if String(g.chapters[k].get("special", {}).get("type", "")) != "":
		b["special"] = true
	return b


func _run() -> void:
	g = root.get_node("Game")
	g.saving_enabled = false
	g.offline_reward = 0
	g.settings.story = false
	g.coins = 0; g.served = 0; g.pad_paid = {}; g.chapter_done = true; g.prestige = 0
	g.venue = 0; g.unlocked = 1; g.venues = []; g.vserved = 0; g.cfg = g.chapter_cfg(0)
	g.reno = {}; g.bigday = {"won": true}; g.seen = {"task_init": true}; g.task_i = 13; g.task_base = 0; g.golden_n = 0
	g.built = _full(0)
	g.crew = {"lumberjack": 2, "waiter": 1, "cook": 1}
	g.woodpile = 10; g.counter_coins = 0
	g.levels = {"tool": 3, "bag": 2, "boots": 1, "fire": 0, "menu": 0, "dining": 0, "sign": 0, "station": 0}
	g.unlocked = 3
	g.jobs_day = ""; g.refresh_jobs()
	g.travel(1)
	g.built = _full(1)
	g.crew = {"lumberjack": 1, "waiter": 1, "cook": 0}
	g.chapter_done = true; g.bigday = {"won": true}; g.task_i = 13
	g.coins = 50000
	change_scene_to_file("res://scenes/main.tscn")
	await _ready_scene()
	await _wait(3)
	var w = current_scene.world

	# ---------- state at chapter 1 before walking east
	g.woodpile = 9
	g.rack = 4
	g.counter_coins = 250
	g.sp["kiosk"] = 0
	w.pile.set_count(9)
	w.rack_stack.set_count(4)
	w.player.back.set_count(5)
	w.player.hands.set_count(3)
	g.levels.menu = 3
	g.reno = {"id": "menu", "end": g.now() + 9999, "to": 4}
	var coins0: int = g.coins
	var stats_logs: int = g.stats.logs
	var moved := await _cross(1)
	w = current_scene.world
	ok(moved and g.venue == 0, "walked east to chapter 0")
	ok(g.coins == coins0, "coins unchanged by the walk (%d -> %d)" % [coins0, g.coins])
	ok(w.player.back.count() == 5, "5 bag logs carried across (got %d)" % w.player.back.count())
	print("  dishes in hands before 3, after the walk %d (rack at ch1 stays %d)" % [w.player.hands.count(), int(g.venues[1].rack)])
	ok(w.player.hands.count() == 3 or int(g.venues[1].rack) == 7, "3 dishes in hands neither lost nor duplicated (hands %d, ch1 rack %d)" % [w.player.hands.count(), int(g.venues[1].rack)])
	var v1: Dictionary = g.venues[1]
	ok(int(v1.woodpile) == 9 and int(v1.rack) == 4, "ch1 woodpile/rack stashed (%d/%d)" % [int(v1.woodpile), int(v1.rack)])
	ok(int(v1.counter_coins) >= 250, "ch1 uncollected counter kept as its till (%d)" % int(v1.counter_coins))
	ok(not v1.reno.is_empty() and int(v1.menu) == 3, "ch1 renovation still running while away")
	ok(g.reno.is_empty(), "ch0 has no renovation of its own")
	ok(g.stats.logs == stats_logs, "walk doesn't count logs as chopped")

	# ---------- stand at ch0 a while: ch1's till grows, ch0's counter doesn't get bg cash
	var t1a: int = g.till(1)
	var ctr0: int = g.counter_coins
	await _secs(6.0)
	var r1: float = g.venue_rate(1) * g.VENUE_EFFICIENCY
	print("  ch1 till %d -> %d in 6 s (bg rate %.2f/s)" % [t1a, g.till(1), r1])
	ok(g.till(1) > t1a, "ch1 till grew while away")

	# ---------- walk back west at once: nothing duplicated
	await _secs(0.5)
	var coins1: int = g.coins
	var t1: int = g.till(1)
	moved = await _cross(-1)
	w = current_scene.world
	ok(moved and g.venue == 1, "walked back west to chapter 1")
	ok(g.coins == coins1, "coins unchanged on the way back (%d -> %d)" % [coins1, g.coins])
	ok(g.counter_coins >= t1 and g.counter_coins <= t1 + int(r1 * 2.0) + 2, "ch1 counter = its till on arrival (%d vs %d)" % [g.counter_coins, t1])
	ok(g.woodpile + g.rack <= 13 and g.woodpile == w.pile.count() and g.rack == w.rack_stack.count(), "ch1 woodpile/rack back, no extra (%d/%d, visuals %d/%d; fires burn logs meanwhile)" % [g.woodpile, g.rack, w.pile.count(), w.rack_stack.count()])
	ok(w.player.back.count() == 5, "still 5 logs on the back (%d)" % w.player.back.count())
	ok(not g.reno.is_empty() and g.levels.menu == 3, "renovation resumed at ch1")

	# ---------- collect the counter: wallet gains exactly the counter
	var ctr: int = g.counter_coins
	var c_before: int = g.coins
	var guard := 0
	while g.counter_coins > 0 and guard < 200:
		w.collect_cash(6)
		guard += 1
	ok(g.coins - c_before == ctr, "collecting pays exactly the counter %d (got %d)" % [ctr, g.coins - c_before])

	# ---------- renovation that finishes while away finishes on time and is kept on return
	g.reno = {"id": "menu", "end": g.now() + 2, "to": 4}
	moved = await _cross(1)
	await _secs(3.0)
	ok(int(g.venues[1].menu) == 4, "while away the renovation still finishes on time (%d)" % int(g.venues[1].menu))
	moved = await _cross(-1)
	await _secs(1.5)
	ok(g.levels.menu == 4 and g.reno.is_empty(), "renovation done on return: menu idx %d, reno %s" % [g.levels.menu, g.reno])

	# ---------- raft away at chapter 2 pays once even if you leave and come back
	moved = await _cross(-1)
	w = current_scene.world
	ok(moved and g.venue == 2, "walked west into chapter 2 (first visit)")
	g.built = _full(2)
	g.state_changed.emit()
	await _wait(3)
	g.sp["away"] = 2.0
	g.sp["paid"] = 777
	g.sp["raft"] = 0
	var cr: int = g.coins
	print("  raft set: sp=%s special built=%s" % [g.sp, current_scene.world.get("specials") != null])
	moved = await _cross(1)        # back to ch1 straight away
	print("  after walk: venue %d coins+%d" % [g.venue, g.coins - cr])
	await _secs(4.0)
	ok(g.coins == cr, "raft doesn't pay while you're away (%d)" % (g.coins - cr))
	moved = await _cross(-1)
	await _secs(4.0)
	var gain: int = g.coins - cr
	print("  raft gain after return: %d (counter collected? no)" % gain)
	ok(gain >= 777 and gain < 777 * 2, "raft paid once after return (+%d)" % gain)

	# ---------- golden tree up while crossing: cleared, no error, no reward
	w = current_scene.world
	w.golden_t = 0.0
	await _wait(3)
	var cg: int = g.coins
	var had_golden: bool = w.golden != null
	moved = await _cross(1)
	ok(had_golden and g.coins == cg, "walked away from a golden tree: no reward, no error (golden was up: %s)" % had_golden)

	# ---------- MAP travel with logs on the back
	w = current_scene.world
	w.player.back.set_count(6)
	current_scene.travel_to(0)
	await _wait(5)
	await _ready_scene()
	await _wait(2)
	w = current_scene.world
	print("  MAP travel: 6 logs on the back -> %d after arrival" % w.player.back.count())
	ok(w.player.back.count() == 6, "MAP travel keeps bag logs like walking does (got %d)" % w.player.back.count())

	var Plot = load("res://scripts/world/plot.gd")
	Plot.finish_jobs()
	print("FAILS=%d" % fails)
	quit()
