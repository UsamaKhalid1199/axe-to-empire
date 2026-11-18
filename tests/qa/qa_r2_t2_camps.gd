extends SceneTree
## QA round 2, tester 2: every chapter's camp in normal play, camera left to settle by itself (no snapping),
## at the spots a player actually stands: spawn, wood pile, counter, shop, crew cabin, forest, camp south edge,
## road middle. Rendered (not headless).
##   $G --path . --resolution 540x1200 -s res://tests/qa/qa_r2_t2_camps.gd -- <outdir> [WxH]
## Also prints where the road sits on screen (fraction of height) per spot.
var out := ""
var g


func _initialize() -> void:
	_run.call_deferred()


func _wait(k: int) -> void:
	for i in k:
		await process_frame


func _full(k: int) -> Dictionary:
	var b := {"campfire": true, "tables_1": true, "shop": true, "crew_hut": true, "fire_2": true, "tables_2": true}
	if String(g.chapters[k].get("special", {}).get("type", "")) != "":
		b["special"] = true
	return b


func _setup(k: int) -> void:
	g.venue = k; g.unlocked = k + 1; g.venues = []; g.cfg = g.chapter_cfg(k)
	g.reno = {}; g.bigday = {}; g.seen = {"task_init": true}; g.task_i = 2; g.task_base = 0; g.chapter_done = false
	g.built = _full(k)
	g.crew = {"lumberjack": 2, "waiter": 1, "cook": 1}
	g.vserved = 40; g.coins = 250000; g.rating_hist = [4.6]; g.woodpile = 12; g.counter_coins = 0
	while g.venues.size() < g.unlocked:
		g.venues.append({})
	for j in k:
		g.venues[j] = {"crew": {"lumberjack": 1, "waiter": 1, "cook": 1}, "built": _full(j), "counter_coins": 500}


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


## Put the player at p and let the normal camera follow (_cam_tick) settle for `t` seconds.
func _spot(k: int, name: String, p: Vector3, t := 1.6) -> void:
	var w = current_scene.world
	w._cross_armed = false
	w.player.global_position = p
	await create_timer(t).timeout
	if current_scene.hud.modal_kind != "":
		current_scene.hud.close_modal()
		await create_timer(0.4).timeout
	var road_y: float = w.cam.unproject_position(Vector3(p.x, 0, 11.5)).y / float(root.get_visible_rect().size.y)
	var pl: Vector2 = w.cam.unproject_position(p + Vector3(0, 1, 0)) / root.get_visible_rect().size
	print("CAMP ch%d %-12s road at %.2f of height, player at (%.2f, %.2f)" % [k, name, road_y, pl.x, pl.y])
	root.get_texture().get_image().save_png("%s/ch%d_%s.png" % [out, k, name])


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
	print("CAMPS window ", DisplayServer.window_get_size(), " ui ", root.get_visible_rect().size)
	g = root.get_node("Game")
	g.saving_enabled = false
	g.offline_reward = 0
	g.settings.story = false
	for k in g.chapters.size():
		_setup(k)
		await _load()
		g._in_background = true
		await _spot(k, "spawn", Vector3(0, 0, -3.6), 2.0)
		await _spot(k, "pile", Vector3(-3.4, 0, -2.4))
		await _spot(k, "counter", Vector3(1.2, 0, 4.4))
		await _spot(k, "shop", Vector3(5.0, 0, -1.5))
		await _spot(k, "forest", Vector3(-2.0, 0, -11.0))
		await _spot(k, "camp_south", Vector3(2.0, 0, 8.6))
		await _spot(k, "road_mid", Vector3(2.0, 0, 11.5))
	print("CAMPS DONE")
	quit()
