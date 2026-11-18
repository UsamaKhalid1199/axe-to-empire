extends SceneTree
## QA round 2, tester 1: normal play (no Big Day) with a modal left open vs closed. While a modal is open guests'
## patience is frozen, but spawning and the crew keep going, so every crew-served guest stays "happy":
## 5★ and +20% pay, and nobody walks out. Compares 240 s of AFK with Settings open vs 240 s of AFK without.
## Run: $G --headless --path . -s res://tests/qa/qa_r2_t1_modal_afk.gd -- [chapter] [station idx] [waiters]
var fails := 0
var g


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
	var lv := int(args[1]) if args.size() > 1 else 2
	var waiters := int(args[2]) if args.size() > 2 else 1
	g = root.get_node("Game")
	g.saving_enabled = false
	g.settings.story = false
	g.prestige = 0
	g.venue = k
	g.unlocked = k + 1
	g.venues = []
	g.cfg = g.chapter_cfg(k)
	g._cc_cache.clear()
	g.built = _full(k)
	g.pad_paid = {}
	g.levels = {"tool": 0, "bag": 0, "boots": 0, "fire": lv, "menu": lv, "dining": lv, "sign": lv, "station": lv}
	g.crew = {"lumberjack": 3, "waiter": waiters, "cook": 0}
	g.reno = {}; g.bigday = {"won": true}; g.seen = {}; g.task_i = 13
	g.woodpile = 30; g.rack = 10; g.counter_coins = 0; g.offline_reward = 0; g.rating_hist = []; g.chapter_done = false
	g.sp = {}
	change_scene_to_file("res://scenes/main.tscn")
	while current_scene == null or current_scene.get("hud") == null or current_scene.get_node_or_null("LoadingScreen") != null:
		await process_frame
	for i in 10:
		await process_frame
	var w = current_scene.world
	var hud = current_scene.hud
	Engine.time_scale = 4.0
	Engine.physics_ticks_per_second = 240
	Engine.max_physics_steps_per_frame = 32
	var res := {}
	# warm-up so the line is busy, then the two phases (order alternates the advantage of warm-up)
	await create_timer(60.0).timeout
	for p in ["closed", "modal"]:
		w.player.global_position = Vector3(0, 0, -28)
		if p.begins_with("modal"):
			hud.open_modal("settings")
		var wo0: int = g.walkouts
		var srv0: int = g.vserved
		var earned0: int = g.counter_coins + int(g.stats.earned)
		g.rating_hist = []
		var t := 0.0
		while t < 240.0:
			await create_timer(4.0).timeout
			t += 4.0
			w.player.global_position = Vector3(0, 0, -28)
			if p.begins_with("modal") and hud.modal_kind == "":
				hud.open_modal("settings")
		var happy := 0
		for x in g.rating_hist:
			if float(x) >= 5.0:
				happy += 1
		res[p] = {"served": g.vserved - srv0, "walkouts": g.walkouts - wo0, "rating": g.rating(), "happy_share": float(happy) / maxf(1.0, g.rating_hist.size()),
			"cash": g.counter_coins + int(g.stats.earned) - earned0}
		print("%-8s %s" % [p, res[p]])
		if hud.modal_kind != "":
			hud.close_modal()
	var m: Dictionary = res.modal
	var c: Dictionary = res.closed
	ok(m.walkouts <= c.walkouts, "modal open: walkouts %d vs %d with the world visible" % [m.walkouts, c.walkouts])
	ok(m.rating <= c.rating + 0.05 and m.happy_share <= c.happy_share + 0.05,
		"AFK in a menu should not rate better than AFK in the world (modal %.2f, %.0f%% happy vs closed %.2f, %.0f%% happy)" % [m.rating, m.happy_share * 100.0, c.rating, c.happy_share * 100.0])
	Engine.time_scale = 1.0
	print("RESULT qa_r2_t1_modal_afk: %d fail(s)" % fails)
	quit()
