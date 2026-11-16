extends SceneTree
## Bakes Pete's 8 skinned meshes into one mesh per outfit variant (one skin, 4 weights, LODs).
## Run with the editor binary: --headless --path . --script res://tests/bake_pete.gd
## Output: res://assets/characters/pete/merged/{full,nohelmet,bare}.res + skin.res

const SRC := "res://assets/characters/pete/pete_idle_skin.fbx"
const OUT := "res://assets/characters/pete/merged/"
# surface name -> source meshes (Ch17_ prefix)
const GROUPS := {"Body": ["Body", "Boots"], "Helmet": ["Helmet"], "Vest": ["Vest"], "Shirt": ["Shirt"], "Pants": ["Pants"], "Hair": ["Hair"]}
const VARIANTS := {"full": [], "nohelmet": ["Helmet"], "bare": ["Helmet", "Vest"]}


func _initialize() -> void:
	var pete: Node3D = load(SRC).instantiate()
	var sk: Skeleton3D = pete.get_node("Skeleton3D")
	# unified skin: one bind per bone name, pose taken from the first skin that binds it
	var skin := Skin.new()
	var bind_of := {}
	var parts := {}
	for c in sk.get_children():
		if c is MeshInstance3D:
			parts[String(c.name).trim_prefix("Ch17_")] = c
			if not c.transform.is_equal_approx(Transform3D.IDENTITY):
				print("WARN non-identity transform on ", c.name)
	for p in parts.values():
		var s: Skin = p.skin
		for i in s.get_bind_count():
			var n := String(s.get_bind_name(i))
			if not bind_of.has(n):
				bind_of[n] = skin.get_bind_count()
				skin.add_named_bind(n, s.get_bind_pose(i))
			elif not skin.get_bind_pose(bind_of[n]).is_equal_approx(s.get_bind_pose(i)):
				print("WARN bind pose differs for ", n)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	ResourceSaver.save(skin, OUT + "skin.res")
	var surfaces := {}
	var ratio := float(OS.get_cmdline_user_args()[0]) if OS.get_cmdline_user_args().size() > 0 else 0.3
	for g in GROUPS:
		surfaces[g] = _decimate(_merge(GROUPS[g], parts, bind_of), ratio, g)
	for v in VARIANTS:
		var im := ImporterMesh.new()
		var tris := 0
		for g in GROUPS:
			if g in VARIANTS[v]:
				continue
			var sd: Dictionary = surfaces[g]
			im.add_surface(Mesh.PRIMITIVE_TRIANGLES, sd.arrays, [], {}, sd.material, g)
			tris += sd.arrays[Mesh.ARRAY_INDEX].size() / 3
		im.generate_lods(25.0, 60.0, [])
		var mesh: ArrayMesh = im.get_mesh()
		ResourceSaver.save(mesh, OUT + v + ".res")
		print("BAKED ", v, " surfaces=", mesh.get_surface_count(), " tris=", tris)
	pete.free()
	quit()


func _merge(names: Array, parts: Dictionary, bind_of: Dictionary) -> Dictionary:
	var V := PackedVector3Array(); var N := PackedVector3Array(); var T := PackedFloat32Array()
	var UV := PackedVector2Array(); var B := PackedInt32Array(); var W := PackedFloat32Array(); var I := PackedInt32Array()
	var material: Material
	for nm in names:
		var mi: MeshInstance3D = parts[nm]
		var m: ArrayMesh = mi.mesh
		var a := m.surface_get_arrays(0)
		if material == null:
			material = m.surface_get_material(0)
		var per := 8 if (m.surface_get_format(0) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS) else 4
		var base := V.size()
		var s: Skin = mi.skin
		var vb: PackedInt32Array = a[Mesh.ARRAY_BONES]
		var vw: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS]
		V.append_array(a[Mesh.ARRAY_VERTEX]); N.append_array(a[Mesh.ARRAY_NORMAL])
		if a[Mesh.ARRAY_TANGENT] != null and a[Mesh.ARRAY_TANGENT].size() > 0:
			T.append_array(a[Mesh.ARRAY_TANGENT])
		UV.append_array(a[Mesh.ARRAY_TEX_UV])
		var vc: int = a[Mesh.ARRAY_VERTEX].size()
		for vi in vc:
			var inf := []
			for k in per:
				var w := vw[vi * per + k]
				if w > 0.0:
					inf.append([w, int(bind_of[String(s.get_bind_name(vb[vi * per + k]))])])
			inf.sort_custom(func(x, y): return x[0] > y[0])
			inf.resize(mini(4, inf.size()))
			var sum := 0.0
			for e in inf: sum += e[0]
			for k in 4:
				if k < inf.size():
					B.append(inf[k][1]); W.append(inf[k][0] / maxf(sum, 0.0001))
				else:
					B.append(0); W.append(0.0)
		for idx in a[Mesh.ARRAY_INDEX]:
			I.append(base + idx)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = V; arrays[Mesh.ARRAY_NORMAL] = N
	if T.size() == V.size() * 4:
		arrays[Mesh.ARRAY_TANGENT] = T
	arrays[Mesh.ARRAY_TEX_UV] = UV; arrays[Mesh.ARRAY_BONES] = B; arrays[Mesh.ARRAY_WEIGHTS] = W; arrays[Mesh.ARRAY_INDEX] = I
	return {"arrays": arrays, "material": material}


## Pick the generated LOD nearest `ratio` of the triangles and drop every vertex it no longer uses
## (the compatibility renderer skins all vertices each frame, so vertex count is what costs).
func _decimate(sd: Dictionary, ratio: float, label: String) -> Dictionary:
	var arrays: Array = sd.arrays
	var full: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var im := ImporterMesh.new()
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, sd.material, label)
	im.generate_lods(25.0, 60.0, [])
	var best := full
	var want := int(full.size() * ratio)
	for li in im.get_surface_lod_count(0):
		var idx: PackedInt32Array = im.get_surface_lod_indices(0, li)
		if absi(idx.size() - want) < absi(best.size() - want):
			best = idx
	var remap := {}
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	var keys := [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TEX_UV]
	var V := PackedVector3Array(); var N := PackedVector3Array(); var UV := PackedVector2Array()
	var T := PackedFloat32Array(); var B := PackedInt32Array(); var W := PackedFloat32Array(); var I := PackedInt32Array()
	var has_t: bool = arrays[Mesh.ARRAY_TANGENT] != null
	for old in best:
		if not remap.has(old):
			remap[old] = V.size()
			V.append(arrays[Mesh.ARRAY_VERTEX][old]); N.append(arrays[Mesh.ARRAY_NORMAL][old]); UV.append(arrays[Mesh.ARRAY_TEX_UV][old])
			if has_t:
				for k in 4: T.append(arrays[Mesh.ARRAY_TANGENT][old * 4 + k])
			for k in 4:
				B.append(arrays[Mesh.ARRAY_BONES][old * 4 + k]); W.append(arrays[Mesh.ARRAY_WEIGHTS][old * 4 + k])
		I.append(remap[old])
	out[Mesh.ARRAY_VERTEX] = V; out[Mesh.ARRAY_NORMAL] = N; out[Mesh.ARRAY_TEX_UV] = UV
	if has_t: out[Mesh.ARRAY_TANGENT] = T
	out[Mesh.ARRAY_BONES] = B; out[Mesh.ARRAY_WEIGHTS] = W; out[Mesh.ARRAY_INDEX] = I
	print("  ", label, " verts ", arrays[Mesh.ARRAY_VERTEX].size(), " -> ", V.size(), "  tris ", full.size() / 3, " -> ", I.size() / 3)
	return {"arrays": out, "material": sd.material}
