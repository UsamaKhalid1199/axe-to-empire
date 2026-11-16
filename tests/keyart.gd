extends SceneTree
## Renders golden-hour key art of the camp for the loading screen / splash.
## -- <out.png> [w] [h] [cam_x cam_y cam_z look_x look_y look_z]
func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var a := OS.get_cmdline_user_args()
	var out := a[0]
	var w := int(a[1]) if a.size() > 1 else 1080
	var h := int(a[2]) if a.size() > 2 else 1920
	var cp := Vector3(3.4, 2.3, 3.4)
	var lk := Vector3(-0.4, 1.0, -2.6)
	if a.size() >= 9:
		cp = Vector3(float(a[3]), float(a[4]), float(a[5]))
		lk = Vector3(float(a[6]), float(a[7]), float(a[8]))
	var g = root.get_node("Game")
	g.saving_enabled = false
	g.offline_reward = 0
	g.built = {"campfire": true, "tables_1": true, "shop": true, "crew_hut": true, "fire_2": true, "tables_2": true}
	g.crew = {"lumberjack": 2, "waiter": 1, "cook": 1}
	g.levels["tool"] = 1
	g.woodpile = 30
	g.rack = 6
	change_scene_to_file("res://scenes/main.tscn")
	while current_scene == null or current_scene.get("hud") == null or current_scene.get_node_or_null("LoadingScreen") != null:
		await process_frame
	var main = current_scene
	var wd = main.world
	main.hud.visible = false
	# let the camp come alive: guests arrive, fires cook, crew works
	Engine.time_scale = 6.0
	for i in 420: await process_frame
	Engine.time_scale = 1.0
	# golden hour
	for n in wd.find_children("*", "DirectionalLight3D", true, false):
		n.rotation_degrees = Vector3(-17, -128, 0)
		n.light_color = Color(1.0, 0.8, 0.6)
		n.light_energy = 1.5
	for n in wd.find_children("*", "WorldEnvironment", true, false):
		var e: Environment = n.environment
		e.ambient_light_energy *= 0.75
		e.fog_enabled = true
		e.fog_light_color = Color(0.85, 0.66, 0.52)
		e.fog_density = 0.0045
		e.glow_enabled = true
		e.glow_intensity = 0.9
		e.glow_bloom = 0.08
	for n in wd.find_children("*", "OmniLight3D", true, false):
		n.light_energy = 2.4
		n.omni_range = 5.5
	var p = wd.player
	p.global_position = Vector3(0.9, 0, -3.1)
	p.input_dir = Vector2.ZERO
	for i in 20: await process_frame
	p.rig.rotation.y = deg_to_rad(35)
	wd.set_process(false)
	if wd.get("arrow"): wd.arrow.visible = false
	for z in wd.zones: z.visible = false
	for f in wd.fires: f.ring.visible = false
	var sv := SubViewport.new()
	sv.size = Vector2i(w, h)
	sv.msaa_3d = Viewport.MSAA_4X
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(sv)
	var cam := Camera3D.new()
	cam.fov = 52
	sv.add_child(cam)
	cam.global_position = cp
	cam.look_at(lk, Vector3.UP)
	cam.make_current()
	for i in 8: await process_frame
	sv.get_texture().get_image().save_png(out)
	print("saved ", out)
	quit()
