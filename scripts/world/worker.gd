class_name Worker
extends Agent
## Crew member. role: lumberjack (chop -> woodpile), waiter (rack -> counter), cook (stands at a fire).
## The crew is slower than the player and never sells logs: a full woodpile means they wait.

var role := "lumberjack"
var state := "idle"
var target: ChopTree
var back: Stack
var hands: Stack
var timer := 0.0
var fire_index := 0
var chop_phase := 0.0
var sink := "counter"


func setup(w: Node, r: String, idx: int) -> Worker:
	world = w
	role = r
	fire_index = idx
	speed = float(Game.cfg.worker.speed)
	return self


func _ready() -> void:
	_make_rig(role, fire_index)
	match role:
		"lumberjack":
			var axe := Art.model("wooden_axe")
			axe.rotation_degrees = Vector3(0, 90, -90)
			axe.position = Vector3(0.03, 0.08, 0.02)
			rig.attach("mixamorig1_RightHand", axe)
			back = Stack.new().setup("log", Stack.Layout.BACK)
			back.position = Vector3(0, 1.0, -0.3)
			rig.add_child(back)
		"waiter":
			hands = Stack.new().setup("dish", Stack.Layout.HANDS)
			hands.position = Vector3(0, 1.02, 0.46)
			rig.add_child(hands)
	state = "idle"


func _process(delta: float) -> void:
	match role:
		"lumberjack": _lumberjack(delta)
		"waiter": _waiter(delta)
		"cook": _cook(delta)


func _lumberjack(delta: float) -> void:
	var carry := int(Game.cfg.worker.carry)
	match state:
		"idle":
			target = world.reserve_tree(self, global_position)
			if target:
				var to := global_position - target.global_position
				to.y = 0
				go([target.global_position + to.normalized() * 1.05])
				state = "to_tree"
			else:
				rig.play("idle")
		"to_tree":
			if not is_instance_valid(target) or not target.alive:
				if back.count() < carry:
					state = "idle"
				else:
					_deliver()
				return
			if walk(delta):
				state = "chop"
				chop_phase = 0.0
				rig.current = ""
		"chop":
			if not is_instance_valid(target) or not target.alive or back.count() >= carry:
				if back.count() >= carry or (back.count() > 0 and not world.has_free_tree()):
					if is_instance_valid(target):
						target.reserved_by = null
					_deliver()
				else:
					state = "idle"
				return
			face(target.global_position, delta)
			var iv := float(Game.cfg.worker.chop_interval)
			rig.play("chop", rig.anim.get_animation("a/chop").length / iv, 0.1)
			var prev := chop_phase
			chop_phase += delta / iv
			if prev < Player.HIT_FRAC and chop_phase >= Player.HIT_FRAC:
				var logs := target.hit(1, global_position)
				world.on_tree_hit(target, logs, self)
				for i in logs:
					back.receive(target.global_position + Vector3(0, 1.2, 0))
			if chop_phase >= 1.0:
				chop_phase -= 1.0
		"to_pile":
			if walk(delta):
				state = "drop"
				timer = 0.0
		"drop":
			timer -= delta
			if timer <= 0.0:
				timer = 0.12
				if back.count() == 0:
					state = "idle"
				elif not world.pile_put_from(back):
					state = "rest"     # pile filled up while unloading: wait for the kitchen to use some
					timer = 2.0
		"to_station":
			if walk(delta):
				state = "feed"
				timer = 0.0
		"feed":
			timer -= delta
			rig.play("idle")
			if timer <= 0.0:
				timer = 0.12
				if back.count() == 0:
					state = "idle"
				elif not world.specials.log_put(back):
					_deliver(true)
		"rest":
			timer -= delta
			rig.play("idle")
			if timer <= 0.0:
				timer = 1.5
				if back.count() == 0:
					state = "idle"
				elif not world.pile_full():
					state = "drop"
				elif world.specials.crew_allowed() and world.specials.type == "raft" and world.specials.log_need() > 0:
					_go_station()


## Kitchen needs wood → woodpile; a cold lodge fireplace gets logs first once the pile has some;
## woodpile full → the timber raft (3x) once the station is level 5, else wait at the pile.
func _deliver(skip_station := false) -> void:
	var sp: Specials = world.specials
	var crew_ok := not skip_station and sp.crew_allowed()
	if crew_ok and sp.type == "fireplace" and sp.log_need() > 0 and int(Game.sp.get("fuel", 0)) < 6 and Game.woodpile >= 6:
		_go_station()
	elif world.pile_full() and crew_ok and sp.type == "raft" and sp.log_need() > 0:
		_go_station()
	else:
		state = "to_pile"
		go([world.pile_zone.global_position + Vector3(0.6, 0, -0.5)])


func _go_station() -> void:
	state = "to_station"
	go([world.specials.log_pos() + Vector3(0.3 * fire_index, 0, -0.4 + 0.4 * fire_index)])


func _waiter(delta: float) -> void:
	carry_anim = hands.count() > 0
	var carry := int(Game.cfg.worker.get("waiter_carry", 2))
	match state:
		"idle":
			go([world.rack_zone.global_position + Vector3(0.5 + fire_index * 0.5, 0, 0)])
			state = "to_rack"
		"to_rack":
			if walk(delta):
				state = "take"
				timer = 0.0
		"take":
			timer -= delta
			rig.play("carry_idle" if hands.count() > 0 else "idle")
			if timer <= 0.0:
				timer = 0.15
				if hands.count() < carry and Game.rack > 0:
					world.rack_take_to(hands)
				elif hands.count() >= carry or (hands.count() > 0 and Game.rack == 0):
					state = "to_counter"
					sink = world.waiter_sink(fire_index)
					if sink == "special":
						go([world.specials.dish_pos() + Vector3(0.4 - fire_index * 0.8, 0, 0)])
					else:
						go([world.serve_zone.global_position + Vector3(-0.6 + fire_index * 1.2, 0, 0)])
		"to_counter":
			if walk(delta):
				state = "drop"
				timer = 0.0
		"drop":
			timer -= delta
			if timer <= 0.0:
				timer = 0.15
				if hands.count() == 0:
					state = "idle"
				elif sink == "special":
					if not world.specials.dish_put(hands):
						sink = "counter"       # station filled up (or the van left): finish at the counter
						state = "to_counter"
						go([world.serve_zone.global_position + Vector3(-0.6 + fire_index * 1.2, 0, 0)])
				elif not world.counter_put_from(hands):
					rig.play("carry_idle")


func _cook(delta: float) -> void:
	var fp: Vector3 = world.fire_positions()[mini(fire_index, world.fire_positions().size() - 1)]
	match state:
		"idle":
			go([fp + Vector3(0.0, 0, 0.95)])
			state = "walk"
		"walk":
			if walk(delta):
				state = "work"
		"work":
			face(fp, delta)
			rig.play("carry_idle" if world.fire_busy(fire_index) else "idle")
