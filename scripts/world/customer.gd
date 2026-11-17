class_name Customer
extends Agent
## Hiker: walks in, queues at the counter, takes dishes, pays, maybe sits and tips, leaves.

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
var hands: Stack
var paid := 0
var vip := false


func setup(w: Node, seed_i: int) -> Customer:
	world = w
	var c: Dictionary = Game.cfg.customers
	speed = float(c.speed) * randf_range(0.9, 1.1)
	walker = true
	patience = float(c.patience)
	order = randi_range(int(c.order_min), int(c.order_max))
	patience *= w.patience_mult()
	vip = w.specials != null and w.specials.roll_vip()
	if vip:
		order += 2
		patience *= 0.6
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
	var spr := Sprite3D.new()
	spr.texture = load("res://assets/icons/dish.svg")
	spr.pixel_size = 0.0042
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.no_depth_test = true
	spr.render_priority = 4
	spr.position.x = -0.18
	bubble.add_child(spr)
	bubble_label = Label3D.new()
	bubble_label.font = UI.font_bold()
	bubble_label.font_size = 72
	bubble_label.pixel_size = 0.0045
	bubble_label.outline_size = 16
	bubble_label.outline_modulate = Color(0.1, 0.06, 0.02)
	bubble_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bubble_label.no_depth_test = true
	bubble_label.render_priority = 5
	bubble_label.position.x = 0.2
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
			bubble_label.text = ("VIP %d" if vip else "%d") % (order - got)
			var urgency := waited / patience
			var base_col := Color("#FFD24A") if vip else Color(1, 1, 1)
			bubble_label.modulate = base_col.lerp(Color("#FF6B5B"), clampf((urgency - 0.5) * 2.0, 0.0, 1.0))
			if path.is_empty():
				face(global_position + Vector3(0, 0, -1), delta)
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
		"leave":
			if walk(delta):
				queue_free()


func _pay() -> void:
	bubble.visible = false
	paid = int(round(order * Game.dish_price() * world.price_mult() * (3.0 if vip else 1.0)))
	var score := 5.0 if waited < 15.0 else (4.0 if waited < 28.0 else 3.0)
	world.customer_paid(self, paid, score)
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
