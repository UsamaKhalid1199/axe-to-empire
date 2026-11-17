class_name Player
extends CharacterBody3D
## The lumberjack you control: run with the joystick, chop nearby trees, carry logs on your back
## and dishes in your hands.

const HIT_FRAC := 0.45        # point in the chop animation where the blade lands
const RUN_ANIM_SPEED := 4.6     # m/s covered by the run cycle at speed_scale 1
const CARRY_ANIM_SPEED := 2.9
const BACK_POS := Vector3(0, 1.12, -0.27)

var world: Node
var rig: CharacterRig
var back: Stack
var hands: Stack
var bubble: Label3D
var tool_root: Node3D
var vehicle: Node3D            # the harvester while you ride it (null on foot)
var harvester: Node3D          # owned harvester; parked in the world while you walk in camp
var saw_disc: Node3D
var input_dir := Vector2.ZERO
var chopping := false
var chop_phase := 0.0
var saw_timer := 0.0
var _targets: Array = []
var _equipped := ""
var _vel := Vector3.ZERO
var _bob := 0.0
var tool_out := false          # tool only appears near trees / while chopping
var _tool_hide_t := 0.0
var _saw: Node3D
var _tool_tw: Tween


func _ready() -> void:
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = 1.7
	cs.shape = cap
	cs.position.y = 0.85
	add_child(cs)
	rig = CharacterRig.new()
	add_child(rig)
	back = Stack.new().setup("log", Stack.Layout.BACK, 60)
	back.position = BACK_POS
	rig.add_child(back)
	hands = Stack.new().setup("dish", Stack.Layout.HANDS)
	hands.position = Vector3(0, 1.02, 0.46)
	rig.add_child(hands)
	bubble = Label3D.new()
	bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bubble.font = UI.font_bold()
	bubble.font_size = 64
	bubble.pixel_size = 0.005
	bubble.outline_size = 14
	bubble.outline_modulate = Color(0.1, 0.06, 0.02, 0.9)
	bubble.position.y = 2.25
	bubble.no_depth_test = true
	bubble.render_priority = 5
	add_child(bubble)
	tool_root = Node3D.new()
	equip_tool.call_deferred()
	Game.state_changed.connect(equip_tool)


const SAW_POS := Vector3(-0.12, 0.93, 0.40)     # in rig space (character faces +Z)
const SAW_ROT := Vector3(10, 6, 0)
var _saw_mount: Node3D
var _hips_rest_y := 0.0


func _hips_y() -> float:
	var sk := rig.skeleton
	var i := sk.find_bone("mixamorig1_Hips")
	return (sk.global_transform * sk.get_bone_global_pose(i)).origin.y - rig.global_position.y
var _pole_r: Node3D
var _pole_l: Node3D


## Elbow hints: right elbow out and back, left elbow out to the left.
func _saw_poles(saw: Node3D) -> void:
	_pole_r = Marker3D.new()
	_pole_r.position = Vector3(-0.55, 0.9, -0.25)
	saw.get_parent().add_child(_pole_r)
	_pole_l = Marker3D.new()
	_pole_l.position = Vector3(0.55, 1.0, 0.15)
	saw.get_parent().add_child(_pole_l)


func equip_tool() -> void:
	var t: Dictionary = Game.tool()
	if _equipped == t.id:
		return
	_equipped = t.id
	for c in tool_root.get_children():
		c.queue_free()
	var old_parent := tool_root.get_parent()
	if old_parent:
		old_parent.remove_child(tool_root)
		old_parent.queue_free()
	if vehicle:
		_dismount(false)
	if is_instance_valid(harvester):
		harvester.queue_free()
	harvester = null
	saw_disc = null
	var node: Node3D
	match t.id:
		"axe":
			node = Art.model("wooden_axe")
			node.rotation_degrees = Vector3(0, 90, -90)
			node.position = Vector3(0.03, 0.08, 0.02)
		"double_axe":
			node = Art.double_axe()
			node.rotation_degrees = Vector3(0, 0, -90)
			node.position = Vector3(0.03, 0.08, 0.02)
			node.scale = Vector3.ONE * 0.9
		"chainsaw":
			node = Art.chainsaw()
		"harvester":
			# parked beside you; you climb in when you walk into the forest
			harvester = Art.harvester()
			world.add_child(harvester)
			harvester.global_position = PARK_POS
			harvester.rotation.y = PI
			saw_disc = harvester.find_child("Disc", true, false)
			_update_ride(true)
	if node and t.id == "chainsaw":
		# held in front of the hips with both hands; arms are solved by IK onto the handles
		tool_root.add_child(node)
		_saw_mount = Node3D.new()        # freed with the tool like a bone attachment would be
		rig.add_child(_saw_mount)
		_saw_mount.add_child(tool_root)
		_hips_rest_y = _hips_y()
		node.position = SAW_POS
		node.rotation_degrees = SAW_ROT
		_saw_poles(node)
		_saw = node
	elif node:
		_saw_mount = null
		_saw = null
		rig.hold_with_both_hands(null, null, null, null)
		tool_root.add_child(node)
		rig.attach("mixamorig1_RightHand", tool_root)
	else:
		_saw_mount = null
		_saw = null
		rig.hold_with_both_hands(null, null, null, null)
	_show_tool(tool_out, true)
	if t.id != "axe":
		world.fx_burst(global_position + Vector3.UP, Color(1, 0.85, 0.4), 30)


## True when the player is standing (no stick input and nearly stopped). Zones act only then.
func is_still() -> bool:
	var kb := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	return input_dir.length() < 0.05 and kb.length() < 0.1 and Vector2(_vel.x, _vel.z).length() < 0.6


func _physics_process(delta: float) -> void:
	var t: Dictionary = Game.tool()
	var speed: float = float(Game.cfg.player.speed) * Game.speed_mult() * (1.15 if vehicle else 1.0)
	var inp := input_dir
	var kb := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if kb.length() > 0.1:
		inp = kb
	var want := Vector3(inp.x, 0, inp.y) * speed
	_vel = _vel.lerp(want, clampf(delta * 14.0, 0.0, 1.0))
	velocity = Vector3(_vel.x, -4.0, _vel.z)
	move_and_slide()
	global_position.y = 0.0
	var moving := Vector2(_vel.x, _vel.z).length() > 0.4
	if is_instance_valid(_saw_mount):
		_saw_mount.position.y = clampf(_hips_y() - _hips_rest_y, -0.12, 0.12) * 0.8
	if moving and inp.length() > 0.05:
		var yaw := atan2(_vel.x, _vel.z)
		rig.rotation.y = lerp_angle(rig.rotation.y, yaw, clampf(delta * 12.0, 0.0, 1.0))
		if vehicle:
			vehicle.rotation.y = rig.rotation.y
	_update_ride(false)
	if vehicle:
		rig.position = Vector3(sin(rig.rotation.y), 0, cos(rig.rotation.y)) * 0.35 + Vector3(0, 0.87, 0)
	_update_chop(delta, t, inp.length() > 0.15)
	_update_tool(delta, t)
	_update_anim(moving, t)
	_update_bubble()
	# back stack sway
	_bob += delta * (10.0 if moving else 2.0)
	if not vehicle:
		back.rotation.x = lerpf(back.rotation.x, (-0.06 if moving else 0.0) + sin(_bob) * 0.012, delta * 6.0)
	hands.rotation.x = back.rotation.x * -0.5


## The harvester is only for the forest: you climb in past the tree line and step out at the camp
## edge, so building, cooking and serving are always done on foot. The machine stays parked
## where you left it.
const RIDE_IN_Z := -4.6
const RIDE_OUT_Z := -4.0
const PARK_POS := Vector3(1.5, 0, -5.4)   # trail-side spot at the tree line, clear of the cookers


func _update_ride(instant: bool) -> void:
	if not is_instance_valid(harvester):
		return
	var z := global_position.z
	if vehicle == null and z < RIDE_IN_Z and hands.count() == 0:
		_mount(instant)
	elif vehicle != null and (z > RIDE_OUT_Z or hands.count() > 0):
		_dismount(not instant)


func _mount(instant: bool) -> void:
	vehicle = harvester
	var from := harvester.global_position
	harvester.reparent(self, false)
	harvester.position = Vector3.ZERO
	harvester.rotation = Vector3(0, rig.rotation.y, 0)
	if not instant:
		# drives up to you from where it was parked
		var off := from - global_position
		off.y = 0.0
		if off.length() > 0.3:
			harvester.position = off.limit_length(6.0)
			var tw := create_tween()
			tw.tween_property(harvester, "position", Vector3.ZERO, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		world.fx_burst(global_position + Vector3(0, 0.4, 0), Color(0.75, 0.62, 0.45), 14)
		Sfx.play("pop", -8.0)
	back.reparent(harvester.get_node("Bed"), false)
	back.layout = Stack.Layout.BUNK
	back.position = Vector3.ZERO
	back.rotation = Vector3.ZERO
	back.relayout()


func _dismount(park: bool) -> void:
	var h := vehicle
	vehicle = null
	back.reparent(rig, false)
	back.layout = Stack.Layout.BACK
	back.position = BACK_POS
	back.rotation = Vector3.ZERO
	back.relayout()
	rig.position = Vector3.ZERO
	Sfx.saw(false)
	if park and is_instance_valid(h):
		var yaw := rig.rotation.y
		h.reparent(world, false)
		# park it a step behind you, back toward the trees, so it never blocks the camp
		h.global_position = Vector3(global_position.x, 0, minf(global_position.z - 1.2, PARK_POS.z))
		h.rotation = Vector3(0, yaw, 0)
		world.fx_burst(global_position + Vector3(0, 0.4, 0), Color(0.75, 0.62, 0.45), 10)


## Tool comes out near trees or while chopping; it is put away when serving, collecting or walking in camp.
func _update_tool(delta: float, t: Dictionary) -> void:
	if is_instance_valid(harvester):
		return
	var want: bool = hands.count() == 0 and (chopping or not world.trees_near(global_position, float(t.range) + 1.8, 1).is_empty())
	if want:
		_tool_hide_t = 0.6
		if not tool_out:
			_show_tool(true)
	else:
		_tool_hide_t -= delta
		if tool_out and _tool_hide_t <= 0.0:
			_show_tool(false)


func _show_tool(on: bool, instant := false) -> void:
	tool_out = on
	if _tool_tw:
		_tool_tw.kill()
	var to := Vector3.ONE if on else Vector3.ONE * 0.001
	if on:
		tool_root.visible = true
	if instant:
		tool_root.scale = to
		tool_root.visible = on
	else:
		_tool_tw = create_tween()
		_tool_tw.tween_property(tool_root, "scale", to, 0.16 if on else 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT if on else Tween.EASE_IN)
		if not on:
			_tool_tw.tween_callback(func(): tool_root.visible = false)
	if is_instance_valid(_saw):
		if on:
			rig.hold_with_both_hands(_saw.get_node("GripRear"), _saw.get_node("GripTop"), _pole_r, _pole_l)
		else:
			rig.hold_with_both_hands(null, null, null, null)


func _update_chop(delta: float, t: Dictionary, pushing: bool) -> void:
	var was := chopping
	chopping = false
	_targets.clear()
	var cap := Game.bag_cap()
	var on_foot_with_harvester := is_instance_valid(harvester) and not vehicle
	if hands.count() == 0 and back.count() < cap and not on_foot_with_harvester:
		var can := bool(t.move_chop) or not pushing
		if can:
			_targets = world.trees_near(global_position, float(t.range), int(t.aoe))
			chopping = not _targets.is_empty()
	if not chopping:
		Sfx.saw(false)
		if saw_disc and vehicle:
			saw_disc.rotate_y(delta * 4.0)
		return
	if bool(t.move_chop):
		Sfx.saw(true, 1.0 + 0.1 * sin(Time.get_ticks_msec() * 0.01))
		if saw_disc:
			saw_disc.rotate_y(delta * 40.0)
		saw_timer -= delta
		if saw_timer <= 0.0:
			saw_timer = float(t.interval)
			_hit(t)
		return
	# axe: face the tree, sync hits to the swing
	var tr: ChopTree = _targets[0]
	var to := tr.global_position - global_position
	rig.rotation.y = lerp_angle(rig.rotation.y, atan2(to.x, to.z), clampf(delta * 14.0, 0.0, 1.0))
	if not was:
		chop_phase = 0.0
		rig.current = ""
	var prev := chop_phase
	chop_phase += delta / float(t.interval)
	if prev < HIT_FRAC and chop_phase >= HIT_FRAC:
		_hit(t)
	if chop_phase >= 1.0:
		chop_phase -= 1.0


func _hit(t: Dictionary) -> void:
	var cap := Game.bag_cap()
	for tr in _targets:
		if not is_instance_valid(tr) or not tr.alive:
			continue
		var room := cap - back.count()
		if room <= 0:
			break
		var logs: int = tr.hit(mini(int(t.dmg), room), global_position)
		world.on_tree_hit(tr, logs, self)
		for i in logs:
			back.receive(tr.global_position + Vector3(0, 1.0 + i * 0.2, 0), 0.3 + i * 0.05)
	if not bool(t.move_chop):
		Sfx.play("chop", -2.0)
		if OS.has_feature("mobile"):
			Input.vibrate_handheld(18)


func _update_anim(moving: bool, t: Dictionary) -> void:
	var carrying := hands.count() > 0
	if vehicle:
		rig.play("carry_idle")
	elif chopping and not bool(t.move_chop):
		rig.play("chop", rig.anim.get_animation("a/chop").length / float(t.interval), 0.1)
	elif tool_out and t.id == "chainsaw":
		rig.play("carry_run" if moving else "carry_idle", _anim_rate(CARRY_ANIM_SPEED) if moving else 1.0)
	elif carrying:
		rig.play("carry_run" if moving else "carry_idle", _anim_rate(CARRY_ANIM_SPEED) if moving else 1.0)
	else:
		rig.play("run" if moving else "idle", _anim_rate(RUN_ANIM_SPEED) if moving else 1.0)


func _anim_rate(cycle_speed: float) -> float:
	return clampf(Vector2(_vel.x, _vel.z).length() / cycle_speed, 0.55, 1.8)


func _update_bubble() -> void:
	var cap := Game.bag_cap()
	if back.count() >= cap:
		bubble.text = "MAX"
		bubble.modulate = Color("#FF8A5B")
	elif hands.count() >= int(Game.cfg.player.carry_dishes):
		bubble.text = "HANDS FULL"
		bubble.modulate = Color("#FFD978")
	elif back.count() > 0:
		bubble.text = "%d/%d" % [back.count(), cap]
		bubble.modulate = Color(1, 1, 1, 0.95)
	else:
		bubble.text = ""
