extends SceneTree
## Empire screens: -- <outdir>
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var out := OS.get_cmdline_user_args()[0]
	var g = root.get_node("Game")
	g.saving_enabled = false; g.offline_reward = 0
	g.venue = 1; g.unlocked = 3; g.cfg = g.chapter_cfg(1)
	g.venues = [{"built": {"campfire": true, "tables_1": true, "fire_2": true}, "crew": {"lumberjack": 2, "waiter": 1, "cook": 1}, "fire": 2, "menu": 1}, {}, {}]
	g.built = {"campfire": true, "tables_1": true, "shop": true, "crew_hut": true, "fire_2": true, "tables_2": true}
	g.vserved = 150; g.coins = 9000; g.rating_hist = [5.0]
	change_scene_to_file("res://scenes/main.tscn")
	while current_scene == null or current_scene.get("hud") == null or current_scene.get_node_or_null("LoadingScreen") != null:
		await process_frame
	var hud = current_scene.hud
	for m in ["empire", "gate", "complete"]:
		hud.open_modal(m)
		await create_timer(0.4).timeout
		root.get_texture().get_image().save_png("%s/%s.png" % [out, m])
		hud.close_modal()
		await create_timer(0.2).timeout
	quit()
