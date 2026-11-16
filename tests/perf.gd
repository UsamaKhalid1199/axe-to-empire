extends SceneTree
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var g = root.get_node("Game"); g.saving_enabled = false; g.offline_reward = 0
	if OS.get_cmdline_user_args().has("mobile"):
		root.mesh_lod_threshold = 8.0
	change_scene_to_file("res://scenes/main.tscn")
	while current_scene == null or current_scene.get("hud") == null or current_scene.get_node_or_null("LoadingScreen") != null:
		await process_frame
	for i in 60: await process_frame
	print("PERF draws=", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME), " prims=", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME), " objs=", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME))
	var counts := {}
	var stack := [current_scene]
	while stack.size() > 0:
		var n = stack.pop_back()
		for c in n.get_children(): stack.append(c)
		if n is GeometryInstance3D and n.is_visible_in_tree():
			var k: String = n.get_class() + ":" + String(n.get_parent().name).left(18)
			if n is MeshInstance3D and n.mesh: k = n.get_class() + ":" + (n.mesh.resource_path.get_file() if n.mesh.resource_path != "" else String(n.name).left(14))
			counts[k] = counts.get(k, 0) + 1
	var arr := []
	for k in counts: arr.append([counts[k], k])
	arr.sort_custom(func(a, b): return a[0] > b[0])
	for i in mini(25, arr.size()): print("OBJ ", arr[i][0], " ", arr[i][1])
	var pete = load("res://assets/characters/pete/pete_idle_skin.fbx").instantiate()
	var tris := 0
	for c in pete.get_node("Skeleton3D").get_children():
		if c is MeshInstance3D:
			for si in c.mesh.get_surface_count():
				tris += c.mesh.surface_get_array_index_len(si) / 3
	print("PETE tris=", tris)
	print("PINE tris=", Art.pine_mesh(0).surface_get_array_index_len(1) / 3 if Art.pine_mesh(0).surface_get_format(1) & Mesh.ARRAY_FORMAT_INDEX else Art.pine_mesh(0).surface_get_array_len(1) / 3)
	quit()
