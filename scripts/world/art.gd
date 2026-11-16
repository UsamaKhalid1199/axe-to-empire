class_name Art
## Procedural meshes, materials and model loading. Everything is cached and shared.

static var _cache: Dictionary = {}


static func _c(key: String, make: Callable):
	if not _cache.has(key):
		_cache[key] = make.call()
	return _cache[key]


static func tex(path: String) -> Texture2D:
	return _c("tex:" + path, func(): return load(path))


static func noise() -> NoiseTexture2D:
	return _c("noise", func():
		var n := NoiseTexture2D.new()
		n.width = 256; n.height = 256; n.seamless = true
		var f := FastNoiseLite.new()
		f.frequency = 0.02; f.fractal_octaves = 4
		n.noise = f
		n.generate_mipmaps = true
		return n)


static func pbr(name: String, uv_scale := 1.0, tint := Color.WHITE) -> StandardMaterial3D:
	return _c("pbr:%s:%s:%s" % [name, uv_scale, tint], func():
		var m := StandardMaterial3D.new()
		m.albedo_texture = tex("res://assets/textures/%s_diff.jpg" % name)
		m.albedo_color = tint
		m.normal_enabled = true
		m.normal_texture = tex("res://assets/textures/%s_nor.jpg" % name)
		m.roughness_texture = tex("res://assets/textures/%s_arm.jpg" % name)
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		m.uv1_scale = Vector3(uv_scale, uv_scale, uv_scale)
		return m)


static func paint(c: Color, rough := 0.6, metal := 0.0) -> StandardMaterial3D:
	return _c("paint:%s:%s:%s" % [c, rough, metal], func():
		var m := StandardMaterial3D.new()
		m.albedo_color = c; m.roughness = rough; m.metallic = metal
		return m)


static func shader_mat(path: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(path)
	return m


## cut = see-through variant (uses discard, so only trees covering the player get it)
static func foliage_mat(dark: Color, light: Color, cut := false) -> ShaderMaterial:
	return _c("fol:%s%s%s" % [dark, light, cut], func():
		var m := shader_mat("res://shaders/foliage_cut.gdshader" if cut else "res://shaders/foliage.gdshader")
		m.set_shader_parameter("dark", dark)
		m.set_shader_parameter("light", light)
		m.set_shader_parameter("noise_tex", noise())
		return m)


static func model(name: String) -> Node3D:
	var ps: PackedScene = _c("model:" + name, func(): return load("res://assets/models/%s/%s.gltf" % [name, name]))
	var n: Node3D = ps.instantiate()
	_no_shadow_small(n)
	return n


static func _no_shadow_small(n: Node) -> void:
	for c in n.get_children():
		_no_shadow_small(c)


# ------------------------------------------------------------------ meshes

static func _cyl(st: SurfaceTool, r0: float, r1: float, y0: float, y1: float, seg: int, v_scale: float, axis_x := false) -> void:
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var p := [
			Vector3(cos(a0) * r0, y0, sin(a0) * r0), Vector3(cos(a1) * r0, y0, sin(a1) * r0),
			Vector3(cos(a1) * r1, y1, sin(a1) * r1), Vector3(cos(a0) * r1, y1, sin(a0) * r1)]
		var n := [Vector3(cos(a0), 0, sin(a0)), Vector3(cos(a1), 0, sin(a1)), Vector3(cos(a1), 0, sin(a1)), Vector3(cos(a0), 0, sin(a0))]
		var uv := [Vector2(float(i) / seg, y0 * v_scale), Vector2(float(i + 1) / seg, y0 * v_scale),
			Vector2(float(i + 1) / seg, y1 * v_scale), Vector2(float(i) / seg, y1 * v_scale)]
		if axis_x:
			for k in 4:
				p[k] = Vector3(p[k].y, p[k].x, p[k].z)
				n[k] = Vector3(n[k].y, n[k].x, n[k].z)
		for k in [0, 2, 1, 0, 3, 2]:
			st.set_normal(n[k]); st.set_uv(uv[k]); st.add_vertex(p[k])


## Disc of fresh-cut wood (COLOR.b = 1 → wood rings in the foliage shader). UV = local radius coords.
static func _cut_cap(st: SurfaceTool, r: float, y: float, down: bool, seg: int) -> void:
	st.set_color(Color(0.5, 1.0, 1.0))
	st.set_normal(Vector3.DOWN if down else Vector3.UP)
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var p0 := Vector3(cos(a0) * r, y, sin(a0) * r)
		var p1 := Vector3(cos(a1) * r, y, sin(a1) * r)
		var tri := [Vector3(0, y, 0), p0, p1] if down else [Vector3(0, y, 0), p1, p0]
		for p in tri:
			st.set_uv(Vector2(p.x, p.z) / r)
			st.add_vertex(p)
	st.set_color(Color(0.5, 1.0, 0.0))


## Stump that matches the procedural trunk: root flare, bark sides, ringed cut top.
static func stump_mesh() -> ArrayMesh:
	return _c("stump", func():
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_color(Color(0.5, 1.0, 0.0))
		_cyl(st, 0.30, 0.19, -0.05, 0.10, 9, 0.6)
		_cyl(st, 0.19, 0.175, 0.10, 0.34, 9, 0.6)
		_cut_cap(st, 0.175, 0.34, false, 9)
		var mesh := st.commit()
		mesh.surface_set_material(0, foliage_mat(Color(0.04, 0.11, 0.06), Color(0.36, 0.55, 0.24)))
		return mesh)


## Log lying along X, radius r, length l. Two surfaces: bark + end rings.
static func log_mesh() -> ArrayMesh:
	return _c("log", func():
		var r := 0.085; var l := 0.62; var seg := 10
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_cyl(st, r, r, -l * 0.5, l * 0.5, seg, 1.2, true)
		var mesh := st.commit()
		mesh.surface_set_material(0, pbr("bark_brown_02", 1.0, Color(1.05, 0.95, 0.85)))
		st = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for side in [-1.0, 1.0]:
			for i in seg:
				var a0 := TAU * i / seg; var a1 := TAU * (i + 1) / seg
				var c := Vector3(side * l * 0.5, 0, 0)
				var p0 := Vector3(side * l * 0.5, cos(a0) * r, sin(a0) * r)
				var p1 := Vector3(side * l * 0.5, cos(a1) * r, sin(a1) * r)
				var verts := [c, p0, p1] if side > 0 else [c, p1, p0]
				for v in verts:
					st.set_normal(Vector3(side, 0, 0))
					st.set_uv(Vector2(0.5 + v.y / (2 * r) * 0.5 * 0.95, 0.5 + v.z / (2 * r) * 0.5 * 0.95) if v != c else Vector2(0.5, 0.5))
					st.add_vertex(v)
		st.commit(mesh)
		mesh.surface_set_material(1, shader_mat("res://shaders/log_end.gdshader"))
		return mesh)


## Stylized-realistic pine. variant 0..3 changes proportions.
static func pine_mesh(variant: int) -> ArrayMesh:
	return _c("pine%d" % variant, func():
		var rng := RandomNumberGenerator.new()
		rng.seed = 1234 + variant * 77
		var h_scale: float = [1.0, 1.15, 0.9, 1.3][variant % 4]
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_color(Color(0.5, 1.0, 0.0))
		_cyl(st, 0.17, 0.06, 0.0, 2.6 * h_scale, 7, 0.6)
		_cut_cap(st, 0.17, 0.0, true, 7)
		var layers := 6
		for li in layers:
			var t := float(li) / (layers - 1)
			var base_y := (0.85 + li * 0.46) * h_scale
			var height := (1.05 - t * 0.3) * h_scale
			var rad := 1.15 - t * 0.85
			var seg := 10 if OS.has_feature("mobile") else 22
			var rot := rng.randf() * TAU
			# rings from the drooping lip up to the apex: (radius factor, height factor, shade)
			var prof := [[1.0, -0.10, 0.18 + t * 0.2], [0.93, 0.08, 0.42 + t * 0.2], [0.66, 0.38, 0.62 + t * 0.2], [0.33, 0.72, 0.85], [0.0, 1.0, 1.0]]
			var rings: Array = []
			var jit: Array = []
			for i in seg:
				jit.append(rng.randf_range(0.93, 1.07))
			for pr in prof:
				var ring: Array = []
				for i in seg:
					var a := rot + TAU * i / seg
					var rr: float = rad * float(pr[0]) * float(jit[i])
					var wave := sin(a * 5.0 + li) * 0.03
					ring.append(Vector3(cos(a) * rr, base_y + height * float(pr[1]) + wave * float(pr[0]), sin(a) * rr))
				rings.append(ring)
			var center := Vector3(0, base_y + height * 0.2, 0)
			for ri in prof.size() - 1:
				var r0: Array = rings[ri]
				var r1: Array = rings[ri + 1]
				var s0: float = prof[ri][2]
				var s1: float = prof[ri + 1][2]
				for i in seg:
					var j := (i + 1) % seg
					for v in [[r0[i], s0], [r1[j], s1], [r0[j], s0], [r0[i], s0], [r1[i], s1], [r1[j], s1]]:
						var pos: Vector3 = v[0]
						st.set_color(Color(v[1], 0, 0))
						st.set_normal(((pos - center).normalized() * 0.7 + Vector3.UP * 0.55).normalized())
						st.add_vertex(pos)
			# closed underside
			var inner := Vector3(0, base_y + 0.1, 0)
			for i in seg:
				var j := (i + 1) % seg
				for v in [rings[0][i], inner, rings[0][j]]:
					st.set_color(Color(0.08, 0, 0))
					st.set_normal(Vector3.DOWN)
					st.add_vertex(v)
		var mesh := st.commit()
		mesh.surface_set_material(0, foliage_mat(Color(0.04, 0.11, 0.06), Color(0.36, 0.55, 0.24)))
		return mesh)


## Rounded broadleaf tree for decoration around the edges.
static func broadleaf_mesh(variant: int) -> ArrayMesh:
	return _c("broad%d" % variant, func():
		var rng := RandomNumberGenerator.new()
		rng.seed = 999 + variant * 31
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var th := 2.2 + variant * 0.3
		st.set_color(Color(0.5, 1.0, 0.0))
		_cyl(st, 0.24, 0.12, 0.0, th + 0.5, 7, 0.6)
		_cut_cap(st, 0.24, 0.0, true, 7)
		var f := FastNoiseLite.new()
		f.seed = variant; f.frequency = 1.3
		var blobs := 6
		for b in blobs:
			var c := Vector3(rng.randf_range(-0.8, 0.8), th + rng.randf_range(0.2, 1.4), rng.randf_range(-0.8, 0.8))
			if b == 0:
				c = Vector3(0, th + 1.0, 0)
			var r := rng.randf_range(0.75, 1.15)
			var sp := SphereMesh.new()
			sp.radius = r; sp.height = r * 1.8; sp.radial_segments = 8 if OS.has_feature("mobile") else 12; sp.rings = 5 if OS.has_feature("mobile") else 7
			var arr := sp.get_mesh_arrays()
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			for k in idx:
				var v := verts[k]
				var nn := norms[k]
				var disp := f.get_noise_3dv(v + c) * 0.28
				var p := c + v + nn * disp
				var shade := clampf(0.35 + (p.y - th) / 2.4 + nn.y * 0.25, 0.1, 1.0)
				st.set_color(Color(shade, 0, 0))
				st.set_normal((nn + (p - Vector3(0, th + 0.9, 0)).normalized()).normalized())
				st.add_vertex(p)
		var mesh := st.commit()
		mesh.surface_set_material(0, foliage_mat(Color(0.07, 0.15, 0.05), Color(0.42, 0.55, 0.20)))
		return mesh)


static func coin_mesh() -> CylinderMesh:
	return _c("coin", func():
		var m := CylinderMesh.new()
		m.top_radius = 0.1; m.bottom_radius = 0.1; m.height = 0.03; m.radial_segments = 16; m.rings = 1
		m.material = paint(Color(1.0, 0.76, 0.22), 0.28, 0.9)
		return m)


## Serving of the active chapter's product (corn, burger, fish, pizza, ribs, steak).
static func dish(product := "") -> Node3D:
	if product == "":
		product = Game.chapter().product if Game.chapters.size() > 0 else "corn"
	var root := Node3D.new()
	if product == "pizza":
		var board := cylinder(0.16, 0.025, plank_mat(), Vector3(0, 0.012, 0), root, 16)
		board.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		cylinder(0.145, 0.03, paint(Color(0.86, 0.62, 0.32), 0.7), Vector3(0, 0.04, 0), root, 18)
		cylinder(0.125, 0.012, paint(Color(0.78, 0.16, 0.08), 0.5), Vector3(0, 0.058, 0), root, 18)
		var cheese := paint(Color(1.0, 0.86, 0.45), 0.5)
		for i in 5:
			var a := i * TAU / 5.0
			cylinder(0.035, 0.01, cheese, Vector3(cos(a) * 0.07, 0.066, sin(a) * 0.07), root, 8)
		for i in 3:
			var a2 := i * TAU / 3.0 + 0.5
			cylinder(0.022, 0.012, paint(Color(0.6, 0.1, 0.06), 0.4), Vector3(cos(a2) * 0.04, 0.07, sin(a2) * 0.04), root, 8)
		return root
	var bowl := model("wooden_bowl_01")
	bowl.scale = Vector3.ONE * 1.5
	root.add_child(bowl)
	match product:
		"burger":
			var bun := paint(Color(0.86, 0.55, 0.22), 0.6)
			cylinder(0.07, 0.03, bun, Vector3(0, 0.05, 0), root, 14)
			cylinder(0.075, 0.03, paint(Color(0.32, 0.17, 0.09), 0.7), Vector3(0, 0.08, 0), root, 14)
			var ch := box(Vector3(0.13, 0.008, 0.13), paint(Color(1.0, 0.75, 0.15), 0.4), Vector3(0, 0.097, 0), root)
			ch.rotation.y = 0.6
			cylinder(0.078, 0.008, paint(Color(0.35, 0.65, 0.2), 0.6), Vector3(0, 0.104, 0), root, 12)
			var top := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.072; sm.height = 0.072; sm.is_hemisphere = true; sm.radial_segments = 14; sm.rings = 4
			sm.material = bun
			top.mesh = sm
			top.position = Vector3(0, 0.108, 0)
			root.add_child(top)
		"fish":
			var gold := paint(Color(0.85, 0.55, 0.18), 0.55)
			for i in 2:
				var f := MeshInstance3D.new()
				var cm := CapsuleMesh.new()
				cm.radius = 0.035; cm.height = 0.17; cm.radial_segments = 8; cm.rings = 2
				cm.material = gold
				f.mesh = cm
				f.rotation = Vector3(PI / 2, 0, 0.3 - i * 0.6)
				f.position = Vector3(-0.03 + i * 0.06, 0.07, 0)
				root.add_child(f)
			var chip := paint(Color(1.0, 0.82, 0.38), 0.6)
			for i in 5:
				var c := box(Vector3(0.015, 0.015, 0.09), chip, Vector3(-0.05 + i * 0.025, 0.1, 0.02), root)
				c.rotation = Vector3(0.3, i * 0.7, 0.2)
			cylinder(0.018, 0.012, paint(Color(1.0, 0.95, 0.3), 0.4), Vector3(0.06, 0.1, -0.04), root, 8)
		"ribs":
			var rib := box(Vector3(0.18, 0.04, 0.09), paint(Color(0.45, 0.13, 0.06), 0.45), Vector3(0, 0.075, 0), root)
			rib.rotation.y = 0.3
			var bone := paint(Color(0.95, 0.9, 0.8), 0.6)
			for i in 4:
				var b := cylinder(0.008, 0.12, bone, Vector3(-0.06 + i * 0.04, 0.08, 0), root, 6)
				b.rotation = Vector3(PI / 2, 0.3, 0)
		"steak":
			var st := box(Vector3(0.16, 0.035, 0.11), paint(Color(0.42, 0.2, 0.1), 0.5), Vector3(0, 0.07, 0), root)
			st.rotation.y = -0.2
			for i in 3:
				var g := box(Vector3(0.012, 0.004, 0.1), paint(Color(0.12, 0.05, 0.02), 0.8), Vector3(-0.04 + i * 0.04, 0.09, 0), root)
				g.rotation.y = 0.6
			cylinder(0.02, 0.02, paint(Color(0.3, 0.6, 0.18), 0.6), Vector3(0.06, 0.09, 0.03), root, 8)
		_:
			var corn := CapsuleMesh.new()
			corn.radius = 0.025; corn.height = 0.16; corn.radial_segments = 8; corn.rings = 2
			corn.material = paint(Color(1.0, 0.72, 0.16), 0.5)
			for i in 2:
				var mi := MeshInstance3D.new()
				mi.mesh = corn
				mi.rotation = Vector3(PI / 2, 0, 0.4 - i * 0.9)
				mi.position = Vector3(-0.02 + i * 0.04, 0.06, 0)
				root.add_child(mi)
			var saus := CapsuleMesh.new()
			saus.radius = 0.02; saus.height = 0.13; saus.radial_segments = 8; saus.rings = 2
			saus.material = paint(Color(0.55, 0.2, 0.1), 0.4)
			var sg := MeshInstance3D.new()
			sg.mesh = saus; sg.rotation = Vector3(PI / 2, 0, 1.3); sg.position = Vector3(0, 0.08, 0.02)
			root.add_child(sg)
	return root


## Cooking station for a chapter (the firepit chapter uses Poly Haven models in world.gd).
## Returns the node; meta "flame_y" = height the flames sit at.
static func cooker(kind: String) -> Node3D:
	var n := Node3D.new()
	var black := paint(Color(0.07, 0.07, 0.075), 0.55, 0.4)
	var steel := paint(Color(0.72, 0.73, 0.75), 0.25, 0.9)
	match kind:
		"grill":
			box(Vector3(1.05, 0.38, 0.62), black, Vector3(0, 0.72, 0), n)
			box(Vector3(1.0, 0.03, 0.58), steel, Vector3(0, 0.92, 0), n)
			var lid := box(Vector3(1.05, 0.05, 0.6), black, Vector3(0, 1.1, -0.36), n)
			lid.rotation.x = -1.1
			for x in [-0.45, 0.45]:
				for z in [-0.25, 0.25]:
					box(Vector3(0.05, 0.55, 0.05), black, Vector3(x, 0.27, z), n)
			box(Vector3(0.95, 0.03, 0.5), steel, Vector3(0, 0.25, 0), n)
			n.set_meta("flame_y", 0.85)
		"fryer":
			box(Vector3(1.05, 0.85, 0.66), steel, Vector3(0, 0.425, 0), n)
			for x in [-0.25, 0.25]:
				box(Vector3(0.4, 0.02, 0.48), paint(Color(0.55, 0.38, 0.1), 0.15, 0.2), Vector3(x, 0.86, 0), n)
				box(Vector3(0.3, 0.12, 0.34), paint(Color(0.15, 0.15, 0.16), 0.4, 0.8), Vector3(x, 0.92, 0), n)
				box(Vector3(0.04, 0.04, 0.3), black, Vector3(x, 0.98, 0.3), n)
			box(Vector3(1.05, 0.2, 0.06), black, Vector3(0, 1.0, -0.32), n)
			n.set_meta("flame_y", 0.6)
		"oven":
			var stone := paint(Color(0.62, 0.58, 0.52), 0.9)
			var brick := paint(Color(0.66, 0.3, 0.18), 0.85)
			box(Vector3(1.5, 0.6, 1.4), stone, Vector3(0, 0.3, 0), n)
			var dome := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.68; sm.height = 0.9; sm.is_hemisphere = true; sm.radial_segments = 20; sm.rings = 8
			sm.material = brick
			dome.mesh = sm
			dome.position = Vector3(0, 0.6, 0)
			n.add_child(dome)
			box(Vector3(0.5, 0.36, 0.3), paint(Color(0.05, 0.03, 0.02), 0.9), Vector3(0, 0.82, 0.55), n)
			box(Vector3(0.62, 0.08, 0.32), stone, Vector3(0, 1.03, 0.58), n)
			cylinder(0.1, 0.6, brick, Vector3(0.0, 1.35, -0.25), n, 10)
			n.set_meta("flame_y", 0.78)
		"smoker":
			var barrel := cylinder(0.34, 1.3, black, Vector3(0, 0.85, 0), n, 18)
			barrel.rotation.z = PI / 2
			var fire_box := box(Vector3(0.5, 0.5, 0.5), black, Vector3(0.85, 0.7, 0), n)
			fire_box.name = "FireBox"
			cylinder(0.08, 0.9, black, Vector3(-0.55, 1.55, 0), n, 10)
			for x in [-0.5, 0.5]:
				box(Vector3(0.05, 0.55, 0.5), black, Vector3(x, 0.28, 0), n)
			box(Vector3(0.04, 0.04, 0.5), steel, Vector3(0, 1.22, 0.2), n)
			n.set_meta("flame_y", 0.7)
	return n


## Recolour the shared foliage materials to the chapter's season.
static func retint_foliage(t: Dictionary) -> void:
	var pairs := [
		[foliage_mat(Color(0.04, 0.11, 0.06), Color(0.36, 0.55, 0.24)), "pine_dark", "pine_light"],
		[foliage_mat(Color(0.04, 0.11, 0.06), Color(0.36, 0.55, 0.24), true), "pine_dark", "pine_light"],
		[foliage_mat(Color(0.07, 0.15, 0.05), Color(0.42, 0.55, 0.20)), "leaf_dark", "leaf_light"],
	]
	for pr in pairs:
		var m: ShaderMaterial = pr[0]
		var d: Array = t.get(pr[1], [0.04, 0.11, 0.06])
		var l: Array = t.get(pr[2], [0.36, 0.55, 0.24])
		m.set_shader_parameter("dark", Color(d[0], d[1], d[2]))
		m.set_shader_parameter("light", Color(l[0], l[1], l[2]))


static func box(size: Vector3, mat: Material, pos := Vector3.ZERO, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	mi.mesh = bm
	mi.position = pos
	if parent:
		parent.add_child(mi)
	return mi


static func cylinder(r: float, h: float, mat: Material, pos := Vector3.ZERO, parent: Node3D = null, seg := 16) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r; cm.bottom_radius = r; cm.height = h; cm.radial_segments = seg
	cm.material = mat
	mi.mesh = cm
	mi.position = pos
	if parent:
		parent.add_child(mi)
	return mi


## Chainsaw, +Z = bar direction. Has GripRear (right hand) and GripTop (left hand) markers for IK.
static func chainsaw() -> Node3D:
	var n := Node3D.new()
	var orange := paint(Color(0.93, 0.40, 0.07), 0.42)
	var cover := paint(Color(0.16, 0.16, 0.17), 0.55, 0.2)
	var black := paint(Color(0.06, 0.06, 0.065), 0.7)
	var steel := paint(Color(0.78, 0.79, 0.8), 0.22, 0.95)
	# engine housing: orange shell, dark side cover, air filter cap
	var body := box(Vector3(0.13, 0.15, 0.27), orange, Vector3(0, 0.0, 0.0), n)
	var bm: BoxMesh = body.mesh
	bm.subdivide_depth = 0
	box(Vector3(0.135, 0.09, 0.16), cover, Vector3(0.0, -0.02, 0.06), n)
	box(Vector3(0.10, 0.035, 0.12), orange, Vector3(0, 0.09, -0.04), n)
	cylinder(0.03, 0.14, black, Vector3(0, 0.005, 0.135), n, 10).rotation.z = PI / 2   # clutch cover
	# rear handle: closed loop behind the body
	box(Vector3(0.03, 0.03, 0.17), black, Vector3(0, 0.07, -0.21), n)
	box(Vector3(0.03, 0.09, 0.03), black, Vector3(0, 0.03, -0.29), n)
	box(Vector3(0.03, 0.03, 0.10), orange, Vector3(0, -0.02, -0.25), n)
	# top (front) handle: tube arching over the body
	var tor := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.085
	tm.outer_radius = 0.105
	tm.rings = 18
	tm.ring_segments = 8
	tor.mesh = tm
	tor.material_override = black
	tor.rotation.z = PI / 2
	tor.position = Vector3(0, 0.035, 0.035)
	tor.scale = Vector3(1.0, 1.0, 0.75)
	n.add_child(tor)
	# hand guard in front of the top handle
	box(Vector3(0.12, 0.13, 0.012), black, Vector3(0, 0.1, 0.12), n).rotation.x = -0.35
	# guide bar + chain
	box(Vector3(0.024, 0.075, 0.52), black, Vector3(0, -0.005, 0.40), n)
	box(Vector3(0.018, 0.06, 0.52), steel, Vector3(0, -0.005, 0.40), n)
	var tip := cylinder(0.0375, 0.024, black, Vector3(0, -0.005, 0.66), n, 14)
	tip.rotation.z = PI / 2
	var gr := Marker3D.new()
	gr.name = "GripRear"
	gr.position = Vector3(0, 0.07, -0.22)
	n.add_child(gr)
	var gt := Marker3D.new()
	gt.name = "GripTop"
	gt.position = Vector3(-0.03, 0.13, 0.03)
	n.add_child(gt)
	return n


static func double_axe() -> Node3D:
	var n := Node3D.new()
	var wood := pbr("wood_planks_grey", 0.3, Color(0.75, 0.55, 0.38))
	var steel := paint(Color(0.7, 0.72, 0.74), 0.3, 0.9)
	cylinder(0.022, 0.8, wood, Vector3(0, 0.25, 0), n, 8)
	var head := box(Vector3(0.03, 0.16, 0.34), steel, Vector3(0, 0.6, 0), n)
	head.name = "Head"
	box(Vector3(0.045, 0.08, 0.06), paint(Color(0.2, 0.2, 0.22), 0.5, 0.6), Vector3(0, 0.6, 0), n)
	return n


static func harvester() -> Node3D:
	var n := Node3D.new()
	var green := paint(Color(0.16, 0.36, 0.14), 0.35, 0.25)
	var yellow := paint(Color(0.96, 0.7, 0.1), 0.38, 0.2)
	var dark := paint(Color(0.07, 0.07, 0.08), 0.75, 0.1)
	var tire := paint(Color(0.05, 0.05, 0.05), 0.92)
	var steel := paint(Color(0.72, 0.73, 0.75), 0.25, 0.9)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.55, 0.75, 0.85, 0.22)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.05
	glass.metallic = 0.3
	box(Vector3(1.5, 0.42, 2.7), green, Vector3(0, 0.62, -0.2), n)
	box(Vector3(1.56, 0.08, 2.76), dark, Vector3(0, 0.4, -0.2), n)
	box(Vector3(1.2, 0.36, 0.8), green, Vector3(0, 1.0, -1.15), n)
	box(Vector3(1.0, 0.04, 0.5), dark, Vector3(0, 1.19, -1.15), n)
	cylinder(0.05, 0.7, steel, Vector3(0.45, 1.45, -1.3), n, 8)
	var fy := 0.84
	box(Vector3(1.1, 0.06, 1.0), dark, Vector3(0, fy, 0.35), n)
	box(Vector3(1.1, 0.42, 0.06), green, Vector3(0, fy + 0.21, 0.85), n)
	for x in [-0.53, 0.53]:
		box(Vector3(0.06, 0.42, 1.0), green, Vector3(x, fy + 0.21, 0.35), n)
		for z in [-0.13, 0.83]:
			box(Vector3(0.06, 1.55, 0.06), dark, Vector3(x, fy + 0.78, z), n)
	box(Vector3(1.22, 0.08, 1.15), yellow, Vector3(0, fy + 1.58, 0.35), n)
	box(Vector3(1.0, 1.1, 0.02), glass, Vector3(0, fy + 0.98, 0.85), n)
	for x in [-0.53, 0.53]:
		box(Vector3(0.02, 1.1, 0.92), glass, Vector3(x, fy + 0.98, 0.35), n)
	for x in [-0.82, 0.82]:
		for z in [-1.3, -0.35, 0.75]:
			var w := cylinder(0.4, 0.3, tire, Vector3(x, 0.4, z), n, 18)
			w.rotation.z = PI / 2
			var hub := cylinder(0.17, 0.32, yellow, Vector3(x, 0.4, z), n, 10)
			hub.rotation.z = PI / 2
	var b1 := box(Vector3(0.16, 0.16, 1.1), yellow, Vector3(0.62, 1.15, 1.25), n)
	b1.rotation.x = 0.4
	var head := Node3D.new()
	head.name = "SawHead"
	head.position = Vector3(0.62, 0.72, 1.85)
	n.add_child(head)
	box(Vector3(0.42, 0.36, 0.3), yellow, Vector3.ZERO, head)
	box(Vector3(0.44, 0.08, 0.32), dark, Vector3(0, 0.2, 0), head)
	var disc := cylinder(0.34, 0.03, steel, Vector3(0, -0.22, 0.08), head, 24)
	disc.name = "Disc"
	for k in 8:
		var tooth := box(Vector3(0.05, 0.035, 0.08), steel, Vector3(cos(k * TAU / 8) * 0.34, 0, sin(k * TAU / 8) * 0.34), disc)
		tooth.rotation.y = -k * TAU / 8
	var bed := Node3D.new()
	bed.name = "Bed"
	bed.position = Vector3(0, 0.86, -0.55)
	n.add_child(bed)
	for x in [-0.66, 0.66]:
		for z in [-0.25, 0.25]:
			box(Vector3(0.07, 0.75, 0.07), yellow, Vector3(x, 0.37, z), bed)
	return n


static func truck() -> Node3D:
	var n := Node3D.new()
	var red := paint(Color(0.62, 0.12, 0.08), 0.35, 0.3)
	var dark := paint(Color(0.08, 0.08, 0.09), 0.8)
	var glass := paint(Color(0.2, 0.28, 0.32), 0.1, 0.5)
	var chrome := paint(Color(0.8, 0.8, 0.82), 0.2, 1.0)
	box(Vector3(1.9, 1.1, 1.5), red, Vector3(0, 1.15, 1.9), n)            # cab
	box(Vector3(1.7, 0.5, 0.06), glass, Vector3(0, 1.4, 2.66), n)          # windscreen
	box(Vector3(1.92, 0.12, 0.2), chrome, Vector3(0, 0.62, 2.68), n)       # bumper
	box(Vector3(2.0, 0.25, 4.2), dark, Vector3(0, 0.58, -0.6), n)          # chassis
	box(Vector3(2.1, 0.12, 3.9), pbr("wood_planks_grey", 1.0, Color(0.8, 0.62, 0.45)), Vector3(0, 0.76, -0.7), n)
	for x in [-1.0, 1.0]:
		for z in [-2.0, -1.1, 1.8]:
			var w := cylinder(0.42, 0.34, dark, Vector3(x, 0.42, z), n, 16)
			w.rotation.z = PI / 2
		for z in [-2.4, -0.7, 1.0]:
			box(Vector3(0.08, 0.9, 0.08), dark, Vector3(x * 0.98, 1.25, z), n)
	return n


static func plank_mat() -> Material:
	return pbr("wood_planks_grey", 1.0, Color(0.95, 0.75, 0.55))


static func counter() -> Node3D:
	var n := Node3D.new()
	box(Vector3(2.6, 0.95, 0.7), plank_mat(), Vector3(0, 0.475, 0), n)
	box(Vector3(2.8, 0.08, 0.85), pbr("wood_planks_grey", 0.6, Color(0.7, 0.5, 0.33)), Vector3(0, 0.99, 0), n)
	return n


static func rack() -> Node3D:
	var n := Node3D.new()
	var m := plank_mat()
	for y in [0.35, 0.8]:
		box(Vector3(1.5, 0.06, 0.6), m, Vector3(0, y, 0), n)
	for x in [-0.72, 0.72]:
		for z in [-0.27, 0.27]:
			box(Vector3(0.06, 0.85, 0.06), m, Vector3(x, 0.42, z), n)
	return n


static func cabin(w: float, d: float, wall: Color) -> Node3D:
	var n := Node3D.new()
	var m := pbr("wood_planks_grey", 1.0, wall)
	box(Vector3(w, 1.9, d), m, Vector3(0, 0.95, 0), n)
	var roof := pbr("bark_brown_02", 2.0, Color(0.75, 0.6, 0.5))
	var a := 0.5
	for s in [-1.0, 1.0]:
		var r := box(Vector3(w + 0.5, 0.12, (d * 0.5 + 0.35) / cos(a)), roof, Vector3(0, 1.9 + d * 0.25 * tan(a) + 0.02, s * d * 0.25), n)
		r.rotation.x = s * a
	# gable triangles
	for gx in [-1.0, 1.0]:
		var g := MeshInstance3D.new()
		var pm := PrismMesh.new()
		pm.size = Vector3(d, d * 0.5 * tan(a), 0.1)
		pm.material = m
		g.mesh = pm
		g.rotation.y = PI / 2
		g.position = Vector3(gx * (w * 0.5 - 0.05), 1.9 + d * 0.25 * tan(a), 0)
		n.add_child(g)
	box(Vector3(0.8, 1.3, 0.05), paint(Color(0.18, 0.11, 0.07), 0.8), Vector3(0, 0.65, d * 0.5 + 0.02), n)
	return n


static func arch(text: String) -> Node3D:
	var n := Node3D.new()
	var m := pbr("bark_brown_02", 1.0)
	for x in [-1.9, 1.9]:
		cylinder(0.16, 3.4, m, Vector3(x, 1.7, 0), n, 10)
	var beam := cylinder(0.14, 4.4, m, Vector3(0, 3.2, 0), n, 10)
	beam.rotation.z = PI / 2
	box(Vector3(3.0, 0.7, 0.08), plank_mat(), Vector3(0, 2.6, 0.05), n)
	var l := Label3D.new()
	l.text = text
	l.font = load("res://assets/fonts/BarlowCondensed-Bold.ttf")
	l.font_size = 120
	l.pixel_size = 0.004
	l.modulate = Color(0.16, 0.09, 0.04)
	l.outline_size = 0
	l.position = Vector3(0, 2.6, 0.1)
	n.add_child(l)
	return n
