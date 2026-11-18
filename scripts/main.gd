extends Node
## Boots the world + HUD and spawns floating texts.

const WorldScript := preload("res://scripts/world/world.gd")
var world: Node3D
var hud: Hud
var _keep: Array = []       # holds preloaded resources so later load() calls hit the cache


func _ready() -> void:
	if OS.has_feature("mobile"):
		_pick_quality()
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


## MAP / gate travel: the same quick swap as walking, with a "Travelling to X" card on the fade; you arrive on
## the road at the side you came from. Only without a world (or while loading) does it rebuild behind the
## full loading screen.
func travel_to(k: int) -> void:
	# a MAP tap while a walk/trip is still fading is queued, not dropped
	while crossing:
		await get_tree().process_frame
	var from := Game.venue
	if from == k or k < 0 or k >= Game.unlocked or crossing:
		return
	if world == null or not is_instance_valid(world) or hud == null or get_node_or_null("LoadingScreen") != null:
		var take := {}
		if world and is_instance_valid(world):
			take = world.carried()             # bag logs and dishes come along, as when walking
			world.before_leave()
		if Game.travel(k):
			var arrive := WorldScript.map_arrival(from, k)
			if not arrive.is_empty():
				arrive.merge(take)
			reload_venue(arrive)
		return
	var arrive := WorldScript.map_arrival(from, k)
	arrive.merge(world.carried())
	await _swap(k, arrive, "Travelling to %s…" % String(Game.chapters[k].name))


## Walking along the road into the plot next door.
func walk_to(k: int, arrive: Dictionary) -> void:
	await _swap(k, arrive, "")


## The quick swap to place k (walking or MAP). The place you leave is frozen as a still picture (retire) while
## the screen fades out, and the next place builds behind it one step per frame during that fade; under black
## the two only trade places (no frees, no HUD rebuild: the HUD rebinds to the new world) and the fade comes
## straight back. The old place is freed a little per frame afterwards (_reap_tick), so the materials and
## shaders both places share never drop out of use (on the phone a dropped shader is recompiled: that was the
## second of black after every walk). Logs `CROSS to k: build X ms (world Y {steps}), black Z ms`.
const FADE_OUT := 0.22             # to DIM: the old place, frozen, while the new one builds
const DIM := 0.9
const FADE_LAST := 0.05            # DIM -> black once the new place is built and prewarmed
const FADE_IN := 0.2
const STEP_BUDGET_MS := 30
var crossing := false
var last_cross_ms := 0.0          # every build step of the last swap, summed
var last_black_ms := 0.0          # how long the screen was fully black
var last_cross_detail := {}
var _reap: Array = []             # retired places, freed a few nodes per frame


func _swap(k: int, arrive: Dictionary, card: String) -> void:
	if crossing or get_node_or_null("LoadingScreen") != null or world == null or not is_instance_valid(world):
		return
	crossing = true
	var t0 := Time.get_ticks_usec()
	var fade := _fade_layer(card)
	var shade: Control = fade.get_child(0)
	var old := world
	old.before_leave()
	if not Game.travel(k):
		fade.queue_free()
		crossing = false
		old._crossing = false
		return
	old.retire()
	Sfx.saw(false)
	var tw := create_tween()
	tw.set_ignore_time_scale(true)
	tw.tween_property(shade, "modulate:a", DIM, FADE_OUT)
	var nw = WorldScript.new()
	nw.staged = true
	nw.quiet = true
	nw.arrival = arrive
	nw.visible = false
	add_child(nw)
	# build while the old place dims: a few steps per frame (about STEP_BUDGET_MS of work, then the frame is
	# drawn), the screen holding at DIM until the build is done, so no build work happens under black
	var build_us := 0
	var dark_us := 0
	var frame_t := Time.get_ticks_usec()
	for st in nw.build_steps():
		var ts := Time.get_ticks_usec()
		st[1].call()
		var d := Time.get_ticks_usec() - ts
		build_us += d
		nw.build_ms[String(st[0]).get_slice(" ", 0)] = d / 1000.0
		nw.process_mode = Node.PROCESS_MODE_DISABLED     # stays still until it is shown
		if Time.get_ticks_usec() - frame_t > STEP_BUDGET_MS * 1000:
			await get_tree().process_frame
			frame_t = Time.get_ticks_usec()
	await _prewarm(nw)
	if tw.is_running():
		await tw.finished
	tw = create_tween()
	tw.set_ignore_time_scale(true)
	tw.tween_property(shade, "modulate:a", 1.0, FADE_LAST)
	await tw.finished
	var t_black := Time.get_ticks_usec()
	# under black: trade places
	var env := old.get_node_or_null("Env")
	if env:
		env.free()                    # the first WorldEnvironment in the tree wins: the new place's sky now
	old.visible = false
	world = nw
	Art.retint_foliage(nw.theme)
	nw.visible = true
	nw.process_mode = Node.PROCESS_MODE_INHERIT
	nw.cam.make_current()
	nw.float_text.connect(_float_text)
	nw.cross_requested.connect(walk_to)
	if hud:
		hud.rebind(nw)
	_reap.append(old)
	var t_swap := Time.get_ticks_usec()
	_marks.clear()
	RenderingServer.frame_pre_draw.connect(_mark_pre)
	RenderingServer.frame_post_draw.connect(_mark_post)
	await get_tree().process_frame                 # resumes once the new place's first frame is drawn (under black)
	var t_drawn := Time.get_ticks_usec()
	RenderingServer.frame_pre_draw.disconnect(_mark_pre)
	RenderingServer.frame_post_draw.disconnect(_mark_post)
	var marks := _marks.duplicate()
	last_cross_ms = build_us / 1000.0
	tw = create_tween()
	tw.set_ignore_time_scale(true)
	tw.tween_property(shade, "modulate:a", 0.0, FADE_IN)
	await get_tree().process_frame
	var t_lit := Time.get_ticks_usec()
	last_black_ms = (t_lit - t_black) / 1000.0
	last_cross_detail = {"fade_out": (t_black - t0) / 1000.0, "built_in_black": dark_us / 1000.0, "build_frames": build_us / 1000.0,
		"swap": (t_swap - t_black) / 1000.0, "first_frame": (t_drawn - t_swap) / 1000.0}
	if marks.has("pre") and marks.has("post"):
		last_cross_detail["frame_cpu"] = (int(marks.pre) - t_swap) / 1000.0         # process + physics of that frame
		last_cross_detail["frame_draw"] = (int(marks.post) - int(marks.pre)) / 1000.0
	print("CROSS to %d: build %.0f ms (world %.0f %s), black %.0f ms %s" % [k, last_cross_ms, last_cross_ms, nw.build_ms,
		last_black_ms, last_cross_detail])
	if tw.is_running():
		await tw.finished           # (a slow first frame can outlast the whole fade-in: then it has already finished)
	fade.queue_free()
	crossing = false


## One frame of the new place drawn off screen while the old one is still showing: it shares the World3D, but
## its instances sit on a render layer only a small offscreen camera sees (and the old camera does not), so the
## GPU work of a place's first frame (buffers, and the shaders of a place not visited yet) happens behind the dim
## screen instead of under black.
const PREWARM_LAYER := 1 << 19


func _prewarm(nw: Node3D) -> void:
	if DisplayServer.get_name() == "headless" or nw.cam == null:
		return
	var vis: Array = nw.find_children("*", "VisualInstance3D", true, false)
	var was: PackedInt32Array = PackedInt32Array()
	was.resize(vis.size())
	for i in vis.size():
		was[i] = vis[i].layers
		vis[i].layers = PREWARM_LAYER
	# each place lit by its own sun only (two directional lights would compile other shader variants)
	var lights: Array = nw.find_children("*", "Light3D", false, false)
	var old_lights: Array = world.find_children("*", "Light3D", false, false) if world else []
	var light_was: Array = []
	for l in lights + old_lights:
		light_was.append(l.light_cull_mask)
	for l in lights:
		l.light_cull_mask = PREWARM_LAYER
	for l in old_lights:
		l.light_cull_mask = l.light_cull_mask & ~PREWARM_LAYER
	var old_cam := get_viewport().get_camera_3d()
	var old_mask := old_cam.cull_mask if old_cam else 0
	if old_cam:
		old_cam.cull_mask = old_mask & ~PREWARM_LAYER
	var sv := SubViewport.new()
	var vsz := get_viewport().get_visible_rect().size
	sv.size = Vector2i(maxi(64, int(vsz.x * 0.25)), maxi(64, int(vsz.y * 0.25)))
	sv.world_3d = get_viewport().find_world_3d()
	sv.render_target_update_mode = SubViewport.UPDATE_ONCE
	var c := Camera3D.new()
	c.cull_mask = PREWARM_LAYER
	c.fov = nw.cam.fov
	c.keep_aspect = nw.cam.keep_aspect
	c.far = nw.cam.far
	sv.add_child(c)
	add_child(sv)
	c.global_transform = nw.cam.global_transform
	c.current = true
	nw.visible = true
	await get_tree().process_frame
	await get_tree().process_frame          # (the first resume can come before the subviewport has drawn)
	nw.visible = false
	sv.free()
	if old_cam and is_instance_valid(old_cam):
		old_cam.cull_mask = old_mask
	for i in vis.size():
		if is_instance_valid(vis[i]):
			vis[i].layers = was[i]
	var all_lights: Array = lights + old_lights
	for i in all_lights.size():
		if is_instance_valid(all_lights[i]):
			all_lights[i].light_cull_mask = light_was[i]


var _marks := {}


func _mark_pre() -> void:
	if not _marks.has("pre"):
		_marks["pre"] = Time.get_ticks_usec()


func _mark_post() -> void:
	if not _marks.has("post"):
		_marks["post"] = Time.get_ticks_usec()


func _fade_layer(card: String) -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.name = "Fade"
	layer.layer = 120
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 1)
	shade.modulate.a = 0.0
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(shade)
	if card != "":
		var l := UI.label(card, 34, Color(1, 0.93, 0.78))
		l.set_anchors_preset(Control.PRESET_FULL_RECT)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		shade.add_child(l)
	add_child(layer)
	return layer


## Frees retired places a few nodes at a time (about 3 ms a frame), never while a swap is running.
func _reap_tick() -> void:
	if _reap.is_empty() or crossing:
		return
	var t0 := Time.get_ticks_usec()
	while not _reap.is_empty() and Time.get_ticks_usec() - t0 < 3000:
		var w = _reap[0]
		if not is_instance_valid(w):
			_reap.pop_front()
			continue
		if w.get_child_count() == 0:
			w.free()
			_reap.pop_front()
			continue
		w.get_child(w.get_child_count() - 1).free()


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


## First launch on a phone (once, and only while the graphics level is on auto): weak GPUs start on Smooth.
## The Balanced default ran the Shack at 16-17 fps on a PowerVR GE8320, just above the auto drop's old
## 17 fps line, so it never stepped down by itself.
func _pick_quality() -> void:
	if Game.settings.get("quality_picked", false) or not Game.quality_auto:
		return
	Game.settings["quality_picked"] = true
	if weak_gpu(RenderingServer.get_video_adapter_name(), OS.get_memory_info().get("physical", 0)) and Game.quality > 0:
		Game.quality = 0
		print("QUALITY auto-picked Smooth for %s" % RenderingServer.get_video_adapter_name())
	Game.save_game()


## Entry-level mobile GPUs (or under ~3.5 GB of RAM): PowerVR, Mali-4xx/T/G31-G52, Adreno below 610.
static func weak_gpu(name: String, ram_bytes: int) -> bool:
	var n := name.to_lower()
	if ram_bytes > 0 and ram_bytes < 3_500_000_000:
		return true
	for tag in ["powervr", "mali-4", "mali-t", "mali-g31", "mali-g51", "mali-g52"]:
		if n.contains(tag):
			return true
	var i := n.find("adreno")
	if i >= 0:
		var digits := ""
		for ch in n.substr(i + 6):
			if ch >= "0" and ch <= "9":
				digits += ch
			elif digits != "":
				break
		return digits != "" and int(digits) < 610
	return false


var _low_t := 0.0
var _watch_t := 0.0


## Auto quality: after the first 20 s, if fps sits under 19 for about 12 s, drop one level (once per level).
## (It was 17 with a double-speed recovery: a phone hovering at 16-17 fps never reached the 12 s.)
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
	_reap_tick()
	if OS.has_feature("mobile") and OS.is_debug_build():
		_perf_log(delta)
		_probe_tick(delta)
		_autowalk_tick(delta)
	if not OS.has_feature("mobile") or _probe >= 0 or not Game.quality_auto or Game.quality == 0 or world == null:
		return
	if get_node_or_null("LoadingScreen") != null:
		_watch_t = 0.0
		return
	_watch_t += delta
	if _watch_t < 20.0:
		return
	_low_t = _low_t + delta if Engine.get_frames_per_second() < 19 else maxf(0.0, _low_t - delta)
	if _low_t > 12.0:
		_low_t = 0.0
		_watch_t = 0.0
		Game.quality -= 1
		Game.save_game()
		apply_quality()
		_float_text("Graphics: " + String(Game.QUALITY_NAMES[Game.quality]), world.player.global_position + Vector3(0, 2.6, 0), Color(1, 0.9, 0.5))


## Debug-only on-device QA (like the probe): if user://autowalk exists, walk across a plot edge every 7 s (east, west, west,
## east: 1 -> 0 -> 1 -> 2 -> 1 from the Shack) and log the slowest frame of the second after arriving; every
## 12th trip is a MAP trip (to the place two steps west and back), logged as "MAPT ... ms" tap to playable.
var _aw := -2
var _aw_t := 0.0
var _aw_i := 0
var _aw_watch := -1.0
var _aw_worst := 0.0
var _aw_frames := 0
var _aw_map_t0 := -1


func _autowalk_tick(delta: float) -> void:
	if _aw == -2:
		_aw = 0 if FileAccess.file_exists("user://autowalk") else -1
	if _aw < 0:
		return
	if _aw_map_t0 >= 0:
		if get_node_or_null("LoadingScreen") == null and not crossing and world != null and world.player != null:
			print("MAPT to %d: %d ms tap to playable" % [Game.venue, Time.get_ticks_msec() - _aw_map_t0])
			_aw_map_t0 = -1
			_aw_t = 0.0
			_aw_watch = 0.0
			_aw_worst = 0.0
			_aw_frames = 0
		return
	if crossing or world == null or get_node_or_null("LoadingScreen") != null:
		_aw_watch = -1.0
		return
	if _aw_watch < 0.0 and _aw_i > 0 and _aw_t == 0.0:
		_aw_watch = 0.0
		_aw_worst = 0.0
		_aw_frames = 0
	if _aw_watch >= 0.0:
		_aw_watch += delta
		_aw_frames += 1
		if _aw_frames > 1:
			_aw_worst = maxf(_aw_worst, delta * 1000.0)
		if _aw_watch >= 1.0:
			print("AFTER %d: worst frame %.0f ms, %d frames in the first second" % [Game.venue, _aw_worst, _aw_frames])
			_aw_watch = -2.0
	_aw_t += delta
	if _aw_t < 7.0:
		return
	_aw_t = 0.0
	_aw_i += 1
	if _aw_i % 12 == 0:
		var to := Game.venue + 2 if Game.venue + 2 < Game.unlocked else Game.venue - 2
		_aw_map_t0 = Time.get_ticks_msec()
		travel_to(to)
		return
	var side: int = [1, -1, -1, 1][_aw_i % 4]
	if not world.can_cross(side):
		side = -side
	if not world.can_cross(side):
		return
	world.player.global_position = Vector3(Plot.west(Game.venue) + 0.2 if side < 0 else Plot.east(Game.venue) - 0.2, 0, 11.5)
	world._cross_armed = true
	world._cross(side)
