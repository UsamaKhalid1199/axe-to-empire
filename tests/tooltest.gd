extends SceneTree
## Tool must be hidden in camp and out next to trees.
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var g = root.get_node("Game")
	g.saving_enabled = false; g.offline_reward = 0
	g.levels["tool"] = 2
	change_scene_to_file("res://scenes/main.tscn")
	while current_scene == null or current_scene.get("hud") == null or current_scene.get_node_or_null("LoadingScreen") != null:
		await process_frame
	var w = current_scene.world
	var p = w.player
	p.equip_tool()
	p.global_position = w.COUNTER_POS + Vector3(0, 0, 1.5)
	await create_timer(1.5).timeout
	var camp: bool = p.tool_out
	var tr = w._nearest_tree_pos()
	p.global_position = tr + Vector3(1.0, 0, 0)
	await create_timer(0.6).timeout
	print("TOOL camp_out=", camp, " forest_out=", p.tool_out, " scale=", p.tool_root.scale.x)
	quit()
