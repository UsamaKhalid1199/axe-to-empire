class_name Customer
extends Agent
## Guest: walks in, queues at the counter, takes dishes, pays, maybe sits and tips, leaves.
## Mood follows the share of patience used: happy (<50%) pays +20% and rates 5★, impatient rates 4★,
## angry rates 2★, and past 100% they walk out (1★) and the two guests behind them get grumpier.
## A guest who finds the line full just walks past ("Too busy!") and the sale is lost.

const HAPPY := 0.5
const ANGRY := 0.8

var state := "arrive"
var slot := -1
var order := 1
var got := 0
var waited := 0.0
var patience := 45.0
var seat := -1
var timer := 0.0
var bubble: Node3D
var bubble_label: Label3D
var face_spr: Sprite3D
var hands: Stack
var paid := 0
var vip := false
var mood := 0                    # 0 happy, 1 impatient, 2 angry
static var _faces: Array = []


func setup(w: Node, seed_i: int) -> Customer:
	world = w
	var c: Dictionary = Game.cfg.customers
	speed = float(c.speed) * randf_range(0.9, 1.1)
	walker = true
	patience = float(c.patience) * randf_range(0.9, 1.1)
	order = randi_range(int(c.order_min), int(c.order_max)) + int(c.get("order_bonus", 0)) + w.order_bonus()
	patience *= w.patience_mult() * Game.dining_patience()
	vip = w.roll_vip()
	if vip:
		order += 2
		patience *= 0.6
	set_meta("seed", seed_i)
	return self


## A passer-by who sees the line is full: walks along the road and keeps going.
func setup_passer(w: Node, seed_i: int) -> Customer:
	world = w
	speed = float(Game.cfg.customers.speed) * randf_range(1.0, 1.15)
	walker = true
	state = "pass"
	set_meta("seed", seed_i)
	return self


func _ready() -> void:
	_make_rig("customer", int(get_meta("seed")))
	hands = Stack.new().setup("dish", Stack.Layout.HANDS)
	hands.position = Vector3(0, 1.0, 0.42)
	rig.add_child(hands)
	bubble = Node3D.new()
	bubble.position.y = 2.15
	add_child(bubble)
	if _faces.is_empty():
		for n in ["face_happy", "face_meh", "face_angry"]:
			var path := "res://assets/icons/%s.svg" % n
			_faces.append(load(path) if ResourceLoader.exists(path) else load("res://assets/icons/smile.svg"))
	face_spr = Sprite3D.new()
	face_spr.texture = _faces[0]
	face_spr.pixel_size = 0.0036
	face_spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	face_spr.no_depth_test = true
	face_spr.render_priority = 4
	face_spr.position.x = -0.2
	bubble.add_child(face_spr)
	bubble_label = Label3D.new()
	bubble_label.font = UI.font_bold()
	bubble_label.font_size = 72
	bubble_label.pixel_size = 0.0045
	bubble_label.outline_size = 16
	bubble_label.outline_modulate = Color(0.1, 0.06, 0.02)
	bubble_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bubble_label.no_depth_test = true
	bubble_label.render_priority = 5
	bubble_label.position.x = 0.22
	bubble.add_child(bubble_label)
	bubble.visible = false


func _process(delta: float) -> void:
	if state != "eat":
		carry_anim = hands.count() > 0
	match state:
		"arrive":
			if walk(delta):
				state = "queue"
		"queue":
			waited += delta
			var front: bool = slot == 0
			bubble.visible = true
			_update_mood()
			bubble_label.text = ("VIP %d" if vip else "%d") % (order - got)
			if path.is_empty():
				face(global_position + Vector3(0, 0, -1), delta)
				if mood == 2:
					rig.play("idle", 1.6, 0.2)    # fidgety
			else:
				walk(delta)
			if front and path.is_empty():
				timer -= delta
				if timer <= 0.0 and world.counter_count() > 0:
					timer = 0.18
					world.counter_give_to(hands)
					got += 1
					if got >= order:
						_pay()
			if waited > patience and state == "queue":
				_leave_angry()
		"to_seat":
			if walk(delta):
				state = "eat"
				timer = float(Game.cfg.customers.eat_time)
				world.seat_food(seat, hands)
				carry_anim = false
				rig.play("sit", 1.0, 0.3)
				var tw := create_tween()
				tw.tween_property(self, "global_position", world.seat_sit_pos(seat), 0.35)
		"eat":
			timer -= delta
			carry_anim = false
			rig.play("sit", 1.0, 0.3)
			var tc: Vector3 = world.seat_table_center(seat)
			face(Vector3(tc.x, 0, global_position.z), delta)
			if timer <= 0.0:
				world.seat_done(seat, paid)
				seat = -1
				_go_home()
		"pass":
			if walk(delta):
				queue_free()
		"leave":
			if walk(delta):
				queue_free()


func _update_mood() -> void:
	var u := waited / maxf(1.0, patience)
	var m := 0 if u < HAPPY else (1 if u < ANGRY else 2)
	if m != mood or face_spr.texture != _faces[m]:
		mood = m
		face_spr.texture = _faces[m]
		if m == 2:
			var tw := create_tween()
			bubble.scale = Vector3.ONE * 1.25
			tw.tween_property(bubble, "scale", Vector3.ONE, 0.25)
	var base_col := Color("#FFD24A") if vip else Color(1, 1, 1)
	bubble_label.modulate = base_col.lerp(Color("#FF6B5B"), clampf((u - HAPPY) / (1.0 - HAPPY), 0.0, 1.0))


## Takes patience away (a guest ahead stormed off).
func annoy(frac: float) -> void:
	waited += patience * frac


func _pay() -> void:
	bubble.visible = false
	_update_mood()
	var mult: float = world.price_mult() * (3.0 if vip else 1.0)
	var bonus := ""
	if mood == 0:
		mult *= 1.0 + float(Game.cfg.customers.happy_bonus)
		bonus = "HAPPY"
	if world.player_serving():
		mult *= 1.0 + float(Game.cfg.customers.hands_on_bonus)
		bonus = "SERVICE" if bonus == "" else bonus + " + SERVICE"
	paid = int(round(order * Game.dish_price() * mult))
	var score: float = [5.0, 4.0, 2.0][mood]
	world.customer_paid(self, paid, score, bonus)
	world.queue_leave(self)
	seat = world.take_seat(self)
	if seat >= 0:
		state = "to_seat"
		go(world.path_to_seat(global_position, seat))
	else:
		_go_home()


func _leave_angry() -> void:
	bubble.visible = false
	world.customer_angry(self)
	world.queue_leave(self)
	_go_home()


func _go_home() -> void:
	state = "leave"
	go(world.path_home(global_position))


func move_to_slot(s: int, p: Vector3) -> void:
	slot = s
	if state == "arrive":
		path[path.size() - 1] = p
	else:
		go([p])
