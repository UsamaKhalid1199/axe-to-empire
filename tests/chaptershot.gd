extends SceneTree
## Gameplay view of a chapter with its camp built: -- <out.png> <chapter> [sp]  (sp = frame the signature station)
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var a := OS.get_cmdline_user_args()
	var k := int(a[1])
	var g = root.get_node("Game")
	g.saving_enabled = false; g.offline_reward = 0
	g.venue = k; g.unlocked = k + 1; g.venues = []
	g.cfg = g.chapter_cfg(k)
	g.built = {"campfire": true, "tables_1": true, "tables_2": true, "shop": true, "crew_hut": true, "fire_2": true, "special": true}
	g.sp = {"fuel": 9}
	g.crew = {"lumberjack": 1, "waiter": 1, "cook": 0}
	g.woodpile = 20; g.rack = 4
	change_scene_to_file("res://scenes/main.tscn")
	while current_scene == null or current_scene.get("hud") == null or current_scene.get_node_or_null("LoadingScreen") != null:
		await process_frame
	while current_scene.world == null or current_scene.world.player == null:
		await process_frame
	await create_timer(1.0).timeout
	var w = current_scene.world
	w.player.global_position = Vector3(1.0, 0, 3.6) if a.size() > 2 and a[2] == "dine" else Vector3(1.0, 0, 1.6)
	if a.size() > 2 and a[2] == "sp" and w.specials.built:
		w.player.global_position = w.specials.pad_pos() + (Vector3(-0.6, 0, 1.2) if w.specials.type == "raft" else Vector3(-2.6, 0, 0.6))
		if w.specials.type == "raft":
			w.player.back.set_count(6)
			w.specials.raft_stack.set_count(9)
		if w.specials.type == "drive_thru":
			w.specials._spawn_car()
		if w.specials.type == "van":
			w.player.hands.set_count(3)
	Engine.time_scale = 4.0
	await create_timer(6.0).timeout
	Engine.time_scale = 1.0
	await create_timer(0.5).timeout
	root.get_texture().get_image().save_png(a[0])
	quit()
