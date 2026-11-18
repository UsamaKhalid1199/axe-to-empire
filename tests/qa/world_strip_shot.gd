extends SceneTree
## Renders the plot boundaries of the one-road world and measures what the neighbour plots cost in draw calls.
##   $G --path . --resolution 720x1600 -s res://tests/qa/world_strip_shot.gd -- <outdir>
## Draw calls: RenderingServer TOTAL_DRAW_CALLS_IN_FRAME with the neighbours shown vs hidden, same camera.
var out := ""
var g


func _initialize() -> void:
	_run.call_deferred()


func _wait(n: int) -> void:
	for i in n:
		await process_frame


func _ready_scene() -> void:
	while current_scene == null or current_scene.get("hud") == null or current_scene.get_node_or_null("LoadingScreen") != null \
			or current_scene.get("crossing"):
		await process_frame


func _full(k: int) -> Dictionary:
	var b := {"campfire": true, "tables_1": true, "shop": true, "crew_hut": true, "fire_2": true, "tables_2": true}
	if String(g.chapters[k].get("special", {}).get("type", "")) != "":
		b["special"] = true
	return b


func _draws() -> int:
	await _wait(4)
	return RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)


func _shot(name: String, x: float, z := 11.5) -> void:
	var w = current_scene.world
	w.player.global_position = Vector3(x, 0, z)
	w._cross_armed = false             # keep the player here (no walking across while we look)
	w._cam_target = w.player.global_position + Vector3(w._hud_side_shift(), 0, -0.8)
	w._place_cam(1.0)
	current_scene.hud.close_modal()
	await _wait(40)
	var on := await _draws()
	for s in w.nb_plots:
		w.nb_plots[s].visible = false
	var off := await _draws()
	for s in w.nb_plots:
		w.nb_plots[s].visible = true
	await _wait(4)
	root.get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("SHOT %s venue=%d x=%.1f draws=%d without_neighbours=%d neighbours=%d" % [name, g.venue, x, on, off, on - off])


func _go(k: int) -> void:
	current_scene.travel_to(k)
	await _wait(5)
	await _ready_scene()
	await _wait(10)


func _run() -> void:
	out = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(out)
	g = root.get_node("Game")
	g.saving_enabled = false
	g.offline_reward = 0
	g.settings.story = false
	g.coins = 5000000; g.prestige = 0; g.pad_paid = {}
	g.venue = 0; g.unlocked = 2; g.venues = []; g.cfg = g.chapter_cfg(0)
	g.reno = {}; g.bigday = {}; g.seen = {"task_init": true}; g.task_i = 0
	g.levels = {"tool": 3, "bag": 2, "boots": 1, "fire": 0, "menu": 0, "dining": 0, "sign": 0, "station": 0}
	g.built = _full(0)
	g.crew = {"lumberjack": 2, "waiter": 1, "cook": 1}
	g.woodpile = 14; g.counter_coins = 0
	g.travel(1)
	g.built = _full(1)
	g.crew = {"lumberjack": 1, "waiter": 1, "cook": 0}
	g.woodpile = 10
	g.venues[0]["counter_coins"] = 1830
	change_scene_to_file("res://scenes/main.tscn")
	await _ready_scene()
	await _wait(20)
	current_scene.hud._story_q.clear()
	await _shot("shack_mid", 0.0, -1.0)
	await _shot("shack_east_edge_to_camp", 13.0)
	await _shot("shack_west_edge_for_sale", -13.0)
	# open the lake, visit it, come back: the west neighbour is the lake plot's shore road
	g.unlocked = 4
	await _go(2)
	g.built = _full(2)
	g.crew = {"lumberjack": 1, "waiter": 1, "cook": 1}
	g.state_changed.emit()
	await _go(1)
	await _shot("shack_west_edge_lake", -13.0)
	await _go(2)
	await _shot("lake_corridor_end", 41.0)
	await _shot("lake_west_edge_lodge_open", -13.0)
	await _go(0)
	await _shot("camp_west_edge_shack", -13.0)
	await _go(3)
	await _shot("lodge_east_edge_lake", 13.0)
	load("res://scripts/world/plot.gd").finish_jobs()
	quit()
