extends SceneTree
## QA round 2, tester 1: frozen patience during a Big Day. A modal (Settings, UPGRADE, ME, jobs...) can be opened
## during a Big Day; guests' patience then holds, but the Big Day timer, spawning and the crew keep going.
## Phase A: the player parks in the forest with Settings open for the whole Big Day (crew only).
## Phase B: same set-up, no modal. Compares walkouts / result.
## Run: $G --headless --path . -s res://tests/qa/qa_r2_t1_bigday_modal.gd -- [chapter] [station idx] [waiters] [cooks]
var fails := 0
var _a_walkouts := -1
var g
var result := []


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


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var k := int(args[0]) if args.size() > 0 else 0
	var lv := int(args[1]) if args.size() > 1 else 9
	var waiters := int(args[2]) if args.size() > 2 else 2
	var cooks := int(args[3]) if args.size() > 3 else 2
	print("chapter %d, station idx %d, waiters %d, cooks %d" % [k, lv, waiters, cooks])
	g = root.get_node("Game")
	g.saving_enabled = false
	g.settings.story = false
	g.prestige = 0
	g.venue = k
	g.unlocked = k + 1
	g.venues = []
	g.cfg = g.chapter_cfg(k)
	g._cc_cache.clear()
	g.coins = 0
	g.built = _full(k)
	g.pad_paid = {}
	g.levels = {"tool": 2, "bag": 2, "boots": 2, "fire": lv, "menu": lv, "dining": lv, "sign": lv, "station": lv}
	g.crew = {"lumberjack": 3, "waiter": waiters, "cook": cooks}
	g.reno = {}; g.bigday = {}; g.seen = {}; g.task_i = 12; g.task_base = 0; g.golden_n = 0; g.walkouts = 0
	g.woodpile = 30; g.rack = 10; g.counter_coins = 0; g.offline_reward = 0; g.rating_hist = []; g.chapter_done = false
	g.vserved = 0; g.sp = {"fuel": 10}
	change_scene_to_file("res://scenes/main.tscn")
	while current_scene == null or current_scene.get("hud") == null or current_scene.get_node_or_null("LoadingScreen") != null:
		await process_frame
	for i in 10:
		await process_frame
	var main = current_scene
	var w = main.world
	var hud = main.hud
	w.big_day_finished.connect(func(won, served, goal): result.append([won, served, goal, w.bd_walkouts]))
	Engine.time_scale = 4.0
	Engine.physics_ticks_per_second = 240
	Engine.max_physics_steps_per_frame = 32

	# --- micro check: a guest about to walk out holds while a modal is open
	await create_timer(20.0).timeout
	w.player.global_position = Vector3(0, 0, -28)
	var cust = null
	for c in w.queue:
		if is_instance_valid(c) and c.state == "queue" and c.slot > 1:
			cust = c
	if cust:
		hud.open_modal("settings")
		var wo0: int = g.walkouts
		cust.waited = cust.patience - 0.2
		await create_timer(15.0).timeout
		ok(g.walkouts == wo0, "guest at 99%% patience doesn't walk out during 15 s under a modal (state %s, walkouts +%d)" % [cust.state if is_instance_valid(cust) else "freed", g.walkouts - wo0])
		hud.close_modal()
	else:
		print("INFO no guest in line at t=20s for the micro check")

	# --- phase A: Big Day with Settings open the whole time, player away from the counter
	for p in ["A_modal", "B_open"]:
		g.bigday = {}
		w._bd_cool = 0.0
		g.woodpile = 30
		g.rack = 10
		g.sp["fuel"] = 10
		w.player.global_position = Vector3(0, 0, -28)
		result.clear()
		var started: bool = w.start_big_day()
		ok(started, "%s: Big Day started" % p)
		if p == "A_modal":
			hud.open_modal("settings")
		var left0: float = w.bd_left
		var t := 0.0
		var max_mid_q := 0
		while w.bd_active and t < 200.0:
			await create_timer(2.0).timeout
			t += 2.0
			w.player.global_position = Vector3(0, 0, -28)
			if p == "A_modal" and hud.modal_kind == "":
				hud.open_modal("settings")
			max_mid_q = maxi(max_mid_q, w.queue.size())
			if int(t) % 30 == 0:
				print("  %s t=%3.0f left=%5.1f served=%d/%d walkouts=%d q=%d modal='%s' rack=%d pile=%d" % [p, t, w.bd_left, w.bd_served, w.bd_goal(), w.bd_walkouts, w.queue.size(), hud.modal_kind, g.rack, g.woodpile])
		print("%s: result %s after %.0f s, walkouts %d, max queue %d, Big Day timer started at %.0f" % [p, result, t, w.bd_walkouts, max_mid_q, left0])
		if p == "A_modal":
			ok(result.size() > 0, "A: Big Day timer ran out / finished while a modal was open the whole time (it does not pause)")
			_a_walkouts = w.bd_walkouts      # the exploit gave 0 here; now patience runs during a Big Day
			print("INFO A_modal: won=%s clean=%s served %d" % [result[0][0] if result.size() else "?", g.bigday.get("clean", false), w.bd_served if result.is_empty() else result[0][1]])
		else:
			print("INFO B_open: won=%s walkouts=%d served %d" % [result[0][0] if result.size() else "?", w.bd_walkouts, w.bd_served if result.is_empty() else result[0][1]])
			if _a_walkouts >= 0:
				ok(_a_walkouts >= w.bd_walkouts, "an open menu does not reduce Big Day walkouts (menu %d, no menu %d)" % [_a_walkouts, w.bd_walkouts])
		if hud.modal_kind != "":
			hud.close_modal()
		await create_timer(1.0).timeout
	Engine.time_scale = 1.0
	print("RESULT qa_r2_t1_bigday_modal: %d fail(s)" % fails)
	quit()
