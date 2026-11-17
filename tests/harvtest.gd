extends SceneTree
## Harvester: ride it in the forest, walk on foot in camp (serve, build, carry dishes), logs move with you.
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var g = root.get_node("Game")
	g.saving_enabled = false; g.offline_reward = 0
	g.levels["tool"] = 3
	change_scene_to_file("res://scenes/main.tscn")
	while current_scene == null or current_scene.get("hud") == null or current_scene.get_node_or_null("LoadingScreen") != null:
		await process_frame
	var w = current_scene.world
	var p = w.player
	p.equip_tool()
	var fails := 0
	await create_timer(0.3).timeout
	if p.vehicle != null: print("FAIL riding at spawn"); fails += 1
	if not is_instance_valid(p.harvester): print("FAIL no harvester"); fails += 1
	# walk into the forest
	var tr = w._nearest_tree_pos()
	p.global_position = tr + Vector3(1.4, 0, 0)
	await create_timer(1.5).timeout
	if p.vehicle == null: print("FAIL not riding in forest"); fails += 1
	var logs: int = p.back.count()
	if logs == 0: print("FAIL harvester cut nothing"); fails += 1
	if p.back.get_parent() == p.rig: print("FAIL logs not on bed"); fails += 1
	# back to camp
	p.global_position = w.COUNTER_POS + Vector3(0, 0, 1.5)
	await create_timer(0.5).timeout
	if p.vehicle != null: print("FAIL still riding in camp"); fails += 1
	if p.back.get_parent() != p.rig: print("FAIL logs not on back"); fails += 1
	if p.back.count() < logs: print("FAIL lost logs ", p.back.count(), "/", logs); fails += 1
	var hz: float = p.harvester.global_position.z
	if hz > -5.3: print("FAIL parked in camp z=", hz); fails += 1
	if p.rig.position.length() > 0.01: print("FAIL rig offset ", p.rig.position); fails += 1
	# camp chores on foot: nothing is cut while walking past
	p.global_position = Vector3(0, 0, -3.9)
	await create_timer(0.5).timeout
	if p.vehicle != null or p.chopping: print("FAIL chopping/riding at camp edge"); fails += 1
	# back into the forest again
	p.global_position = tr + Vector3(-1.4, 0, -0.5)
	await create_timer(0.6).timeout
	if p.vehicle == null: print("FAIL did not remount"); fails += 1
	# downgrade (prestige reset) removes the machine
	g.levels["tool"] = 0
	p.equip_tool()
	await create_timer(0.3).timeout
	if p.vehicle != null or is_instance_valid(p.harvester): print("FAIL harvester left after downgrade"); fails += 1
	print("HARV fails=", fails, " logs=", logs, " parked_z=", hz)
	quit()
