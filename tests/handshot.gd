extends SceneTree
## Close-up of the player holding the current tool: -- <outdir> <tool_level>
func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0]
	var g = root.get_node("Game")
	g.saving_enabled = false
	g.offline_reward = 0
	g.levels["tool"] = int(args[1]) if args.size() > 1 else 2
	change_scene_to_file("res://scenes/main.tscn")
	while current_scene == null or current_scene.get("hud") == null or current_scene.get_node_or_null("LoadingScreen") != null:
		await process_frame
	var w = current_scene.world
	var p = w.player
	p.equip_tool()
	current_scene.hud.visible = false
	w.set_process(false)
	p.global_position = w.SPAWN
	for i in 30: await process_frame
	var shots := [["idle", Vector2.ZERO], ["run", Vector2(0.0, 1.0)]]
	for s in shots:
		p.input_dir = s[1]
		for k in 3:
			for i in 9: await process_frame
			p.rig.rotation.y = 0.55
			var c: Camera3D = w.cam
			var target: Vector3 = p.global_position + Vector3(0, 1.05, 0)
			c.global_position = target + Vector3(1.1, 0.35, 1.9)
			c.look_at(target, Vector3.UP)
			c.fov = 40
			await process_frame
			root.get_texture().get_image().save_png("%s/%s_%d.png" % [out, s[0], k])
		p.global_position = w.SPAWN
	quit()
