class_name Stack
extends Node3D
## Visual stack of items (logs, dishes, coins). Items fly in along an arc.

enum Layout { BACK, HANDS, PILE, RACK, COUNTER, COINS, TABLE, BUNK }

var kind := "log"
var layout := Layout.BACK
var items: Array[Node3D] = []
var max_visual := 999
var sway := 0.0


func setup(k: String, l: Layout, max_vis := 999) -> Stack:
	kind = k
	layout = l
	max_visual = max_vis
	return self


func count() -> int:
	return items.size()


static func make_item(k: String) -> Node3D:
	match k:
		"log":
			var mi := MeshInstance3D.new()
			mi.mesh = Art.log_mesh()
			return mi
		"dish":
			return Art.dish()
		_:
			var c := MeshInstance3D.new()
			c.mesh = Art.coin_mesh()
			c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			return c


func slot(i: int) -> Transform3D:
	var t := Transform3D.IDENTITY
	match layout:
		Layout.BACK:
			# a second row behind the first once the column is shoulder-high, so a full bag stays readable
			var row := i / 14
			t.origin = Vector3(0, (i % 14) * 0.16 + row * 0.04, -row * 0.19)
			t.basis = Basis(Vector3.UP, 0.08 * sin(i * 1.7))
		Layout.HANDS:
			t.origin = Vector3(0, i * 0.1, 0)
			t.basis = Basis(Vector3.UP, i * 0.5)
		Layout.PILE:
			var per := 6
			var layer := i / per
			var k := i % per
			var off := 0.09 if layer % 2 == 1 else 0.0
			t.origin = Vector3(0, 0.085 + layer * 0.155, (k - 2.5) * 0.18 + off * 0.0)
			t.basis = Basis(Vector3.UP, (0.06 * sin(i * 2.3)))
		Layout.RACK:
			var shelf := i / 6
			var k2 := i % 6
			t.origin = Vector3((k2 - 2.5) * 0.24, 0.38 + shelf * 0.45, 0)
		Layout.COUNTER:
			t.origin = Vector3((i % 8 - 3.5) * 0.3, 1.03 + (i / 8) * 0.1, 0)
		Layout.COINS:
			var per2 := 9
			var layer2 := i / per2
			var k3 := i % per2
			t.origin = Vector3((k3 % 3 - 1) * 0.27, 0.018 + layer2 * 0.037, (k3 / 3 - 1) * 0.16)
			t.basis = Basis(Vector3.UP, 0.12 * sin(i * 1.9))
		Layout.BUNK:
			var per3 := 7
			var layer3 := i / per3
			var k4 := i % per3
			t.origin = Vector3((k4 - 3) * 0.175 + (0.087 if layer3 % 2 == 1 else 0.0), 0.09 + layer3 * 0.15, 0)
			t.basis = Basis(Vector3.UP, PI / 2)
		Layout.TABLE:
			t.origin = Vector3((i % 2) * 0.3 - 0.15, 0, (i / 2) * 0.3)
	return t


func _place(it: Node3D, i: int) -> void:
	it.top_level = false
	it.transform = slot(i)
	if batching:
		it.visible = false   # resting items are drawn by the batch
		_mark()


# ------------------------------------------------------------------ batching
# Resting items are hidden and drawn as one MultiMesh per mesh part, so a 20-log pile is 1 draw, not 20.

static var batching := true
static var _part_cache := {}
var _mmis: Array[MultiMeshInstance3D] = []
var _dirty := false


## [mesh (materials baked in), transform relative to the item root] for every mesh in an item.
static func _parts(k: String) -> Array:
	var key := k + (":" + String(Game.chapter().product) if k == "dish" else "")
	if _part_cache.has(key):
		return _part_cache[key]
	var out := []
	var it := make_item(k)
	var walk := [[it, Transform3D.IDENTITY]]
	while walk.size() > 0:
		var e: Array = walk.pop_back()
		var n: Node = e[0]
		var xf: Transform3D = e[1]
		if n is MeshInstance3D and n.mesh:
			var mesh: Mesh = n.mesh
			var over: Array = []
			for si in mesh.get_surface_count():
				over.append(n.material_override if n.material_override else n.get_surface_override_material(si))
			if over.any(func(m): return m != null):
				mesh = mesh.duplicate()
				for si in mesh.get_surface_count():
					if over[si]:
						if mesh is PrimitiveMesh:
							mesh.material = over[si]
						else:
							mesh.surface_set_material(si, over[si])
			out.append([mesh, xf])
		for c in n.get_children():
			if c is Node3D:
				walk.append([c, xf * c.transform])
	it.free()
	_part_cache[key] = out
	return out


func _mark() -> void:
	if not _dirty:
		_dirty = true
		_rebuild.call_deferred()


func _rebuild() -> void:
	_dirty = false
	if not is_inside_tree() or not batching:
		return
	var parts := _parts(kind)
	while _mmis.size() < parts.size():
		var mmi := MultiMeshInstance3D.new()
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = parts[_mmis.size()][0]
		mmi.multimesh = mm
		if kind == "coin":
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
		_mmis.append(mmi)
	var resting: Array[Transform3D] = []
	for i in mini(items.size(), max_visual):
		var it := items[i]
		if is_instance_valid(it) and not it.top_level and not it.is_queued_for_deletion():
			resting.append(it.transform)
	for pi in parts.size():
		var mm := _mmis[pi].multimesh
		if mm.instance_count < resting.size():
			mm.instance_count = maxi(resting.size(), maxi(mm.instance_count * 2, 8))
		mm.visible_instance_count = resting.size()
		var pxf: Transform3D = parts[pi][1]
		for i in resting.size():
			mm.set_instance_transform(i, resting[i] * pxf)


## Add an item. If from_global is given it flies there along an arc.
func receive(from_global = null, dur := 0.32, on_land: Callable = Callable()) -> void:
	var i := items.size()
	var it := make_item(kind)
	add_child(it)
	items.append(it)
	if i >= max_visual:
		it.visible = false
	if from_global == null:
		_place(it, i)
		return
	it.top_level = true
	var start: Vector3 = from_global
	it.global_position = start
	var step := func(t: float):
		if not is_instance_valid(it) or not is_inside_tree(): return
		var target := global_transform * slot(i)
		var p := start.lerp(target.origin, t)
		p.y += sin(t * PI) * (0.9 + start.distance_to(target.origin) * 0.12)
		it.global_position = p
		it.global_basis = Basis.IDENTITY.slerp(target.basis.orthonormalized(), t)
	var tw := create_tween()
	it.set_meta("tw", tw)
	tw.tween_method(step, 0.0, 1.0, dur).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func():
		if is_instance_valid(it):
			var idx := items.find(it)
			if idx >= 0:
				_place(it, idx)
		if on_land.is_valid():
			on_land.call())


## Remove the top item; returns its global position (for chaining into another fly).
func take() -> Vector3:
	if items.is_empty():
		return global_position
	var it: Node3D = items.pop_back()
	var p := it.global_position
	_kill(it)
	_mark()
	return p


func _kill(it: Node3D) -> void:
	if it.has_meta("tw"):
		var t: Tween = it.get_meta("tw")
		if t and t.is_valid():
			t.kill()
	it.queue_free()


func relayout() -> void:
	for i in items.size():
		if not items[i].top_level:
			items[i].transform = slot(i)
	_mark()


func set_count(n: int) -> void:
	while items.size() > n:
		_kill(items.pop_back())
	_mark()
	while items.size() < n:
		receive()


func top_global() -> Vector3:
	return global_transform * slot(items.size()).origin


## Fly a throwaway copy of an item from a to b, then free it.
static func fly_free(parent: Node, k: String, a: Vector3, b: Vector3, dur := 0.3, on_land: Callable = Callable()) -> void:
	var it := make_item(k)
	parent.add_child(it)
	it.top_level = true
	it.global_position = a
	var step := func(t: float):
		var p := a.lerp(b, t)
		p.y += sin(t * PI) * (0.8 + a.distance_to(b) * 0.1)
		it.global_position = p
	var tw := it.create_tween()
	tw.tween_method(step, 0.0, 1.0, dur).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func():
		if on_land.is_valid():
			on_land.call()
		it.queue_free())
