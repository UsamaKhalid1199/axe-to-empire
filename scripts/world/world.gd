extends Node3D
## Chapter 1 "Forest Camp": layout, stations, build pads, customers, crew, fires, FX, objective.

signal zone_entered(kind: String, id: String)
signal zone_exited(kind: String, id: String)
signal float_text(text: String, world_pos: Vector3, color: Color)
signal big_day_finished(won: bool, served: int, goal: int)
## The player walked along the road into the plot next door (chapter k); main.gd switches venue.
## `arrive` = where to put them there: {x, z, yaw, logs}.
signal cross_requested(k: int, arrive: Dictionary)

const SPAWN := Vector3(0, 0, -3.6)
var LOW_END := OS.has_feature("mobile")
const PILE_POS := Vector3(-2.7, 0, -2.1)
const FIRE_POS := [Vector3(-0.3, 0, -1.8), Vector3(1.9, 0, -1.8)]
const RACK_POS := Vector3(0.8, 0, 0.35)
const COUNTER_POS := Vector3(0.8, 0, 3.3)
const COIN_POS := Vector3(2.95, 0, 2.55)
const COOKER_FOOT := {               # kind -> [width x, depth z, x offset]: the cooker's footprint on the ground
	"firepit": [1.2, 1.2, 0.0], "grill": [1.1, 0.75, 0.0], "fryer": [1.1, 0.75, 0.0], "oven": [1.5, 1.45, 0.0],
	"smoker": [1.8, 0.75, 0.22]}
const COOKER_LANE := 1.0              # a gap narrower than this between the two cookers is walled off
const TRUCK_POS := Vector3(-8.2, 0, 3.6)
const SELL_POS := Vector3(-6.1, 0, 2.6)
const SHOP_POS := Vector3(6.3, 0, -2.6)
const CREW_POS := Vector3(6.6, 0, 3.4)
const GATE_POS := Vector3(-9.5, 0, 11.5)
const ROAD_Z := 11.5
const TABLE_SCALE := 0.85
const ROAD_EAST := Vector3(20, 0, 11.5)
const TABLES := {
	"tables_1": [Vector3(-3.2, 0, 4.6), Vector3(-3.2, 0, 8.7)],
	"tables_2": [Vector3(5.0, 0, 5.6), Vector3(5.0, 0, 9.5)],
}
const PADS := {
	"campfire": Vector3(-0.3, 0, -1.8), "tables_1": Vector3(-3.2, 0, 6.65), "shop": Vector3(5.2, 0, -0.9),
	"crew_hut": Vector3(5.0, 0, 3.4), "fire_2": Vector3(1.9, 0, -1.8), "tables_2": Vector3(5.0, 0, 7.55),
	"gate": Vector3(-7.6, 0, 11.5),
}

var player: Player
var cam: Camera3D
var trees: Array[ChopTree] = []
var zones: Array[Zone] = []
var pads: Dictionary = {}
var buildings: Dictionary = {}
var pile: Stack
var rack_stack: Stack
var counter_stack: Stack
var coin_stack: Stack
var pile_zone: Zone
var rack_zone: Zone
var serve_zone: Zone
var coin_zone: Zone
var sell_zone: Zone
var fires: Array = []          # {pos, cooking, t, ring, built}
var customers: Array = []
var queue: Array = []
var seats: Array = []          # {pos, center, by, plate}
var workers: Array = []
var spawn_t := 3.0
var cust_seed := 0
var objective := {"text": "", "pos": Vector3.ZERO}
var arrow: Node3D
var _fx_pool: Array[CPUParticles3D] = []
var _fx_i := 0
var _shake := 0.0
var _cam_target := Vector3.ZERO
var _inside: Dictionary = {}
var _engaged := {}          # zone -> player has stopped on it (actions running)
var _obj_t := 0.0
var cam_off := Vector3(0, 10.5, 8.2)
var theme: Dictionary = {}
var specials: Specials
# crowds
var group_t := 150.0
var group_left := 0
var group_gap := 0.0
var passers := 0
# golden tree
var golden: ChopTree
var golden_left := 0.0
var golden_t := 90.0
var _gold_mat: Material
var _gold_fx: Node3D
# Big Day
var bd_active := false
var bd_left := 0.0
var bd_served := 0
var bd_walkouts := 0
var bd_scores: Array = []
var bd: Dictionary = {}
var _bd_cool := 0.0
# one road: the plots next door (see plot.gd / neighbor_plot.gd)
var arrival: Dictionary = {}       # set before building: where the player enters this plot {x, z, yaw, logs}
var nb_plots: Dictionary = {}      # side (-1 west, +1 east) -> NeighborPlot
var _gap_shapes: Dictionary = {}   # side -> CollisionShape3D closing the road at that plot edge
var _nb_unlocked := -1
var _cross_armed := true           # false right after arriving at an edge, until the player steps inside
var _crossing := false
var _edge_warn_ms := -100000
var _edge_warn_msg := ""
var fence_zone: Zone               # gate prompt at a FOR SALE neighbour's fence
var _fence_prompted := false       # the gate prompt has shown since the player came to the fence
var _push_t := 0.0                 # seconds of pushing on the fence before its prompt has shown
var modal_kind := ""               # the HUD's open modal or story card ("" = none), refreshed every frame


func _tc(key: String, def: Color) -> Color:
	var a: Array = theme.get(key, [])
	return Color(a[0], a[1], a[2]) if a.size() >= 3 else def


## When true, main.gd drives the build step by step (so the loading bar moves).
var staged := false
var build_ms: Dictionary = {}       # step -> ms of the last unstaged build (walking into the next plot)


## Walking: built behind the old place while the screen fades; main.gd retints the shared foliage at the swap.
var quiet := false


func _ready() -> void:
	theme = Game.chapter().theme
	if not quiet:
		Art.retint_foliage(theme)
	if staged:
		process_mode = Node.PROCESS_MODE_DISABLED
		return
	for st in build_steps():
		var t0 := Time.get_ticks_usec()
		st[1].call()
		build_ms[String(st[0]).get_slice(" ", 0)] = (Time.get_ticks_usec() - t0) / 1000.0


## [label, step] pairs; run in order to build the venue.
func build_steps() -> Array:
	return [
		["Painting the sky", _env],
		["Laying the ground", _ground],
		["Planting the forest", _forest],
		["Scattering the wilds", _decor],
		["Raising the camp", _static_camp],
		["Walking the road", _neighbours],
		["Waking the crew", _finish_build],
		["Opening up", _open_up],
	]


var _pad_warn_ms := -100000


func _finish_build() -> void:
	apply_quality()
	player = Player.new()
	player.world = self
	ChopTree.player = player
	ChopTree.woken.clear()
	add_child(player)
	player.global_position = SPAWN
	if not arrival.is_empty():
		# came along the road (or by MAP) from the plot next door: enter at that edge, facing inward
		player.global_position = Vector3(float(arrival.x), 0, float(arrival.z))
		player.rig.rotation.y = float(arrival.get("yaw", 0.0))
		var logs := mini(int(arrival.get("logs", 0)), Game.bag_cap())
		if logs > 0:
			player.back.set_count(logs)
		var dishes := mini(int(arrival.get("dishes", 0)), int(Game.cfg.player.carry_dishes))
		if dishes > 0:
			player.hands.set_count(dishes)      # what you carry comes with you (it already left the rack)
		_cross_armed = false
	cam = Camera3D.new()
	var vsz := get_viewport().get_visible_rect().size
	cam.fov = 56.0 if vsz.x / maxf(1.0, vsz.y) < 0.5 else 52.0     # tall 20:9 phones: a bit wider so edge labels fit
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.far = 120.0
	add_child(cam)
	_cam_target = cam_aim(player.global_position)
	_place_cam(1.0)
	for i in 8:
		var p := CPUParticles3D.new()
		p.emitting = false
		p.one_shot = true
		p.explosiveness = 0.95
		add_child(p)
		_fx_pool.append(p)
	_make_arrow()
	specials = Specials.new().setup(self)
	add_child(specials)


## Last build step: the buildings, the crew, and the place starts running.
func _open_up() -> void:
	process_mode = Node.PROCESS_MODE_INHERIT
	_rebuild_all(false)
	Game.fire_story("start")
	if Game.task_i == 0 and not Game.seen.has("task_init"):
		Game._task_start()
	golden_t = randf_range(60.0, 100.0)
	if Game.refund_note > 0:
		Game.toast.emit("Gate fees refunded: +%s. Your savings now always come with you!" % UI.cash(Game.refund_note))
		Game.refund_note = 0
		Game.save_game()
	if Game.head_start_note:
		Game.head_start_note = false
		Game.toast.emit("Welcome next door! Your %s came with you, and your crew set up the %s." % [UI.cash(Game.coins), String(Game.build_def("campfire").name).to_lower()])
		var intro := String(Game.special_def().get("intro", ""))
		if intro != "":
			Game.toast.emit(intro)
	Game.state_changed.connect(_on_state_changed)


# ------------------------------------------------------------------ environment

func _env() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = _tc("sky_top", Color(0.36, 0.55, 0.8))
	sm.sky_horizon_color = _tc("sky_horizon", Color(0.8, 0.82, 0.78))
	sm.ground_horizon_color = Color(0.55, 0.55, 0.45)
	sm.ground_bottom_color = Color(0.2, 0.22, 0.15)
	sm.sun_angle_max = 30.0
	sky.sky_material = sm
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = float(theme.get("ambient", 0.55))
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.88
	env.tonemap_white = 6.0
	env.glow_enabled = not OS.has_feature("mobile")
	env.glow_intensity = 0.35
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	env.fog_enabled = not LOW_END
	env.fog_light_color = _tc("sky_horizon", Color(0.72, 0.78, 0.74)).lerp(Color(0.72, 0.78, 0.74), 0.4)
	env.fog_density = 0.0025
	env.fog_sky_affect = 0.3
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.15
	env.adjustment_contrast = 1.06
	we.environment = env
	we.name = "Env"
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(float(theme.get("sun_pitch", -52)), -38, 0)
	sun.light_color = _tc("sun", Color(1.0, 0.92, 0.8))
	sun.light_energy = float(theme.get("sun_energy", 1.45))
	sun.shadow_enabled = not LOW_END
	sun.shadow_opacity = 0.85
	sun.shadow_blur = 1.2
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 22.0 if OS.has_feature("mobile") else 32.0
	add_child(sun)


func _ground() -> void:
	# this plot's ground stops where a neighbour's begins (both share the edge vertices: no seam, no overlap)
	var x0 := Plot.west(Game.venue) if Plot.neighbour(Game.venue, -1) >= 0 else -40.0
	var x1 := Plot.east(Game.venue) if Plot.neighbour(Game.venue, 1) >= 0 else Plot.mask_x(Game.venue).y
	var gm := Plot.ground_mat(Game.venue, 0.0, false, LOW_END)
	for side in [-1, 1]:
		var nk := Plot.neighbour(Game.venue, side)
		if nk >= 0:
			Plot.blend_edge(gm, side, x0 if side < 0 else x1, nk)
	var mi := Plot.ground_plane(x0, x1, gm)
	add_child(mi)
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var ws := WorldBoundaryShape3D.new()
	cs.shape = ws
	sb.add_child(cs)
	add_child(sb)
	if theme.get("water", false):
		_lake()
	# invisible walls keep the player in the play area; the road runs on through a gap at each side edge,
	# closed by a toggled collider unless you can walk into the plot next door
	var we := Plot.west(Game.venue)
	var ee := Plot.east(Game.venue)
	var gz := Plot.ROAD_GAP
	_collider(Vector3(0, 1, -27), Vector3(40, 2, 1))
	_collider(Vector3((we + ee) * 0.5, 1, 14.5), Vector3(ee - we + 12.0, 2, 1))
	for x in [-15.5, 15.5]:
		_collider(Vector3(x, 1, (gz.x - 30.0) * 0.5), Vector3(1, 2, gz.x + 30.0))
	if ee > 15.6:
		_collider(Vector3((15.5 + ee) * 0.5, 1, gz.x - 0.5), Vector3(ee - 15.5, 2, 1))    # lakeshore road
	for side in [-1, 1]:
		var sb2 := StaticBody3D.new()
		var cs2 := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(1, 2, gz.y - gz.x + 0.4)
		cs2.shape = bs
		sb2.add_child(cs2)
		sb2.position = Vector3(we if side < 0 else ee, 1, (gz.x + gz.y) * 0.5)
		sb2.name = "RoadGap_%s" % ("west" if side < 0 else "east")
		add_child(sb2)
		_gap_shapes[side] = cs2
	_road_ends()


## Where the road has no plot next door (east of the Forest Camp, west of the last venue) it ends at a striped
## barrier instead of an invisible wall (walking into it says so: _road_tick). Baked flat: one draw each.
func _road_ends() -> void:
	for side in [-1, 1]:
		if Plot.neighbour(Game.venue, side) >= 0:
			continue
		var x: float = (Plot.west(Game.venue) if side < 0 else Plot.east(Game.venue)) + side * 0.35
		var n := Node3D.new()
		n.name = "RoadEnd_%s" % ("west" if side < 0 else "east")
		add_child(n)
		var wood := Art.paint(Color(0.36, 0.25, 0.16), 0.9)
		var z0 := Plot.ROAD_GAP.x + 0.1
		var z1 := Plot.ROAD_GAP.y - 0.3
		for z in [z0, (z0 + z1) * 0.5, z1]:
			Art.box(Vector3(0.16, 1.2, 0.16), wood, Vector3(x, 0.6, z), n)
		for y in [0.55, 1.0]:
			for i in 6:
				var col := Color(0.85, 0.15, 0.1) if (i + int(y > 0.7)) % 2 == 0 else Color(0.96, 0.94, 0.9)
				var seg := (z1 - z0) / 6.0
				Art.box(Vector3(0.1, 0.24, seg), Art.paint(col, 0.6), Vector3(x + side * 0.1, y, z0 + seg * (i + 0.5)), n)
		Art.bake_flat(n)


## Lakeside chapter: a lake along the east edge with a small dock.
func _lake() -> void:
	# rounded, wavy east end; the shore is worn ground in the ground mask (Plot.lake_sd), not a flat strip
	add_child(Plot.lake_node())
	add_child(Plot.lake_dressing())
	var dock := Art.box(Vector3(5.0, 0.12, 1.4), Art.plank_mat(), Vector3(18.5, 0.25, 4.0), self)
	dock.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for x in [16.5, 18.5, 20.5]:
		for z in [3.4, 4.6]:
			Art.cylinder(0.07, 0.6, Art.pbr("bark_brown_02"), Vector3(x, 0.0, z), self, 8)


func _seg(x: float, z: float, a: Vector2, b: Vector2, w: float) -> float:
	var p := Vector2(x, z)
	var ab := b - a
	var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return 1.0 - (p - (a + ab * t)).length() / w


func _collider(pos: Vector3, size: Vector3, rot_y := 0.0) -> void:
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	sb.add_child(cs)
	sb.position = pos
	sb.rotation.y = rot_y
	add_child(sb)


## Choppable forest. Each chapter shapes it differently (chapters.json "forest"):
##   spacing / row_gap / jitter  tree grid; clearings [[x, z, r]] meadows with rocks;
##   avenue [x0, x1] an open alley through the whole forest; thin_east x where trees thin out (lakeshore).
func _forest() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42 + Game.venue * 17
	var cfg: Dictionary = Game.cfg.tree
	var f: Dictionary = Game.chapter().get("forest", {})
	var spacing := float(f.get("spacing", 2.75))
	var row_gap := float(f.get("row_gap", 2.5))
	var jitter := float(f.get("jitter", 0.5))
	var clearings: Array = f.get("clearings", [])
	var avenue: Array = f.get("avenue", [])
	var thin_east := float(f.get("thin_east", 99.0))
	var z := -6.2
	var row := 0
	while z > -25.0:
		var x := -13.0 + (spacing * 0.42 if row % 2 == 1 else 0.0)
		while x < 13.5:
			var p := Vector3(x + rng.randf_range(-jitter, jitter), 0, z + rng.randf_range(-jitter * 0.9, jitter * 0.9))
			x += spacing
			var keep := not (absf(p.x + 1.0) < 1.2 and p.z > -12.0)   # keep the trail open
			for c in clearings:
				if Vector2(p.x - float(c[0]), p.z - float(c[1])).length() < float(c[2]):
					keep = false
			if avenue.size() == 2 and p.x > float(avenue[0]) and p.x < float(avenue[1]):
				keep = false
			if p.x > thin_east and rng.randf() < clampf((p.x - thin_east) / 6.0, 0.0, 0.85):
				keep = false
			if not keep:
				continue
			var t := ChopTree.new()
			t.setup(rng.randi() % 4, int(cfg.hp), float(cfg.regrow))
			add_child(t)
			t.position = p
			trees.append(t)
		z -= row_gap
		row += 1
	# meadows get a rock or two so they read as places, not gaps
	for c in clearings:
		var rock := Art.model("rock_moss_set_01")
		rock.position = Vector3(float(c[0]) + 0.4, 0, float(c[1]) - 0.3)
		rock.scale = Vector3.ONE * 1.2
		rock.rotation.y = rng.randf() * TAU
		add_child(rock)
	_build_tree_batch()


func _decor() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	# edge forest (not choppable), batched per mesh
	var groups := {}
	for i in (36 if LOW_END else 70):
		var p: Vector3
		var side := i % 4
		match side:
			0: p = Vector3(rng.randf_range(-24, -15.8), 0, rng.randf_range(-30, 16))
			1: p = Vector3(rng.randf_range(15.8, 24), 0, rng.randf_range(-30, 16)) if not theme.get("water", false) else Vector3(rng.randf_range(-24, -15.8), 0, rng.randf_range(-30, 16))
			2: p = Vector3(rng.randf_range(-16, 16), 0, rng.randf_range(-33, -26))
			_: p = Vector3(rng.randf_range(-22, 22), 0, rng.randf_range(16.5, 23))   # clear of the road and car lane
		var mesh: Mesh = Art.broadleaf_mesh(rng.randi() % 3) if rng.randf() < 0.45 else Art.pine_mesh(rng.randi() % 4)
		var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(1.1, 1.7)), p)
		if not _decor_clear(p):
			continue
		# one MultiMesh per (mesh, side of the map) so sides off screen are culled
		var gk := [mesh, side]
		if not groups.has(gk):
			groups[gk] = []
		groups[gk].append(xf)
	# the plots next door: their forest behind the camp and a tree line south of the road (same MultiMeshes)
	for side in [-1, 1]:
		if Plot.neighbour(Game.venue, side) < 0:
			continue
		var edge := Plot.west(Game.venue) if side < 0 else Plot.east(Game.venue)
		var n := 12 if LOW_END else 22
		for i in n:
			var south := i % 3 == 2
			# south of the road only past the old tree band (|x| > 22): near the edge they would hide the road
			var p := Vector3(edge + side * rng.randf_range(7.0 if south else 0.6, Plot.NB_DEPTH),
				0, rng.randf_range(17.5, 23.0) if south else rng.randf_range(-30.0, -7.0))
			if south and absf(p.x) < 22.0:
				continue
			var mesh: Mesh = Art.broadleaf_mesh(rng.randi() % 3) if rng.randf() < 0.45 else Art.pine_mesh(rng.randi() % 4)
			var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(1.1, 1.7)), p)
			if not _decor_clear(p):
				continue
			var gk := [mesh, 3 if south else (0 if side < 0 else 1)]
			if not groups.has(gk):
				groups[gk] = []
			groups[gk].append(xf)
	if Plot.east(Game.venue) > 30.0:
		for i in 8:     # south of the lakeshore road
			var p := Vector3(rng.randf_range(22.0, Plot.east(Game.venue) - 1.0), 0, rng.randf_range(16.5, 23.0))
			var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(1.1, 1.7)), p)
			if not _decor_clear(p):
				continue        # (all of them now: under the camera on the lakeshore road)
			var gk := [Art.pine_mesh(i % 4), 3]
			if not groups.has(gk):
				groups[gk] = []
			groups[gk].append(xf)
	for gk in groups:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = gk[0]
		mm.instance_count = groups[gk].size()
		for k in groups[gk].size():
			mm.set_instance_transform(k, groups[gk][k])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.add_to_group("edge_forest")
		add_child(mmi)
	# rocks, ferns, grass
	var spots := [[Vector3(-5.5, 0, -3.5), "rock_moss_set_01", 1.0], [Vector3(-10.8, 0, -2.2), "rock_moss_set_01", 1.3],
		[Vector3(-12, 0, 8), "rock_moss_set_01", 1.6], [Vector3(12.9, 0, -2.6), "dead_tree_trunk", 1.0],
		[Vector3(-6.5, 0, 8.5), "dead_tree_trunk", 0.9]]
	for s in spots:
		var m := Art.model(s[1])
		m.position = s[0]
		m.scale = Vector3.ONE * s[2] * (0.45 if s[1] == "rock_moss_set_01" else 1.0)
		m.rotation.y = rng.randf() * TAU
		add_child(m)
	var plants := {"fern_02": [], "grass_medium_01": []}
	for i in (24 if LOW_END else 46):
		var p := Vector3(rng.randf_range(-15, 15), 0, rng.randf_range(-26, 14))
		if _near_camp(p):
			continue
		var key := "fern_02" if rng.randf() < 0.5 else "grass_medium_01"
		plants[key].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.8, 1.3)), p))
	for key in plants:
		_scatter_model(key, plants[key])
	# a low band south of the road (fence and crops, reeds, snow drifts, hay, hedges...): on the road the bottom
	# third of the screen is that strip. One MultiMesh per prop type (2 draws), static, no shadows.
	var bx0 := Plot.west(Game.venue) - (0.0 if Plot.neighbour(Game.venue, -1) >= 0 else 12.0)
	var bx1 := Plot.east(Game.venue) + (0.0 if Plot.neighbour(Game.venue, 1) >= 0 else 12.0)
	add_child(Plot.band_node(Game.venue, bx0, bx1))


## Batches every mesh of a model into MultiMeshes: one draw per sub-mesh for all copies.
func _scatter_model(name: String, xfs: Array) -> void:
	if xfs.is_empty():
		return
	var m := Art.model(name)
	var parts: Array = []
	var stack: Array = [[m, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var it: Array = stack.pop_back()
		var n: Node3D = it[0]
		var xf: Transform3D = it[1]
		for c in n.get_children():
			if c is Node3D:
				var cx: Transform3D = xf * c.transform
				if c is MeshInstance3D and c.mesh:
					parts.append([c.mesh, cx])
				stack.append([c, cx])
	for part in parts:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = part[0]
		mm.instance_count = xfs.size()
		for k in xfs.size():
			mm.set_instance_transform(k, xfs[k] * part[1])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.add_to_group("scatter")
		add_child(mmi)
	m.free()


## Forest batching: one MultiMesh per pine variant draws every idle standing tree (1 draw instead of ~60).
var _tree_mm: Dictionary = {}


func _build_tree_batch() -> void:
	# one MultiMesh per (variant, depth band) so bands off screen are culled
	var by_variant := {}
	for t in trees:
		var key := Vector2i(t.variant, int(floor((-t.position.z - 6.0) / 6.5)))
		if not by_variant.has(key):
			by_variant[key] = []
		by_variant[key].append(t)
	for v in by_variant:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = Art.pine_mesh(v.x)
		mm.instance_count = by_variant[v].size()
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if LOW_END else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(mmi)
		_tree_mm[v] = mm
		var i := 0
		for t in by_variant[v]:
			t.batch_key = v
			t.batch_idx = i
			t.batched = false
			mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO))
			i += 1


func _batch_tree(t: ChopTree, want: bool) -> void:
	if t.batch_idx < 0 or want == t.batched or not _tree_mm.has(t.batch_key):
		return
	t.batched = want
	t.mesh.visible = not want
	var mm: MultiMesh = _tree_mm[t.batch_key]
	mm.set_instance_transform(t.batch_idx, global_transform.affine_inverse() * t.mesh.global_transform if want else Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO))


## Cheap fake firelight for phones: one additive quad on the ground, no extra light pass.
func _glow_decal(p: Vector3) -> Node3D:
	var mi := MeshInstance3D.new()
	var q := PlaneMesh.new()
	q.size = Vector2(6.5, 6.5)
	mi.mesh = q
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.62, 0.25, 0.55))
	g.set_color(1, Color(1.0, 0.45, 0.1, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 128
	gt.height = 128
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_texture = gt
	m.no_depth_test = false
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = p + Vector3(0, 0.03, 0)
	return mi


func _shadows_off(n: Node) -> void:
	if n is GeometryInstance3D:
		n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in n.get_children():
		_shadows_off(c)


const DECOR_SOUTH_Z := 2.0


## Edge-forest spots that stay empty: everything south of DECOR_SOUTH_Z, and the neighbour's camp
## (its forest, behind its camp, is kept: it reads as the next place's woods). Not on a neighbour's lake.
func _decor_clear(p: Vector3) -> bool:
	# No edge forest on or south of the road, nor just north of it (tall pines there loomed over the road
	# ends). The camera sits about 7 m south of what it looks at and 10.5 m up, and its view reaches ~2 m
	# behind itself: anywhere the player can walk, a tree between the road and z ~ 21 stands right under the
	# lens (a huge blurry blob), and one further south is never on screen.
	if p.z > DECOR_SOUTH_Z:
		return false
	for side in [-1, 1]:
		var k := Plot.neighbour(Game.venue, side)
		if k < 0:
			continue
		var edge := Plot.west(Game.venue) if side < 0 else Plot.east(Game.venue)
		var beyond := p.x < edge + 0.4 if side < 0 else p.x > edge - 0.4
		if not beyond:
			continue
		if p.z > -6.5 and p.z < 16.0:
			return false
		if Game.chapters[k].get("theme", {}).get("water", false) and p.x - Plot.offset(Game.venue, k) > 15.0 and p.z < 10.0:
			return false
	return true


func _near_camp(p: Vector3) -> bool:
	# the east side (x 9..15) hosts each chapter's signature station
	return (p.x > -9 and p.x < 15.5 and p.z > -4 and p.z < 14) or absf(p.z - ROAD_Z) < 2.6


func _static_camp() -> void:
	var truck := Art.truck()
	truck.position = TRUCK_POS
	truck.rotation.y = -0.25
	add_child(truck)
	_collider(TRUCK_POS + Vector3(0, 1, 0), Vector3(2.2, 2, 5.4), -0.25)
	var load_pile := Stack.new().setup("log", Stack.Layout.PILE)
	truck.add_child(load_pile)
	load_pile.position = Vector3(0, 0.82, -0.7)
	load_pile.rotation.y = PI / 2
	load_pile.set_count(14)
	sell_zone = _zone("sell", "sell", SELL_POS, Vector2(1.9, 1.9), Color("#FFD978"), "SELL", "res://assets/icons/truck.svg")
	# The gate pad needs no arch where the plot next door has its own fence, barrier and FOR SALE board (an arch
	# across the road 6 m before them read as a second gate). At the end of the road (the last chapter: the gate
	# starts a New Empire) the arch stays, as a sign beside the road with its name plank facing the camera.
	if Plot.neighbour(Game.venue, -1) < 0:
		var arch := Art.arch("NEW EMPIRE")
		arch.position = Vector3(GATE_POS.x, 0, Plot.ROAD_GAP.x - 1.3)
		add_child(arch)
	# lanterns and props around the camp
	for p in [Vector3(-4.2, 0, 1.2), Vector3(3.8, 0, 0.2), Vector3(-1.2, 0, 10.2), Vector3(3.6, 0, 10.2)]:
		var post := Art.cylinder(0.06, 1.6, Art.pbr("bark_brown_02"), p + Vector3(0, 0.8, 0), self, 8)
		post.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		var lan := Art.model("wooden_lantern_01")
		lan.position = p + Vector3(0, 1.6, 0)
		add_child(lan)
	var crates := Art.model("wooden_crate_01")
	crates.position = Vector3(-4.0, 0, -2.6)
	add_child(crates)
	var barrels := Art.model("wooden_barrels_01")
	barrels.position = Vector3(-6.8, 0, 0.6)
	add_child(barrels)
	_chapter_props()


## A few props that give each venue its own identity (kept to a handful of meshes for the phone).
func _chapter_props() -> void:
	var ch: Dictionary = Game.chapter()
	# road sign with the venue's name where guests arrive (north of the road, clear of the label over the
	# road at the east edge: NeighborPlot.SIGN_AT matches)
	var sign_pos := Vector3(13.4, 0, 7.6)
	var wood := Art.pbr("bark_brown_02")
	for x in [-0.9, 0.9]:
		var p := Art.cylinder(0.07, 2.4, wood, sign_pos + Vector3(x, 1.2, 0), self, 6)
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var board := Art.box(Vector3(2.3, 0.75, 0.1), Art.plank_mat(), sign_pos + Vector3(0, 2.1, 0), self)
	board.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var l := Label3D.new()
	l.text = String(ch.name).to_upper()
	l.font = load("res://assets/fonts/BarlowCondensed-Bold.ttf")
	l.font_size = 76
	l.pixel_size = 0.004
	l.modulate = Color(0.18, 0.1, 0.04)
	l.position = sign_pos + Vector3(0, 2.1, 0.06)
	add_child(l)
	var spot := Vector3(-5.3, 0, -0.5)
	match String(ch.id):
		"camp":
			var tent := MeshInstance3D.new()
			var pm := PrismMesh.new()
			pm.size = Vector3(1.8, 1.3, 2.0)
			pm.material = Art.paint(Color(0.85, 0.5, 0.18), 0.85)
			tent.mesh = pm
			tent.position = spot + Vector3(0, 0.65, 0)
			tent.rotation.y = 0.4
			tent.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			add_child(tent)
		"shack":
			var red := Art.paint(Color(0.78, 0.12, 0.08), 0.4)
			var pump := Art.box(Vector3(0.6, 1.5, 0.45), red, spot + Vector3(0, 0.75, 0), self)
			pump.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			Art.box(Vector3(0.5, 0.35, 0.47), Art.paint(Color(0.95, 0.92, 0.85), 0.3), spot + Vector3(0, 1.2, 0), self)
			Art.box(Vector3(0.9, 0.12, 0.7), Art.paint(Color(0.3, 0.3, 0.32), 0.7), spot + Vector3(0, 0.06, 0), self)
		"lake":
			var boat := Art.box(Vector3(2.2, 0.35, 0.8), Art.plank_mat(), spot + Vector3(0, 0.18, 0), self)
			boat.rotation.y = 0.5
			boat.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			var oar := Art.box(Vector3(1.6, 0.05, 0.12), wood, spot + Vector3(0.2, 0.42, 0.1), self)
			oar.rotation.y = 0.9
		"lodge":
			var snow := Art.paint(Color(0.96, 0.97, 1.0), 0.7)
			for i in 3:
				var r: float = [0.42, 0.31, 0.22][i]
				var y: float = [0.4, 1.05, 1.52][i]
				var sm := SphereMesh.new()
				sm.radius = r
				sm.height = r * 2.0
				sm.radial_segments = 10
				sm.rings = 6
				sm.material = snow
				var mi := MeshInstance3D.new()
				mi.mesh = sm
				mi.position = spot + Vector3(0, y, 0)
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
				add_child(mi)
			for x in [-0.3, 0.3]:
				var ski := Art.box(Vector3(0.08, 1.7, 0.05), Art.paint(Color(0.85, 0.2, 0.15), 0.4), spot + Vector3(1.0 + x, 0.85, 0.3), self)
				ski.rotation.z = 0.12
		"smoke":
			var hay := Art.paint(Color(0.86, 0.7, 0.32), 0.95)
			for i in 2:
				var b := Art.cylinder(0.5, 0.9, hay, spot + Vector3(i * 1.05, 0.5, 0), self, 10)
				b.rotation.x = PI / 2
				b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			var pumpkin := Art.paint(Color(0.92, 0.45, 0.08), 0.6)
			for q in [Vector3(-0.6, 0.2, 0.7), Vector3(0.4, 0.17, 0.85), Vector3(1.2, 0.22, 0.75)]:
				var sm2 := SphereMesh.new()
				sm2.radius = q.y * 1.4
				sm2.height = q.y * 2.0
				sm2.radial_segments = 10
				sm2.rings = 5
				sm2.material = pumpkin
				var pk := MeshInstance3D.new()
				pk.mesh = sm2
				pk.position = spot + q
				add_child(pk)
		"hotel":
			var stone := Art.paint(Color(0.82, 0.8, 0.76), 0.8)
			var green := Art.paint(Color(0.2, 0.42, 0.18), 0.9)
			for i in 2:
				var pos := spot + Vector3(i * 1.4, 0, 0)
				Art.box(Vector3(0.8, 0.6, 0.8), stone, pos + Vector3(0, 0.3, 0), self).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
				var sm3 := SphereMesh.new()
				sm3.radius = 0.45
				sm3.height = 0.8
				sm3.radial_segments = 10
				sm3.rings = 6
				sm3.material = green
				var bush := MeshInstance3D.new()
				bush.mesh = sm3
				bush.position = pos + Vector3(0, 0.95, 0)
				add_child(bush)


# ------------------------------------------------------------------ one road: the plots next door

func _exit_tree() -> void:
	if not retired:
		Plot.finish_jobs()      # never leave a ground-mask job running past this venue (or app exit)


## Walking (or MAP) to another place: this one is frozen as a still picture while the screen fades and the next
## place builds; main.gd frees it a little at a time afterwards. Nothing here may react to the game any more
## (the active place is already the next one), so every connection to Game from this subtree is cut.
var retired := false


func retire() -> void:
	retired = true
	process_mode = Node.PROCESS_MODE_DISABLED       # also takes its bodies and areas out of the physics space
	for sig in Game.get_signal_list():
		for c in Game.get_signal_connection_list(sig.name):
			var o = c.callable.get_object()
			if o is Node and (o == self or is_ancestor_of(o)):
				Game.disconnect(sig.name, c.callable)


## Builds (or rebuilds, when a gate opens) the static pictures of the plots west and east of this one.
func _neighbours() -> void:
	_nb_unlocked = Game.unlocked
	for side in [-1, 1]:
		var k := Plot.neighbour(Game.venue, side)
		if nb_plots.has(side):
			nb_plots[side].queue_free()
			nb_plots.erase(side)
		if k < 0:
			continue
		var np := NeighborPlot.new().setup(self, k, side)
		add_child(np)
		nb_plots[side] = np
	# the plots two steps away: their ground masks get computed on a worker thread now, so walking on is quick
	var want: Array = []
	for side in [-1, 1]:
		var k1 := Plot.neighbour(Game.venue, side)
		if k1 < 0:
			continue
		want.append([k1, false])
		var k2 := Plot.neighbour(k1, side)
		if k2 >= 0:
			want.append([k2, not (k2 < Game.unlocked and k2 < Game.venues.size() and not Game.venues[k2].is_empty())])
			want.append([k2, false])
	Plot.prefetch(want)
	if is_instance_valid(player):
		_sync_fence_zone()


## Can the player walk into the plot on that side right now? (owned, and no Big Day running)
func can_cross(side: int) -> bool:
	var k := Plot.neighbour(Game.venue, side)
	return k >= 0 and k < Game.unlocked and not bd_active


## A FOR SALE neighbour gets a gate prompt at its fence once the gate pad is up (same modal as the pad).
func _sync_fence_zone() -> void:
	var k := Plot.neighbour(Game.venue, -1)
	var want := k >= 0 and k >= Game.unlocked and pads.has("gate")
	if want == (fence_zone != null):
		return
	if want:
		fence_zone = _zone("gate_fence", "gate", Vector3(Plot.west(Game.venue) + 1.35, 0, ROAD_Z), Vector2(1.5, 2.6),
			Color("#8EE07A"), "", "res://assets/icons/gate.svg", true)
	else:
		zones.erase(fence_zone)
		fence_zone.queue_free()
		fence_zone = null


## Road edges: open/close the gaps, hand the player over to the next plot, explain a closed way.
func _road_tick() -> void:
	for side in _gap_shapes:
		var shut := not can_cross(side)
		var cs: CollisionShape3D = _gap_shapes[side]
		if cs.disabled == shut:
			cs.set_deferred("disabled", not shut)
	if _crossing:
		return
	var pp := player.global_position
	var we := Plot.west(Game.venue)
	var ee := Plot.east(Game.venue)
	if modal_kind == "gate":
		_fence_prompted = true
	elif pp.x > we + 4.0:
		_fence_prompted = false     # walked away: the next approach prompts again
	if not _cross_armed:
		_cross_armed = pp.x > we + 1.2 and pp.x < ee - 1.2
		return
	if pp.z < Plot.ROAD_GAP.x or pp.z > Plot.ROAD_GAP.y:
		return
	for side in [-1, 1]:
		var d := pp.x - we if side < 0 else ee - pp.x       # distance to that edge
		if d > 0.9:
			continue
		if can_cross(side):
			if d < 0.35:
				_cross(side)
			return
		# pushing against a closed way (or the end of the road)
		var k := Plot.neighbour(Game.venue, side)
		if player._vel.x * side < 0.5:
			_push_t = 0.0
			continue
		if modal_kind != "":
			continue            # a toast would only hide behind the modal
		var msg := "The road ends here"
		if k >= 0:
			msg = "Finish the Big Day first!" if bd_active else "%s is for sale: open the gate to buy it" % String(Game.chapters[k].name)
		if k >= 0 and not bd_active and fence_zone != null and not _fence_prompted:
			# the gate prompt opens as soon as the player stops at the fence: on the first approach that is the
			# one message, the toast only comes on later pushes (or if they keep pushing without stopping)
			_push_t += get_process_delta_time()
			if _push_t < 1.0:
				continue
		var now_ms := Time.get_ticks_msec()
		if now_ms - _edge_warn_ms < 4000 and msg == _edge_warn_msg:
			continue
		_edge_warn_ms = now_ms
		_edge_warn_msg = msg
		Game.toast.emit(msg)


func _cross(side: int) -> void:
	var k := Plot.neighbour(Game.venue, side)
	_crossing = true
	var dir := float(side)
	var x := Plot.east(k) - 0.6 if side < 0 else Plot.west(k) + 0.6
	var arrive := {"x": x, "z": clampf(player.global_position.z, 10.0, 13.6), "yaw": atan2(dir, 0.0)}
	arrive.merge(carried())
	cross_requested.emit(k, arrive)


## What the player takes along to another place (walking or MAP): the logs in the bag, the dishes in hand.
func carried() -> Dictionary:
	if not is_instance_valid(player):
		return {}
	return {"logs": player.back.count(), "dishes": player.hands.count()}


## Called just before this place is stashed (walking next door, MAP, gate): dishes a drive-thru car has taken
## but not paid for go back in the window, so nothing is lost.
func before_leave() -> void:
	if specials:
		specials.on_leave()


## Where a MAP / gate trip from chapter `from` puts you in chapter k: on the road at the side you came from.
static func map_arrival(from: int, k: int) -> Dictionary:
	if from == k:
		return {}
	var east_side := k > from          # higher chapters lie further west: you come in from their east
	return {"x": 11.0 if east_side else -11.0, "z": ROAD_Z, "yaw": -PI / 2 if east_side else PI / 2}


func _zone(id: String, kind: String, pos: Vector3, size: Vector2, color: Color, text := "", icon := "", dashed := false) -> Zone:
	var z := Zone.new()
	add_child(z)
	z.setup(id, kind, size, color, text, icon, dashed)
	z.position = pos
	zones.append(z)
	return z


# ------------------------------------------------------------------ build state

func _on_state_changed() -> void:
	_rebuild_all(true)
	if Game.unlocked != _nb_unlocked:
		_neighbours()          # a gate opened: the FOR SALE plot next door is yours now


func _rebuild_all(animate: bool) -> void:
	for b in Game.cfg.builds:
		var id: String = b.id
		if Game.built.has(id) and not buildings.has(id) and id != "gate":
			_spawn_building(id, animate)
		# the gate pad stays after the road opens: it holds the Big Day replay (star 3) and, in the
		# last chapter, the way to a New Empire
		if pads.has(id) and id != "gate" and (Game.built.has(id) or not Game.build_available(id)):
			zones.erase(pads[id])
			pads[id].queue_free()
			pads.erase(id)
		if not pads.has(id) and (Game.build_available(id) or (id == "gate" and Game.built.has("gate"))):
			_spawn_pad(id, animate)
	_sync_workers()
	_sync_fence_zone()


func _spawn_pad(id: String, animate: bool) -> void:
	var b := Game.build_def(id)
	var z: Zone
	if id == "gate":
		z = _zone(id, "gate", pad_pos(id), Vector2(2.4, 2.4), Color("#8EE07A"), "NEXT", "res://assets/icons/gate.svg", true)
	else:
		var left := int(b.cost) - int(Game.pad_paid.get(id, 0))
		z = _zone(id, "build", pad_pos(id), Vector2(2.0, 2.0), Color("#FFD978"), UI.fmt(left), "res://assets/icons/coin.svg", true)
		z.set_progress(float(Game.pad_paid.get(id, 0)) / float(b.cost))
	var name_l := Label3D.new()
	name_l.text = String(b.name).to_upper()
	name_l.font = UI.font_bold()
	name_l.font_size = 64
	name_l.pixel_size = 0.0045
	name_l.outline_size = 14
	name_l.outline_modulate = Color(0.08, 0.05, 0.02, 0.9)
	name_l.rotation.x = -PI / 2
	name_l.position = Vector3(0, 0.05, z.size.y * 0.5 + 0.32)
	name_l.modulate = Color("#FFE7A8")
	z.add_child(name_l)
	pads[id] = z
	if animate:
		z.scale = Vector3.ONE * 0.01
		z.create_tween().tween_property(z, "scale", Vector3.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _spawn_building(id: String, animate: bool) -> void:
	var root := Node3D.new()
	add_child(root)
	buildings[id] = root
	match id:
		"campfire":
			_make_fire(0, root)
			var pallet := Art.box(Vector3(1.3, 0.1, 1.3), Art.plank_mat(), PILE_POS + Vector3(0, 0.05, 0), root)
			pallet.name = "Pallet"
			pile = Stack.new().setup("log", Stack.Layout.PILE)
			root.add_child(pile)
			pile.position = PILE_POS + Vector3(0, 0.1, 0)
			pile.set_count(Game.woodpile)
			pile_zone = _zone("pile", "pile", PILE_POS + Vector3(0, 0, 1.25), Vector2(1.9, 1.1), Color("#FFD978"), "", "res://assets/icons/log.svg")
			var rk := Art.rack()
			rk.position = RACK_POS
			root.add_child(rk)
			_collider(RACK_POS + Vector3(0, 0.45, 0), Vector3(1.5, 0.9, 0.6))
			rack_stack = Stack.new().setup("dish", Stack.Layout.RACK)
			rack_stack.position = RACK_POS + Vector3(0, 0.03, 0)
			root.add_child(rack_stack)
			rack_stack.set_count(Game.rack)
			rack_zone = _zone("rack", "rack", RACK_POS + Vector3(0, 0, 0.95), Vector2(1.7, 1.0), Color("#FFD978"), "", "res://assets/icons/dish.svg")
			var ct := Art.counter()
			ct.position = COUNTER_POS
			root.add_child(ct)
			_collider(COUNTER_POS + Vector3(0, 0.5, 0), Vector3(2.8, 1.0, 0.8))
			var lan := Art.model("wooden_lantern_01")
			lan.position = COUNTER_POS + Vector3(1.15, 1.03, 0.1)
			root.add_child(lan)
			counter_stack = Stack.new().setup("dish", Stack.Layout.COUNTER)
			counter_stack.position = COUNTER_POS + Vector3(-0.1, 0, 0)
			root.add_child(counter_stack)
			serve_zone = _zone("serve", "serve", COUNTER_POS + Vector3(0, 0, -0.95), Vector2(2.6, 1.0), Color("#FFD978"), "SERVE")
			coin_stack = Stack.new().setup("coin", Stack.Layout.COINS, 54)
			coin_stack.position = COIN_POS
			root.add_child(coin_stack)
			coin_stack.set_count(_coin_visuals(Game.counter_coins))
			coin_zone = _zone("coins", "coins", COIN_POS, Vector2(1.6, 1.6), Color("#FFD978"), "")
			# standing anywhere on the pad (the player's body over its edge, e.g. pressed against the counter's
			# end) collects: the pad edge alone missed a player who visibly stood on it
			coin_zone.reach = 0.45
			var bench := Art.model("wooden_stool_01")
			bench.position = FIRE_POS[0] + Vector3(-1.1, 0, 0.4)
			root.add_child(bench)
		"fire_2":
			_make_fire(1, root)
		"tables_1", "tables_2":
			for c in TABLES[id]:
				_dining_table(c, root)
				_collider(c + Vector3(0, 0.4, 0), Vector3(1.9, 0.8, 2.5))
				for side in [-1.0, 1.0]:
					for end in [-1.0, 1.0]:
						var plate := Stack.new().setup("dish", Stack.Layout.TABLE)
						plate.position = c + Vector3(side * 0.28, 0.645, end * 0.62)
						root.add_child(plate)
						seats.append({"pos": c + Vector3(side * 0.74, -0.06, end * 0.62), "side": side,
							"center": c, "by": null, "plate": plate})
		"shop":
			var cab := Art.cabin(2.6, 2.2, _tc("wall", Color(1.35, 1.1, 0.85)))
			cab.position = SHOP_POS
			cab.rotation.y = 0.0
			root.add_child(cab)
			_collider(SHOP_POS + Vector3(0, 1, 0), Vector3(2.7, 2, 2.3))
			var crate := Art.model("wooden_crate_01")
			crate.position = SHOP_POS + Vector3(-1.9, 0, 0.9)
			root.add_child(crate)
			var axe := Art.model("wooden_axe_02")
			axe.position = SHOP_POS + Vector3(-1.9, 0.62, 0.9)
			axe.rotation_degrees = Vector3(0, 30, 75)
			root.add_child(axe)
			_zone("shop", "shop", PADS.shop, Vector2(1.9, 1.6), Color("#8EC9FF"), "TOOLS", "res://assets/icons/hammer.svg")
		"crew_hut":
			# its roof dithers out near the camera like the parasols (from the tool shed it filled the bottom half)
			var cab2 := Art.cabin(3.0, 2.4, _tc("wall", Color(1.25, 1.0, 0.78)).darkened(0.08), true)
			cab2.position = CREW_POS
			cab2.rotation.y = -PI / 2
			root.add_child(cab2)
			_collider(CREW_POS + Vector3(0, 1, 0), Vector3(2.5, 2, 3.1))
			var st := Art.model("wooden_stool_01")
			st.position = CREW_POS + Vector3(-1.6, 0, 1.4)
			root.add_child(st)
			_zone("crew", "crew", PADS.crew_hut, Vector2(1.9, 1.6), Color("#8EC9FF"), "CREW", "res://assets/icons/crew.svg")
		"special":
			specials.spawn(root)
	if animate:
		_push_player_clear(pad_pos(id))
		Sfx.play("build")
		fx_dust(pad_pos(id))
		for c in root.get_children():
			if c is Node3D and not (c is Stack):
				var s: Vector3 = c.scale
				c.scale = s * 0.01
				c.create_tween().tween_property(c, "scale", s, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		Game.toast.emit(String(Game.build_def(id).name) + " built!")


## Dining furniture per chapter (chapters.json "dining"). Seat spots are the same for every style.
##   picnic   wooden picnic tables
##   parasol  picnic tables under striped parasols (roadside)
##   lodge    picnic tables with a lantern on each (mountain evenings)
##   round    round clothed tables, parasols and stools (hotel terrace)
func _dining_table(c: Vector3, root: Node3D) -> void:
	var style := String(Game.chapter().get("dining", "picnic"))
	if style == "round":
		var cloth := Art.paint(Color(0.96, 0.95, 0.92), 0.85)
		var dark := Art.paint(Color(0.18, 0.15, 0.13), 0.5, 0.3)
		var top := Art.cylinder(0.95, 0.06, cloth, c + Vector3(0, 0.64, 0), root, 20)
		top.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		Art.cylinder(0.97, 0.22, cloth, c + Vector3(0, 0.52, 0), root, 20)
		Art.cylinder(0.08, 0.6, dark, c + Vector3(0, 0.3, 0), root, 8)
		Art.cylinder(0.4, 0.04, dark, c + Vector3(0, 0.02, 0), root, 12)
		for side in [-1.0, 1.0]:
			for end in [-1.0, 1.0]:
				Art.cylinder(0.22, 0.42, Art.plank_mat(), c + Vector3(side * 0.74, 0.21, end * 0.62), root, 10)
	else:
		var t := Art.model("wooden_picnic_table")
		t.position = c
		t.scale = Vector3.ONE * TABLE_SCALE
		root.add_child(t)
	if style in ["parasol", "round"]:
		var stripe := _tc("parasol", Color(0.82, 0.16, 0.1))
		# at the far end of the table so the top-down camera still sees the guests and their food; the first table
		# of the second row has the crew cabin's CREW pad at its north end, so its parasol stands at the south end
		var at := c + Vector3(0, 0, 1.55 if c.is_equal_approx(TABLES.tables_2[0]) else -1.55)
		var pole := Art.cylinder(0.04, 2.3, _near_fade(Color(0.9, 0.88, 0.84), 0.4), at + Vector3(0, 1.15, 0), root, 6)
		pole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var cm := CylinderMesh.new()
		cm.top_radius = 0.05
		cm.bottom_radius = 0.95
		cm.height = 0.5
		cm.radial_segments = 8
		cm.material = _near_fade(stripe, 0.7)
		var shade := MeshInstance3D.new()
		shade.mesh = cm
		shade.position = at + Vector3(0, 2.3, 0)
		shade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		root.add_child(shade)
	elif style == "lodge":
		var lan := Art.model("wooden_lantern_01")
		lan.position = c + Vector3(0, 0.68, 0)
		root.add_child(lan)


## Parasols are the only tall thing in the dining area: right under the camera (the player up by the cookers or
## the forest) they filled the bottom corners as big red blobs. Their material dithers them out within ~9 m of
## the camera, i.e. only in the bottom fifth of the screen (cheap: no blending, no sorting).
func _near_fade(c: Color, rough: float) -> StandardMaterial3D:
	return Art._c("nearfade:%s:%s" % [c, rough], func():
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = rough
		m.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_DITHER
		m.distance_fade_min_distance = 7.8
		m.distance_fade_max_distance = 8.9
		return m)


func pad_pos(id: String) -> Vector3:
	if id == "special":
		return specials.pad_pos()
	return PADS.get(id, Vector3.ZERO)


func _push_player_clear(pad: Vector3) -> void:
	# a new building can appear on top of the player: hop them to the side of it
	if player.global_position.distance_to(pad) < 1.6:
		var dest := pad + Vector3(0, 0, 1.7)
		var tw := player.create_tween()
		tw.tween_property(player, "global_position", dest, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _make_fire(i: int, root: Node3D) -> void:
	var p: Vector3 = FIRE_POS[i]
	var kind: String = Game.chapter().cooker
	var flame_y := 0.2
	if kind == "firepit":
		var pit := Art.model("stone_fire_pit")
		pit.position = p
		pit.scale = Vector3.ONE * 0.9
		root.add_child(pit)
		var pot := Art.model("pot_enamel_01")
		pot.position = p + Vector3(0, 0.22, 0)
		pot.scale = Vector3.ONE * 1.6
		root.add_child(pot)
		for k in 3:
			var lg := MeshInstance3D.new()
			lg.mesh = Art.log_mesh()
			lg.position = p + Vector3(0, 0.12, 0)
			lg.rotation = Vector3(0, k * TAU / 3.0, 0.25)
			root.add_child(lg)
	else:
		var ck := Art.cooker(kind)
		ck.position = p
		root.add_child(ck)
		flame_y = float(ck.get_meta("flame_y", 0.6))
	# the collider matches what you see (the oven and smoker are wider than the old 1.2 m box). Where two
	# cookers stand closer than a body can pass (oven, smoker) the gap is closed, so nobody walks into a
	# dead end behind them: the way round is at either end of the row.
	var fp: Array = COOKER_FOOT.get(kind, COOKER_FOOT.firepit)
	_collider(p + Vector3(float(fp[2]), 0.3, 0), Vector3(float(fp[0]), 0.6, float(fp[1])))
	if i == 1:
		var gap := FIRE_POS[1].x - FIRE_POS[0].x - float(fp[0])
		if gap < COOKER_LANE:
			var mid: Vector3 = (FIRE_POS[0] + FIRE_POS[1]) * 0.5
			_collider(mid + Vector3(float(fp[2]), 0.3, 0), Vector3(gap + 0.2, 0.6, minf(0.8, float(fp[1]))))
	var flames := CPUParticles3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.45, 0.45)
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	fm.vertex_color_use_as_albedo = true
	fm.albedo_texture = _soft_dot()
	qm.material = fm
	flames.mesh = qm
	flames.amount = 26
	flames.lifetime = 0.8
	flames.position = p + Vector3(0, flame_y, 0)
	flames.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	flames.emission_sphere_radius = 0.18
	flames.direction = Vector3.UP
	flames.spread = 12.0
	flames.gravity = Vector3(0, 1.4, 0)
	flames.initial_velocity_min = 0.4
	flames.initial_velocity_max = 0.9
	flames.scale_amount_min = 0.6
	flames.scale_amount_max = 1.2
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.85, 0.4, 0.9))
	ramp.set_color(1, Color(0.9, 0.2, 0.05, 0.0))
	ramp.add_point(0.4, Color(1.0, 0.5, 0.1, 0.75))
	flames.color_ramp = ramp
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.6))
	curve.add_point(Vector2(0.3, 1.0))
	curve.add_point(Vector2(1, 0.1))
	flames.scale_amount_curve = curve
	root.add_child(flames)
	var light: Node3D
	if LOW_END:
		light = _glow_decal(p)
	else:
		var ol := OmniLight3D.new()
		ol.light_color = Color(1.0, 0.6, 0.25)
		ol.light_energy = 1.4
		ol.omni_range = 4.0
		ol.position = p + Vector3(0, 0.8, 0)
		light = ol
	root.add_child(light)
	var ring := MeshInstance3D.new()
	var rq := QuadMesh.new()
	rq.size = Vector2(0.62, 0.62)
	ring.mesh = rq
	var rmat := Art.shader_mat("res://shaders/ring.gdshader")
	ring.material_override = rmat
	ring.position = p + Vector3(0, 1.75, 0)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.visible = false
	root.add_child(ring)
	fires.append({"pos": p, "fuel": 0, "cooking": false, "t": 0.0, "ring": ring, "mat": rmat, "light": light, "flames": flames})


func _soft_dot() -> Texture2D:
	return Art._c("softdot", func():
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		var gt := GradientTexture2D.new()
		gt.gradient = g
		gt.fill = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(0.5, 0.5)
		gt.fill_to = Vector2(0.5, 0.0)
		gt.width = 64
		gt.height = 64
		return gt)


func _sync_workers() -> void:
	var have := {"lumberjack": 0, "waiter": 0, "cook": 0}
	for w in workers:
		have[w.role] += 1
	for role in have:
		while have[role] < int(Game.crew[role]):
			if role != "lumberjack" and not Game.built.has("campfire"):
				break
			var w := Worker.new().setup(self, role, have[role])
			add_child(w)
			w.global_position = CREW_POS + Vector3(-1.8, 0, 0.5 * have[role]) if Game.built.has("crew_hut") else SPAWN
			workers.append(w)
			have[role] += 1


# ------------------------------------------------------------------ queries used by agents

func trees_near(p: Vector3, r: float, n: int) -> Array:
	var out: Array = []
	var best: Array = []
	for t in trees:
		if not t.alive:
			continue
		var d := Vector2(t.global_position.x - p.x, t.global_position.z - p.z).length()
		if d <= r and (t.reserved_by == null or not is_instance_valid(t.reserved_by)):
			best.append([d, t])
	best.sort_custom(func(a, b): return a[0] < b[0])
	for i in mini(n, best.size()):
		out.append(best[i][1])
	return out


func has_free_tree() -> bool:
	for t in trees:
		if t.alive and t.reserved_by == null:
			return true
	return false


func reserve_tree(by: Node, p: Vector3) -> ChopTree:
	var best: ChopTree = null
	var bd := INF
	for t in trees:
		if not t.alive or (t.reserved_by != null and is_instance_valid(t.reserved_by)) or t == golden:
			continue
		if player.global_position.distance_to(t.global_position) < 2.5:
			continue
		var d := p.distance_squared_to(t.global_position)
		if d < bd:
			bd = d
			best = t
	if best:
		best.reserved_by = by
	return best


func fire_positions() -> Array:
	var out := []
	for f in fires:
		out.append(f.pos)
	return out


func fire_busy(i: int) -> bool:
	return i < fires.size() and fires[i].cooking


func pile_full() -> bool:
	return Game.woodpile >= int(Game.cfg.woodpile_cap)


## Sells one log from a stack at the truck (player or lumberjack). Returns false when empty.
func sell_log_from(s: Stack, by: Node3D) -> bool:
	if s.count() == 0:
		return false
	var from := s.take()
	Stack.fly_free(self, "log", from, TRUCK_POS + Vector3(0, 1.6, -0.6), 0.35)
	var price := int(Game.cfg.log_sell_price)
	Game.add_coins(price)
	Game.stats.sold += 1
	if by == player:
		Game.job_progress("sell")
	Sfx.play("coin", -8.0 if by == player else -14.0, 1.0, 0.05)
	float_text.emit("+$%d" % price, by.global_position + Vector3(randf_range(-0.3, 0.3), 2.3, 0), UI.CASH)
	return true


func pile_put_from(s: Stack) -> bool:
	if pile == null or Game.woodpile >= int(Game.cfg.woodpile_cap) or s.count() == 0:
		return false
	var from := s.take()
	pile.receive(from, 0.28)
	Game.woodpile += 1
	Sfx.play("clack", -8.0, 1.0, 0.04)
	return true


func rack_take_to(s: Stack) -> bool:
	if rack_stack == null or Game.rack <= 0:
		return false
	var from := rack_stack.take()
	Game.rack -= 1
	s.receive(from, 0.22)
	Sfx.play("pop", -10.0, 1.2)
	return true


func counter_count() -> int:
	return counter_stack.count() if counter_stack else 0


func counter_put_from(s: Stack) -> bool:
	if counter_stack == null or counter_stack.count() >= 8 or s.count() == 0:
		return false
	counter_stack.receive(s.take(), 0.22)
	Sfx.play("pop", -10.0, 1.0)
	return true


func counter_give_to(s: Stack) -> void:
	if counter_stack and counter_stack.count() > 0:
		s.receive(counter_stack.take(), 0.25)


## Moves cash from the counter pile to the player. The whole pile comes over in about `ticks` ticks.
func collect_cash(ticks: int) -> void:
	if Game.counter_coins <= 0:
		return
	var n := coin_stack.count()
	var bills := maxi(2, int(ceil(54.0 / float(ticks))))   # fixed batch: a full pile (54 bills) empties in `ticks` ticks
	var amount := Game.counter_coins if n <= bills else int(ceil(float(Game.counter_coins) * float(bills) / float(n)))
	amount = mini(amount, Game.counter_coins)
	Game.counter_coins -= amount
	Game.add_coins(amount)
	for i in mini(bills, n):
		Stack.fly_free(self, "coin", coin_stack.take(), player.global_position + Vector3(0, 1.4, 0), 0.22 + i * 0.03)
	Sfx.play("coin", -6.0, 1.0 + randf() * 0.2, 0.05)


func _coin_visuals(amount: int) -> int:
	return mini(54, int(ceil(amount / 5.0)))


func customer_paid(c: Node3D, amount: int, score: float, bonus := "") -> void:
	_bd_count(1, score)
	Game.counter_coins += amount
	Game.served += 1
	Game.vserved += 1
	Game.stats.served += 1
	Game.add_rating(score)
	Game.job_progress("serve")
	var want := _coin_visuals(Game.counter_coins)
	var from := c.global_position + Vector3(0, 1.2, 0)
	while coin_stack.count() < want:
		coin_stack.receive(from, 0.35 + coin_stack.count() % 5 * 0.04)
	Sfx.play("cash", -4.0)
	float_text.emit("+" + UI.cash(amount), c.global_position + Vector3(0, 2.4, 0), UI.CASH)
	if bonus != "":
		float_text.emit(bonus, c.global_position + Vector3(0, 3.0, 0), UI.GOLD_LIGHT)
	Game.refresh_stars()


## Price multiplier for guests paying right now (warm fireplace, fair rush).
func price_mult() -> float:
	return specials.price_mult() if specials else 1.0


func patience_mult() -> float:
	var m: float = specials.patience_mult() if specials else 1.0
	if bd_active:
		m *= float(bd.get("patience_mult", 1.0))
	return m


## Drive-thru cars and the room-service van pay straight into your coins.
func card_paid(at: Vector3, amount: int, score: float, guests: int) -> void:
	_bd_count(guests, score)
	Game.add_coins(amount)
	Game.served += guests
	Game.vserved += guests
	Game.stats.served += guests
	for i in guests:
		Game.add_rating(score)
		Game.job_progress("serve")
	Sfx.play("cash", -4.0)
	float_text.emit("+" + UI.cash(amount), at + Vector3(0, 2.6, 0), UI.CASH)


## Where a waiter should take dishes: the counter, or the drive-thru / van when it needs them.
func waiter_sink(idx: int) -> String:
	var need: int = specials.dish_need() if specials.crew_allowed() else 0
	# the station only gets dishes the counter can spare: guests in line come first
	if need > 0 and (counter_count() >= 3 or queue.is_empty()):
		return "special"
	return "counter"


func customer_angry(c: Node3D) -> void:
	Game.add_rating(1.0)
	Game.walkouts += 1
	Game.stats.walkouts += 1
	if bd_active:
		bd_walkouts += 1
		bd_scores.append(1.0)
	float_text.emit("TOO SLOW!", c.global_position + Vector3(0, 2.4, 0), UI.RED)
	Sfx.play("clack", -6.0, 0.6)
	# the two guests behind them get grumpier
	var i := queue.find(c)
	if i >= 0:
		for k in [i + 1, i + 2]:
			if k < queue.size() and is_instance_valid(queue[k]):
				queue[k].annoy(0.1)
	Game.fire_story("walkout")
	_check_rating()


func _check_rating() -> void:
	if Game.rating_hist.size() >= 12 and Game.rating() < 3.5:
		Game.fire_story("rating_low")


## True while the player stands at the counter: guests served then pay the hands-on bonus.
func player_serving() -> bool:
	return serve_zone != null and _inside.get(serve_zone, false)


func order_bonus() -> int:
	return int(bd.get("order_bonus", 0)) if bd_active else 0


func roll_vip() -> bool:
	if bd_active and randf() < float(bd.get("vip_share", 0.0)):
		return true
	return specials != null and specials.roll_vip()


func car_rate() -> float:
	return float(bd.get("car_mult", 1.0)) if bd_active else 1.0


func queue_leave(c: Node) -> void:
	queue.erase(c)
	_reslot()


func _reslot() -> void:
	for i in queue.size():
		queue[i].move_to_slot(i, _slot_pos(i))


## The line snakes: six guests down from the counter, then six back up beside them.
func _slot_pos(i: int) -> Vector3:
	var k := i % 6
	if i < 6:
		return COUNTER_POS + Vector3(-0.2, 0, 0.95 + k * 0.92)
	return COUNTER_POS + Vector3(0.95, 0, 0.95 + (5 - k) * 0.92)


func take_seat(c: Node) -> int:
	var free: Array = []
	for i in seats.size():
		if seats[i].by == null:
			free.append(i)
	if free.is_empty():
		return -1
	var i: int = free[randi() % free.size()]
	seats[i].by = c
	return i


func path_to_seat(from: Vector3, i: int) -> Array:
	var s: Dictionary = seats[i]
	var approach := Vector3(s.center.x + s.side * 1.55, 0, s.pos.z)
	var dir := 1.0 if s.center.x > from.x else -1.0
	return [from + Vector3(dir * 1.7, 0, 0.4), Vector3(approach.x, 0, s.center.z + 1.9), approach]


func seat_sit_pos(i: int) -> Vector3:
	var s: Dictionary = seats[i]
	return Vector3(s.pos.x + s.side * 0.12, -0.05, s.pos.z)


func seat_table_center(i: int) -> Vector3:
	return seats[i].center if i >= 0 else Vector3.ZERO


func seat_food(i: int, hands: Stack) -> void:
	var plate: Stack = seats[i].plate
	while hands.count() > 0:
		plate.receive(hands.take(), 0.25)


func seat_done(i: int, paid: int) -> void:
	var plate: Stack = seats[i].plate
	plate.set_count(0)
	seats[i].by = null
	var tip := int(round(paid * Game.seated_tip()))
	if tip > 0:
		Game.counter_coins += tip
		var want := _coin_visuals(Game.counter_coins)
		while coin_stack.count() < want:
			coin_stack.receive(seats[i].pos + Vector3(0, 1, 0), 0.5)
		float_text.emit("TIP +" + UI.cash(tip), seats[i].pos + Vector3(0, 2.2, 0), UI.CASH)
		Game.add_rating(5.0)


func path_home(from: Vector3) -> Array:
	var out: Array = []
	for s in seats:
		if Vector2(from.x - s.pos.x, from.z - s.pos.z).length() < 0.6:
			out.append(Vector3(s.center.x + s.side * 1.55, 0, s.pos.z))
			break
	out.append(Vector3(out[0].x if out.size() > 0 else from.x + (2.0 if from.x < 2.0 else 0.0), 0, ROAD_Z - 0.6))
	out.append(ROAD_EAST)
	return out


func on_tree_hit(t: ChopTree, logs: int, by: Node) -> void:
	fx_chips(t.global_position + Vector3(0, 0.8, 0))
	if not t.alive and t == golden:
		_golden_felled(by == player)
	if not t.alive:
		Game.stats.trees += 1
		if by == player:
			Game.job_progress("chop")
			_shake = 0.25
		Sfx.play("fall", -6.0 if by == player else -16.0)
		fx_leaves(t.global_position + Vector3(0, 1.8, 0))
	elif by != player and player.global_position.distance_to(t.global_position) < 9.0:
		Sfx.play("chop", -18.0)
	Game.stats.logs += logs


# ------------------------------------------------------------------ main loop

func _process(delta: float) -> void:
	var hud = get_parent().get("hud") if get_parent() else null
	modal_kind = String(hud.modal_kind) if hud != null and is_instance_valid(hud) else ""
	_zones_tick(delta)
	_fires_tick(delta)
	_customers_tick(delta)
	_golden_tick(delta)
	_bd_tick(delta)
	specials.tick(delta)
	_road_tick()
	_cam_tick(delta)
	_obj_t -= delta
	if _obj_t <= 0.0:
		_obj_t = 0.25
		_update_objective()
	if arrow.visible:
		arrow.position.y = objective.pos.y + 2.2 + sin(Time.get_ticks_msec() * 0.006) * 0.18
		arrow.rotate_y(delta * 2.0)


func _zones_tick(delta: float) -> void:
	var pp := player.global_position
	for z in zones.duplicate():
		if not is_instance_valid(z):
			continue
		var inside: bool = z.contains(pp)
		var was: bool = _inside.get(z, false)
		if inside != was:
			_inside[z] = inside
			z.set_active(inside)
			if not inside and _engaged.get(z, false):
				_engaged[z] = false
				zone_exited.emit(z.kind, z.id)
		if not inside:
			continue
		# zones only work once the player stops on them — walking across never spends or opens anything
		# (picking up cash is harmless, so that one also works on the move)
		if not player.is_still() and z.kind != "coins":
			z.tick = maxf(z.tick, 0.12)
			continue
		if not _engaged.get(z, false):
			_engaged[z] = true
			z.tick = 0.12
			zone_entered.emit(z.kind, z.id)
		z.tick -= delta
		if z.tick <= 0.0:
			_zone_action(z)


func _zone_action(z: Zone) -> void:
	match z.kind:
		"sell":
			z.tick = 0.07
			sell_log_from(player.back, player)
		"pile":
			z.tick = 0.06
			pile_put_from(player.back)
		"rack":
			z.tick = 0.12
			if player.hands.count() < int(Game.cfg.player.carry_dishes):
				rack_take_to(player.hands)
		"coins":
			z.tick = 0.05
			collect_cash(8)
		"serve":
			z.tick = 0.12
			counter_put_from(player.hands)
			collect_cash(14)        # standing at the counter also scoops up the cash next to it
		"build":
			z.tick = 0.035
			var b := Game.build_def(z.id)
			var rate := maxi(1, int(ceil(float(b.cost) / 40.0)))
			var moved := Game.pay_pad(z.id, rate)
			if moved == 0 and Game.coins <= 0 and not Game.built.has(z.id):
				z.tick = 0.5
				var now_ms := Time.get_ticks_msec()
				if now_ms - _pad_warn_ms > 5000:
					_pad_warn_ms = now_ms
					Game.toast.emit("Not enough cash: serve guests, then come back to build")
			if moved > 0:
				if randf() < 0.5:
					Stack.fly_free(self, "coin", player.global_position + Vector3(0, 1.3, 0), z.global_position, 0.25)
					Sfx.play("coin", -12.0, 1.3, 0.06)
				if is_instance_valid(z) and pads.has(z.id):
					var paid := int(Game.pad_paid.get(z.id, 0))
					z.set_text(UI.fmt(int(b.cost) - paid))
					z.set_progress(float(paid) / float(b.cost))
		_:
			if not specials.zone_action(z):
				z.tick = 999.0


func _fires_tick(delta: float) -> void:
	var cap := int(Game.cfg.rack_cap)
	var cooking := 0
	for f in fires:
		if f.cooking:
			cooking += 1
	for i in fires.size():
		var f: Dictionary = fires[i]
		var flick := sin(Time.get_ticks_msec() * 0.013 + i) * 0.25 + randf() * 0.15
		if f.light is OmniLight3D:
			f.light.light_energy = 1.2 + flick
		else:
			f.light.transparency = 0.15 - flick * 0.3
		if f.cooking:
			f.t -= delta
			f.mat.set_shader_parameter("progress", 1.0 - f.t / Game.cook_time())
			if f.t <= 0.0:
				f.cooking = false
				f.ring.visible = false
				Game.rack += 1
				rack_stack.receive(f.pos + Vector3(0, 0.8, 0), 0.4)
				Sfx.play("pop", -12.0, 0.9)
		elif (f.fuel > 0 or Game.woodpile > 0) and Game.rack + cooking < cap:
			if f.fuel <= 0:
				Game.woodpile -= 1
				f.fuel = int(Game.cfg.dishes_per_log)
				Stack.fly_free(self, "log", pile.take(), f.pos + Vector3(0, 0.3, 0), 0.4)
			f.fuel -= 1
			cooking += 1
			f.cooking = true
			f.t = Game.cook_time()
			f.ring.visible = true
		f.flames.scale = Vector3.ONE * (1.25 if f.cooking else 0.8)


func _customers_tick(delta: float) -> void:
	if not Game.built.has("campfire"):
		return
	var c: Dictionary = Game.cfg.customers
	spawn_t -= delta
	var max_q := max_queue()
	var limit := max_q + seats.size() + 4
	if spawn_t <= 0.0:
		spawn_t = spawn_interval() * randf_range(0.75, 1.25)
		_arrive(max_q, limit)
	# groups: a bunch of guests arrive together every couple of minutes once there are tables
	if Game.built.has("tables_1") and not bd_active:
		group_t -= delta
		if group_t <= 0.0:
			var gr: Array = c.group_every
			group_t = randf_range(float(gr[0]), float(gr[1]))
			var gs: Array = c.group_size
			group_left = randi_range(int(gs[0]), int(gs[1])) + Game.venue / 2
			Game.toast.emit(String(Game.chapter().get("group", "A group of guests is coming!")))
			Game.fire_story("group")
	if group_left > 0:
		group_gap -= delta
		if group_gap <= 0.0:
			group_gap = 0.55
			group_left -= 1
			_arrive(max_q, limit)
	customers = customers.filter(func(x): return is_instance_valid(x))


## One guest shows up: joins the line, or walks past if it's full (a lost sale).
func _arrive(max_q: int, limit: int) -> void:
	if queue.size() < max_q and customers.size() < limit:
		_spawn_customer()
	elif passers < 3:
		_spawn_passer()


## Demand grows with the whole business: tables, fires, kitchen upgrades, cooks and menu.
## Rating still matters, but a dip slows guests by at most ~30% instead of halving them.
func spawn_interval() -> float:
	var c: Dictionary = Game.cfg.customers
	var demand := 1.0 + Game.tables() * float(c.per_table_bonus)
	demand += (fires.size() - 1) * 0.20
	demand += int(Game.levels.get("fire", 0)) * 0.14
	demand += int(Game.levels.get("menu", 0)) * 0.10
	demand += int(Game.crew.get("cook", 0)) * 0.12
	demand *= Game.sign_demand()
	var rate_mult := lerpf(1.35, 0.85, clampf((Game.rating() - 3.0) / 2.0, 0.0, 1.0))
	if bd_active:
		return float(bd.get("interval", 1.0)) / Game.sign_demand()
	var interval: float = float(c.interval) / demand * rate_mult
	# Demand grows faster than the kitchen (+14% guests vs -5% cook time a kitchen level, +10% a menu level), so in
	# later places guests came 2-3x faster than the cookers can feed them: the line was always full and every
	# extra guest only walked past as a lost sale (163 lost vs 670 served in 23 min on the phone; 3 passers always
	# on screen). Arrivals are capped at ARRIVAL_HEADROOM x what the cookers can serve: the line still fills when
	# you fall behind, but the overflow is no longer most of the crowd. Income is unchanged (it is kitchen-bound).
	var per_guest := (float(c.order_min) + float(c.order_max)) * 0.5 + float(c.get("order_bonus", 0))
	var dishes_s := float(maxi(1, fires.size())) / maxf(0.2, Game.cook_time())
	# specials (a bell rush) still multiply on top of the cap, so they keep their flood of guests
	return maxf(interval, per_guest / dishes_s / ARRIVAL_HEADROOM) * (specials.spawn_mult() if specials else 1.0)


const ARRIVAL_HEADROOM := 1.25


## A second fire and kitchen upgrades let a longer line form at the counter.
func max_queue() -> int:
	var q := int(Game.cfg.customers.max_queue) + (fires.size() - 1) + int(Game.levels.get("dining", 0)) / 8 \
		+ (specials.extra_queue() if specials else 0) + (3 if bd_active else 0)
	return mini(q, int(Game.cfg.customers.queue_cap))


func _spawn_customer() -> void:
	cust_seed += 1
	var cu := Customer.new().setup(self, cust_seed + randi() % 1000)
	add_child(cu)
	cu.global_position = ROAD_EAST + Vector3(0, 0, randf_range(-0.4, 0.4))
	var i := queue.size()
	queue.append(cu)
	cu.slot = i
	var sp := _slot_pos(i)
	cu.go([Vector3(COUNTER_POS.x + 2.2, 0, ROAD_Z - 0.4), sp])
	customers.append(cu)


func _spawn_passer() -> void:
	cust_seed += 1
	passers += 1
	Game.stats.lost += 1
	var cu := Customer.new().setup_passer(self, cust_seed + randi() % 1000)
	add_child(cu)
	cu.global_position = ROAD_EAST + Vector3(0, 0, randf_range(0.0, 0.5))
	var end_x := -22.0
	var wk := Plot.neighbour(Game.venue, -1)
	if wk >= Game.unlocked:
		end_x = Plot.west(Game.venue) + 0.8          # the way west is fenced off
	cu.go([Vector3(COUNTER_POS.x + 2.5, 0, ROAD_Z + 0.2), Vector3(end_x, 0, ROAD_Z + 0.3)])
	cu.tree_exited.connect(func(): passers -= 1)
	var tw := cu.create_tween()
	tw.tween_interval(4.5)
	tw.tween_callback(func():
		if is_instance_valid(cu):
			float_text.emit("TOO BUSY!", cu.global_position + Vector3(0, 2.4, 0), Color(1, 1, 1, 0.75)))
	Game.fire_story("balk")


func _place_cam(t: float) -> void:
	var off := cam_off
	var shake := Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * _shake * 0.25
	cam.global_position = cam.global_position.lerp(_cam_target + off, t) + shake
	cam.look_at(cam.global_position - off + Vector3(0, 0, 0), Vector3.UP)


## The HUD's button column covers the right edge, so the camera looks a little to the right:
## the player (and the counter next to them) sit in the middle of the uncovered part of the screen.
func _hud_side_shift() -> float:
	var vs := get_viewport().get_visible_rect().size
	var ground_w := 2.0 * cam_off.length() * tan(deg_to_rad(cam.fov * 0.5))
	return ground_w * (59.0 / maxf(1.0, vs.x))


## Left edge (viewport px) of the HUD's right-hand button column (the screen width without a HUD).
func _hud_column_left() -> float:
	var vw := get_viewport().get_visible_rect().size.x
	var hud = get_parent().get("hud") if get_parent() else null
	if hud == null or not is_instance_valid(hud) or hud.get("jobs_btn") == null:
		return vw
	var col: Control = hud.jobs_btn.get_parent().get_parent()
	return minf(vw, col.get_global_rect().position.x) if col.is_visible_in_tree() else vw


## Where the camera looks for a player at p. In the camp it is just ahead of the player. On the road and near a
## plot edge the steep portrait camera would show mostly empty grass south of the road, so the aim is held at
## ROAD_Z - CAM_ROAD_BACK (the road sits in the lower third, the camp and the plot next door fill the rest) and leans a
## little toward the edge, so the neighbour shows more.
func cam_aim(p: Vector3) -> Vector3:
	var aim := p + Vector3(_hud_side_shift(), 0, -0.8)
	var we := Plot.west(Game.venue)
	var ee := Plot.east(Game.venue)
	var d_w := p.x - we
	var d_e := ee - p.x
	var edge_w := 1.0 - smoothstep(3.0, CAM_EDGE_NEAR, minf(d_w, d_e))
	var road_w := smoothstep(Plot.ROAD_GAP.x - 1.6, Plot.ROAD_GAP.x, p.z)     # 0 in the camp, 1 on the road
	var w := maxf(edge_w, road_w)
	if w > 0.0:
		aim.z = lerpf(aim.z, minf(aim.z, ROAD_Z - CAM_ROAD_BACK), w)
		aim.x += (-1.0 if d_w < d_e else 1.0) * 1.5 * edge_w * road_w
	return aim


const CAM_EDGE_NEAR := 7.0
const CAM_ROAD_BACK := 4.0       # on the road the camera aims this far north of it


## Snaps the camera to look at `aim` (a cam_aim() result).
func cam_look(aim: Vector3) -> void:
	_cam_target = aim
	_place_cam(1.0)


## Camera aims that show each road edge with a plot next door (main.gd looks there behind the loading screen).
func prewarm_aims() -> Array:
	var out: Array = []
	for side in [-1, 1]:
		if Plot.neighbour(Game.venue, side) >= 0:
			var edge := Plot.west(Game.venue) if side < 0 else Plot.east(Game.venue)
			out.append(cam_aim(Vector3(edge - side * 1.0, 0, ROAD_Z)))
	return out


func _cam_tick(delta: float) -> void:
	_cam_target = _cam_target.lerp(cam_aim(player.global_position), clampf(delta * 5.0, 0.0, 1.0))
	_shake = maxf(0.0, _shake - delta)
	_place_cam(clampf(delta * 8.0, 0.0, 1.0))
	# the neighbours' road labels stay between the screen edge and the HUD's button column
	var col_l := _hud_column_left()
	for side in nb_plots:
		if is_instance_valid(nb_plots[side]):
			nb_plots[side].place_label(cam, col_l)
	# see-through foliage around the player
	var head := player.global_position + Vector3(0, 1.0, 0)
	if not cam.is_position_behind(head):
		_foliage_tick(head)


## See-through trees + forest batching, run every frame. Kept cheap: tree positions are cached (trees never
## move); each frame only looks at the trees that can change: those near the player (list refreshed every few
## frames), trees not in the batch (shaking, fallen, regrowing), trees just hit (ChopTree.woken) and the golden
## one. The cut shader's uniforms are only pushed while some tree actually uses it.
const FOLIAGE_NEAR := 8.5         # > reach of the see-through box (5.2 m) + how far the player moves between refreshes
const FOLIAGE_REFRESH := 6        # frames between full scans
var _tree_pos := PackedVector3Array()
var _cut_mat: ShaderMaterial
var _cut_trees: Array = []        # trees currently wearing the see-through material
var _hot_trees: Array = []        # near the player or out of the batch (refreshed by the full scan)
var _foliage_n := 0


func _foliage_tick(head: Vector3) -> void:
	if _cut_mat == null:
		_cut_mat = Art.foliage_mat(Color(0.04, 0.11, 0.06), Color(0.36, 0.55, 0.24), true)
	var ppos := player.global_position
	_foliage_n -= 1
	if _foliage_n <= 0 or _tree_pos.size() != trees.size():
		_foliage_n = FOLIAGE_REFRESH
		if _tree_pos.size() != trees.size():
			_tree_pos.resize(trees.size())
			for i in trees.size():
				_tree_pos[i] = trees[i].global_position
		_hot_trees.clear()
		var r2 := FOLIAGE_NEAR * FOLIAGE_NEAR
		for i in trees.size():
			var t: ChopTree = trees[i]
			if not t.batched or _tree_pos[i].distance_squared_to(ppos) < r2:
				_hot_trees.append(t)
	var cands: Array = _hot_trees
	if not ChopTree.woken.is_empty() or not _cut_trees.is_empty() or golden:
		cands = _hot_trees + ChopTree.woken + _cut_trees
		if golden:
			cands.append(golden)
		for t in ChopTree.woken:
			if is_instance_valid(t) and not _hot_trees.has(t):
				_hot_trees.append(t)   # keep watching it until it is back in the batch
		ChopTree.woken.clear()
	var cut := _cut_mat
	var chopping: Array = player._targets
	var was_cut := _cut_trees
	_cut_trees = []
	for o in cands:
		if not is_instance_valid(o):
			continue
		var t: ChopTree = o
		var d: Vector3 = t.global_position - ppos
		var covers: bool = d.z > 0.9 and d.z < 4.8 and absf(d.x) < 1.9 and t.alive and not chopping.has(t)
		if covers and not _cut_trees.has(t):
			_cut_trees.append(t)
		if covers or t == golden or was_cut.has(t):
			var want: Material = cut if covers else (_gold_mat if t == golden and _gold_mat else null)
			if t.mesh.material_override != want:
				t.mesh.material_override = want
		var batch: bool = t.alive and not covers and t._shake <= 0.0 and not t.growing and t != golden
		if batch != t.batched:
			_batch_tree(t, batch)
	if not _cut_trees.is_empty():
		var vs := get_viewport().get_visible_rect().size
		cut.set_shader_parameter("player_screen", cam.unproject_position(head) / vs)
		cut.set_shader_parameter("player_dist", cam.global_position.distance_to(head))
		cut.set_shader_parameter("aspect", vs.x / vs.y)


# ------------------------------------------------------------------ objective arrow

func _make_arrow() -> void:
	arrow = Node3D.new()
	var spr := Sprite3D.new()
	spr.texture = load("res://assets/icons/arrow.svg")
	spr.pixel_size = 0.006
	spr.no_depth_test = true
	spr.render_priority = 6
	spr.shaded = false
	arrow.add_child(spr)
	var spr2 := spr.duplicate()
	spr2.rotation.y = PI / 2
	arrow.add_child(spr2)
	add_child(arrow)


func _update_objective() -> void:
	var o := _compute_objective()
	if specials.rush_active():
		o = {"text": "FAIR RUSH x2 · %ds · " % ceili(float(Game.sp.rush)) + String(o.text), "pos": o.pos}
	objective = o
	var show: bool = o.pos != Vector3.ZERO and player.global_position.distance_to(o.pos) > 1.6
	arrow.visible = show
	if show:
		arrow.position = Vector3(o.pos.x, arrow.position.y, o.pos.z)


func _nearest_tree_pos() -> Vector3:
	var best := Vector3.ZERO
	var bd := INF
	for t in trees:
		if t.alive:
			var d := player.global_position.distance_squared_to(t.global_position)
			if d < bd:
				bd = d
				best = t.global_position
	return best


func _compute_objective() -> Dictionary:
	var p := player
	var cap := Game.bag_cap()
	if Game.chapter_done and Game.venue + 1 < Game.unlocked and (Game.venue + 1 >= Game.venues.size() or Game.venues[Game.venue + 1].is_empty()):
		return {"text": "Open the MAP: travel to " + String(Game.chapters[Game.venue + 1].name), "pos": Vector3.ZERO}
	if not Game.built.has("campfire"):
		var cost := int(Game.build_def("campfire").cost) - int(Game.pad_paid.get("campfire", 0))
		if Game.coins >= cost or (Game.coins > 0 and p.back.count() == 0):
			return {"text": "Build the " + String(Game.build_def("campfire").name).to_lower(), "pos": PADS.campfire}
		if p.back.count() >= cap or (p.back.count() > 0 and p.back.count() * int(Game.cfg.log_sell_price) + Game.coins >= cost):
			return {"text": "Sell logs at the truck", "pos": SELL_POS}
		return {"text": "Chop trees (stand next to one)", "pos": _nearest_tree_pos()}
	if bd_active:
		if p.hands.count() > 0:
			return {"text": "Serve the crowd!", "pos": serve_zone.global_position}
		if Game.rack > 0 and (Game.crew.waiter == 0 or Game.rack >= 6):
			return {"text": "Carry food to the counter!", "pos": rack_zone.global_position}
		if p.back.count() >= mini(6, cap) or (p.back.count() > 0 and Game.woodpile < 4):
			return {"text": "Stack logs: the kitchen needs wood!", "pos": pile_zone.global_position}
		if Game.woodpile < 10:
			return {"text": "Chop wood: keep the kitchen going!", "pos": _nearest_tree_pos()}
		return {"text": "Serve the crowd!", "pos": rack_zone.global_position if Game.rack > 0 else serve_zone.global_position}
	if golden and golden.alive and p.hands.count() == 0 and p.back.count() < cap:
		return {"text": "Chop the golden tree! %ds" % ceili(golden_left), "pos": golden.global_position}
	# affordable build pad first
	for b in Game.cfg.builds:
		if pads.has(b.id) and b.id != "gate":
			var left := int(b.cost) - int(Game.pad_paid.get(b.id, 0))
			if Game.coins >= left:
				return {"text": "Build: " + String(b.name), "pos": pad_pos(b.id)}
	if pads.has("gate") and Game.gate_ready():
		return {"text": "Unlock " + String(Game.build_def("gate").name) + "!", "pos": PADS.gate}

	var bd_ready: bool = pads.has("gate") and Game.big_day_ready() and _bd_cool <= 0.0
	if bd_ready and Game.woodpile >= 20 and p.hands.count() == 0 and Game.counter_coins < int(20.0 * Game.dish_price()):
		return {"text": "Ready? Start the Big Day: " + String(Game.big_day_def().get("name", "")), "pos": PADS.gate}
	var sp_obj: Dictionary = specials.objective(p)
	if not sp_obj.is_empty():
		return sp_obj
	if p.hands.count() > 0:
		return {"text": "Serve the guests", "pos": serve_zone.global_position}
	var hungry := queue.size() > 0 and counter_count() == 0
	if Game.rack > 0 and Game.crew.waiter == 0 and (hungry or Game.rack >= int(Game.cfg.rack_cap)):
		return {"text": "Carry food to the counter", "pos": rack_zone.global_position}
	var fires_idle := Game.woodpile == 0 and Game.rack == 0 and not fires.any(func(f): return f.fuel > 0 or f.cooking)
	var pile_full: bool = Game.woodpile >= int(Game.cfg.woodpile_cap)
	if (p.back.count() >= cap and not pile_full) or (p.back.count() >= mini(4, cap) and Game.woodpile < 3) or (p.back.count() > 0 and fires_idle):
		return {"text": "Stack logs by the " + String(Game.build_def("campfire").name).to_lower(), "pos": pile_zone.global_position}
	if Game.counter_coins >= int(10.0 * Game.dish_price()):
		return {"text": "Collect your cash", "pos": COIN_POS}
	if Game.woodpile < 4:
		return {"text": "Chop wood for the " + _cooker_word(), "pos": _nearest_tree_pos()}
	if bd_ready and Game.woodpile < 20:
		return {"text": "Big Day prep: fill the woodpile (%d/20)" % Game.woodpile, "pos": _nearest_tree_pos() if p.back.count() < cap else pile_zone.global_position}
	if Game.counter_coins > 0:
		return {"text": "Collect your cash", "pos": COIN_POS}
	if Game.built.has("shop"):
		for tr in ["tool", "bag", "boots"]:
			var n := Game.next_upgrade(tr)
			if not n.is_empty() and Game.coins >= int(n.cost):
				return {"text": "Upgrade at the " + String(Game.build_def("shop").name).to_lower(), "pos": PADS.shop}
	for key in Game.STATIONS:
		if Game.station_locked(key) == "" and Game.coins >= Game.station_cost(key):
			return {"text": "Tap UPGRADE: level up your " + String(Game.station_def(key).name).to_lower(), "pos": Vector3.ZERO}
	return {"text": "Keep the " + _cooker_word() + " fed", "pos": Vector3.ZERO}


# ------------------------------------------------------------------ FX

func _fx(pos: Vector3, color: Color, amount: int, vel: float, size: float, grav: float, mesh_kind := "box") -> void:
	var p := _fx_pool[_fx_i]
	_fx_i = (_fx_i + 1) % _fx_pool.size()
	p.position = pos
	p.amount = amount
	p.lifetime = 0.9
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = vel * 0.5
	p.initial_velocity_max = vel
	p.gravity = Vector3(0, grav, 0)
	p.scale_amount_min = size * 0.6
	p.scale_amount_max = size
	if mesh_kind == "box":
		var bm := BoxMesh.new()
		bm.size = Vector3(0.06, 0.03, 0.09)
		var m := Art.paint(color, 0.8)
		bm.material = m
		p.mesh = bm
		p.color = Color.WHITE
		p.angular_velocity_min = -400
		p.angular_velocity_max = 400
		p.particle_flag_rotate_y = true
	else:
		var qm := QuadMesh.new()
		qm.size = Vector2(0.25, 0.25)
		var fm := StandardMaterial3D.new()
		fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		fm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		fm.vertex_color_use_as_albedo = true
		fm.albedo_texture = _soft_dot()
		qm.material = fm
		p.mesh = qm
		var g := Gradient.new()
		g.set_color(0, color)
		g.set_color(1, Color(color, 0.0))
		p.color_ramp = g
	if mesh_kind == "box":
		p.color_ramp = null
	p.restart()
	p.emitting = true


func fx_chips(pos: Vector3) -> void:
	_fx(pos, Color(0.85, 0.65, 0.4), 10, 3.0, 1.0, -9.0)


func fx_leaves(pos: Vector3) -> void:
	_fx(pos, Color(0.25, 0.45, 0.18), 18, 2.5, 1.3, -3.0)


func fx_dust(pos: Vector3) -> void:
	_fx(pos + Vector3(0, 0.4, 0), Color(0.9, 0.85, 0.75, 0.8), 24, 3.0, 2.5, -1.0, "soft")


func fx_burst(pos: Vector3, color: Color, n: int) -> void:
	_fx(pos, color, n, 4.0, 0.8, -4.0, "soft")


func _cooker_word() -> String:
	return {"firepit": "fire", "grill": "grill", "fryer": "fryer", "oven": "oven", "smoker": "smoker"}.get(String(Game.chapter().cooker), "fire")


## Graphics level -> how much background decor is drawn (Smooth thins it out).
func apply_quality() -> void:
	var smooth := LOW_END and Game.quality == 0
	for n in get_tree().get_nodes_in_group("edge_forest") + get_tree().get_nodes_in_group("scatter"):
		if not is_ancestor_of(n):
			continue
		var mm: MultiMesh = n.multimesh
		var keep := 0.55 if n.is_in_group("edge_forest") else 0.35
		mm.visible_instance_count = int(mm.instance_count * keep) if smooth else -1


# ------------------------------------------------------------------ golden tree

func _golden_tick(delta: float) -> void:
	if golden:
		golden_left -= delta
		if golden_left <= 0.0 or not golden.alive:
			_golden_clear()
		elif _gold_fx:
			_gold_fx.rotate_y(delta * 2.0)
		return
	if not Game.built.has("campfire") or bd_active:
		return
	golden_t -= delta
	if golden_t > 0.0:
		return
	var gr: Array = Game.cfg.golden.every
	golden_t = randf_range(float(gr[0]), float(gr[1]))
	var pick: Array = []
	for t in trees:
		if t.alive and not t.growing and (t.reserved_by == null or not is_instance_valid(t.reserved_by)) \
				and t.global_position.z > -15.0 and absf(t.global_position.x) < 11.0:
			pick.append(t)
	if pick.is_empty():
		return
	golden = pick[randi() % pick.size()]
	golden_left = float(Game.cfg.golden.life)
	if _gold_mat == null:
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(1.0, 0.78, 0.25)
		m.emission_enabled = true
		m.emission = Color(1.0, 0.62, 0.12)
		m.emission_energy_multiplier = 0.9
		m.roughness = 0.35
		m.metallic = 0.6
		_gold_mat = m
	_batch_tree(golden, false)
	golden.mesh.material_override = _gold_mat
	_gold_fx = Node3D.new()
	golden.add_child(_gold_fx)
	var sp := CPUParticles3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.18, 0.18)
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	fm.albedo_texture = _soft_dot()
	fm.albedo_color = Color(1.0, 0.85, 0.3)
	qm.material = fm
	sp.mesh = qm
	sp.amount = 14
	sp.lifetime = 1.4
	sp.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	sp.emission_sphere_radius = 1.0
	sp.position = Vector3(0, 1.6, 0)
	sp.gravity = Vector3(0, 0.6, 0)
	sp.initial_velocity_min = 0.1
	sp.initial_velocity_max = 0.4
	_gold_fx.add_child(sp)
	var l := Label3D.new()
	l.text = "GOLDEN TREE"
	l.font = UI.font_bold()
	l.font_size = 64
	l.pixel_size = 0.005
	l.outline_size = 14
	l.outline_modulate = Color(0.25, 0.12, 0.0)
	l.modulate = UI.GOLD_LIGHT
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.position = Vector3(0, 3.6, 0)
	golden.add_child(l)
	l.name = "GoldLabel"
	Game.toast.emit("A golden tree appeared!")
	Game.fire_story("golden")
	Sfx.play("build", -10.0, 1.4)


func _golden_clear() -> void:
	if is_instance_valid(golden):
		if golden.mesh.material_override == _gold_mat:
			golden.mesh.material_override = null
		var l := golden.get_node_or_null("GoldLabel")
		if l:
			l.queue_free()
	if is_instance_valid(_gold_fx):
		_gold_fx.queue_free()
	_gold_fx = null
	golden = null


func _golden_felled(by_player: bool) -> void:
	var pos := golden.global_position
	_golden_clear()
	if not by_player:
		return
	var reward := int(round(float(Game.cfg.golden.reward_dishes) * Game.dish_price()))
	Game.add_coins(reward)
	Game.golden_n += 1
	Game.stats.golden += 1
	Game.task_changed.emit()
	float_text.emit("GOLDEN! +" + UI.cash(reward), pos + Vector3(0, 3.0, 0), UI.GOLD_LIGHT)
	fx_burst(pos + Vector3(0, 1.5, 0), Color(1, 0.85, 0.3), 40)
	_shake = 0.4
	Sfx.play("cash", -2.0)


# ------------------------------------------------------------------ Big Day

## Starts the chapter finale: a timed rush; serve the goal before time runs out.
func start_big_day() -> bool:
	if bd_active or not Game.big_day_replayable() or _bd_cool > 0.0:
		return false
	bd = Game.big_day_def().duplicate()
	bd_active = true
	bd_left = float(bd.get("seconds", 150))
	bd_served = 0
	bd_walkouts = 0
	bd_scores = []
	spawn_t = 0.5
	group_left = 3
	for c in queue:
		if is_instance_valid(c):
			c.waited = 0.0          # the festival starts fresh for everyone already in line
	_golden_clear()
	Sfx.play("build", -2.0, 0.8)
	return true


func bd_goal() -> int:
	return int(bd.get("goal", 40))


func bd_rating() -> float:
	if bd_scores.is_empty():
		return 5.0
	var s := 0.0
	for x in bd_scores:
		s += float(x)
	return s / bd_scores.size()


func _bd_count(guests: int, score: float) -> void:
	if not bd_active:
		return
	bd_served += guests
	for i in guests:
		bd_scores.append(score)


func _bd_tick(delta: float) -> void:
	_bd_cool = maxf(0.0, _bd_cool - delta)
	if not bd_active:
		return
	bd_left -= delta
	if bd_served >= bd_goal():
		_bd_end(true)
	elif bd_left <= 0.0 or bd_walkouts > bd_max_walkouts():
		_bd_end(false)


func bd_max_walkouts() -> int:
	return int(bd.get("max_walkouts", bd_goal() / 3))


func _bd_end(won: bool) -> void:
	bd_active = false
	if not won:
		_bd_cool = 45.0
	else:
		Game.stats.bigdays += 1
	var clean := won and bd_walkouts == 0
	Game.big_day_result(won, clean)
	big_day_finished.emit(won, bd_served, bd_goal())
	if won:
		fx_burst(player.global_position + Vector3(0, 2, 0), Color(1, 0.85, 0.3), 60)
		Sfx.play("cash", 0.0)
