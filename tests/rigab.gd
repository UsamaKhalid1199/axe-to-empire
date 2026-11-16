extends SceneTree
## A/B: original 8-mesh rig (top) vs merged rig (bottom), every outfit. -- <outdir>
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var out := OS.get_cmdline_user_args()[0]
	var scene := Node3D.new()
	root.add_child(scene)
	var env := WorldEnvironment.new(); env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR; env.environment.background_color = Color(0.5, 0.6, 0.7)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; env.environment.ambient_light_color = Color(0.6, 0.6, 0.6)
	scene.add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-40, 20, 0); scene.add_child(sun)
	var kinds := ["player", "lumberjack", "waiter", "cook", "customer"]
	var RigScript = load("res://scripts/world/character_rig.gd")
	for row in 2:
		if row == 0: continue
		RigScript.use_merged = row == 1
		for i in kinds.size():
			var r = RigScript.new()
			scene.add_child(r)
			r.position = Vector3((i - 2) * 1.1, (1 - row) * 2.0, 0)
			if kinds[i] != "player":
				r.outfit(kinds[i], 3)
	var cam := Camera3D.new(); cam.position = Vector3(0, 0.9, 3.6); scene.add_child(cam); cam.look_at(Vector3(0, 0.9, 0))
	for i in 20: await process_frame
	root.get_texture().get_image().save_png(out + "/rigab.png")
	quit()
