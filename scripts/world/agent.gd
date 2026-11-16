class_name Agent
extends Node3D
## Base for crew and customers: a Pete rig that walks along waypoints.

var world: Node
var rig: CharacterRig
var speed := 2.5
var path: Array[Vector3] = []
var carry_anim := false
var walker := false          # customers walk; crew jog
const WALK_CYCLE := 1.45
const RUN_CYCLE := 4.6
const CARRY_CYCLE := 2.9


func _make_rig(kind: String, seed_i: int) -> void:
	rig = CharacterRig.new()
	add_child(rig)
	rig.outfit(kind, seed_i)


func go(points: Array) -> void:
	path.clear()
	for p in points:
		path.append(p)


## Steps along the path; returns true when the path is finished.
func walk(delta: float) -> bool:
	if path.is_empty():
		rig.play("carry_idle" if carry_anim else "idle")
		return true
	var target: Vector3 = path[0]
	var to := target - global_position
	to.y = 0
	var d := to.length()
	var step := speed * delta
	if d <= step:
		global_position = Vector3(target.x, 0, target.z)
		path.pop_front()
		if path.is_empty():
			rig.play("carry_idle" if carry_anim else "idle")
			return true
		return false
	global_position += to / d * step
	rig.rotation.y = lerp_angle(rig.rotation.y, atan2(to.x, to.z), clampf(delta * 10.0, 0.0, 1.0))
	if carry_anim:
		rig.play("carry_run", speed / CARRY_CYCLE)
	elif walker:
		rig.play("walk", speed / WALK_CYCLE)
	else:
		rig.play("run", clampf(speed / RUN_CYCLE * 1.25, 0.6, 1.4))
	return false


func face(p: Vector3, delta: float) -> void:
	var to := p - global_position
	rig.rotation.y = lerp_angle(rig.rotation.y, atan2(to.x, to.z), clampf(delta * 8.0, 0.0, 1.0))
