extends SceneTree
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	root.get_node("Game").saving_enabled = false
	root.get_node("Game").offline_reward = 0
	change_scene_to_file("res://scenes/main.tscn")
	while current_scene == null or current_scene.get("hud") == null or current_scene.get_node_or_null("LoadingScreen") != null:
		await process_frame
	for i in 20: await process_frame
	var p = current_scene.world.player
	var start: Vector3 = p.global_position
	var t := InputEventScreenTouch.new(); t.index = 0; t.pressed = true; t.position = Vector2(360, 1000)
	Input.parse_input_event(t)
	for i in 3: await process_frame
	var d := InputEventScreenDrag.new(); d.index = 0; d.position = Vector2(460, 1000); d.relative = Vector2(100, 0)
	Input.parse_input_event(d)
	for i in 40: await physics_frame
	print("JOY moved: ", p.global_position - start, " input=", p.input_dir)
	t = InputEventScreenTouch.new(); t.index = 0; t.pressed = false; t.position = Vector2(460, 1000)
	Input.parse_input_event(t)
	for i in 5: await process_frame
	print("JOY released input=", p.input_dir)
	quit()
