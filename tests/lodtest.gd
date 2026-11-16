extends SceneTree
## Primitive budget breakdown at the mobile LOD threshold.
func _initialize() -> void:
	_run.call_deferred()
func _p() -> int:
	return RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
func _settle() -> void:
	for i in 4: await process_frame
func _run() -> void:
	var g = root.get_node("Game"); g.saving_enabled = false; g.offline_reward = 0
	g.built = {"campfire": true, "tables_1": true, "shop": true, "crew_hut": true, "fire_2": true, "tables_2": true}
	g.crew = {"lumberjack": 3, "waiter": 2, "cook": 2}
	change_scene_to_file("res://scenes/main.tscn")
	while current_scene == null or current_scene.get("hud") == null or current_scene.get_node_or_null("LoadingScreen") != null:
		await process_frame
	await create_timer(5.0).timeout
	root.mesh_lod_threshold = 8.0
	var w = current_scene.world
	w.find_children("*", "DirectionalLight3D", true, false)[0].shadow_enabled = false
	await _settle(); var base := _p(); print("BASE prims=", base)
	var skels: Array = w.find_children("*", "Skeleton3D", true, false)
	print("characters=", skels.size())
	for s in skels: s.get_parent().visible = false
	await _settle(); print("  chars cost=", base - _p())
	for s in skels: s.get_parent().visible = true
	var sun: DirectionalLight3D = w.find_children("*", "DirectionalLight3D", true, false)[0]
	var hudn = current_scene.hud
	hudn.visible = false
	await _settle(); print("  hud cost=", base - _p())
	hudn.visible = true
	var other := 0
	for n in w.get_children():
		if n is MeshInstance3D: other += 1
	print("  direct MeshInstance3D children of world=", other)
	var mm: Array = w.find_children("*", "MultiMeshInstance3D", true, false)
	for m in mm: m.visible = false
	await _settle(); print("  multimesh cost=", base - _p(), " (", mm.size(), " mmi)")
	for m in mm: m.visible = true
	var trees: Array = []
	for c in w.get_children():
		if c.get_script() and String(c.get_script().resource_path).ends_with("chop_tree.gd"): trees.append(c)
	for t in trees: t.visible = false
	await _settle(); print("  chop trees cost=", base - _p(), " (", trees.size(), ")")
	quit()
