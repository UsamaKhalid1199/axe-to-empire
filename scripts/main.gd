extends Node
## Boots the world + HUD and spawns floating texts.

const WorldScript := preload("res://scripts/world/world.gd")
var world: Node3D
var hud: Hud
var _keep: Array = []       # holds preloaded resources so later load() calls hit the cache


func _ready() -> void:
	if OS.has_feature("mobile"):
		Engine.max_fps = 30
		var vp := get_viewport()
		vp.scaling_3d_scale = Game.QUALITY_SCALE[Game.quality]
		Engine.physics_ticks_per_second = 30
		vp.mesh_lod_threshold = 8.0
	var ls := LoadingScreen.new()
	ls.name = "LoadingScreen"
	add_child(ls)
	await _frames(2)
	# 1) stream heavy assets on a worker thread while the bar moves
	var paths: Array[String] = []
	for f in CharacterRig.ANIMS.values():
		paths.append(CharacterRig.BASE + f)
	for m in ["stone_fire_pit", "wooden_axe", "wooden_axe_02", "wooden_barrels_01", "wooden_bowl_01", "wooden_crate_01",
			"wooden_lantern_01", "wooden_picnic_table", "wooden_stool_01", "pot_enamel_01", "rock_moss_set_01", "fern_02", "grass_medium_01"]:
		paths.append("res://assets/models/%s/%s.gltf" % [m, m])
	for p in paths:
		ResourceLoader.load_threaded_request(p, "", true)
	var done := 0
	while done < paths.size():
		done = 0
		var part := 0.0
		for p in paths:
			var prog := []
			var st := ResourceLoader.load_threaded_get_status(p, prog)
			if st == ResourceLoader.THREAD_LOAD_LOADED or st == ResourceLoader.THREAD_LOAD_FAILED or st == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				done += 1
				part += 1.0
			else:
				part += float(prog[0]) if prog.size() > 0 else 0.0
		ls.set_status("Sharpening the axe…" if part < paths.size() * 0.5 else "Packing the backpack…", 0.62 * part / paths.size())
		await get_tree().process_frame
	for p in paths:
		if ResourceLoader.load_threaded_get_status(p) == ResourceLoader.THREAD_LOAD_LOADED:
			_keep.append(ResourceLoader.load_threaded_get(p))
	# 2) build the world (blocking) — show the step first
	await _build_venue(ls, 0.66)


## Builds the active venue's world + HUD behind the loader (boot, travel, new empire).
func _build_venue(ls: LoadingScreen, from: float, arrive := {}) -> void:
	var ch: Dictionary = Game.chapter()
	ls.set_status("Opening " + String(ch.name) + "…", from)
	ls.sync()
	await _frames(2)
	world = WorldScript.new()
	world.staged = true
	world.arrival = arrive
	add_child(world)
	var steps: Array = world.build_steps()
	for i in steps.size():
		ls.set_status(String(steps[i][0]) + "…", lerpf(from, 0.92, float(i) / steps.size()))
		ls.sync()
		await _frames(1)
		steps[i][1].call()
	ls.set_status("Lighting the " + String(Game.build_def("campfire").name).to_lower() + "…", 0.93)
	ls.sync()
	await _frames(2)
	hud = Hud.new()
	hud.world = world
	add_child(hud)
	move_child(ls, -1)
	world.float_text.connect(_float_text)
	world.cross_requested.connect(walk_to)
	# let shaders compile behind the loader: first a look at each road edge (the plots next door use materials
	# nothing in the camp does; the first walk there used to hitch for ~0.4 s on the phone), then back home
	ls.set_status("Almost there…", 0.96)
	for aim in world.prewarm_aims():
		world.cam_look(aim)
		await _frames(2)
	world.cam_look(world.cam_aim(world.player.global_position))
	await _frames(6)
	ls.finish()


## MAP / gate travel: full rebuild behind the loading screen; you arrive on the road at the side you came from.
func travel_to(k: int) -> void:
	var from := Game.venue
	var take := {}
	if world and is_instance_valid(world) and from != k:
		take = world.carried()             # bag logs and dishes come along, as when walking
		world.before_leave()
	if Game.travel(k):
		var arrive := WorldScript.map_arrival(from, k)
		if not arrive.is_empty():
			arrive.merge(take)
		reload_venue(arrive)


## Walking along the road into the plot next door: a quick fade instead of the loading screen.
## The venue still has to be rebuilt (every plot is laid out around the origin), but the heavy parts are
## cached (models, materials, ground masks precomputed on a worker thread), so the screen is black only for
## the build itself plus two frames.
var crossing := false
var last_cross_ms := 0.0


func walk_to(k: int, arrive: Dictionary) -> void:
	if crossing or get_node_or_null("LoadingScreen") != null:
		return
	crossing = true
	var layer := CanvasLayer.new()
	layer.name = "Fade"
	layer.layer = 120
	var black := ColorRect.new()
	black.color = Color(0, 0, 0, 0)
	black.mouse_filter = Control.MOUSE_FILTER_STOP
	black.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(black)
	add_child(layer)
	var tw := create_tween()
	tw.set_ignore_time_scale(true)
	tw.tween_property(black, "color:a", 1.0, 0.14)
	await tw.finished
	if world and is_instance_valid(world):
		world.before_leave()
	if not Game.travel(k):
		layer.queue_free()
		crossing = false
		if world:
			world._crossing = false
		return
	Sfx.saw(false)
	var t0 := Time.get_ticks_usec()
	if hud:
		hud.queue_free()
		hud = null
	if world:
		world.queue_free()
		world = null
	await get_tree().process_frame
	var t1 := Time.get_ticks_usec()
	world = WorldScript.new()
	world.arrival = arrive
	add_child(world)            # builds every step at once (not staged)
	var t_world := (Time.get_ticks_usec() - t1) / 1000.0
	hud = Hud.new()
	hud.world = world
	add_child(hud)
	move_child(layer, -1)
	world.float_text.connect(_float_text)
	world.cross_requested.connect(walk_to)
	last_cross_ms = (Time.get_ticks_usec() - t1) / 1000.0
	await _frames(2)
	print("CROSS to %d: build %.0f ms (world %.0f %s), black %.0f ms" % [k, last_cross_ms, t_world, world.build_ms, (Time.get_ticks_usec() - t0) / 1000.0])
	tw = create_tween()
	tw.set_ignore_time_scale(true)
	tw.tween_property(black, "color:a", 0.0, 0.2)
	await tw.finished
	layer.queue_free()
	crossing = false


## Tear down the current venue and build the active one again.
func reload_venue(arrive := {}) -> void:
	Sfx.saw(false)
	var ls := LoadingScreen.new()
	ls.name = "LoadingScreen"
	add_child(ls)
	await _frames(2)
	if hud:
		hud.queue_free()
		hud = null
	if world:
		world.queue_free()
		world = null
	await _frames(2)
	await _build_venue(ls, 0.3, arrive)
	var t := Timer.new()
	t.wait_time = 5.0
	t.autostart = true
	t.timeout.connect(func(): print("PERF fps=%d draw=%d prims=%d" % [Engine.get_frames_per_second(),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)]))
	add_child(t)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _float_text(text: String, pos: Vector3, color: Color) -> void:
	if world == null or not is_instance_valid(world) or not world.is_inside_tree():
		return                          # the venue is being rebuilt (travel)
	var l := Label3D.new()
	l.text = text
	l.font = UI.font_bold()
	l.font_size = 80
	l.pixel_size = 0.005
	l.outline_size = 16
	l.outline_modulate = Color(0.1, 0.05, 0.0, 0.9)
	l.modulate = color
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.render_priority = 8
	world.add_child(l)
	l.global_position = pos
	var tw := l.create_tween()
	tw.tween_property(l, "global_position", pos + Vector3(0, 1.1, 0), 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.9).set_delay(0.35)
	tw.tween_callback(l.queue_free)


## Apply the graphics level now (render scale + decor density). Mobile only.
func apply_quality() -> void:
	if not OS.has_feature("mobile"):
		return
	get_viewport().scaling_3d_scale = Game.QUALITY_SCALE[Game.quality]
	if world:
		world.apply_quality()


var _low_t := 0.0
var _watch_t := 0.0


## Auto quality: after the first 20 s, if fps sits under 17 for 12 s, drop one level (once per level).
var _perf_t := 0.0


func _perf_log(delta: float) -> void:
	_perf_t += delta
	if _perf_t < 5.0:
		return
	_perf_t = 0.0
	var rid := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	print("PERFLOG fps=%d proc=%.1fms phys=%.1fms rcpu=%.1fms rgpu=%.1fms draws=%d prims=%d q=%d" % [
		Engine.get_frames_per_second(), Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		RenderingServer.viewport_get_measured_render_time_cpu(rid), RenderingServer.viewport_get_measured_render_time_gpu(rid),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME), Game.quality])


## Debug-only on-device ablation: if user://probe exists, cycle render configs every 8 s and log fps.
var _probe := -2
var _probe_t := 0.0
var _probe_fps: Array = []
const PROBES := ["base", "scale50", "no_chars", "no_trees", "no_decor", "no_hud", "no_anim", "no_ground", "all_off"]


func _probe_set(i: int, on: bool) -> void:
	var w := world
	match PROBES[i]:
		"scale50": get_viewport().scaling_3d_scale = 0.5 if on else Game.QUALITY_SCALE[Game.quality]
		"no_chars":
			for s in w.find_children("*", "Skeleton3D", true, false): s.get_parent().visible = not on
		"no_trees":
			for t in w.trees: t.visible = not on
		"no_decor":
			for n in w.find_children("*", "MultiMeshInstance3D", true, false): n.visible = not on
		"no_hud": hud.visible = not on
		"no_anim":
			for a in w.find_children("*", "AnimationTree", true, false) + w.find_children("*", "AnimationPlayer", true, false):
				a.process_mode = Node.PROCESS_MODE_DISABLED if on else Node.PROCESS_MODE_INHERIT
		"no_ground":
			for n in w.get_children():
				if n is MeshInstance3D and n.mesh is PlaneMesh: n.visible = not on
		"all_off":
			for k in range(1, PROBES.size() - 1): _probe_set(k, on)


func _probe_tick(delta: float) -> void:
	if _probe == -2:
		_probe = 0 if FileAccess.file_exists("user://probe") else -1
	if _probe < 0 or world == null or get_node_or_null("LoadingScreen") != null:
		return
	_probe_t += delta
	if _probe_t > 3.0:
		_probe_fps.append(Engine.get_frames_per_second())
	if _probe_t < 8.0:
		return
	var avg := 0.0
	for f in _probe_fps: avg += f
	print("PROBE %s fps=%.1f" % [PROBES[_probe], avg / maxf(1.0, _probe_fps.size())])
	_probe_fps.clear()
	_probe_t = 0.0
	if _probe > 0:
		_probe_set(_probe, false)
	_probe += 1
	if _probe >= PROBES.size():
		_probe = -1
		print("PROBE done")
		return
	if _probe > 0:
		_probe_set(_probe, true)


func _process(delta: float) -> void:
	if OS.has_feature("mobile") and OS.is_debug_build():
		_perf_log(delta)
		_probe_tick(delta)
	if not OS.has_feature("mobile") or _probe >= 0 or not Game.quality_auto or Game.quality == 0 or world == null:
		return
	if get_node_or_null("LoadingScreen") != null:
		_watch_t = 0.0
		return
	_watch_t += delta
	if _watch_t < 20.0:
		return
	_low_t = _low_t + delta if Engine.get_frames_per_second() < 17 else maxf(0.0, _low_t - delta * 2.0)
	if _low_t > 12.0:
		_low_t = 0.0
		_watch_t = 0.0
		Game.quality -= 1
		Game.save_game()
		apply_quality()
		_float_text("Graphics: " + String(Game.QUALITY_NAMES[Game.quality]), world.player.global_position + Vector3(0, 2.6, 0), Color(1, 0.9, 0.5))
