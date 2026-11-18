class_name Plot
## One road, six plots. Every chapter is a plot along the same east-west road (z = ROAD_Z): chapter k+1 lies
## to the WEST of chapter k (through its gate), chapter k-1 to the EAST. Each plot is laid out around its own
## origin (world.gd); a neighbour is the same layout shifted by `offset()` along x.
##
## Also owns the ground masks (dirt paths, clearings, road) per chapter. They are cached for the session and
## the neighbours' masks are computed on a worker thread ahead of time, so walking into the next plot
## does not have to wait for them.

const ROAD_Z := 11.5
const PLOT_HALF := 15.5            # standard plot: x in [-15.5, 15.5] (the play area walls)
const LAKE_EAST := 43.5            # the Lakeside plot runs on along the lakeshore road to here
const ROAD_GAP := Vector2(9.6, 14.0)   # z range of the road opening at a plot edge
const NB_DEPTH := 26.0             # how far into a neighbour its ground (and props) are drawn


static func west(_k: int) -> float:
	return -PLOT_HALF


static func east(k: int) -> float:
	if k >= 0 and k < Game.chapters.size() and Game.chapters[k].get("theme", {}).get("water", false):
		return LAKE_EAST
	return PLOT_HALF


## x offset of plot k's origin when standing in plot `cur` (only for direct neighbours).
static func offset(cur: int, k: int) -> float:
	if k == cur + 1:            # west
		return west(cur) - east(k)
	if k == cur - 1:            # east
		return east(cur) - west(k)
	return 0.0


## The chapter beside `cur` on that side (-1 west, +1 east), or -1 at the end of the road.
static func neighbour(cur: int, side: int) -> int:
	var k := cur + 1 if side < 0 else cur - 1
	return k if k >= 0 and k < Game.chapters.size() else -1


# ------------------------------------------------------------------ ground masks

static var _masks: Dictionary = {}       # key -> Image
static var _tasks: Dictionary = {}       # key -> WorkerThreadPool task id
static var _mutex := Mutex.new()


static func _key(k: int, bare: bool) -> String:
	return "%d:%s" % [k, bare]


## Mask domain of chapter k in its own coordinates: x0, x1 (z is always -40..40).
static func mask_x(k: int) -> Vector2:
	return Vector2(-40.0, maxf(40.0, east(k) + 4.0))


## Computes the ground mask of plot k. `bare` = land nobody has built on yet (just the road).
## Pure maths on plain data, so it can run on a worker thread.
static func _make_mask(k: int, bare: bool, patches: Array) -> Image:
	var res := 256
	var mx := mask_x(k)
	var sx := (mx.y - mx.x) / res
	var sz := 80.0 / res
	var data := PackedByteArray()
	data.resize(res * res)
	var segs := [[Vector2(-1, 2), Vector2(-7, 3.4), 1.3, 1.0], [Vector2(-0.5, -2), Vector2(-1.5, -12), 1.1, 0.8],
		[Vector2(1.5, 1), Vector2(6.3, 3.4), 1.0, 1.0]]
	for y in res:
		var wz := -40.0 + (y + 0.5) * sz
		var road := 1.0 - absf(wz - ROAD_Z) / 1.8
		var row := y * res
		var near_camp := not bare and wz > -13.5 and wz < 10.5
		for x in res:
			var wx := mx.x + (x + 0.5) * sx
			var v := road
			if near_camp and wx > -9.0 and wx < 10.0:
				# camp clearing
				var cx := (wx - 1.2) / 8.6
				var cz := (wz - 3.0) / 7.2
				v = maxf(v, 1.0 - sqrt(cx * cx + cz * cz))
				# path to the truck, trail into the forest, path to the shop
				for s in segs:
					var a: Vector2 = s[0]
					var ab: Vector2 = s[1] - a
					var p := Vector2(wx, wz)
					var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
					v = maxf(v, (1.0 - (p - (a + ab * t)).length() / float(s[2])) * float(s[3]))
			for pt in patches:
				var px := (wx - float(pt[0])) / float(pt[2])
				if absf(px) >= 1.0:
					continue
				var pz := (wz - float(pt[1])) / float(pt[3])
				v = maxf(v, (1.0 - sqrt(px * px + pz * pz)) * 1.4)
			data[row + x] = int(clampf(v * 1.8, 0.0, 1.0) * 255.0)
	return Image.create_from_data(res, res, false, Image.FORMAT_L8, data)


static func _patches(k: int, bare: bool) -> Array:
	return [] if bare else Game.chapters[k].get("ground_patches", []).duplicate(true)


## Starts computing masks on worker threads (skips ones already cached or queued).
static func prefetch(list: Array) -> void:
	for it in list:
		var k: int = it[0]
		var bare: bool = it[1]
		if k < 0 or k >= Game.chapters.size():
			continue
		var key := _key(k, bare)
		_mutex.lock()
		var have := _masks.has(key) or _tasks.has(key)
		_mutex.unlock()
		if have:
			continue
		var patches := _patches(k, bare)
		var job := func():
			var img := _make_mask(k, bare, patches)
			_mutex.lock()
			_masks[key] = img
			_mutex.unlock()
		_mutex.lock()
		_tasks[key] = WorkerThreadPool.add_task(job, false, "ground mask")
		_mutex.unlock()


static func mask_image(k: int, bare: bool) -> Image:
	var key := _key(k, bare)
	_mutex.lock()
	var tid: int = _tasks.get(key, -1)
	_mutex.unlock()
	if tid >= 0:
		WorkerThreadPool.wait_for_task_completion(tid)
		_mutex.lock()
		_tasks.erase(key)
		_mutex.unlock()
	_mutex.lock()
	var img: Image = _masks.get(key)
	_mutex.unlock()
	if img == null:
		img = _make_mask(k, bare, _patches(k, bare))
		_mutex.lock()
		_masks[key] = img
		_mutex.unlock()
	return img


## Waits for queued mask jobs (tests call this before quitting).
static func finish_jobs() -> void:
	_mutex.lock()
	var ids := _tasks.duplicate()
	_mutex.unlock()
	for key in ids:
		WorkerThreadPool.wait_for_task_completion(ids[key])
	_mutex.lock()
	_tasks.clear()
	_mutex.unlock()


static func mask_tex(k: int, bare: bool) -> ImageTexture:
	return Art._c("gmask:" + _key(k, bare), func(): return ImageTexture.create_from_image(mask_image(k, bare)))


static func _tc(theme: Dictionary, key: String, def: Color) -> Color:
	var a: Array = theme.get(key, [])
	return Color(a[0], a[1], a[2]) if a.size() >= 3 else def


## Ground material of plot k drawn with its origin at x = ox (0 for the active plot).
static func ground_mat(k: int, ox: float, bare: bool, lite: bool) -> ShaderMaterial:
	var theme: Dictionary = Game.chapters[k].get("theme", {})
	var mat := Art.shader_mat("res://scripts/world/ground_strip.gdshader")      # ground.gdshader + edge blend
	mat.set_shader_parameter("grass_alb", Art.tex("res://assets/textures/leafy_grass_diff.jpg"))
	mat.set_shader_parameter("dirt_alb", Art.tex("res://assets/textures/forrest_ground_01_diff.jpg"))
	if not lite:
		mat.set_shader_parameter("grass_nor", Art.tex("res://assets/textures/leafy_grass_nor.jpg"))
		mat.set_shader_parameter("dirt_nor", Art.tex("res://assets/textures/forrest_ground_01_nor.jpg"))
	var mx := mask_x(k)
	mat.set_shader_parameter("mask_tex", mask_tex(k, bare))
	mat.set_shader_parameter("world_min", Vector2(mx.x + ox, -40.0))
	mat.set_shader_parameter("world_size", Vector2(mx.y - mx.x, 80.0))
	mat.set_shader_parameter("noise_tex", Art.noise())
	mat.set_shader_parameter("lite", lite)
	mat.set_shader_parameter("grass_tint", _tc(theme, "grass", Color(0.80, 1.0, 0.55)))
	mat.set_shader_parameter("dirt_tint", _tc(theme, "dirt", Color(1.05, 0.97, 0.9)))
	return mat


## Fades this ground's tints halfway toward chapter `other`'s at the shared edge x (side -1 = its west edge).
static func blend_edge(mat: ShaderMaterial, side: int, x: float, other: int) -> void:
	var theme: Dictionary = Game.chapters[other].get("theme", {})
	var pre := "west_" if side < 0 else "east_"
	mat.set_shader_parameter(pre + "x", x)
	mat.set_shader_parameter(pre + "grass", _tc(theme, "grass", Color(0.80, 1.0, 0.55)))
	mat.set_shader_parameter(pre + "dirt", _tc(theme, "dirt", Color(1.05, 0.97, 0.9)))


## A flat ground plane covering x0..x1 (world), z -40..40. Neighbouring planes share their edge vertices.
static func ground_plane(x0: float, x1: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(x1 - x0, 80)
	pm.subdivide_width = 4
	pm.subdivide_depth = 4
	mi.mesh = pm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3((x0 + x1) * 0.5, 0, 0)
	return mi
