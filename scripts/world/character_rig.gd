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


func _ready() -> void:
	if _scene == null:
		_scene = load(BASE + "pete_idle_skin.fbx")
	var inst: Node3D = _scene.instantiate()
	add_child(inst)
	skeleton = inst.get_node("Skeleton3D")
	anim = inst.get_node("AnimationPlayer")
	anim.add_animation_library("a", library())
	# one baked skinned mesh instead of 8 (see tests/bake_pete.gd): far fewer skinning passes and draws
	if not use_merged:
		play("idle")
		return
	for c in skeleton.get_children():
		if c is MeshInstance3D:
			c.free()
	body = MeshInstance3D.new()
	body.name = "Body"
	skeleton.add_child(body)
	body.skeleton = NodePath("..")
	body.skin = load(MERGED + "skin.res")
	_set_variant("full")
	play("idle")


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
