class_name ChopTree
extends Node3D
## A choppable pine: HP = logs it gives. Falls, leaves a stump, regrows.

signal felled(tree: ChopTree)

var max_hp := 4
var hp := 4
var alive := true
var reserved_by: Node = null
var regrow_left := 0.0
var regrow_time := 16.0
var variant := 0
## Drawn by the world's forest MultiMesh while standing still (see world._batch_trees).
var batched := false
var batch_idx := -1
var batch_key := Vector2i(-1, -1)
var growing := false
## Stumps don't regrow while the player stands near them; they must move on.
static var player: Node3D
## Trees hit since the world's last foliage pass (it takes them out of the batch the same frame).
static var woken: Array = []
const REGROW_CLEAR := 7.0
var body: Node3D          # rotates when falling
var mesh: MeshInstance3D
var stump: Node3D
var collider: CollisionShape3D
var _shake := 0.0


func setup(v: int, hp_max: int, regrow: float) -> void:
	variant = v
	max_hp = hp_max
	hp = hp_max
	regrow_time = regrow


func _ready() -> void:
	body = Node3D.new()
	add_child(body)
	mesh = MeshInstance3D.new()
	mesh.mesh = Art.pine_mesh(variant)
	body.add_child(mesh)
	var sm := MeshInstance3D.new()
	sm.mesh = Art.stump_mesh()
	sm.rotation.y = randf() * TAU
	stump = sm
	stump.scale = Vector3.ONE
	stump.visible = false
	add_child(stump)
	var sb := StaticBody3D.new()
	collider = CollisionShape3D.new()
	var cs := CylinderShape3D.new()
	cs.radius = 0.32
	cs.height = 2.0
	collider.shape = cs
	collider.position.y = 1.0
	sb.add_child(collider)
	add_child(sb)
	rotation.y = randf() * TAU
	var s := randf_range(0.85, 1.12)
	body.scale = Vector3(s, s * randf_range(0.95, 1.08), s)


func _process(delta: float) -> void:
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta * 6.0)
		body.rotation.z = sin(_shake * 40.0) * 0.06 * _shake
		body.rotation.x = cos(_shake * 33.0) * 0.04 * _shake
	if not alive:
		regrow_left -= delta
		if regrow_left <= 0.0 and not body.visible and not _watched():
			_regrow()


## Returns logs produced by this hit.
func hit(dmg: int, from: Vector3) -> int:
	if not alive:
		return 0
	var n := mini(dmg, hp)
	hp -= n
	_shake = 1.0
	woken.append(self)
	if hp <= 0:
		_fall(from)
	return n


func _fall(from: Vector3) -> void:
	alive = false
	reserved_by = null
	collider.set_deferred("disabled", true)
	regrow_left = regrow_time
	stump.visible = true
	stump.scale = Vector3.ONE
	var away := global_position - from
	away.y = 0
	if away.length() < 0.01:
		away = Vector3.FORWARD
	away = away.normalized()
	# fall: rotate around an axis perpendicular to `away`, in local space
	var axis := Vector3.UP.cross(away).normalized()
	var local_axis := (global_basis.inverse() * axis).normalized()
	var start_b := body.basis
	var rest := 1.22          # crown lies on the ground instead of cutting into it
	var tw := create_tween()
	var fall_step := func(a: float):
		body.basis = Basis(local_axis, a) * start_b
	tw.tween_method(fall_step, 0.0, rest, 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_method(fall_step, rest, rest - 0.09, 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_method(fall_step, rest - 0.09, rest, 0.16).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_interval(0.35)
	tw.tween_property(body, "position:y", -2.2, 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		body.visible = false
		body.position.y = 0.0
		body.scale = Vector3(0.001, 0.001, 0.001))
	felled.emit(self)


func _regrow() -> void:
	body.basis = Basis.IDENTITY
	body.position.y = 0.0
	body.scale = Vector3(0.12, 0.12, 0.12)
	body.visible = true
	var s := randf_range(0.85, 1.12)
	growing = true
	var tw := create_tween()
	tw.tween_property(body, "scale", Vector3(s, s, s), 2.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(stump, "scale", Vector3.ONE * 0.001, 0.6)
	tw.tween_callback(func():
		stump.visible = false
		growing = false)
	hp = max_hp
	alive = true
	collider.set_deferred("disabled", false)


func top_pos() -> Vector3:
	return global_position + Vector3(0, 2.6, 0)


func _watched() -> bool:
	return is_instance_valid(player) and player.global_position.distance_squared_to(global_position) < REGROW_CLEAR * REGROW_CLEAR
