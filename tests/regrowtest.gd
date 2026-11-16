extends SceneTree
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var g = root.get_node("Game"); g.saving_enabled = false; g.offline_reward = 0
	change_scene_to_file("res://scenes/main.tscn")
	while current_scene == null or current_scene.get("hud") == null or current_scene.get_node_or_null("LoadingScreen") != null:
		await process_frame
	var w = current_scene.world
	var t = w.trees[0]
	t.regrow_time = 1.0
	while t.alive:
		t.hit(99, w.player.global_position)
	w.player.global_position = t.global_position + Vector3(2, 0, 0)
	w.player.set_physics_process(false)
	await create_timer(3.0).timeout
	print("REGROW near-player alive=", t.alive, " (want false)")
	w.player.global_position = t.global_position + Vector3(12, 0, 0)
	await create_timer(3.5).timeout
	print("REGROW away alive=", t.alive, " (want true)")
	quit()
