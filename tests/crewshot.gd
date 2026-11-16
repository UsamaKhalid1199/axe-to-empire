extends SceneTree
## Camp with a full crew + guests, for checking character outfits: -- <outdir>
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var out := OS.get_cmdline_user_args()[0]
	if OS.get_cmdline_user_args().has("nobatch"):
		load("res://scripts/world/stack.gd").batching = false
	var g = root.get_node("Game"); g.saving_enabled = false; g.offline_reward = 0
	g.built = {"campfire": true, "tables_1": true, "shop": true, "crew_hut": true, "fire_2": true, "tables_2": true}
	g.crew = {"lumberjack": 2, "waiter": 2, "cook": 1}; g.woodpile = 20
	change_scene_to_file("res://scenes/main.tscn")
	while current_scene == null or current_scene.get("hud") == null or current_scene.get_node_or_null("LoadingScreen") != null:
		await process_frame
	await create_timer(14.0).timeout
	var w = current_scene.world
	w.cam.global_position = w.player.global_position + Vector3(0, 6.5, 6.0)
	w.cam.look_at(w.player.global_position + Vector3(0, 0, 2.5))
	w.set_process(false)
	w.find_children("*", "DirectionalLight3D", true, false)[0].shadow_enabled = false
	await create_timer(0.3).timeout
	root.get_texture().get_image().save_png(out + "/crew.png")
	print("DRAWS ", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME), " pile=", g.woodpile, " rack=", g.rack)
	quit()
