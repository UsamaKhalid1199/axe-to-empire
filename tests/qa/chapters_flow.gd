extends SceneTree
## QA2: chapter flow (gate -> complete -> travel), every chapter arrival, travel back, save/load, prestige.
var fails := 0
var g
func ok(c: bool, msg: String) -> void:
	print(("PASS " if c else "FAIL ") + msg)
	if not c: fails += 1
func _initialize() -> void:
	_run.call_deferred()
func _ready_scene() -> void:
	while current_scene == null or current_scene.get("hud") == null or current_scene.get_node_or_null("LoadingScreen") != null:
		await process_frame
func _wait(n: int) -> void:
	for i in n: await process_frame

func _complete_venue(coins: int) -> void:
	g.built = {"campfire": true, "tables_1": true, "shop": true, "crew_hut": true, "fire_2": true, "tables_2": true}
	if g.special_type() != "":
		g.built["special"] = true
	g.crew = {"lumberjack": 2, "waiter": 1, "cook": 1}
	g.vserved = int(g.cfg.gate.served) + 5
	g.rating_hist = [5.0, 5.0]
	g.coins = maxi(g.coins, coins)
	g.bigday = {"won": true, "tries": 1}

func N(x) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(x)), "", true)

func _vs(k: int) -> String:
	var d: Dictionary = g.venues[k].duplicate(true)
	return N(d)

func _travel(k: int) -> void:
	current_scene.travel_to(k)
	await _wait(5)
	await _ready_scene()
	await _wait(3)

func _run() -> void:
	g = root.get_node("Game")
	g.saving_enabled = true
	g.offline_reward = 0
	g.coins = 0; g.served = 0; g.built = {}; g.pad_paid = {}; g.chapter_done = false
	g.venue = 0; g.unlocked = 1; g.venues = []; g.vserved = 0; g.prestige = 0; g.cfg = g.chapter_cfg(0)
	g.reno = {}; g.bigday = {}; g.seen = {}; g.task_i = 0; g.task_base = 0; g.golden_n = 0
	g.crew = {"lumberjack": 0, "waiter": 0, "cook": 0}
	g.levels = {"tool": 3, "bag": 2, "boots": 1, "fire": 0, "menu": 0, "dining": 0, "sign": 0, "station": 0}
	g.settings.story = false
	g.jobs_day = ""; g.refresh_jobs()
	change_scene_to_file("res://scenes/main.tscn")
	await _ready_scene()
	var w = current_scene.world
	var hud = current_scene.hud
	# ---------- chapter 1: Big Day won WITH walkouts, then gate
	_complete_venue(9000)
	g.bigday = {}
	g.levels.fire = 6; g.levels.menu = 4
	g.woodpile = 17; g.rack = 3; g.counter_coins = 123; g.golden_n = 2; g.task_i = 7; g.walkouts = 4
	g.reno = {"id": "dining", "end": g.now() + 30, "to": 9}
	ok(w.start_big_day(), "ch1 big day starts")
	w.bd_walkouts = 1
	w.bd_served = 999
	await create_timer(0.3).timeout
	ok(g.bigday.get("won", false) and not g.bigday.get("clean", false), "won with walkouts")
	ok(g.big_day_replayable(), "replay for star 3 offered by game state")
	hud.close_modal()
	await _wait(2)
	hud.open_modal("gate")
	await _wait(2)
	ok(hud.modal_kind == "gate", "gate modal open")
	g.open_next_venue()
	hud.open_modal("complete")
	await _wait(3)
	ok(w.pads.has("gate"), "gate pad stays after unlocking (replay + new empire) (pads=%s)" % [w.pads.keys()])
	print("INFO after gate: big_day_replayable=%s gate_pad=%s -> star-3 replay reachable only via gate modal" % [g.big_day_replayable(), w.pads.has("gate")])
	var obj: Dictionary = w._compute_objective()
	ok(String(obj.text).begins_with("Open the MAP"), "objective says open the map (%s)" % obj.text)
	var snap0 := N(g._snapshot())
	# ---------- save mid "complete" modal + reload
	g.save_game()
	g.load_game()
	ok(N(g._snapshot()) == snap0, "save/load with complete modal open: venue 0 state identical")
	# ---------- travel to every chapter 2..6
	for k in range(1, 6):
		var coins_before: int = g.coins
		await _travel(k)
		w = current_scene.world; hud = current_scene.hud
		ok(g.venue == k, "arrived at venue %d" % (k + 1))
		ok(g.built.keys() == ["campfire"] and g.crew.lumberjack == 1 and g.crew.waiter == 0 and g.woodpile >= 6, "ch%d head start built=%s crew=%s wood=%d" % [k + 1, g.built.keys(), g.crew, g.woodpile])
		ok(absi(g.coins - coins_before) < coins_before / 50 + 50, "ch%d cash carried (%d -> %d)" % [k + 1, coins_before, g.coins])
		ok(g.task_i == 0 and String(g.current_task().get("t", "")) == "serve", "ch%d tasks start at 1 (%s)" % [k + 1, g.task_text(g.current_task())])
		ok(g.levels.fire == 0 and g.levels.menu == 0 and g.levels.dining == 0 and g.reno.is_empty(), "ch%d station levels fresh, no reno" % [k + 1])
		ok(g.levels.tool == 3 and g.levels.bag == 2, "ch%d player tools kept" % [k + 1])
		ok(not g.bigday.get("won", false) and g.star_count() == 0 and not g.chapter_done, "ch%d bigday/stars fresh" % [k + 1])
		ok(w.specials != null and w.specials.type == g.special_type(), "ch%d special = %s" % [k + 1, g.special_type()])
		ok(g.venue_rate(k - 1) > 0.0 and g.empire_rate() > 0.0, "ch%d background income from previous venue %.2f c/s" % [k + 1, g.empire_rate()])
		obj = w._compute_objective()
		print("INFO ch%d objective: %s  task card: %s" % [k + 1, obj.text, hud.task_title.text])
		# save + reload during first arrival
		var sk := N(g._snapshot())
		g.save_game(); g.load_game()
		ok(N(g._snapshot()) == sk, "ch%d save/load on first arrival identical" % [k + 1])
		ok(g.head_start_note == false, "head start toast not repeated")
		# finish this venue
		_complete_venue(int(g.cfg.gate.coins) + 10)
		g.levels.menu = k + 2
		g.counter_coins = 10 * k; g.woodpile = 5 + k; g.golden_n = k; g.task_i = k + 2
		g.reno = {"id": "sign", "end": g.now() + 3600, "to": 4}
		ok(g.gate_ready(), "ch%d gate ready" % [k + 1])
		g.open_next_venue()
		if k < 5:
			ok(g.unlocked == k + 2, "ch%d unlocks %d" % [k + 1, k + 2])
	# ---------- in last chapter, gate opened
	ok(g.is_last_chapter() and g.chapter_done, "last chapter done")
	var stays: int = 0
	# simulate STAY HERE then try to find a way to start a new empire
	await _wait(3)
	w = current_scene.world
	ok(w.pads.has("gate"), "last chapter: gate pad still available after STAY HERE (pads=%s)" % [w.pads.keys()])
	print("INFO last-chapter objective after gate: " + String(w._compute_objective().text))
	# ---------- travel back and forth, check stash round trip
	var stash := {}
	g._stash()
	for k in 6:
		stash[k] = _vs(k)
	for path in [[0], [3], [5], [1], [0], [4], [2], [5]]:
		var k: int = path[0]
		var before := _vs(k)
		var from: int = g.venue
		if g.travel(k):
			var now_s := N(g._snapshot())
			ok(now_s == before, "travel %d->%d restores exact state" % [from + 1, k + 1])
			if now_s != before:
				print("  BEFORE " + before.replace("\n", " "))
				print("  AFTER  " + now_s.replace("\n", " "))
			current_scene.reload_venue()
			await _wait(5); await _ready_scene(); await _wait(3)
			var st := N(g._snapshot())
			g.save_game(); g.load_game()
			ok(N(g._snapshot()) == st, "venue %d save/load identical" % [k + 1])
	# renovation that finished while away
	g.venues[0]["reno"] = {"id": "dining", "end": g.now() - 5, "to": 9}
	await _travel(0)
	await create_timer(1.2).timeout
	ok(g.reno.is_empty() and g.levels.dining == 9, "reno finished while away applied on return (dining=%d reno=%s)" % [g.levels.dining, g.reno])
	ok(g.bigday.get("won", false) and g.chapter_done and g.built.has("gate"), "ch1 bigday/chapter_done kept")
	ok(g.golden_n == 2 and g.task_i == 7, "ch1 golden/task kept (%d,%d)" % [g.golden_n, g.task_i])
	# ---------- mid-big-day save/load (replay at venue 1)
	w = current_scene.world
	var tries: int = int(g.bigday.get("tries", 0))
	ok(w.start_big_day(), "replay big day at ch1 via world (no UI path once gate pad is gone)")
	g.save_game(); g.load_game()
	ok(int(g.bigday.get("tries", 0)) == tries and g.bigday.get("won", false), "mid-big-day save keeps bigday won")
	await _travel(5)
	print("STARS total=%d per venue=%s" % [g.total_stars(), range(6).map(func(k): return g.star_count(k))])
	# ---------- prestige
	w = current_scene.world
	var prof = g.profile.duplicate(true)
	var stats_trees = g.stats.trees
	var job_rewards = g.jobs.map(func(j): return j.reward)
	g.start_new_empire()
	current_scene.reload_venue()
	await _wait(5); await _ready_scene(); await _wait(3)
	ok(g.prestige == 1 and g.venue == 0 and g.unlocked == 1 and g.coins == 0, "new empire reset")
	ok(g.built.is_empty() and g.crew.lumberjack == 0 and g.task_i == 0 and g.reno.is_empty() and g.woodpile == 0 and g.counter_coins == 0, "venue 0 fresh")
	ok(g.profile == prof, "wardrobe/profile persists")
	print("INFO after prestige: tools=%s stars=%d stats.trees=%s served=%d jobs rewards before=%s after=%s" % [[g.levels.tool, g.levels.bag, g.levels.boots], g.total_stars(), g.stats.trees, g.served, job_rewards, g.jobs.map(func(j): return j.reward)])
	ok(current_scene.world.pads.has("campfire"), "campfire pad in new empire")
	g.save_game(); g.load_game()
	ok(g.prestige == 1 and g.venue == 0 and g.unlocked == 1, "prestige survives reload")
	print("CHAPTERS RESULT fails=%d" % fails)
	quit()
