class_name Wardrobe
## Player outfits: catalog (data/outfits.json), buy/equip against Game.profile, and applying the look
## to a CharacterRig. Static only. Only the player wears outfits; crew and customers keep their variants.

const PATH := "res://data/outfits.json"
const SLOTS := ["shirt", "hat", "pants"]
const DEFAULTS := {"shirt": "shirt_orange", "hat": "hat_none", "pants": "pants_dark"}

static var _items: Array = []
static var _by_id: Dictionary = {}
static var _hat_meshes: Dictionary = {}


static func catalog() -> Array:
	if _items.is_empty():
		var f := FileAccess.open(PATH, FileAccess.READ)
		if f:
			var d = JSON.parse_string(f.get_as_text())
			if d is Dictionary:
				_items = d.get("items", [])
		for it in _items:
			_by_id[it.id] = it
	return _items


static func item(id: String) -> Dictionary:
	catalog()
	return _by_id.get(id, {})


static func items_for(slot: String) -> Array:
	return catalog().filter(func(it): return it.slot == slot)


## The Game autoload, looked up at runtime so this class also compiles in --script tools/tests.
static func _game() -> Node:
	return (Engine.get_main_loop() as SceneTree).root.get_node("Game")


static func _profile() -> Dictionary:
	var p: Dictionary = _game().profile
	if not p.has("owned"):
		p["owned"] = DEFAULTS.values()
	if not p.has("equipped"):
		p["equipped"] = DEFAULTS.duplicate()
	return p


static func owned(id: String) -> bool:
	return id in _profile().owned or (id in DEFAULTS.values())


static func equipped(slot: String) -> String:
	var id: String = _profile().equipped.get(slot, DEFAULTS.get(slot, ""))
	return id if item(id).size() > 0 else DEFAULTS.get(slot, "")


static func price(id: String) -> int:
	return int(item(id).get("price", 0))


static func stars_needed(id: String) -> int:
	return int(item(id).get("stars", 0))


static func color(id: String, key := "color") -> Color:
	var a: Array = item(id).get(key, [1, 1, 1])
	return Color(a[0], a[1], a[2])


## "" when the item can be bought now, otherwise the reason ("Owned", "Need 6 ★", "Need $2,000").
static func can_buy(id: String) -> String:
	var it := item(id)
	if it.is_empty():
		return "Unknown item"
	if owned(id):
		return "Owned"
	var st := stars_needed(id)
	if st > 0 and _game().total_stars() < st:
		return "Need %d ★" % st
	var p := price(id)
	if p > _game().coins:
		return "Need $" + money(p)
	return ""


static func buy(id: String) -> bool:
	if can_buy(id) != "":
		return false
	var p := price(id)
	if p > 0 and not _game().spend(p):
		return false
	var pr := _profile()
	if not id in pr.owned:
		pr.owned.append(id)
	pr.equipped[item(id).slot] = id
	_changed()
	return true


static func equip(id: String) -> bool:
	var it := item(id)
	if it.is_empty() or not owned(id):
		return false
	var pr := _profile()
	if pr.equipped.get(it.slot, "") == id:
		return true
	pr.equipped[it.slot] = id
	_changed()
	return true


static func _changed() -> void:
	_game().profile_changed.emit()
	_game().save_game()


## Applies the equipped look. preview = {slot: id} to try something on (shop preview) without owning it.
static func apply(rig: CharacterRig, preview := {}) -> void:
	if rig == null:
		return
	var look := {}
	for s in SLOTS:
		look[s] = item(preview.get(s, equipped(s)))
	rig.wear(look.shirt, look.hat, look.pants)


## "250,000"
static func money(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


# ------------------------------------------------------------------ hats

## Head-bone space: +Y up the skull, +Z = face. Hat band sits at HAT_BASE.
const HAT_BASE := Vector3(0, 0.145, 0.03)


## One merged, vertex-coloured mesh per hat (one draw call). null for "none" / built-in helmet.
static func hat_mesh(it: Dictionary) -> ArrayMesh:
	var kind: String = it.get("mesh", "none")
	if kind == "none":
		return null
	var key: String = it.get("id", kind)
	if _hat_meshes.has(key):
		return _hat_meshes[key]
	var a: Array = it.get("color", [0.5, 0.5, 0.5])
	var b: Array = it.get("secondary", a)
	var ca := Color(a[0], a[1], a[2])
	var cb := Color(b[0], b[1], b[2])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var o := HAT_BASE
	match kind:
		"beanie":
			_add(st, _sphere(0.118, 10, 4, true), Transform3D(Basis.from_scale(Vector3(1.0, 1.05, 1.08)), o + Vector3(0, 0.0, 0)), ca)
			_add(st, _cyl(0.121, 0.121, 0.045, 10), Transform3D(Basis.from_scale(Vector3(1, 1, 1.08)), o + Vector3(0, 0.005, 0)), cb)
			_add(st, _sphere(0.032, 6, 3, false), Transform3D(Basis.IDENTITY, o + Vector3(0, 0.13, 0)), cb)
		"cap":
			_add(st, _sphere(0.114, 10, 4, true), Transform3D(Basis.from_scale(Vector3(1.0, 0.82, 1.08)), o), ca)
			_add(st, _cyl(0.085, 0.085, 0.012, 10), Transform3D(Basis.from_scale(Vector3(1.0, 1.0, 0.9)), o + Vector3(0, 0.005, 0.105)), cb)
			_add(st, _sphere(0.014, 5, 2, true), Transform3D(Basis.IDENTITY, o + Vector3(0, 0.092, 0)), cb)
		"hardhat":
			_add(st, _sphere(0.126, 10, 4, true), Transform3D(Basis.from_scale(Vector3(1.0, 0.92, 1.08)), o), ca)
			_add(st, _cyl(0.15, 0.15, 0.012, 12), Transform3D(Basis.from_scale(Vector3(1.0, 1.0, 1.1)), o + Vector3(0, 0.0, 0.01)), ca)
			_add(st, _box(Vector3(0.03, 0.03, 0.2)), Transform3D(Basis.IDENTITY, o + Vector3(0, 0.108, 0)), ca.darkened(0.08))
		"ranger":
			_add(st, _cyl(0.09, 0.108, 0.11, 10), Transform3D(Basis.from_scale(Vector3(1, 1, 1.08)), o + Vector3(0, 0.055, 0)), ca)
			_add(st, _cyl(0.11, 0.11, 0.028, 10), Transform3D(Basis.from_scale(Vector3(1, 1, 1.08)), o + Vector3(0, 0.016, 0)), cb)
			_add(st, _cyl(0.21, 0.21, 0.012, 12), Transform3D(Basis.from_scale(Vector3(1, 1, 1.05)), o), ca)
		"chef":
			_add(st, _cyl(0.112, 0.112, 0.06, 10), Transform3D(Basis.from_scale(Vector3(1, 1, 1.08)), o + Vector3(0, 0.025, 0)), ca)
			_add(st, _cyl(0.145, 0.112, 0.1, 10), Transform3D(Basis.from_scale(Vector3(1, 1, 1.05)), o + Vector3(0, 0.105, 0)), ca)
			_add(st, _sphere(0.145, 10, 3, true), Transform3D(Basis.from_scale(Vector3(1, 0.5, 1.05)), o + Vector3(0, 0.155, 0)), ca)
		_:
			return null
	var m := st.commit()
	m.surface_set_material(0, _hat_mat())
	_hat_meshes[key] = m
	return m


static func _hat_mat() -> StandardMaterial3D:
	if not _hat_meshes.has("_mat"):
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.vertex_color_is_srgb = true
		m.roughness = 0.8
		_hat_meshes["_mat"] = m
	return _hat_meshes["_mat"]


static func _sphere(r: float, seg: int, rings: int, hemi: bool) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r; s.height = r if hemi else r * 2.0
	s.is_hemisphere = hemi; s.radial_segments = seg; s.rings = rings
	return s


static func _cyl(top: float, bottom: float, h: float, seg: int) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top; c.bottom_radius = bottom; c.height = h; c.radial_segments = seg; c.rings = 0
	return c


static func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


static func _add(st: SurfaceTool, m: PrimitiveMesh, xf: Transform3D, c: Color) -> void:
	var arr := m.get_mesh_arrays()
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var nb := xf.basis.inverse().transposed()
	st.set_color(c)
	for k in idx:
		st.set_normal((nb * n[k]).normalized())
		st.add_vertex(xf * v[k])


static func tri_count(m: Mesh) -> int:
	if m == null:
		return 0
	var t := 0
	for i in m.get_surface_count():
		var ilen: int = m.surface_get_array_index_len(i)
		t += (ilen if ilen > 0 else m.surface_get_array_len(i)) / 3
	return t
