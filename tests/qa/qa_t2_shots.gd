extends SceneTree
## QA tester 2: modal states uiqa.gd does not reach, road edges of every chapter, and the walk-across fade.
##   $G --path . --resolution 540x1200 -s res://tests/qa/qa_t2_shots.gd -- <outdir> [WxH] [part]
## part: all (default) | modals | edges | fade. Not headless (it renders).
var out := ""
var n := 0
var g


func _initialize() -> void:
	_run.call_deferred()


func _wait(k: int) -> void:
	for i in k:
		await process_frame


func _shot(name: String, wait := 0.45) -> void:
	await create_timer(wait).timeout
	n += 1
	root.get_texture().get_image().save_png("%s/%02d_%s.png" % [out, n, name])
	print("SHOT ", name)


func _full(k: int) -> Dictionary:
	var b := {"campfire": true, "tables_1": true, "shop": true, "crew_hut": true, "fire_2": true, "tables_2": true}
	if String(g.chapters[k].get("special", {}).get("type", "")) != "":
		b["special"] = true
	return b


## Stand in chapter k, owning k+1 places (west of k is FOR SALE unless own_next), earlier ones built with crews.
func _setup(k: int, own_next := false) -> void:
	g.venue = k; g.unlocked = k + (2 if own_next else 1); g.venues = []; g.cfg = g.chapter_cfg(k)
	g.reno = {}; g.bigday = {}; g.seen = {"task_init": true}; g.task_i = 0; g.task_base = 0; g.chapter_done = false
	g.built = _full(k)
	g.crew = {"lumberjack": 1, "waiter": 1, "cook": 1}
	g.vserved = 40; g.coins = 250000; g.rating_hist = [4.6]; g.woodpile = 12; g.counter_coins = 0
	while g.venues.size() < g.unlocked:
		g.venues.append({})
	for j in k:
		g.venues[j] = {"crew": {"lumberjack": 2, "waiter": 2, "cook": 1}, "built": _full(j), "counter_coins": 0}
	for j in k:
		g.venues[j]["counter_coins"] = int(g.till_cap(j) * (0.35 + 0.2 * j))


func _load() -> void:
	change_scene_to_file("res://scenes/main.tscn")
	await _wait(2)
	while current_scene == null or current_scene.get("hud") == null or current_scene.get_node_or_null("LoadingScreen") != null \
			or current_scene.get("crossing"):
		await process_frame
	await _wait(20)
	current_scene.hud._story_q.clear()
	if current_scene.hud.modal_kind != "":
		current_scene.hud.close_modal()
	g._in_background = true
	g.tills_changed.emit()


func _stand(x: float, z := 11.5) -> void:
	var w = current_scene.world
	w.player.global_position = Vector3(x, 0, z)
	w._cross_armed = false
	w._cam_target = w.player.global_position + Vector3(w._hud_side_shift(), 0, -0.8)
	w._place_cam(1.0)


func _modals() -> void:
	# ---- Lakeside Diner (k=2), four places owned, gear maxed with Pro levels
	_setup(2)
	g.unlocked = 4
	while g.venues.size() < 4:
		g.venues.append({})
	g.levels.tool = g.cfg.tools.size() - 1
	g.levels.bag = g.cfg.bag.size() - 1
	g.levels.boots = g.cfg.boots.size() - 1
	g.pro = {"tool": 3, "bag": 10, "boots": 0}
	g.crew = {"lumberjack": 3, "waiter": 2, "cook": 2}
	g.vserved = 9999
	await _load()
	var hud = current_scene.hud
	await _shot("lake_hud_tills")
	for m in ["shop", "crew", "character"]:
		hud.open_modal(m)
		await _shot("lake_" + m)
		hud.close_modal()
	# map: top and bottom, with three places waiting
	g.venues[3] = {"crew": {"lumberjack": 1}, "built": {"campfire": true}, "counter_coins": 0}
	g.tills_changed.emit()
	hud.open_modal("empire")
	await _shot("lake_map_top")
	var sc: Array = hud.modal.find_children("*", "ScrollContainer", true, false)
	if not sc.is_empty():
		sc[0].scroll_vertical = 100000
	await _shot("lake_map_bottom")
	hud.close_modal()
	# gate: everything done but the Big Day / Big Day won (replay) / chapter done
	g.coins = 99999999; g.vserved = 9999
	hud.open_modal("gate")
	await _shot("lake_gate_bd_ready")
	g.bigday = {"won": true}
	hud._rebuild_modal_now()
	await _shot("lake_gate_ready_replay")
	g.bigday = {"won": true, "clean": true}
	hud._rebuild_modal_now()
	await _shot("lake_gate_ready_clean")
	g.chapter_done = true
	hud._rebuild_modal_now()
	await _shot("lake_gate_chapter_done")
	hud.close_modal()
	g.chapter_done = false; g.bigday = {}
	# Big Day banner + chip hidden; toast while walking
	current_scene.world.start_big_day()
	await _shot("lake_bigday_running")
	current_scene.world.bd_active = false
	await _wait(5)
	hud._toast_q.clear(); hud._toast_t = 0.0
	hud.show_toast("Lakeside Diner is for sale: open the gate to buy it")
	await _shot("lake_toast_edge", 0.3)
	# FPS label on
	g.settings["show_fps"] = true
	await _shot("lake_fps")
	g.settings["show_fps"] = false


func _edges() -> void:
	for k in g.chapters.size():
		_setup(k)
		await _load()
		var we := -15.5
		var ee: float = 43.5 if g.chapters[k].get("theme", {}).get("water", false) else 15.5
		if k + 1 < g.chapters.size():
			_stand(we + 1.0)
			await create_timer(0.6).timeout
			var opened: String = current_scene.hud.modal_kind
			print("EDGE ch%d standing at the fence opens modal '%s'" % [k, opened])
			if opened != "":
				await _shot("edge_ch%d_west_fence_prompt" % k, 0.1)
				current_scene.hud.close_modal()
			await _shot("edge_ch%d_west_forsale" % k, 0.8)
			# walk into the closed way: the toast
			var w = current_scene.world
			w._cross_armed = true
			w.player._vel = Vector3(-3, 0, 0)
			_stand(we + 0.5)
			w._cross_armed = true
			await _wait(3)
			w._road_tick()
			if current_scene.hud.modal_kind != "":
				current_scene.hud.close_modal()
			await _shot("edge_ch%d_west_push" % k, 0.5)
		if k > 0:
			_stand(ee - 1.0)
			await _shot("edge_ch%d_east_owned" % k, 0.8)


func _fade() -> void:
	_setup(1, true)
	g.venues[2] = {"crew": {"lumberjack": 1, "waiter": 1, "cook": 1}, "built": _full(2), "counter_coins": 3000}
	await _load()
	_stand(-14.2)
	await _shot("fade_before", 0.6)
	var w = current_scene.world
	w._cross_armed = true
	w._cross(-1)
	var t0 := Time.get_ticks_msec()
	var i := 0
	while i < 40 and Time.get_ticks_msec() - t0 < 4000:
		await _wait(1)
		if i % 3 == 0:
			n += 1
			root.get_texture().get_image().save_png("%s/%02d_fade_%03dms.png" % [out, n, Time.get_ticks_msec() - t0])
		i += 1
	while current_scene.get("crossing"):
		await process_frame
	await _shot("fade_after", 0.3)
	print("FADE venue now %d, last_cross_ms %.0f" % [g.venue, current_scene.last_cross_ms])


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	if args.size() > 1 and args[1].contains("x"):
		var wh: PackedStringArray = args[1].split("x")
		root.borderless = true
		root.position = Vector2i(0, 0)
		root.size = Vector2i(int(wh[0]), int(wh[1]))
		await _wait(5)
	print("QA_T2 window ", DisplayServer.window_get_size(), " ui ", root.get_visible_rect().size)
	var part: String = args[2] if args.size() > 2 else "all"
	g = root.get_node("Game")
	g.saving_enabled = false
	g.offline_reward = 0
	g.settings.story = false
	if part in ["all", "modals"]:
		await _modals()
	if part in ["all", "edges"]:
		await _edges()
	if part in ["all", "fade"]:
		await _fade()
	load("res://scripts/world/plot.gd").finish_jobs()
	quit()
