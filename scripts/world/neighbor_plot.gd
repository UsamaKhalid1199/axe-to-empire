class_name NeighborPlot
extends Node3D
## The plot next door on the same road: a cheap, static picture of another chapter's place.
##   owned + visited   its ground and what is built there (cooker, counter, tables, cabins, station, truck),
##                     a cash pile on its counter and a label with the cash waiting there (Game.till(k))
##   owned, not yet    bare land with a "walk in" sign
##   locked            fenced FOR SALE land with the chapter name
## Everything solid is baked into one vertex-coloured mesh (Art.bake_flat): about 6-9 draws in all, no shadows,
## no characters. Positioned at x = Plot.offset(); children use that plot's own coordinates.

var world: Node
var k := -1
var side := -1                      # -1 = west of the active plot, +1 = east
var owned := false
var visited := false
var state: Dictionary = {}
var theme: Dictionary = {}
var near_x := 0.0                   # the edge facing the active plot (local x)
var till_label: Label3D
var pile_label: Label3D
var coins_mm: MultiMesh
var baked: MeshInstance3D


func setup(w: Node, chapter: int, s: int) -> NeighborPlot:
	world = w
	k = chapter
	side = s
	name = "Neighbor_%s" % ("west" if s < 0 else "east")
	owned = k < Game.unlocked
	state = Game.venues[k] if k < Game.venues.size() else {}
	visited = owned and not state.is_empty()
	theme = Game.chapters[k].get("theme", {})
	near_x = Plot.east(k) if side < 0 else Plot.west(k)
	position = Vector3(Plot.offset(Game.venue, k), 0, 0)
	return self


func _ready() -> void:
	_ground()
	var props := Node3D.new()
	props.name = "Props"
	add_child(props)
	# the baked mesh only depends on what is built there, so walking back and forth reuses it
	var key := _bake_key()
	if _bakes.has(key):
		baked = MeshInstance3D.new()
		baked.name = "Baked"
		baked.mesh = _bakes[key]
		baked.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		props.add_child(baked)
	else:
		if visited:
			_camp(props)
		elif owned:
			_new_land(props)
		else:
			_for_sale(props)
		baked = Art.bake_flat(props)
		if _bakes.size() > 16:
			_bakes.clear()
		_bakes[key] = baked.mesh
	_sign_labels()
	_labels()
	Game.tills_changed.connect(refresh)
	refresh()


static var _bakes: Dictionary = {}


func _bake_key() -> String:
	var b: Array = state.get("built", {}).keys()
	b.sort()
	var cr: Dictionary = state.get("crew", {})
	return "%d|%d|%s|%s|%s|%d|%s|%s" % [k, side, owned, visited, ",".join(b), mini(int(state.get("woodpile", 0)), 18),
		int(cr.get("lumberjack", 0)) > 0, int(cr.get("waiter", 0)) + int(cr.get("cook", 0)) > 0]


func _far_x() -> float:
	return near_x - Plot.NB_DEPTH if side < 0 else near_x + Plot.NB_DEPTH


func _tc(key: String, def: Color) -> Color:
	var a: Array = theme.get(key, [])
	return Color(a[0], a[1], a[2]) if a.size() >= 3 else def


func _has(id: String) -> bool:
	return state.get("built", {}).has(id)


# ------------------------------------------------------------------ ground

func _ground() -> void:
	var x0 := minf(near_x, _far_x())
	var x1 := maxf(near_x, _far_x())
	var gm := Plot.ground_mat(k, position.x, not visited, world.LOW_END)
	Plot.blend_edge(gm, -side, position.x + near_x, Game.venue)        # meets the active plot's ground
	var g := Plot.ground_plane(x0, x1, gm)
	g.name = "Ground"
	add_child(g)
	if theme.get("water", false):
		add_child(Plot.lake_node())         # the same lake as world._lake (shared mesh)


# ------------------------------------------------------------------ an owned, built plot

func _camp(r: Node3D) -> void:
	var wall := _tc("wall", Color(1.35, 1.1, 0.85))
	var truck := Art.truck()
	truck.position = world.TRUCK_POS
	truck.rotation.y = -0.25
	r.add_child(truck)
	_road_sign(r, SIGN_AT)
	if theme.get("water", false):
		Art.box(Vector3(5.0, 0.12, 1.4), Art.plank_mat(), Vector3(18.5, 0.25, 4.0), r)
	_road_on(r)
	if _has("campfire"):
		_cooker(r, world.FIRE_POS[0])
		Art.box(Vector3(1.3, 0.1, 1.3), Art.plank_mat(), world.PILE_POS + Vector3(0, 0.05, 0), r)
		var logs := mini(int(state.get("woodpile", 0)), 18)
		for i in logs:
			var lg := MeshInstance3D.new()
			lg.mesh = Art.log_mesh()
			lg.position = world.PILE_POS + Vector3(0, 0.185 + (i / 6) * 0.155, ((i % 6) - 2.5) * 0.18)
			lg.rotation.y = PI / 2
			r.add_child(lg)
		var rk := Art.rack()
		rk.position = world.RACK_POS
		r.add_child(rk)
		var ct := Art.counter()
		ct.position = world.COUNTER_POS
		r.add_child(ct)
		if int(state.get("crew", {}).get("waiter", 0)) + int(state.get("crew", {}).get("cook", 0)) > 0:
			_figure(r, world.COUNTER_POS + Vector3(0.6, 0, -0.9), PI, Color(0.2, 0.42, 0.7))
	if _has("fire_2"):
		_cooker(r, world.FIRE_POS[1])
	if int(state.get("crew", {}).get("lumberjack", 0)) > 0:
		_figure(r, world.PILE_POS + Vector3(0.9, 0, 0.9), -0.6, Color(0.75, 0.2, 0.12))
	for id in ["tables_1", "tables_2"]:
		if _has(id):
			for c in world.TABLES[id]:
				_table(r, c)
	if _has("shop"):
		var cab := Art.cabin(2.6, 2.2, wall)
		cab.position = world.SHOP_POS
		r.add_child(cab)
	if _has("crew_hut"):
		var cab2 := Art.cabin(3.0, 2.4, wall.darkened(0.08))
		cab2.position = world.CREW_POS
		cab2.rotation.y = -PI / 2
		r.add_child(cab2)
	if _has("special"):
		_special(r, wall)


## Simplified cooker per chapter (the real ones have flames, lights and timers).
func _cooker(r: Node3D, p: Vector3) -> void:
	var kind := String(Game.chapters[k].cooker)
	if kind == "firepit":
		var stone := Art.paint(Color(0.45, 0.43, 0.4), 0.95)
		for i in 8:
			var a := i * TAU / 8.0
			Art.box(Vector3(0.28, 0.22, 0.22), stone, p + Vector3(cos(a) * 0.48, 0.11, sin(a) * 0.48), r).rotation.y = -a
		Art.cylinder(0.26, 0.3, Art.paint(Color(0.12, 0.14, 0.18), 0.4, 0.5), p + Vector3(0, 0.4, 0), r, 10)
		for i in 3:
			var lg := MeshInstance3D.new()
			lg.mesh = Art.log_mesh()
			lg.position = p + Vector3(0, 0.12, 0)
			lg.rotation = Vector3(0, i * TAU / 3.0, 0.25)
			r.add_child(lg)
	else:
		var ck := Art.cooker(kind)
		ck.position = p
		r.add_child(ck)


func _table(r: Node3D, c: Vector3) -> void:
	var style := String(Game.chapters[k].get("dining", "picnic"))
	var plank := Art.plank_mat()
	if style == "round":
		var cloth := Art.paint(Color(0.96, 0.95, 0.92), 0.85)
		Art.cylinder(0.95, 0.06, cloth, c + Vector3(0, 0.64, 0), r, 14)
		Art.cylinder(0.97, 0.22, cloth, c + Vector3(0, 0.52, 0), r, 14)
		Art.cylinder(0.08, 0.6, Art.paint(Color(0.18, 0.15, 0.13), 0.5), c + Vector3(0, 0.3, 0), r, 6)
		for sx in [-1.0, 1.0]:
			for ez in [-1.0, 1.0]:
				Art.cylinder(0.22, 0.42, plank, c + Vector3(sx * 0.74, 0.21, ez * 0.62), r, 8)
	else:
		Art.box(Vector3(0.9, 0.07, 2.1), plank, c + Vector3(0, 0.66, 0), r)
		for sx in [-1.0, 1.0]:
			Art.box(Vector3(0.32, 0.06, 2.1), plank, c + Vector3(sx * 0.72, 0.4, 0), r)
			for ez in [-0.85, 0.85]:
				Art.box(Vector3(0.08, 0.64, 0.08), plank, c + Vector3(sx * 0.3, 0.32, ez), r)
	if style in ["parasol", "round"]:
		var at := c + Vector3(0, 0, -1.55)
		Art.cylinder(0.04, 2.3, Art.paint(Color(0.9, 0.88, 0.84), 0.4), at + Vector3(0, 1.15, 0), r, 6)
		var cm := CylinderMesh.new()
		cm.top_radius = 0.05
		cm.bottom_radius = 0.95
		cm.height = 0.5
		cm.radial_segments = 8
		cm.material = Art.paint(_tc("parasol", Color(0.82, 0.16, 0.1)), 0.7)
		var shade := MeshInstance3D.new()
		shade.mesh = cm
		shade.position = at + Vector3(0, 2.3, 0)
		r.add_child(shade)


## The chapter's signature station, as boxes (positions match specials.gd).
func _special(r: Node3D, wall: Color) -> void:
	match Game.special_type(k):
		"drive_thru":
			var p := Specials.KIOSK
			Art.box(Vector3(2.6, 2.2, 1.6), Art.pbr("wood_planks_grey", 1.0, wall), p + Vector3(0, 1.1, 0), r)
			Art.box(Vector3(2.9, 0.12, 1.9), Art.pbr("bark_brown_02", 2.0, Color(0.6, 0.48, 0.4)), p + Vector3(0, 2.27, 0), r)
			for i in 6:
				var col := Color(0.82, 0.14, 0.1) if i % 2 == 0 else Color(0.96, 0.94, 0.9)
				Art.box(Vector3(0.3, 0.05, 0.7), Art.paint(col, 0.6), p + Vector3(-0.75 + i * 0.3, 1.98, 1.1), r).rotation.x = 0.35
			Art.box(Vector3(1.5, 0.75, 0.06), Art.paint(Color(0.15, 0.2, 0.24), 0.1), p + Vector3(0, 1.45, 0.81), r)
			Art.box(Vector3(1.6, 0.8, 0.12), Art.paint(Color(0.95, 0.75, 0.2), 0.4), p + Specials.SIGN_ON_ROOF, r)
		"raft":
			var bark := Art.pbr("bark_brown_02")
			for i in 7:
				Art.cylinder(0.17, 3.0, bark, Specials.RAFT_POS + Vector3(0, 0.05, (i - 3) * 0.33), r, 6).rotation.z = PI / 2
			Art.cylinder(0.05, 1.8, bark, Specials.RAFT_POS + Vector3(-1.2, 1.0, 0), r, 6)
			Art.box(Vector3(0.04, 0.6, 0.9), Art.paint(Color(0.92, 0.88, 0.78), 0.9), Specials.RAFT_POS + Vector3(-1.2, 1.5, 0.45), r)
		"fireplace":
			var p := Specials.HEARTH
			var stone := Art.paint(Color(0.6, 0.56, 0.52), 0.92)
			var dark := Art.paint(Color(0.45, 0.42, 0.4), 0.95)
			Art.box(Vector3(2.8, 0.35, 1.5), dark, p + Vector3(0, 0.175, 0.1), r)
			Art.box(Vector3(2.6, 1.7, 0.45), stone, p + Vector3(0, 0.85, -0.45), r)
			Art.box(Vector3(0.55, 1.5, 0.9), stone, p + Vector3(-1.02, 0.75, -0.05), r)
			Art.box(Vector3(0.55, 1.5, 0.9), stone, p + Vector3(1.02, 0.75, -0.05), r)
			Art.box(Vector3(1.2, 2.4, 0.7), stone, p + Vector3(0, 2.85, -0.45), r)
			Art.box(Vector3(1.4, 0.18, 0.85), dark, p + Vector3(0, 4.1, -0.45), r)
			Art.box(Vector3(3.0, 0.16, 0.6), Art.plank_mat(), p + Vector3(0, 1.58, 0.05), r)
			Art.box(Vector3(1.45, 1.1, 0.05), Art.paint(Color(0.05, 0.035, 0.03), 0.95), p + Vector3(0, 0.88, -0.2), r)
		"bell":
			var p := Specials.BELL
			var wood := Art.pbr("bark_brown_02")
			for x in [-0.85, 0.85]:
				Art.cylinder(0.1, 3.0, wood, p + Vector3(x, 1.5, 0), r, 6)
			Art.cylinder(0.09, 2.0, wood, p + Vector3(0, 2.9, 0), r, 6).rotation.z = PI / 2
			for s in [-1.0, 1.0]:
				Art.box(Vector3(2.3, 0.08, 0.75), Art.paint(Color(0.62, 0.18, 0.09), 0.6), p + Vector3(0, 3.25, s * 0.3), r).rotation.x = s * 0.55
			var cm := CylinderMesh.new()
			cm.top_radius = 0.2
			cm.bottom_radius = 0.5
			cm.height = 0.75
			cm.radial_segments = 12
			cm.material = Art.paint(Color(0.9, 0.66, 0.22), 0.22)
			var bm := MeshInstance3D.new()
			bm.mesh = cm
			bm.position = p + Vector3(0, 2.4, 0)
			r.add_child(bm)
		"van":
			var v := Node3D.new()
			v.position = Specials.VAN
			v.rotation.y = PI / 2
			r.add_child(v)
			var white := Art.paint(Color(0.93, 0.93, 0.9), 0.35)
			var dark := Art.paint(Color(0.07, 0.07, 0.08), 0.8)
			Art.box(Vector3(3.8, 1.5, 1.7), white, Vector3(0.2, 1.15, 0), v)
			Art.box(Vector3(0.06, 0.6, 1.5), Art.paint(Color(0.2, 0.28, 0.32), 0.1), Vector3(-1.72, 1.45, 0), v)
			for x in [-1.2, 1.3]:
				for z in [-0.82, 0.82]:
					Art.cylinder(0.36, 0.25, dark, Vector3(x, 0.36, z), v, 10).rotation.x = PI / 2


## A blocky crew member standing at their post (static, part of the baked mesh).
func _figure(r: Node3D, p: Vector3, yaw: float, shirt: Color) -> void:
	var n := Node3D.new()
	n.position = p
	n.rotation.y = yaw
	r.add_child(n)
	var pants := Art.paint(Color(0.2, 0.22, 0.28), 0.8)
	var skin := Art.paint(Color(0.93, 0.72, 0.56), 0.7)
	for x in [-0.1, 0.1]:
		Art.box(Vector3(0.15, 0.8, 0.18), pants, Vector3(x, 0.4, 0), n)
	Art.box(Vector3(0.44, 0.62, 0.26), Art.paint(shirt, 0.8), Vector3(0, 1.1, 0), n)
	for x in [-0.29, 0.29]:
		Art.box(Vector3(0.12, 0.55, 0.14), Art.paint(shirt, 0.8), Vector3(x, 1.12, 0.04), n)
	var sm := SphereMesh.new()
	sm.radius = 0.17
	sm.height = 0.36
	sm.radial_segments = 10
	sm.rings = 6
	sm.material = skin
	var head := MeshInstance3D.new()
	head.mesh = sm
	head.position = Vector3(0, 1.6, 0)
	n.add_child(head)
	Art.box(Vector3(0.38, 0.08, 0.38), Art.paint(Color(0.95, 0.75, 0.2), 0.6), Vector3(0, 1.76, 0), n)


const SIGN_AT := Vector3(13.4, 0, 7.6)          # = world._chapter_props


func _road_sign(r: Node3D, at: Vector3) -> void:
	var wood := Art.pbr("bark_brown_02")
	for x in [-0.9, 0.9]:
		Art.cylinder(0.07, 2.4, wood, at + Vector3(x, 1.2, 0), r, 6)
	Art.box(Vector3(2.3, 0.75, 0.1), Art.plank_mat(), at + Vector3(0, 2.1, 0), r)


## Text on the signs (Label3Ds are not baked, so they are made whether or not the mesh came from the cache).
func _sign_labels() -> void:
	var l := Label3D.new()
	l.font = load("res://assets/fonts/BarlowCondensed-Bold.ttf")
	l.modulate = Color(0.18, 0.1, 0.04)
	var nm := String(Game.chapters[k].name).to_upper()
	if visited:
		l.text = nm
		l.font_size = 76
		l.pixel_size = 0.004
		l.position = SIGN_AT + Vector3(0, 2.1, 0.06)
		l.name = "SignLabel"
	else:
		l.text = ("OPEN" if owned else "FOR SALE") + "\n" + nm
		l.font_size = 64
		l.pixel_size = 0.0052
		l.line_spacing = -8.0
		l.position = _board_at() + Vector3(0, 2.0, 0.07)
		l.name = "BoardLabel"
	add_child(l)


# ------------------------------------------------------------------ land that is not yours (yet)

func _inward() -> float:
	return -1.0 if side < 0 else 1.0          # from the near edge into this plot


## A fence along the near edge (leaving the road open, so the road visibly runs on) and a sign.
func _for_sale(r: Node3D) -> void:
	var x := near_x + _inward() * 0.45
	var wood := Art.pbr("bark_brown_02")
	var rail := Art.plank_mat()
	for seg in [[-6.5, Plot.ROAD_GAP.x - 0.3], [Plot.ROAD_GAP.y + 0.6, 15.6]]:
		var z0: float = seg[0]
		var z1: float = seg[1]
		var n := int(ceil((z1 - z0) / 2.0))
		for i in n + 1:
			Art.box(Vector3(0.14, 1.2, 0.14), wood, Vector3(x, 0.6, lerpf(z0, z1, float(i) / n)), r)
		for y in [0.45, 0.95]:
			Art.box(Vector3(0.06, 0.12, z1 - z0), rail, Vector3(x, y, (z0 + z1) * 0.5), r)
	# a striped barrier across the road: the way on is closed until the gate opens
	for i in 5:
		var col := Color(0.85, 0.15, 0.1) if i % 2 == 0 else Color(0.96, 0.94, 0.9)
		Art.box(Vector3(0.12, 0.22, 0.9), Art.paint(col, 0.6), Vector3(x, 0.85, Plot.ROAD_GAP.x + 0.45 + i * 0.9), r)
	for z in [Plot.ROAD_GAP.x + 0.1, Plot.ROAD_GAP.y + 0.3]:
		Art.box(Vector3(0.16, 1.0, 0.16), wood, Vector3(x, 0.5, z), r)
	_board(r, "FOR SALE", Color(0.75, 0.12, 0.08))
	_road_on(r, false)


func _new_land(r: Node3D) -> void:
	_board(r, "OPEN", Color(0.2, 0.5, 0.18))
	_road_on(r)


## Beside the road just past the edge, on the north side facing the camera (south of the road it stood under
## the camera and showed its back), clear of the lake at the Lakeside plot's rounded east end.
func _board_at() -> Vector3:
	return Vector3(near_x + _inward() * 2.1, 0, Plot.ROAD_GAP.x - 1.7)


## The road visibly runs on: white edge posts along both sides for a few metres into this plot and, where the
## player can walk in, two arrows painted on the road at the crossing. Part of the baked mesh (no extra draws).
func _road_on(r: Node3D, walk_in := true) -> void:
	var white := Art.paint(Color(0.95, 0.94, 0.9), 0.6)
	var red := Art.paint(Color(0.85, 0.15, 0.1), 0.5)
	for i in 4:
		var x := near_x + _inward() * (1.6 + i * 3.2)
		for z in [Plot.ROAD_GAP.x + 0.15, Plot.ROAD_GAP.y - 0.75]:
			Art.box(Vector3(0.14, 0.8, 0.14), white, Vector3(x, 0.4, z), r)
			Art.box(Vector3(0.15, 0.12, 0.15), red, Vector3(x, 0.68, z), r)
	if not walk_in:
		return
	var paint := Art.paint(Color(0.97, 0.95, 0.86), 0.8)
	for j in 2:
		var tip := near_x + _inward() * (1.0 + j * 1.6)
		for s in [-1.0, 1.0]:
			# a chevron pointing into this plot: two bars meeting at the tip
			var bar := Art.box(Vector3(1.0, 0.02, 0.2), paint, Vector3(tip - _inward() * 0.33, 0.025, Plot.ROAD_Z + s * 0.33), r)
			bar.rotation.y = s * _inward() * PI / 4.0


func _board(r: Node3D, _head: String, col: Color) -> void:
	# faces the camera (+z), standing beside the road like the road signs
	var at := _board_at()
	var wood := Art.pbr("bark_brown_02")
	for dx in [-1.0, 1.0]:
		Art.cylinder(0.08, 2.6, wood, at + Vector3(dx, 1.3, 0), r, 6)
	Art.box(Vector3(2.4, 1.15, 0.1), Art.paint(Color(0.96, 0.93, 0.84), 0.8), at + Vector3(0, 2.05, 0), r)
	Art.box(Vector3(2.4, 0.3, 0.12), Art.paint(col, 0.6), at + Vector3(0, 2.5, 0), r)


# ------------------------------------------------------------------ labels + cash

func _labels() -> void:
	till_label = Label3D.new()
	till_label.name = "TillLabel"
	till_label.font = UI.font_bold()
	till_label.font_size = 64
	till_label.pixel_size = LABEL_PX
	till_label.outline_size = 16
	till_label.outline_modulate = Color(0.08, 0.05, 0.02, 0.9)
	till_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	till_label.line_spacing = -6.0
	# just past the edge, over the road and above the player's head on screen. A portrait view only shows a few
	# metres beyond the edge, and the HUD's button column covers the right of the screen, so the label is
	# centred on the edge (the camera leans toward the edge there, see world.cam_aim). The venues' road signs
	# stand further north (SIGN_AT), clear of it.
	till_label.position = Vector3(near_x if side < 0 else near_x - 0.6, 3.4, Plot.ROAD_Z - 0.4)
	add_child(till_label)
	if not visited or not _has("campfire"):
		return
	# the cash pile on that place's counter (the same spot the coin zone collects from on arrival)
	coins_mm = MultiMesh.new()
	coins_mm.transform_format = MultiMesh.TRANSFORM_3D
	coins_mm.mesh = Art.coin_mesh()
	coins_mm.instance_count = 54
	for i in 54:
		var layer := i / 9
		var q := i % 9
		coins_mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, 0.12 * sin(i * 1.9)),
			world.COIN_POS + Vector3((q % 3 - 1) * 0.27, 0.018 + layer * 0.037, (q / 3 - 1) * 0.16)))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "CashPile"
	mmi.multimesh = coins_mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	pile_label = Label3D.new()
	pile_label.name = "PileLabel"
	pile_label.font = UI.font_bold()
	pile_label.font_size = 64
	pile_label.pixel_size = 0.005
	pile_label.outline_size = 14
	pile_label.outline_modulate = Color(0.08, 0.05, 0.02, 0.9)
	pile_label.modulate = UI.CASH
	pile_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	pile_label.position = world.COIN_POS + Vector3(0, 1.5, 0)
	add_child(pile_label)


const LABEL_PX := 0.0082          # 1.7x the first version: readable on a 720-wide phone
const LABEL_MAX_W := 3.9           # metres


func _cue(s: String) -> String:
	return "‹ " + s if side < 0 else s + " ›"


func till() -> int:
	return Game.till(k) if visited else 0


## Updates the cash pile and labels (Game.tills_changed).
func refresh() -> void:
	var nm := String(Game.chapters[k].name).to_upper()
	var cash := till()
	var text := ""
	# the arrow says which way along the road it lies
	if not owned:
		text = _cue(nm) + "\nFOR SALE"
		till_label.modulate = Color(1.0, 0.86, 0.6)
	elif not visited:
		text = _cue("WALK IN") + "\n" + nm
		till_label.modulate = Color(0.75, 1.0, 0.65)
	else:
		# the cue gets its own line: one "WALK TO <NAME>" line was too wide for a portrait screen
		text = _cue("WALK TO") + "\n" + nm + ("\n%s waiting" % UI.cash(cash) if cash > 0 else "")
		till_label.modulate = Color(1, 1, 1)
	if text != till_label.text:
		till_label.text = text
		# long names shrink a little so the label never runs under the HUD buttons or off screen
		var w := till_label.font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, till_label.font_size).x
		till_label.pixel_size = minf(LABEL_PX, LABEL_MAX_W / maxf(1.0, w))
	if coins_mm:
		coins_mm.visible_instance_count = mini(54, int(ceil(cash / 5.0)))
	if pile_label:
		pile_label.text = UI.cash(cash) if cash > 0 else ""
		pile_label.visible = cash > 0
