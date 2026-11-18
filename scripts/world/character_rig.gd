class_name CharacterRig
extends Node3D
## Pete (Mixamo) + shared animation library. Variants hide/tint parts for crew and customers.

const BASE := "res://assets/characters/pete/"
const ANIMS := {
	"idle": "pete_idle_skin.fbx", "run": "anim_run.fbx", "chop": "anim_chop.fbx",
	"carry_run": "anim_carry_run.fbx", "carry_idle": "anim_carry_idle.fbx", "pickup": "anim_pickup.fbx",
	"walk": "anim_walk.fbx", "sit": "anim_sit.fbx",
}
const LOOPS := ["idle", "run", "carry_run", "carry_idle", "chop", "walk", "sit"]

static var _scene: PackedScene
static var _lib: AnimationLibrary
static var _tints: Dictionary = {}

var anim: AnimationPlayer
var skeleton: Skeleton3D
var current := ""


static func library() -> AnimationLibrary:
	if _lib:
		return _lib
	_lib = AnimationLibrary.new()
	for key in ANIMS:
		var ps: PackedScene = load(BASE + ANIMS[key])
		var inst := ps.instantiate()
		var ap: AnimationPlayer = inst.get_node("AnimationPlayer")
		var a: Animation = ap.get_animation("mixamo_com").duplicate(true)
		a.loop_mode = Animation.LOOP_LINEAR if key in LOOPS else Animation.LOOP_NONE
		_strip_root_xz(a)
		_lib.add_animation(key, a)
		inst.free()
	return _lib


static func _strip_root_xz(a: Animation) -> void:
	for t in a.get_track_count():
		if a.track_get_type(t) != Animation.TYPE_POSITION_3D:
			continue
		if not String(a.track_get_path(t)).ends_with("Hips"):
			continue
		if a.track_get_key_count(t) == 0:
			continue
		var first: Vector3 = a.track_get_key_value(t, 0)
		for k in a.track_get_key_count(t):
			var v: Vector3 = a.track_get_key_value(t, k)
			a.track_set_key_value(t, k, Vector3(first.x, v.y, first.z))


## The imported rig with its 8 part meshes already removed and the animation library attached, packed once:
## every crew member and guest instantiates this instead of the full import (then freeing 8 meshes each).
static var _stripped: PackedScene


## Set owners so pack() keeps the children (local copy: this script must not depend on art.gd / the Game autoload).
static func _own(n: Node, root: Node) -> void:
	for c in n.get_children():
		c.owner = root
		_own(c, root)


static func _stripped_scene() -> PackedScene:
	if _stripped == null:
		var inst: Node3D = _scene.instantiate()
		var sk := inst.get_node("Skeleton3D")
		for c in sk.get_children():
			if c is MeshInstance3D:
				c.free()
		(inst.get_node("AnimationPlayer") as AnimationPlayer).add_animation_library("a", library())
		_own(inst, inst)
		_stripped = PackedScene.new()
		_stripped.pack(inst)
		inst.free()
	return _stripped


func _ready() -> void:
	if _scene == null:
		_scene = load(BASE + "pete_idle_skin.fbx")
	var inst: Node3D = (_stripped_scene() if use_merged else _scene).instantiate()
	add_child(inst)
	skeleton = inst.get_node("Skeleton3D")
	anim = inst.get_node("AnimationPlayer")
	# one baked skinned mesh instead of 8 (see tests/bake_pete.gd): far fewer skinning passes and draws
	if not use_merged:
		anim.add_animation_library("a", library())
		play("idle")
		return
	body = MeshInstance3D.new()
	body.name = "Body"
	skeleton.add_child(body)
	body.skeleton = NodePath("..")
	body.skin = load(MERGED + "skin.res")
	_set_variant("full")
	play("idle")
	# player.gd builds a bare CharacterRig; agents call outfit(kind) afterwards
	var p := get_parent()
	if p and p.get_script() and p.get_script().get_global_name() == &"Player":
		_enable_outfit()
		_lod_focus = p
	else:
		_lod_on()


# ------------------------------------------------------------------ animation LOD
## Crew and guests drive their AnimationPlayer by hand: full rate near the player, every other frame
## (staggered) elsewhere on screen, and only a few times a second while off screen. Skeleton + skinning
## updates only happen when the pose changes, so this saves both the animation and the skinning cost.
## Movement (the agent's position) is untouched: only limb poses update less often.
const LOD_NEAR := 5.5            # metres from the player: full rate
const LOD_OFF_EVERY := 10        # frames between pose updates while off screen
static var _lod_n := 0
static var _lod_focus: Node3D    # the player (full-rate radius centre)
var _lod := false
var _lod_acc := 0.0
var _lod_slot := 0


func _lod_on() -> void:
	_lod = true
	_lod_slot = _lod_n
	_lod_n += 1
	anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	process_priority = 10        # after the agent's own _process (which picks the animation)


func _process(delta: float) -> void:
	if not _lod:
		return
	_lod_acc += delta
	var every := _lod_every()
	if every > 1 and (Engine.get_process_frames() + _lod_slot) % every != 0:
		return
	anim.advance(_lod_acc)
	_lod_acc = 0.0


func _lod_every() -> int:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return 1
	var p := global_position + Vector3(0, 0.9, 0)
	if cam.is_position_behind(p):
		return LOD_OFF_EVERY
	var vs := get_viewport().get_visible_rect().size
	var sp := cam.unproject_position(p)
	var mx := vs.x * 0.12
	var my := vs.y * 0.12
	if sp.x < -mx or sp.y < -my or sp.x > vs.x + mx or sp.y > vs.y + my:
		return LOD_OFF_EVERY
	var pl := _lod_focus
	if is_instance_valid(pl) and pl.global_position.distance_squared_to(p) < LOD_NEAR * LOD_NEAR:
		return 1
	return 2


const MERGED := BASE + "merged/"
static var use_merged := true
var body: MeshInstance3D
var _tint_of := {}


func _set_variant(v: String) -> void:
	if body == null:
		return
	body.mesh = load(MERGED + v + ".res")
	var lite := OS.has_feature("mobile")
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if lite else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for i in body.mesh.get_surface_count():
		body.set_surface_override_material(i, null)
	if lite:
		_lite_materials(body)
	for pn in _tint_of:
		_tint(pn, _tint_of[pn])


static var _lite_cache := {}


## Phones: drop normal/roughness/metal maps on the character (big fill-rate cost on weak GPUs).
func _lite_materials(mi: MeshInstance3D) -> void:
	for i in mi.mesh.get_surface_count():
		var src: Material = mi.get_active_material(i)
		if not (src is StandardMaterial3D):
			continue
		if not _lite_cache.has(src):
			var m: StandardMaterial3D = src.duplicate()
			m.normal_enabled = false
			m.roughness_texture = null
			m.metallic_texture = null
			m.ao_enabled = false
			m.metallic = 0.0
			m.roughness = 0.85
			_lite_cache[src] = m
		mi.set_surface_override_material(i, _lite_cache[src])


var _ik: TwoBoneIK3D


## Puts both hands on IK targets (e.g. chainsaw handles). Pass nulls to release.
func hold_with_both_hands(right: Node3D, left: Node3D, right_pole: Node3D, left_pole: Node3D) -> void:
	if _ik == null:
		_ik = TwoBoneIK3D.new()
		skeleton.add_child(_ik)
		_ik.set("setting_count", 2)
		var sides := [["Right"], ["Left"]]
		for i in 2:
			var sd: String = sides[i][0]
			_ik.set_root_bone_name(i, "mixamorig1_%sArm" % sd)
			_ik.set_middle_bone_name(i, "mixamorig1_%sForeArm" % sd)
			_ik.set_end_bone_name(i, "mixamorig1_%sHand" % sd)
	if right == null:
		_ik.active = false
		return
	_ik.active = true
	_ik.set_target_node(0, _ik.get_path_to(right))
	_ik.set_target_node(1, _ik.get_path_to(left))
	_ik.set_pole_node(0, _ik.get_path_to(right_pole))
	_ik.set_pole_node(1, _ik.get_path_to(left_pole))


func play(name: String, speed := 1.0, blend := 0.18) -> void:
	if current == name:
		anim.speed_scale = speed
		return
	current = name
	anim.play("a/" + name, blend)
	anim.speed_scale = speed


func attach(bone: String, node: Node3D) -> BoneAttachment3D:
	var ba := BoneAttachment3D.new()
	ba.bone_name = bone
	skeleton.add_child(ba)
	ba.add_child(node)
	return ba


func _surface(part_name: String) -> int:
	return body.mesh.surface_find_by_name(part_name) if body and body.mesh else -1


## Outfit variants. kind: "player", "lumberjack", "waiter", "cook", "customer"
func outfit(kind: String, seed_i := 0) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_i * 7919 + 13
	match kind:
		"player":
			_enable_outfit()
		"lumberjack":
			_tint("Shirt", Color(0.85, 0.32, 0.25))
			_tint("Vest", Color(0.55, 0.75, 1.0))
		"waiter":
			_set_variant("bare")
			_tint("Shirt", Color(1.15, 1.15, 1.15))
			_tint("Pants", Color(0.35, 0.35, 0.4))
		"cook":
			_set_variant("nohelmet")
			_tint("Vest", Color(1.4, 1.4, 1.4))
			_tint("Shirt", Color(1.2, 1.2, 1.2))
		"customer":
			_set_variant("bare")
			var shirts := [Color(0.45, 0.65, 1.0), Color(1.0, 0.55, 0.45), Color(0.6, 0.95, 0.6),
				Color(1.0, 0.9, 0.5), Color(0.8, 0.6, 1.0), Color(0.5, 0.5, 0.55), Color(1.2, 1.2, 1.2)]
			_tint("Shirt", shirts[rng.randi() % shirts.size()])
			_tint("Pants", [Color(0.5, 0.6, 0.9), Color(0.6, 0.5, 0.4), Color(0.3, 0.3, 0.32)][rng.randi() % 3])
			_tint("Hair", [Color(0.35, 0.25, 0.2), Color(1.4, 1.2, 0.8), Color(0.25, 0.25, 0.25), Color(1.2, 0.7, 0.45)][rng.randi() % 4])
			scale = Vector3.ONE * rng.randf_range(0.92, 1.06)
	if kind != "player" and bake_tints:
		_bake_tints()


func _tint(part_name: String, c: Color) -> void:
	_tint_of[part_name] = c
	var si := _surface(part_name)
	if si < 0:
		return
	var src: Material = body.get_active_material(si)
	if src is StandardMaterial3D:
		var key := "%s:%s:%s" % [part_name, c.to_html(), src.normal_enabled]
		if not _tints.has(key):
			var m: StandardMaterial3D = src.duplicate()
			m.albedo_color = c
			_tints[key] = m
		body.set_surface_override_material(si, _tints[key])


# ------------------------------------------------------------------ baked crew / guest outfits
## Body, helmet, vest, shirt and pants all use the same texture and material; only the tint differs. For crew
## and guests those surfaces are baked into ONE surface whose vertex colours carry the tints, so a guest is
## 2 draws (that + hair) instead of 4, a lumberjack 2 instead of 6. Vertex colours are 8-bit (max 1.0), so a
## part tinted brighter than 1.0 (white shirts, the cook's vest) keeps its own surface and tinted material.
## Colours match the old per-surface tints (vertex colour is sRGB like albedo_color; checked pixel for pixel).
## Geometry (incl. every LOD level) is merged once per variant + part set; each tint combo is one cached mesh.
static var bake_tints := true
static var _bake_geo := {}       # variant path + parts -> {arrays, lods, parts: [[name, from, count]], rest: [[arrays, lods, name, src surface]]}
static var _bake_meshes := {}    # variant + parts + tints -> ArrayMesh
static var _bake_mats := {}      # source material -> vertex-colour material


func _bake_tints() -> void:
	if body == null or not (body.mesh is ArrayMesh):
		return
	var src: ArrayMesh = body.mesh
	var main_mat := src.surface_get_material(0) as StandardMaterial3D
	if main_mat == null or not (body.get_active_material(0) is StandardMaterial3D):
		return
	var merge_names := []
	for si in src.get_surface_count():
		if src.surface_get_material(si) != main_mat:
			continue
		var t: Color = _tint_of.get(src.surface_get_name(si), main_mat.albedo_color)
		if maxf(t.r, maxf(t.g, t.b)) <= 1.0:
			merge_names.append(src.surface_get_name(si))
	if merge_names.size() < 2:
		return
	var gkey := src.resource_path + ":" + ",".join(merge_names)
	var geo: Dictionary = _bake_geo.get(gkey, {})
	if geo.is_empty():
		geo = _bake_merge(src, merge_names)
		_bake_geo[gkey] = geo
	var key := gkey
	for part in geo.parts:
		key += ":" + (_tint_of.get(part[0], main_mat.albedo_color) as Color).to_html()
	var rest_mats := []
	for r in geo.rest:
		rest_mats.append(body.get_active_material(r[3]))
	if not _bake_meshes.has(key):
		var am := ArrayMesh.new()
		var arrays: Array = geo.arrays.duplicate()
		var colors := PackedColorArray()
		for part in geo.parts:
			var t: Color = _tint_of.get(part[0], main_mat.albedo_color)
			var chunk := PackedColorArray()
			chunk.resize(part[2])
			chunk.fill(Color(t.r, t.g, t.b, 1.0))
			colors.append_array(chunk)
		arrays[Mesh.ARRAY_COLOR] = colors
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], geo.lods)
		am.surface_set_name(0, "Baked")
		for r in geo.rest:
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, r[0], [], r[1])
			am.surface_set_name(am.get_surface_count() - 1, r[2])
		_bake_meshes[key] = am
	# the vertex-colour material is the one the main surfaces wear untinted (lite on phones), albedo white
	var base: StandardMaterial3D = _lite_cache.get(main_mat, main_mat) if OS.has_feature("mobile") else main_mat
	if not _bake_mats.has(base):
		var vm: StandardMaterial3D = base.duplicate()
		vm.albedo_color = Color(1, 1, 1, base.albedo_color.a)
		vm.vertex_color_use_as_albedo = true
		vm.vertex_color_is_srgb = true
		_bake_mats[base] = vm
	body.mesh = _bake_meshes[key]
	body.set_surface_override_material(0, _bake_mats[base])
	for i in geo.rest.size():
		body.set_surface_override_material(i + 1, rest_mats[i])


## Concatenates the named surfaces (vertices, skin weights, indices and LOD indices); the rest stay as they are.
static func _bake_merge(src: ArrayMesh, names: Array) -> Dictionary:
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	var idx := PackedInt32Array()
	var parts := []
	var rest := []
	var lod_parts := []          # per merged part: [base indices, {edge_length: indices}], already offset
	var n := 0
	for si in src.get_surface_count():
		var a := src.surface_get_arrays(si)
		var lods := _surface_lods(src, si)
		if not names.has(src.surface_get_name(si)):
			rest.append([a, lods, src.surface_get_name(si), si])
			continue
		var cnt: int = (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		for k in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TANGENT, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2,
				Mesh.ARRAY_BONES, Mesh.ARRAY_WEIGHTS]:
			if a[k] == null:
				continue
			if out[k] == null:
				out[k] = a[k].duplicate()
			else:
				out[k].append_array(a[k])
		var ia: PackedInt32Array = _offset(a[Mesh.ARRAY_INDEX], n)
		idx.append_array(ia)
		for e in lods:
			lods[e] = _offset(lods[e], n)
		parts.append([src.surface_get_name(si), n, cnt])
		lod_parts.append([ia, lods])
		n += cnt
	out[Mesh.ARRAY_INDEX] = idx
	# LOD levels: for every edge length used by any part, each part contributes its coarsest level that is
	# not coarser than that edge length (exactly what it would have drawn on its own at that distance)
	var edges := []
	for lp in lod_parts:
		for e in lp[1]:
			if not edges.has(e):
				edges.append(e)
	edges.sort()
	var merged_lods := {}
	for e in edges:
		var li := PackedInt32Array()
		for lp in lod_parts:
			var best := -1.0
			for pe in lp[1]:
				if pe <= e and pe > best:
					best = pe
			li.append_array(lp[0] if best < 0.0 else lp[1][best])
		merged_lods[e] = li
	return {"arrays": out, "lods": merged_lods, "parts": parts, "rest": rest}


static func _offset(a: PackedInt32Array, by: int) -> PackedInt32Array:
	var o := a.duplicate()
	if by != 0:
		for j in o.size():
			o[j] += by
	return o


## A surface's LOD index lists ({edge_length: PackedInt32Array}), read back from the RenderingServer.
static func _surface_lods(m: ArrayMesh, si: int) -> Dictionary:
	var sd: Dictionary = RenderingServer.mesh_get_surface(m.get_rid(), si)
	var out := {}
	var lods: Array = sd.get("lods", [])
	if lods.is_empty():
		return out
	var vcount: int = sd.get("vertex_count", 0)
	var wide: bool = vcount > 65535 or (sd.has("index_count") and sd.index_count > 0 and (sd.index_data as PackedByteArray).size() / int(sd.index_count) == 4)
	for l in lods:
		var data: PackedByteArray = l.index_data
		var ia := PackedInt32Array()
		if wide:
			ia = data.to_int32_array()
		else:
			ia.resize(data.size() / 2)
			for j in ia.size():
				ia[j] = data.decode_u16(j * 2)
		out[float(l.edge_length)] = ia
	return out


# ------------------------------------------------------------------ player wardrobe
## Shirt/Pants/Vest/Helmet are separate surfaces of the merged mesh, so outfits only swap per-surface
## materials (no extra draws). Hats that the mesh lacks are one merged vertex-coloured mesh on the head bone.

const HEAD_BONE := "mixamorig1_Head"
## Recolour: keep the painted folds/dirt (luminance), replace the hue. Optional plaid/stripes from UV.
const RECOLOR_SHADER := """
shader_type spatial;
render_mode cull_back;
uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 col_a : source_color = vec3(1.0);
uniform vec3 col_b : source_color = vec3(0.0);
uniform int pattern = 0;
uniform float gain = 3.0;
uniform float freq = 36.0;
uniform float rough = 0.85;
uniform float flatten = 0.0;
//NORMAL_DECL
float band(float x, float a, float b) {
	float w = fwidth(x) * 1.5 + 0.001;
	return smoothstep(a - w, a + w, x) - smoothstep(b - w, b + w, x);
}
void fragment() {
	vec3 t = texture(tex, UV).rgb;
	float l = dot(t, vec3(0.299, 0.587, 0.114));
	// vest as shirt: hide the yellow reflective bands (green ~ red there, unlike the orange cloth)
	l = mix(l, 0.42, flatten * smoothstep(0.55, 0.8, t.g / max(t.r, 0.02)));
	float shade = clamp(sqrt(l * gain), 0.3, 1.25);
	vec3 c = col_a;
	if (pattern == 1) {
		vec2 g = fract(UV * freq);
		float bx = band(g.x, 0.0, 0.42);
		float by = band(g.y, 0.0, 0.42);
		c = mix(col_a, col_b, clamp((bx + by) * 0.5, 0.0, 1.0));
		float th = max(band(g.x, 0.66, 0.70), band(g.y, 0.66, 0.70));
		c = mix(c, mix(col_a, vec3(1.0), 0.45), th * 0.6);
	} else if (pattern == 2) {
		c = mix(col_a, col_b, band(fract(UV.y * freq), 0.0, 0.4));
	}
	ALBEDO = c * shade;
	ROUGHNESS = rough;
	//NORMAL_USE
}
"""
const PATTERNS := {"plain": 0, "plaid": 1, "stripes": 2}
const GAIN := {"Shirt": 4.0, "Pants": 4.0, "Vest": 2.3}

static var _recolor_shaders := {}
static var _recolor_mats := {}

var wears_outfit := false
var _hat: MeshInstance3D


func _enable_outfit() -> void:
	if wears_outfit:
		return
	wears_outfit = true
	var g := get_node_or_null("/root/Game")
	if g and g.has_signal("profile_changed") and not g.profile_changed.is_connected(apply_outfit):
		g.profile_changed.connect(apply_outfit)
	apply_outfit()


## Re-reads Game.profile and dresses the rig (player only). Safe to call any time after _ready.
func apply_outfit() -> void:
	Wardrobe.apply(self)


## Dresses the rig with catalog items (dictionaries from Wardrobe.item). Used by Wardrobe.apply.
func wear(shirt: Dictionary, hat: Dictionary, pants: Dictionary) -> void:
	if body == null:
		return
	# The "bare" mesh has no torso (it is cut away under the vest), so the player always keeps the
	# Vest surface: hi-vis items tint it, every other shirt recolours it into the shirt's torso.
	var vest: Array = shirt.get("vest", [])
	var hat_kind: String = hat.get("mesh", "none")
	var builtin_helmet := hat_kind == "hardhat"
	_tint_of.clear()
	if not vest.is_empty():
		_tint_of["Vest"] = Color(vest[0], vest[1], vest[2])
	if builtin_helmet:
		var hc: Array = hat.get("color", [1, 1, 1])
		_tint_of["Helmet"] = Color(hc[0], hc[1], hc[2]) * 1.1
	_set_variant("full" if builtin_helmet else "nohelmet")
	if vest.is_empty():
		_recolor("Vest", shirt)
	if shirt.has("under"):
		var u: Array = shirt.under
		_recolor("Shirt", {"id": shirt.get("id", "") + ":under", "color": u})
	elif not shirt.get("original", false):
		_recolor("Shirt", shirt)
	if not pants.get("original", false):
		_recolor("Pants", pants)
	var hm: ArrayMesh = null if builtin_helmet else Wardrobe.hat_mesh(hat)
	if hm == null:
		if _hat:
			_hat.visible = false
		return
	if _hat == null:
		_hat = MeshInstance3D.new()
		_hat.name = "Hat"
		attach(HEAD_BONE, _hat)
	_hat.mesh = hm
	_hat.cast_shadow = body.cast_shadow
	_hat.visible = true


func _recolor(part: String, it: Dictionary) -> void:
	var si := _surface(part)
	if si < 0 or not it.has("color"):
		return
	var src: Material = body.mesh.surface_get_material(si)
	if not (src is StandardMaterial3D):
		return
	var lite := OS.has_feature("mobile")
	var key := "%s:%s:%s:%s" % [part, it.get("id", ""), it.color, lite]
	if not _recolor_mats.has(key):
		var sm: StandardMaterial3D = src
		var normal := sm.normal_enabled and not lite and sm.normal_texture != null
		if not _recolor_shaders.has(normal):
			var sh := Shader.new()
			var code := RECOLOR_SHADER
			if normal:
				code = code.replace("//NORMAL_DECL", "uniform sampler2D nrm : hint_normal, filter_linear_mipmap;")
				code = code.replace("//NORMAL_USE", "NORMAL_MAP = texture(nrm, UV).rgb;")
			sh.code = code
			_recolor_shaders[normal] = sh
		var m := ShaderMaterial.new()
		m.shader = _recolor_shaders[normal]
		var a: Array = it.color
		var b: Array = it.get("secondary", a)
		m.set_shader_parameter("tex", sm.albedo_texture)
		m.set_shader_parameter("col_a", Color(a[0], a[1], a[2]))
		m.set_shader_parameter("col_b", Color(b[0], b[1], b[2]))
		m.set_shader_parameter("pattern", PATTERNS.get(it.get("pattern", "plain"), 0))
		m.set_shader_parameter("gain", GAIN.get(part, 3.0))
		m.set_shader_parameter("flatten", 1.0 if part == "Vest" else 0.0)
		m.set_shader_parameter("rough", 0.85 if lite else 0.75)
		if normal:
			m.set_shader_parameter("nrm", sm.normal_texture)
		_recolor_mats[key] = m
	body.set_surface_override_material(si, _recolor_mats[key])
