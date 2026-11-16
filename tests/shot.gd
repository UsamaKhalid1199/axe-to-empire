extends SceneTree
## Renders screenshots of the running game: res://tests/shot.gd -- <out_dir> <scenario>
var out := ""
var scen := "start"
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0] if args.size() > 0 else "C:/tmp"
	scen = args[1] if args.size() > 1 else "start"
	_run.call_deferred()
func _frames(n: int) -> void:
	for i in n:
		await process_frame
func _snap(name: String) -> void:
	await _frames(2)
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(out + "/" + name + ".png")
	print("saved ", name)
func _run() -> void:
	var g = root.get_node("Game")
	g.saving_enabled = false
	if scen != "keep":
		g.coins = 0; g.built = {}; g.pad_paid = {}; g.levels = {"tool":0,"bag":0,"boots":0,"fire":0,"menu":0}
		g.crew = {"lumberjack":0,"waiter":0,"cook":0}; g.woodpile = 0; g.rack = 0; g.counter_coins = 0; g.offline_reward = 0
	if scen == "camp" or scen == "ui":
		g.coins = 2400
		for b in ["campfire","tables_1","shop","crew_hut","fire_2"]: g.built[b] = true
		g.crew = {"lumberjack":2,"waiter":1,"cook":1}; g.woodpile = 20; g.rack = 5; g.counter_coins = 40
	if scen == "saw":
		g.levels.tool = 2; g.levels.bag = 3; g.built["campfire"] = true
	if scen == "harv":
		g.levels.tool = 3; g.levels.bag = 4; g.built["campfire"] = true
	change_scene_to_file("res://scenes/main.tscn")
	while current_scene == null or current_scene.get("hud") == null or current_scene.get_node_or_null("LoadingScreen") != null:
		await process_frame
	await _frames(40)
	var main = current_scene
	var w = main.world
	await _frames(30)
	await _snap(scen + "_0")
	# walk toward the forest and chop
	var p = w.player
	p.input_dir = Vector2(0.0, -1.0)
	await _frames(45 if scen != "close" else 38)
	p.input_dir = Vector2.ZERO
	await _frames(100)
	await _snap(scen + "_1")
	if scen in ["saw", "harv", "close", "fall"]:
		var best = null
		for t in w.trees:
			if t.alive and (best == null or t.global_position.z > best.global_position.z or (absf(t.global_position.z - best.global_position.z) < 0.6 and absf(t.global_position.x - 3.0) < absf(best.global_position.x - 3.0))):
				best = t
		p.back.set_count(0)
		p.global_position = best.global_position + Vector3(0.2, 0, 1.05)
		w.cam_off = Vector3(2.6, 2.4, 3.4)
		w._cam_target = p.global_position
		if not scen in ["close", "fall"]:
			p.input_dir = Vector2(-0.2, -0.3)
		if scen == "fall":
			await _frames(20)
			best.hit(99, p.global_position)
		for k in (12 if scen == "fall" else 8):
			await _frames(9 if scen == "fall" else 6)
			await _snap(scen + "_s%d" % k)
		p.input_dir = Vector2.ZERO
	if scen == "ui":
		for m in ["jobs", "crew", "gate", "offline", "complete", "settings"]:
			if m == "offline":
				g.offline_reward = 1840
				g.offline_seconds = 4600
			main.hud.open_modal(m)
			await _frames(25)
			await _snap("ui_" + m)
			main.hud.close_modal()
			await _frames(10)
	if scen == "camp":
		p.global_position = Vector3(5.2, 0, -0.9)
		await _frames(30)
		await _snap(scen + "_shop")
		main.hud.close_modal()
		p.global_position = Vector3(0.8, 0, 1.0)
		await _frames(200)
		await _snap(scen + "_2")
	quit()
