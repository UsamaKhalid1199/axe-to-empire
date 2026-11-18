extends SceneTree
## QA round 3, tester 1: scene-level logic. Big Day start/win/lose/cooldown, leaving during a Big Day,
## collecting a till in the world, arrival cap numbers. Headless. Run with APPDATA pointed at a scratch dir:
##   APPDATA=<scratch> $G --headless --path . -s res://tests/qa/qa_r3_t1_scene.gd
var fails := 0
var g
var main


func ok(c: bool, msg: String) -> void:
	print(("PASS " if c else "FAIL ") + msg)
	if not c:
		fails += 1


func _initialize() -> void:
	_run.call_deferred()


func _full(k: int) -> Dictionary:
	var b := {"campfire": true, "tables_1": true, "shop": true, "crew_hut": true, "fire_2": true, "tables_2": true}
	if String(g.chapters[k].get("special", {}).get("type", "")) != "":
		b["special"] = true
	return b


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _settle() -> void:
	var guard := 0
	while (main.crossing or main.get_node_or_null("LoadingScreen") != null or main.world == null) and guard < 3000:
		await process_frame
		guard += 1
	await _frames(5)


func _run() -> void:
	g = root.get_node("Game")
	if not OS.get_user_data_dir().contains("scratchpad"):
		print("ABORT: run with APPDATA pointed at a scratch dir")
		quit(1)
		return
	g.saving_enabled = false
	g.settings.story = false
	g.prestige = 0
	g.pro = {"tool": 0, "bag": 0, "boots": 0}
	g.levels = {"tool": 2, "bag": 2, "boots": 2, "fire": 0, "menu": 0, "dining": 0, "sign": 0, "station": 0}
	# place 1 finished with crew, place 2 (active) fully built, gate checklist done except the Big Day
	g.venues = [{"built": _full(0).merged({"gate": true}), "crew": {"lumberjack": 3, "waiter": 2, "cook": 2}, "fire": 9, "menu": 9,
		"bigday": {"won": true}, "chapter_done": true, "task_i": 13, "rating_hist": [4.8], "vserved": 600, "counter_coins": 0}, {}]
	g.unlocked = 2
	g.venue = 1
	g._unstash(1)
	g.cfg = g.chapter_cfg(1)
	g.built = _full(1)
	g.crew = {"lumberjack": 2, "waiter": 1, "cook": 1}
	g.vserved = 500
	g.rating_hist = [4.8]
	g.coins = int(g.cfg.gate.coins) + 1000
	g.woodpile = 30
	g._cc_cache.clear(); g._rates.clear(); g._rates_t = 0.0
	g.refresh_stars()
	change_scene_to_file("res://scenes/main.tscn")
	while current_scene == null or current_scene.get("hud") == null or current_scene.get_node_or_null("LoadingScreen") != null:
		await process_frame
	main = current_scene
	await _frames(10)
	var w = main.world
	# ---------------- Big Day: lose, cooldown
	ok(g.big_day_ready(), "Big Day ready at the Shack")
	ok(w.start_big_day(), "Big Day starts")
	ok(not w.start_big_day(), "second start while running refused")
	ok(not w.can_cross(1) and not w.can_cross(-1), "can't walk off during the Big Day")
	w.bd_left = 0.0
	await _frames(3)
	ok(not w.bd_active and not g.bigday.get("won", false) and int(g.bigday.get("tries", 0)) == 1, "time out -> lost, tries 1")
	ok(w._bd_cool > 40.0 and not w.start_big_day(), "45 s cooldown after a loss (%.0f)" % w._bd_cool)
	# cooldown after walking next door and back
	main.travel_to(0)
	await _settle()
	main.travel_to(1)
	await _settle()
	w = main.world
	print("INFO cooldown after walking to the Camp and back: %.0f s" % w._bd_cool)
	ok(w._bd_cool > 0.0, "the 45 s Big Day cooldown survives a trip next door and back")
	w._bd_cool = 0.0
	# walkouts limit
	ok(w.start_big_day(), "Big Day restarts")
	w.bd_walkouts = w.bd_max_walkouts() + 1
	await _frames(3)
	ok(not w.bd_active and int(g.bigday.tries) == 2 and not g.bigday.get("won", false), "too many walkouts -> lost, tries 2")
	w._bd_cool = 0.0
	# win
	ok(w.start_big_day(), "Big Day starts again")
	w.bd_served = w.bd_goal()
	w.bd_walkouts = 1
	await _frames(3)
	ok(not w.bd_active and g.bigday.get("won", false) and not g.bigday.get("clean", false) and int(g.bigday.tries) == 3, "goal served -> won (not clean), tries 3")
	ok(g.gate_ready(), "gate ready after the win")
	ok(g.big_day_replayable() and not g.big_day_ready(), "replayable for star 3, not 'ready' any more")
	var c0: int = g.coins
	g.open_next_venue()
	ok(g.unlocked == 3 and g.coins == c0, "gate opened, no fee")
	# ---------------- leaving during a Big Day replay through the gate modal's GO TO button (travel_to)
	ok(w.start_big_day(), "replay for star 3 starts")
	var tries: int = int(g.bigday.tries)
	main.hud.open_modal("gate")
	await _frames(2)
	var go_btn_found := false
	for b in main.hud.modal.find_children("*", "", true, false):
		if b.get("text") is String and String(b.get("text")).begins_with("GO TO"):
			go_btn_found = true
	for l in main.hud.modal.find_children("*", "Label", true, false):
		if String(l.text).begins_with("GO TO"):
			go_btn_found = true
	print("INFO gate modal during a running Big Day shows GO TO next door: %s" % go_btn_found)
	main.hud.close_modal()
	main.travel_to(2)
	await _settle()
	print("INFO travel_to during a running Big Day replay: venue now %d, bigday tries %d (was %d)" % [g.venue, int(g.venues[1].bigday.get("tries", 0)), tries])
	ok(g.venue == 1, "MAP/gate travel refused while a Big Day runs (else the Big Day is silently dropped)")
	if g.venue != 1:
		main.travel_to(1)
		await _settle()
	w = main.world
	# ---------------- till collection in the world
	g.venues[0]["counter_coins"] = 0
	g._rates_t = 0.0
	var acc_t := 0.0
	Engine.time_scale = 4.0
	while acc_t < 30.0:
		await process_frame
		acc_t += get_root().get_process_delta_time() if false else 1.0 / 60.0
	Engine.time_scale = 1.0
	var till0: int = g.till(0)
	ok(till0 > 0, "Camp till grew while at the Shack: %d" % till0)
	main.travel_to(0)
	await _settle()
	w = main.world
	var on_counter: int = g.counter_coins
	ok(on_counter >= till0, "arriving at the Camp: its till is on the counter (%d >= %d)" % [on_counter, till0])
	ok(w.coin_stack.count() > 0, "the pile is visible (%d bills)" % w.coin_stack.count())
	var c1: int = g.coins
	var guard := 0
	while g.counter_coins > 0 and guard < 200:
		w.collect_cash(8)
		guard += 1
	ok(g.coins == c1 + on_counter and g.counter_coins == 0, "collected exactly %d in %d ticks" % [on_counter, guard])
	ok(g.till(1) >= 0, "Shack is now a background place (till %d)" % g.till(1))
	# ---------------- arrival cap: what spawn_interval gives vs what the kitchen can serve, per chapter (static)
	print("--- arrival cap (mid-chapter: both fires, kitchen Lv 5, menu Lv 5, tables, 1 cook)")
	for k in 6:
		var cc: Dictionary = g.chapter_cfg(k)
		var c: Dictionary = cc.customers
		var fire_lv := 4
		var demand := (1.0 + 4 * float(c.per_table_bonus) + 0.2 + fire_lv * 0.14 + 4 * 0.10 + 0.12) * 1.0
		var interval := float(c.interval) / demand * 0.85
		var cook: float = g.kitchen_cook(cc, fire_lv) / 1.3
		var per_guest := (float(c.order_min) + float(c.order_max)) * 0.5 + float(c.get("order_bonus", 0))
		var dishes_s := 2.0 / cook
		var capped := per_guest / dishes_s / 1.25
		print("INFO ch%d %s: demand interval %.2fs, kitchen cap interval %.2fs -> spawn %.2fs; guests/min %.1f vs servable %.1f" % [k + 1, g.chapters[k].name, interval, capped, maxf(interval, capped), 60.0 / maxf(interval, capped), 60.0 * dishes_s / per_guest])
	print("RESULT qa_r3_t1_scene: %d fail(s)" % fails)
	quit()
