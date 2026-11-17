class_name Specials
extends Node3D
## Each chapter after the first has one signature station with its own mechanic:
##   drive_thru (Shack)  cars queue on the road, dishes go through the window, they pay 1.5x by card
##   raft (Lake)         logs go on a raft that sails to the sawmill and comes back paying 3x the truck price
##   fireplace (Lodge)   a log-burning hearth; while it is lit guests pay +50% and wait longer
##   bell (Smokehouse)   ring it for a 30 s harvest-fair rush: crowds of guests paying double
##   van (Hotel)         dishes go in a room-service van that delivers them for 2x; VIP guests pay 3x
## State that must survive a reload lives in Game.sp.

var world: Node
var type := ""
var built := false
var zone: Zone
var root: Node3D
var _label: Label3D

# drive-thru
const KIOSK := Vector3(10.2, 0, 9.3)
const CAR_Z := 12.9
const CAR_STOP_X := 10.2
const CAR_GAP := 3.4
const DRIVE_CAP := 6
var kiosk_stack: Stack
var cars: Array = []            # {node, order, got, waited, state, x, t}
var _car_t := 4.0

# raft
const RAFT_DOCK := Vector3(14.3, 0, 1.8)
const RAFT_POS := Vector3(17.9, 0.08, 1.8)
const RAFT_CAP := 16
const RAFT_AWAY := 20.0
var raft: Node3D
var raft_stack: Stack
var _idle_t := 0.0

# fireplace
const HEARTH := Vector3(10.6, 0, 4.4)
const FIRE_CAP := 16
const BURN_S := 6.0
var hearth_flames: CPUParticles3D
var hearth_stack: Stack
var _burn_t := 0.0

# bell
const BELL := Vector3(9.9, 0, 0.4)
const RUSH_S := 30.0
const BELL_CD := 75.0
var bell_mesh: Node3D
var _swing := 0.0

# van
const VAN := Vector3(10.7, 0, 5.4)
const VAN_CAP := 10
const VAN_AWAY := 20.0
var van: Node3D
var van_stack: Stack


func setup(w: Node) -> Specials:
	world = w
	type = Game.special_type()
	return self


## Where the build pad (and later the station's zone) sits.
func pad_pos() -> Vector3:
	match type:
		"drive_thru": return KIOSK + Vector3(0, 0, -1.35)
		"raft": return RAFT_DOCK
		"fireplace": return HEARTH + Vector3(0, 0, 1.75)
		"bell": return BELL + Vector3(0, 0, 1.3)
		"van": return VAN + Vector3(-1.75, 0, 0)
	return Vector3.ZERO


func spawn(r: Node3D) -> void:
	root = r
	built = true
	match type:
		"drive_thru": _build_drive()
		"raft": _build_raft()
		"fireplace": _build_hearth()
		"bell": _build_bell()
		"van": _build_van()


func _z(kind: String, text: String, icon := "", size := Vector2(2.3, 2.0)) -> void:
	zone = world._zone("special", kind, pad_pos(), size, Color("#FFD978"), text, icon)


func _sign(text: String, pos: Vector3, size := 64) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = UI.font_bold()
	l.font_size = size
	l.pixel_size = 0.005
	l.outline_size = 14
	l.outline_modulate = Color(0.08, 0.05, 0.02, 0.9)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.position = pos
	root.add_child(l)
	return l


# ------------------------------------------------------------------ builds

func _build_drive() -> void:
	var wall: Color = world._tc("wall", Color(1.3, 1.05, 0.8))
	var body := Art.box(Vector3(2.6, 2.2, 1.6), Art.pbr("wood_planks_grey", 1.0, wall), KIOSK + Vector3(0, 1.1, 0), root)
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	Art.box(Vector3(2.9, 0.12, 1.9), Art.pbr("bark_brown_02", 2.0, Color(0.6, 0.48, 0.4)), KIOSK + Vector3(0, 2.27, 0), root)
	for i in 6:      # red and white awning over the window
		var col := Color(0.82, 0.14, 0.1) if i % 2 == 0 else Color(0.96, 0.94, 0.9)
		var aw := Art.box(Vector3(0.3, 0.05, 0.7), Art.paint(col, 0.6), KIOSK + Vector3(-0.75 + i * 0.3, 1.98, 1.1), root)
		aw.rotation.x = 0.35
	Art.box(Vector3(1.5, 0.75, 0.06), Art.paint(Color(0.15, 0.2, 0.24), 0.1, 0.4), KIOSK + Vector3(0, 1.45, 0.81), root)
	Art.box(Vector3(1.8, 0.08, 0.5), Art.plank_mat(), KIOSK + Vector3(0, 1.0, 0.98), root)
	var post := Art.cylinder(0.08, 3.4, Art.paint(Color(0.2, 0.2, 0.22), 0.4, 0.6), KIOSK + Vector3(1.9, 1.7, 1.4), root, 8)
	post.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	Art.box(Vector3(1.6, 0.8, 0.12), Art.paint(Color(0.95, 0.75, 0.2), 0.4), KIOSK + Vector3(1.9, 3.2, 1.4), root)
	var s := Label3D.new()
	s.text = "DRIVE-THRU"
	s.font = UI.font_bold()
	s.font_size = 56
	s.pixel_size = 0.005
	s.modulate = Color(0.3, 0.08, 0.04)
	s.position = KIOSK + Vector3(1.9, 3.2, 1.47)
	root.add_child(s)
	world._collider(KIOSK + Vector3(0, 1, 0), Vector3(2.6, 2, 1.6))
	kiosk_stack = Stack.new().setup("dish", Stack.Layout.COUNTER, DRIVE_CAP)
	kiosk_stack.position = KIOSK + Vector3(0.45, 0.0, 0.98)
	kiosk_stack.scale = Vector3(0.6, 1, 0.6)
	root.add_child(kiosk_stack)
	kiosk_stack.set_count(int(Game.sp.get("kiosk", 0)))
	_z("drive", "DRIVE-THRU", "res://assets/icons/dish.svg", Vector2(2.4, 1.0))


func _build_raft() -> void:
	raft = Node3D.new()
	root.add_child(raft)
	raft.position = RAFT_POS
	var bark := Art.pbr("bark_brown_02")
	for i in 7:
		var lg := Art.cylinder(0.17, 3.0, bark, Vector3(0, 0.05, (i - 3) * 0.33), raft, 8)
		lg.rotation.z = PI / 2
	Art.box(Vector3(0.1, 0.1, 2.3), Art.plank_mat(), Vector3(-1.1, 0.24, 0), raft)
	Art.box(Vector3(0.1, 0.1, 2.3), Art.plank_mat(), Vector3(1.1, 0.24, 0), raft)
	var mast := Art.cylinder(0.05, 1.8, bark, Vector3(-1.2, 1.0, 0), raft, 6)
	mast.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	Art.box(Vector3(0.04, 0.6, 0.9), Art.paint(Color(0.92, 0.88, 0.78), 0.9), Vector3(-1.2, 1.5, 0.45), raft)
	raft_stack = Stack.new().setup("log", Stack.Layout.PILE)
	raft_stack.position = Vector3(0.2, 0.2, 0)
	raft_stack.rotation.y = PI / 2
	raft.add_child(raft_stack)
	raft_stack.set_count(int(Game.sp.get("raft", 0)))
	_label = _sign("", RAFT_POS + Vector3(0, 2.4, 0), 56)
	_z("raft", "RAFT", "res://assets/icons/log.svg")
	if float(Game.sp.get("away", 0.0)) > 0.0:
		raft.visible = false


func _build_hearth() -> void:
	# an outdoor stone hearth facing the camp, with a mantel, chimney and its own log store
	var stone := Art.paint(Color(0.6, 0.56, 0.52), 0.92)
	var dark_stone := Art.paint(Color(0.45, 0.42, 0.4), 0.95)
	var parts := [
		[Vector3(2.8, 0.35, 1.5), Vector3(0, 0.175, 0.1), dark_stone],      # hearth slab
		[Vector3(2.6, 1.7, 0.45), Vector3(0, 0.85, -0.45), stone],          # back wall
		[Vector3(0.55, 1.5, 0.9), Vector3(-1.02, 0.75, -0.05), stone],      # left pillar
		[Vector3(0.55, 1.5, 0.9), Vector3(1.02, 0.75, -0.05), stone],       # right pillar
		[Vector3(1.2, 2.4, 0.7), Vector3(0, 2.85, -0.45), stone],           # chimney
		[Vector3(1.4, 0.18, 0.85), Vector3(0, 4.1, -0.45), dark_stone],     # chimney cap
	]
	for pr in parts:
		var b := Art.box(pr[0], pr[2], HEARTH + pr[1], root)
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	Art.box(Vector3(3.0, 0.16, 0.6), Art.plank_mat(), HEARTH + Vector3(0, 1.58, 0.05), root)
	Art.box(Vector3(1.45, 1.1, 0.05), Art.paint(Color(0.05, 0.035, 0.03), 0.95), HEARTH + Vector3(0, 0.88, -0.2), root)
	for k in 3:
		var lg := MeshInstance3D.new()
		lg.mesh = Art.log_mesh()
		lg.position = HEARTH + Vector3(-0.3 + k * 0.3, 0.42, 0.0)
		lg.rotation = Vector3(0, PI / 2 + (k - 1) * 0.3, 0)
		root.add_child(lg)
	world._collider(HEARTH + Vector3(0, 1, -0.2), Vector3(2.8, 2, 1.3))
	hearth_stack = Stack.new().setup("log", Stack.Layout.PILE)
	hearth_stack.position = HEARTH + Vector3(2.0, 0.0, 0.1)
	root.add_child(hearth_stack)
	hearth_stack.set_count(int(Game.sp.get("fuel", 0)))
	hearth_flames = _flames(HEARTH + Vector3(0, 0.55, 0.0))
	_label = _sign("", HEARTH + Vector3(0, 2.3, 0.5), 60)
	_z("fireplace", "FIREPLACE", "res://assets/icons/log.svg", Vector2(2.2, 1.4))


func _build_bell() -> void:
	# a fairground bell frame facing the camp: two posts, a beam, a little gabled roof and a brass bell
	var wood := Art.pbr("bark_brown_02")
	for x in [-0.85, 0.85]:
		var p := Art.cylinder(0.1, 3.0, wood, BELL + Vector3(x, 1.5, 0), root, 8)
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var beam := Art.cylinder(0.09, 2.0, wood, BELL + Vector3(0, 2.9, 0), root, 8)
	beam.rotation.z = PI / 2
	var roof_m := Art.paint(Color(0.62, 0.18, 0.09), 0.6)
	for s in [-1.0, 1.0]:
		var r := Art.box(Vector3(2.3, 0.08, 0.75), roof_m, BELL + Vector3(0, 3.25, s * 0.3), root)
		r.rotation.x = s * 0.55
		r.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	bell_mesh = Node3D.new()
	bell_mesh.position = BELL + Vector3(0, 2.85, 0)
	root.add_child(bell_mesh)
	var cm := CylinderMesh.new()
	cm.top_radius = 0.2
	cm.bottom_radius = 0.5
	cm.height = 0.75
	cm.radial_segments = 16
	cm.material = Art.paint(Color(0.9, 0.66, 0.22), 0.22, 0.9)
	var bm := MeshInstance3D.new()
	bm.mesh = cm
	bm.position.y = -0.45
	bell_mesh.add_child(bm)
	var rope := Art.cylinder(0.025, 1.6, Art.paint(Color(0.85, 0.75, 0.55), 0.9), Vector3(0, -1.5, 0.05), bell_mesh, 6)
	rope.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world._collider(BELL + Vector3(0, 1, 0), Vector3(2.0, 2, 0.4))
	_label = _sign("", BELL + Vector3(0, 3.9, 0), 60)
	_z("bell", "RING", "res://assets/icons/star.svg", Vector2(2.1, 1.7))


func _build_van() -> void:
	van = _vehicle(Color(0.93, 0.93, 0.9), 3.8, true)
	root.add_child(van)
	van.position = VAN
	van.rotation.y = PI / 2       # nose toward the road
	var l := Label3D.new()
	l.text = "ROOM SERVICE"
	l.font = UI.font_bold()
	l.font_size = 48
	l.pixel_size = 0.005
	l.modulate = Color(0.55, 0.38, 0.12)
	l.position = Vector3(-0.3, 1.35, -0.93)
	l.rotation.y = PI
	van.add_child(l)
	van_stack = Stack.new().setup("dish", Stack.Layout.RACK, VAN_CAP)
	van_stack.position = Vector3(-1.0, 0.45, 0)
	van_stack.rotation.y = PI / 2
	van_stack.scale = Vector3(0.6, 0.6, 0.6)
	van.add_child(van_stack)
	van_stack.set_count(int(Game.sp.get("van", 0)))
	world._collider(VAN + Vector3(0, 1, 0), Vector3(1.9, 2, 3.8))
	_label = _sign("", VAN + Vector3(0, 2.8, 0), 56)
	_z("van", "LOAD", "res://assets/icons/dish.svg", Vector2(1.8, 2.2))
	if float(Game.sp.get("away", 0.0)) > 0.0:
		van.visible = false


## Box-built road vehicle, nose toward -X. `boxy` = van body, else a car.
func _vehicle(col: Color, length: float, boxy: bool) -> Node3D:
	var n := Node3D.new()
	var paint := Art.paint(col, 0.35, 0.35)
	var dark := Art.paint(Color(0.07, 0.07, 0.08), 0.8)
	var glass := Art.paint(Color(0.18, 0.26, 0.32), 0.1, 0.5)
	if boxy:
		var b := Art.box(Vector3(length, 1.55, 1.8), paint, Vector3(0, 1.15, 0), n)
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		Art.box(Vector3(0.06, 0.6, 1.6), glass, Vector3(-length * 0.5 - 0.01, 1.45, 0), n)
	else:
		var b2 := Art.box(Vector3(length, 0.55, 1.6), paint, Vector3(0, 0.62, 0), n)
		b2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		Art.box(Vector3(length * 0.5, 0.5, 1.45), glass, Vector3(0.1, 1.12, 0), n)
		Art.box(Vector3(length * 0.48, 0.06, 1.47), paint, Vector3(0.1, 1.38, 0), n)
	for x in [-length * 0.32, length * 0.32]:
		for z in [-0.82, 0.82]:
			var w := Art.cylinder(0.3, 0.22, dark, Vector3(x, 0.3, z), n, 12)
			w.rotation.x = PI / 2
	return n


func _flames(p: Vector3) -> CPUParticles3D:
	var f := CPUParticles3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.5, 0.5)
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	fm.vertex_color_use_as_albedo = true
	fm.albedo_texture = world._soft_dot()
	qm.material = fm
	f.mesh = qm
	f.amount = 22
	f.lifetime = 0.8
	f.position = p
	f.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	f.emission_box_extents = Vector3(0.1, 0.05, 0.4)
	f.direction = Vector3.UP
	f.spread = 10.0
	f.gravity = Vector3(0, 1.4, 0)
	f.initial_velocity_min = 0.3
	f.initial_velocity_max = 0.8
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.85, 0.4, 0.9))
	ramp.set_color(1, Color(0.9, 0.2, 0.05, 0.0))
	f.color_ramp = ramp
	root.add_child(f)
	return f


# ------------------------------------------------------------------ tick

func tick(delta: float) -> void:
	if not built:
		return
	match type:
		"drive_thru": _tick_drive(delta)
		"raft": _tick_raft(delta)
		"fireplace": _tick_hearth(delta)
		"bell": _tick_bell(delta)
		"van": _tick_van(delta)


func _tick_drive(delta: float) -> void:
	_car_t -= delta * world.car_rate()
	if _car_t <= 0.0:
		_car_t = world.spawn_interval() * 1.9 * randf_range(0.8, 1.2)
		if cars.size() < 3:
			_spawn_car()
	var slot := 0
	for c in cars.duplicate():
		var n: Node3D = c.node
		match c.state:
			"arrive":
				var tx: float = CAR_STOP_X + slot * CAR_GAP
				c.x = move_toward(c.x, tx, delta * 7.0)
				if c.x <= tx + 0.01 and slot == 0:
					c.state = "wait"
			"wait":
				c.waited += delta
				c.t -= delta
				if c.t <= 0.0 and kiosk_stack.count() > 0:
					c.t = 0.22
					Stack.fly_free(world, "dish", kiosk_stack.take(), n.global_position + Vector3(0, 1.0, 0), 0.25)
					Game.sp["kiosk"] = kiosk_stack.count()
					c.got += 1
					Sfx.play("pop", -10.0, 1.1)
					if c.got >= c.order:
						var amount: int = int(round(c.order * Game.dish_price() * 1.5 * world.price_mult() * boost()))
						var score: float = 5.0 if c.waited < 18.0 else (4.0 if c.waited < 32.0 else 3.0)
						world.card_paid(n.global_position, amount, score, c.order)
						c.state = "leave"
				if c.state == "wait" and c.waited > float(Game.cfg.customers.patience):
					world.customer_angry(n)
					c.state = "leave"
			"leave":
				c.x -= delta * 9.0
				if c.x < -26.0:
					n.queue_free()
					cars.erase(c)
					continue
		n.position.x = c.x
		_bubble(c)
		if c.state != "leave":
			slot += 1
	if zone:
		var waiting := 0
		for c in cars:
			if c.state != "leave":
				waiting += 1
		zone.set_text("DRIVE-THRU" if waiting == 0 else "%d CAR%s" % [waiting, "S" if waiting > 1 else ""])


func _spawn_car() -> void:
	var cols := [Color(0.75, 0.12, 0.1), Color(0.15, 0.32, 0.62), Color(0.88, 0.7, 0.18), Color(0.2, 0.45, 0.28), Color(0.85, 0.85, 0.82), Color(0.25, 0.25, 0.28)]
	var n := _vehicle(cols[randi() % cols.size()], 3.2, false)
	root.add_child(n)
	n.position = Vector3(26.0, 0, CAR_Z)
	var l := Label3D.new()
	l.font = UI.font_bold()
	l.font_size = 72
	l.pixel_size = 0.0045
	l.outline_size = 16
	l.outline_modulate = Color(0.1, 0.06, 0.02)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.position = Vector3(0, 2.0, 0)
	n.add_child(l)
	cars.append({"node": n, "order": randi_range(2, 4), "got": 0, "waited": 0.0, "state": "arrive", "x": 26.0, "t": 0.0, "label": l})


func _bubble(c: Dictionary) -> void:
	var l: Label3D = c.label
	l.visible = c.state == "wait" or (c.state == "arrive" and c.x < 20.0)
	if l.visible:
		l.text = "%d" % (c.order - c.got)
		var urg: float = c.waited / float(Game.cfg.customers.patience)
		l.modulate = Color(1, 1, 1).lerp(Color("#FF6B5B"), clampf((urg - 0.5) * 2.0, 0.0, 1.0))


func _tick_raft(delta: float) -> void:
	var away := float(Game.sp.get("away", 0.0))
	if away > 0.0:
		away -= delta
		Game.sp["away"] = away
		if away <= 0.0:
			_raft_return()
		_label.text = "AT THE MILL %d s" % ceili(maxf(away, 0.0))
		zone.set_text("RAFT AWAY")
		return
	var n := raft_stack.count()
	_idle_t += delta
	if n >= RAFT_CAP or (n >= 6 and _idle_t > 10.0):
		_raft_depart()
		return
	_label.text = "%d / %d LOGS" % [n, RAFT_CAP]
	zone.set_text("RAFT %d/%d" % [n, RAFT_CAP])
	raft.position.y = RAFT_POS.y + sin(Time.get_ticks_msec() * 0.002) * 0.04


func _raft_depart() -> void:
	var n := raft_stack.count()
	Game.sp["paid"] = int(round(n * int(Game.cfg.log_sell_price) * 3 * boost()))
	Game.sp["away"] = RAFT_AWAY
	Game.sp["raft"] = 0
	var tw := raft.create_tween()
	tw.tween_property(raft, "position", RAFT_POS + Vector3(14, 0, -6), 2.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		raft.visible = false
		raft_stack.set_count(0))
	Game.toast.emit("Raft away: %d logs to the sawmill" % n)
	Sfx.play("build", -6.0)


func _raft_return() -> void:
	var paid := int(Game.sp.get("paid", 0))
	Game.sp["away"] = 0.0
	Game.sp["paid"] = 0
	_idle_t = 0.0
	raft_stack.set_count(0)
	raft.position = RAFT_POS + Vector3(14, 0, -6)
	raft.visible = true
	var tw := raft.create_tween()
	tw.tween_property(raft, "position", RAFT_POS, 2.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if paid > 0:
		Game.add_coins(paid)
		Game.stats.sold += paid / maxi(1, int(Game.cfg.log_sell_price) * 3)
		world.float_text.emit("SAWMILL +%s" % UI.fmt(paid), RAFT_DOCK + Vector3(0, 2.4, 0), UI.GOLD_LIGHT)
		Game.toast.emit("Raft is back: +%s" % UI.cash(paid))
		Sfx.play("cash", -4.0)


func _tick_hearth(delta: float) -> void:
	var fuel := int(Game.sp.get("fuel", 0))
	if fuel > 0:
		_burn_t += delta
		if _burn_t >= BURN_S:
			_burn_t = 0.0
			fuel -= 1
			Game.sp["fuel"] = fuel
			if hearth_stack.count() > 0:
				Stack.fly_free(world, "log", hearth_stack.take(), HEARTH + Vector3(0.45, 0.4, 0), 0.35)
			if fuel == 0:
				Game.toast.emit("The fireplace went out: guests are cold")
	hearth_flames.emitting = fuel > 0
	hearth_flames.scale = Vector3.ONE * (0.7 + 0.6 * fuel / float(FIRE_CAP))
	_label.text = ("WARM  +50%%  %d/%d" % [fuel, FIRE_CAP]) if fuel > 0 else "COLD: ADD LOGS"
	_label.modulate = Color("#FFB45B") if fuel > 0 else Color("#9FD4FF")
	zone.set_text("%d/%d" % [fuel, FIRE_CAP])


func _tick_bell(delta: float) -> void:
	var rush := float(Game.sp.get("rush", 0.0))
	var cd := float(Game.sp.get("cd", 0.0))
	if rush > 0.0:
		rush -= delta
		Game.sp["rush"] = maxf(rush, 0.0)
		if rush <= 0.0:
			Game.sp["cd"] = BELL_CD
			Game.toast.emit("The fair rush is over")
		_label.text = "FAIR RUSH  x2  %d s" % ceili(maxf(rush, 0.0))
		_label.modulate = Color("#FFD978")
		zone.set_text("RUSH!")
	elif cd > 0.0:
		cd -= delta
		Game.sp["cd"] = maxf(cd, 0.0)
		_label.text = "NEXT FAIR IN %d s" % ceili(maxf(cd, 0.0))
		_label.modulate = Color(1, 1, 1, 0.85)
		zone.set_text("%d s" % ceili(maxf(cd, 0.0)))
	else:
		_label.text = "RING FOR A RUSH!"
		_label.modulate = Color("#8EE07A")
		zone.set_text("RING")
	_swing = maxf(0.0, _swing - delta * 0.6)
	bell_mesh.rotation.x = sin(Time.get_ticks_msec() * 0.012) * 0.6 * _swing


func ring() -> bool:
	if float(Game.sp.get("rush", 0.0)) > 0.0 or float(Game.sp.get("cd", 0.0)) > 0.0:
		return false
	Game.sp["rush"] = RUSH_S
	_swing = 1.0
	Sfx.play("build", -2.0, 1.4)
	Sfx.play("cash", -6.0, 0.8)
	world._shake = 0.3
	world.fx_burst(BELL + Vector3(0, 2.6, 0), Color(1, 0.85, 0.4), 30)
	Game.toast.emit("Harvest fair rush! Prices x2 for 30 s")
	world.spawn_t = 0.0
	return true


func rush_active() -> bool:
	return type == "bell" and built and float(Game.sp.get("rush", 0.0)) > 0.0


func _tick_van(delta: float) -> void:
	var away := float(Game.sp.get("away", 0.0))
	if away > 0.0:
		away -= delta
		Game.sp["away"] = away
		if away <= 0.0:
			_van_return()
		_label.text = "DELIVERING %d s" % ceili(maxf(away, 0.0))
		zone.set_text("OUT")
		return
	var n := van_stack.count()
	_idle_t += delta
	if n >= VAN_CAP or (n >= 3 and _idle_t > 8.0):
		_van_depart()
		return
	_label.text = "%d / %d ORDERS" % [n, VAN_CAP]
	zone.set_text("LOAD %d/%d" % [n, VAN_CAP])


func _van_depart() -> void:
	var n := van_stack.count()
	Game.sp["paid"] = int(round(n * Game.dish_price() * 2.0 * boost()))
	Game.sp["dishes"] = n
	Game.sp["away"] = VAN_AWAY
	Game.sp["van"] = 0
	var tw := van.create_tween()
	tw.tween_property(van, "position", VAN + Vector3(0, 0, 7.0), 1.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(van, "position", VAN + Vector3(16, 0, 7.0), 1.4)
	tw.tween_callback(func():
		van.visible = false
		van_stack.set_count(0))
	Game.toast.emit("Room service: %d orders on the way" % n)
	Sfx.play("build", -6.0)


func _van_return() -> void:
	var paid := int(Game.sp.get("paid", 0))
	var n := int(Game.sp.get("dishes", 0))
	Game.sp["away"] = 0.0
	Game.sp["paid"] = 0
	Game.sp["dishes"] = 0
	_idle_t = 0.0
	van_stack.set_count(0)
	van.visible = true
	van.position = VAN + Vector3(16, 0, 7.0)
	var tw := van.create_tween()
	tw.tween_property(van, "position", VAN + Vector3(0, 0, 7.0), 1.4)
	tw.tween_property(van, "position", VAN, 1.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if paid > 0:
		world.card_paid(VAN, paid, 5.0, n)
		Game.toast.emit("Room service paid +%s" % UI.fmt(paid))


# ------------------------------------------------------------------ player and crew hand-offs

## Player standing on the station's zone.
func zone_action(z: Zone) -> bool:
	if z != zone:
		return false
	var p: Player = world.player
	match z.kind:
		"drive":
			z.tick = 0.12
			dish_put(p.hands)
		"raft", "fireplace":
			z.tick = 0.07
			log_put(p.back)
		"van":
			z.tick = 0.12
			dish_put(p.hands)
		"bell":
			z.tick = 0.5
			ring()
		_:
			z.tick = 999.0
	return true


## How many dishes this station could take right now (drive-thru, van).
func dish_need() -> int:
	if not built:
		return 0
	match type:
		"drive_thru":
			var want := 0
			for c in cars:
				if c.state != "leave":
					want += c.order - c.got
			return clampi(want - kiosk_stack.count(), 0, DRIVE_CAP - kiosk_stack.count())
		"van":
			if float(Game.sp.get("away", 0.0)) > 0.0:
				return 0
			return VAN_CAP - van_stack.count()
	return 0


func dish_pos() -> Vector3:
	return zone.global_position if zone else Vector3.ZERO


func dish_put(s: Stack) -> bool:
	if s.count() == 0 or dish_need() <= 0:
		return false
	match type:
		"drive_thru":
			kiosk_stack.receive(s.take(), 0.22)
			Game.sp["kiosk"] = kiosk_stack.count()
		"van":
			van_stack.receive(s.take(), 0.22)
			Game.sp["van"] = van_stack.count()
			_idle_t = 0.0
		_:
			return false
	Sfx.play("pop", -10.0, 1.0)
	return true


## Logs this station could take right now (raft, fireplace).
func log_need() -> int:
	if not built:
		return 0
	match type:
		"raft":
			return 0 if float(Game.sp.get("away", 0.0)) > 0.0 else RAFT_CAP - raft_stack.count()
		"fireplace":
			return FIRE_CAP - int(Game.sp.get("fuel", 0))
	return 0


func log_pos() -> Vector3:
	return zone.global_position if zone else Vector3.ZERO


func log_put(s: Stack) -> bool:
	if s.count() == 0 or log_need() <= 0:
		return false
	match type:
		"raft":
			raft_stack.receive(s.take(), 0.35)
			Game.sp["raft"] = raft_stack.count()
			_idle_t = 0.0
		"fireplace":
			hearth_stack.receive(s.take(), 0.3)
			Game.sp["fuel"] = int(Game.sp.get("fuel", 0)) + 1
		_:
			return false
	Sfx.play("clack", -8.0, 1.0, 0.04)
	return true


# ------------------------------------------------------------------ effects on guests

## Station level: every level makes the station pay 4% more.
func boost() -> float:
	return 1.0 + 0.04 * Game.levels.station


## The crew only works the station from level 5 (index 4) on; before that it's the player's job.
func crew_allowed() -> bool:
	return built and Game.levels.station >= 4


func price_mult() -> float:
	if not built:
		return 1.0
	if type == "fireplace" and int(Game.sp.get("fuel", 0)) > 0:
		return 1.5
	if rush_active():
		return 2.0
	return 1.0


func patience_mult() -> float:
	if built and type == "fireplace" and int(Game.sp.get("fuel", 0)) > 0:
		return 1.4
	return 1.0


func spawn_mult() -> float:
	return 0.3 if rush_active() else 1.0


func extra_queue() -> int:
	return 3 if rush_active() else 0


## Hotel guests: about one in six is a VIP (bigger order, pays 3x, less patient).
func roll_vip() -> bool:
	return type == "van" and built and randf() < 0.17 * (1.0 + 0.02 * Game.levels.station)


# ------------------------------------------------------------------ objective hints

func objective(p: Player) -> Dictionary:
	if not built:
		return {}
	match type:
		"drive_thru":
			if p.hands.count() > 0 and dish_need() > 0 and (world.counter_count() >= 3 or world.queue.is_empty()):
				return {"text": "Serve the drive-thru car", "pos": dish_pos()}
		"van":
			if p.hands.count() > 0 and dish_need() > 0 and (world.counter_count() >= 3 or world.queue.is_empty()):
				return {"text": "Load the room-service van (pays 2x)", "pos": dish_pos()}
		"raft":
			if p.back.count() > 0 and log_need() > 0 and (world.pile_full() or p.back.count() >= Game.bag_cap()):
				return {"text": "Load the timber raft (3x price)", "pos": log_pos()}
		"fireplace":
			var fuel := int(Game.sp.get("fuel", 0))
			if p.back.count() > 0 and fuel < 5 and Game.woodpile >= 4:
				return {"text": "Feed the lodge fireplace" if fuel > 0 else "Light the fireplace: guests pay +50%", "pos": log_pos()}
		"bell":
			if not rush_active() and float(Game.sp.get("cd", 0.0)) <= 0.0 and (Game.rack >= 6 or Game.woodpile >= 12):
				return {"text": "Ring the fair bell for a rush!", "pos": zone.global_position}
	return {}
