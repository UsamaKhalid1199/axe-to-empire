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
	var water := east(k) > PLOT_HALF + 1.0
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
			if water and wx > 14.0 and wz < 11.5:
				# a worn sandy shore all round the lake, a little under the water's edge too
				v = maxf(v, 1.0 - absf(lake_sd(wx, wz) + 0.3) / 1.4)
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


# ------------------------------------------------------------------ the lake (Lakeside Diner)

## The lake north of the lakeshore road, in the Lakeside plot's coordinates: a rectangle with a straight west
## shore (the dock and the raft) and wide, slightly wavy rounded corners in the east, where the lakeshore road
## ends. Signed distance in metres (< 0 = water), shared by the water mesh and the shore in the ground mask.
const LAKE_MIN := Vector2(16.5, -34.0)
const LAKE_MAX := Vector2(42.5, 9.3)


static func lake_sd(x: float, z: float) -> float:
	var c := (LAKE_MIN + LAKE_MAX) * 0.5
	var half := (LAKE_MAX - LAKE_MIN) * 0.5
	var r := 9.0 if x > c.x else 1.0
	var q := Vector2(absf(x - c.x), absf(z - c.y)) - half + Vector2(r, r)
	var d := Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - r
	# gentle waves along the south and east shores (none by the dock)
	return d + 0.35 * sin(x * 0.55 + 1.3) * sin(z * 0.45 + 0.4) * smoothstep(20.0, 26.0, x)


## The water surface: a fan from the middle out to where lake_sd = 0 (cached; one draw).
static func lake_mesh() -> ArrayMesh:
	return Art._c("lake_mesh", func():
		var c := (LAKE_MIN + LAKE_MAX) * 0.5
		var n := 96
		var rim := PackedVector3Array()
		for i in n:
			var a := TAU * i / n
			var dir := Vector2(cos(a), sin(a))
			var lo := 0.0
			var hi := 40.0
			for it in 22:
				var mid := (lo + hi) * 0.5
				var p := c + dir * mid
				if lake_sd(p.x, p.y) < 0.0:
					lo = mid
				else:
					hi = mid
			var e := c + dir * lo
			rim.append(Vector3(e.x, 0.0, e.y))
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_normal(Vector3.UP)
		var mid3 := Vector3(c.x, 0.0, c.y)
		for i in n:
			var a := rim[i]
			var b := rim[(i + 1) % n]
			for v in [mid3, b, a]:
				st.set_uv(Vector2(v.x, v.z) * 0.05)
				st.add_vertex(v)
		var am := st.commit()
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.12, 0.32, 0.42)
		m.roughness = 0.08
		m.metallic = 0.35
		m.metallic_specular = 0.8
		m.cull_mode = BaseMaterial3D.CULL_DISABLED      # (winding-proof: it is only ever seen from above)
		am.surface_set_material(0, m)
		return am)


static func lake_node() -> MeshInstance3D:
	var w := MeshInstance3D.new()
	w.name = "Water"
	w.mesh = lake_mesh()
	w.position.y = 0.04
	w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return w


# ------------------------------------------------------------------ the low band south of the road

const BAND_Z := Vector2(14.5, 20.6)    # from inside the road wall (z 14..15) south: nobody walks there


## The low dressing south of the road for chapter k over x0..x1 (that plot's own coordinates): a fence, hedge or
## hay line along the road wall and crops, flower beds, reeds, snow drifts, pumpkins or parked cars behind it.
## Everything is under ~0.6 m (it sits right under the camera and must never hide the player).
## Returns [[mesh, [Transform3D, ...]], ...]: one entry per prop type, i.e. one MultiMesh (one draw) each.
static func band(k: int, x0: float, x1: float) -> Array:
	var id := String(Game.chapters[k].get("id", ""))
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242 + k * 17 + int(x0 * 3.0)
	var a: Array = []
	var b: Array = []
	var ka := ""
	var kb := ""
	match id:
		"camp", "shack":
			ka = "fence"
			a = _band_line(x0, x1, 2.0, 14.55, 0.0)
			if id == "camp":
				kb = "flowers"
				for r in 3:
					var x := x0 + 1.3 + (1.25 if r % 2 == 1 else 0.0)
					while x < x1 - 1.0:
						if rng.randf() > 0.18:
							b.append(Transform3D(Basis(), Vector3(x + rng.randf_range(-0.2, 0.2), 0, 15.6 + r * 1.35)))
						x += 2.5
			else:
				kb = "crops"
				for r in 6:
					b.append_array(_band_line(x0, x1, 2.0, 15.3 + r * 0.8, 0.0))
		"lake":
			ka = "reeds"
			kb = "rocks"
			for i in int((x1 - x0) * 2.6):
				var z := 14.6 + pow(rng.randf(), 1.6) * 5.0        # thicker near the road
				var s := rng.randf_range(0.75, 1.25)
				a.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, rng.randf_range(0.85, 1.05), s)),
					Vector3(rng.randf_range(x0 + 0.4, x1 - 0.4), 0, z)))
			for i in int((x1 - x0) * 0.22):
				var s := rng.randf_range(0.7, 1.3)
				b.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s),
					Vector3(rng.randf_range(x0 + 0.5, x1 - 0.5), 0, rng.randf_range(14.8, 19.5))))
		"lodge":
			ka = "drift"
			kb = "skis"
			for i in int((x1 - x0) * 1.1):
				var w := rng.randf_range(0.45, 1.0)
				a.append(Transform3D(Basis(Vector3.UP, rng.randf_range(-0.3, 0.3)).scaled(Vector3(w, rng.randf_range(0.8, 1.4), w * 0.6)),
					Vector3(rng.randf_range(x0 + 0.6, x1 - 0.6), 0, rng.randf_range(14.7, 20.0))))
			var x := x0 + 2.5
			while x < x1 - 1.5:
				b.append(Transform3D(Basis(Vector3.UP, rng.randf_range(-0.12, 0.12)), Vector3(x + rng.randf_range(-0.8, 0.8), 0, 14.95)))
				x += rng.randf_range(3.0, 4.6)
		"smoke":
			ka = "hay"
			kb = "pumpkins"
			var x := x0 + 1.2
			while x < x1 - 0.8:
				a.append(Transform3D(Basis(Vector3.UP, rng.randf_range(-0.25, 0.25)), Vector3(x, 0, 14.75)))
				if rng.randf() < 0.35:
					a.append(Transform3D(Basis(Vector3.UP, PI / 2 + rng.randf_range(-0.3, 0.3)), Vector3(x + 0.2, 0, 15.7)))
				x += rng.randf_range(1.6, 2.8)
			for r in 4:
				for t in _band_line(x0, x1, 2.0, 16.5 + r * 0.85, 0.0):
					if rng.randf() > 0.12:
						b.append(t)
		"hotel":
			ka = "hedge"
			kb = "cars"
			a = _band_line(x0, x1, 2.0, 14.6, 0.0)
			for z in [16.6, 19.3]:
				var x := x0 + 1.6
				while x < x1 - 1.4:
					if rng.randf() < 0.75:
						b.append(Transform3D(Basis(Vector3.UP, PI if rng.randf() < 0.5 else 0.0), Vector3(x, 0, z)))
					x += 2.76
	var out: Array = []
	if ka != "" and not a.is_empty():
		out.append([Art.band_mesh(ka), a])
	if kb != "" and not b.is_empty():
		out.append([Art.band_mesh(kb), b])
	return out


## Pieces of length `step` end to end along x (centred), from x0 to x1 at depth z.
static func _band_line(x0: float, x1: float, step: float, z: float, yaw: float) -> Array:
	var out: Array = []
	var n := int(floor((x1 - x0) / step))
	var start := (x0 + x1) * 0.5 - (n - 1) * step * 0.5
	for i in n:
		out.append(Transform3D(Basis(Vector3.UP, yaw), Vector3(start + i * step, 0, z)))
	return out


## The band as a node of MultiMeshes (static, no shadows: one draw per prop type).
static func band_node(k: int, x0: float, x1: float) -> Node3D:
	var n := Node3D.new()
	n.name = "RoadBand"
	for e in band(k, x0, x1):
		var xfs: Array = e[1]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = e[0]
		mm.instance_count = xfs.size()
		for i in xfs.size():
			mm.set_instance_transform(i, xfs[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(mmi)
	return n


## The band merged into one plain mesh per prop type, for a neighbour's flat bake (Art.bake_flat folds them into
## its baked mesh: no extra draws there).
static func band_meshes(k: int, x0: float, x1: float, parent: Node3D) -> void:
	for e in band(k, x0, x1):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for xf in e[1]:
			st.append_from(e[0], 0, xf)
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.mesh.surface_set_material(0, Art.band_mat())
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)
