extends SceneTree
## Road-edge fixes, rendered: the two ends of the road (east of the Forest Camp, west of the last venue: barrier,
## "road ends" toast, the NEW EMPIRE sign beside the road), the Shack's DRIVE-THRU sign next to its road sign,
## the camp middle, and the draw calls at each spot.
##   $G --path . --resolution 540x1200 -s res://tests/qa/road_ends_shot.gd -- <outdir>
## Not headless (it renders). Prints FAILS=n for the toast checks.
var out := ""
var g
var fails := 0
var toasts: Array = []


func ok(c: bool, msg: String) -> void:
	print(("PASS " if c else "FAIL ") + msg)
	if not c:
		fails += 1


func _initialize() -> void:
	_run.call_deferred()


func _wait(n: int) -> void:
	for i in n:
		await process_frame


func _full(k: int) -> Dictionary:
	var b := {"campfire": true, "tables_1": true, "shop": true, "crew_hut": true, "fire_2": true, "tables_2": true}
	if String(g.chapters[k].get("special", {}).get("type", "")) != "":
		b["special"] = true
	return b


func _setup(k: int) -> void:
	g.venue = k; g.unlocked = k + 1; g.venues = []; g.cfg = g.chapter_cfg(k)
	g.reno = {}; g.bigday = {}; g.seen = {"task_init": true}; g.task_i = 0; g.task_base = 0; g.chapter_done = false
	g.built = _full(k)
	g.crew = {"lumberjack": 1, "waiter": 1, "cook": 1}
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


func _shot(name: String, x: float, z := 11.5) -> void:
	var w = current_scene.world
	w.player.global_position = Vector3(x, 0, z)
	w._cross_armed = false
	w.cam_look(w.cam_aim(w.player.global_position))
	await _wait(30)
	var d := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	root.get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("SHOT %s venue=%d x=%.1f draws=%d" % [name, g.venue, x, d])


func _push(side: int) -> void:
	var w = current_scene.world
	var we := -15.5
	var ee := 15.5
	toasts.clear()
	w.player.global_position = Vector3((we + 0.5) if side < 0 else (ee - 0.5), 0, 11.5)
	w._cross_armed = true
	w._edge_warn_ms = -100000
	w.player._vel = Vector3(3.0 * side, 0, 0)
	w._road_tick()
	await _wait(2)


func _run() -> void:
	out = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(out)
	g = root.get_node("Game")
	g.saving_enabled = false
	g.offline_reward = 0
	g.settings.story = false
	g.toast.connect(func(m): toasts.append(String(m)))
	# ---- Forest Camp: the camp middle and the east end of the road
	_setup(0)
	await _load()
	await _shot("camp_mid", 0.0, -1.0)
	await _shot("camp_cookers", 0.0, -3.5)
	await _shot("camp_east_end", 14.5)
	await _push(1)
	ok(toasts.has("The road ends here"), "pushing on the east end of the road says so (%s)" % [toasts])
	await _shot("camp_east_end_push", 15.0)
	current_scene.hud.open_modal("shop")
	await _wait(3)
	await _push(1)
	ok(toasts.is_empty(), "no toast while a modal is open (%s)" % [toasts])
	current_scene.hud.close_modal()
	# ---- Roadside Shack: DRIVE-THRU sign on the kiosk roof, road sign beside it
	_setup(1)
	await _load()
	await _shot("shack_cookers", 0.0, -3.5)       # parasols at the bottom corners (they dither out near the lens)
	await _shot("shack_kiosk", 10.5, 9.0)
	await _shot("shack_east_edge", 14.5)
	# ---- last venue: west end of the road with the NEW EMPIRE sign
	var last: int = g.chapters.size() - 1
	_setup(last)
	await _load()
	await _shot("last_west_end", -14.5)
	await _shot("last_gate_sign", -10.8, 10.2)
	await _shot("last_west_end", -14.5)       # (off the gate pad again)
	if current_scene.hud.modal_kind != "":
		current_scene.hud.close_modal()        # standing on the gate pad opened its modal
	await _wait(3)
	await _push(-1)
	ok(toasts.has("The road ends here"), "pushing on the west end of the last road says so (%s)" % [toasts])
	load("res://scripts/world/plot.gd").finish_jobs()
	print("FAILS=%d" % fails)
	quit()
