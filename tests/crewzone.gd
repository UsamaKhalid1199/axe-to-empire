extends SceneTree
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var k := int(OS.get_cmdline_user_args()[0])
	var g = root.get_node("Game"); g.saving_enabled = false; g.offline_reward = 0
	g.venue = k; g.unlocked = k + 1; g.venues = []; g.cfg = g.chapter_cfg(k)
	g.built = {"campfire": true, "tables_1": true, "shop": true, "crew_hut": true}
	g.crew = {"lumberjack": 0, "waiter": 0, "cook": 0}; g.coins = 999999
	change_scene_to_file("res://scenes/main.tscn")
	while current_scene == null or current_scene.get("hud") == null or current_scene.get_node_or_null("LoadingScreen") != null:
		await process_frame
	var w = current_scene.world
	for z in w.zones:
		if z.global_position.distance_to(w.PADS.crew_hut) < 4.0:
			print("zone near crew_hut: kind=", z.get("kind"), " at ", z.global_position)
	w.player.global_position = w.PADS.crew_hut
	await create_timer(2.5).timeout
	print("CH", k, " modal=", current_scene.hud.modal_kind, " player=", w.player.global_position)
	quit()
