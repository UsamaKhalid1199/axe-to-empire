extends Control
## Placeholder "visual sim" (spec 2.1): draws what the economy sim decided and
## never decides outcomes. Taps become sim commands. All art is boxes/dots.

const Fmt = preload("res://scripts/game/fmt.gd")
const BASE := Vector2(720, 600)
const C_TEXT := Color(0.95, 0.95, 0.9)
const C_DIM := Color(0.7, 0.7, 0.65)
const C_GOLD := Color(1.0, 0.82, 0.2)
const C_RED := Color(1.0, 0.4, 0.35)
const C_GREEN := Color(0.45, 0.9, 0.45)

var sim
var hint_target := ""
var font: Font
var _sc := Vector2.ONE
var _hits: Array = []
var _anchors: Dictionary = {}
var _floats: Array = []
var _shake := 0.0
var _flash := ""
var _flash_t := 0.0
var _time := 0.0


func _ready() -> void:
	font = ThemeDB.fallback_font
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true


func flash(target: String) -> void:
	_flash = target
	_flash_t = 1.5


func add_events(evs: Array) -> void:
	for e in evs:
		match str(e.type):
			"coins":
				_float(str(e.where), "+" + Fmt.num(e.amount), C_GOLD)
			"fall":
				_shake = 10.0 if e.golden else 4.0
				_float("tree%d" % e.idx, ("GOLDEN OAK! +%d" if e.golden else "+%d logs") % int(e.logs), C_GOLD if e.golden else C_TEXT)
				if float(e.wasted) > 0.5:
					_float("wood", "Pile full!", C_RED)
			"chop":
				_float("tree%d" % e.idx, "chop", C_DIM)
			"balk":
				_float(str(e.where) + "_q", "queue full - walked past", C_RED)
			"renege":
				_float(str(e.where) + "_q", "left unhappy", C_RED)
			"free_crate":
				_float("shelf", "Free crate (you were broke)", C_GREEN)
			"crate":
				_float("shelf", "+crate", C_GREEN)
			"poor":
				_float("shelf", "Not enough coins", C_RED)
			"full":
				_float(str(e.where), "Full!", C_RED)
			"busy":
				_float("player", "Busy...", C_DIM)
			"supplier":
				_float("shelf", "Supplier restocked", C_GREEN)
			"truck_departs":
				_float("truck", "Truck departs!", C_TEXT)
			"chapter":
				_shake = 12.0
				_float("center", "CHAPTER %d!" % int(e.n), C_GOLD)
			"critic":
				_float("dine_q", "Critic: " + ("loved it!" if e.good else "unimpressed"), C_GOLD if e.good else C_RED)
			"rush_ok":
				_float("dine_q", "Rush survived, nobody left!", C_GREEN)
			"event":
				_float("center", "POWER CUT! Cooking slowed" if e.kind == "power_cut" else "Celebrity visit! Crowds incoming", C_GOLD)
			"upgrade":
				_float("center", "Upgraded!", C_GREEN)
	while _floats.size() > 40:
		_floats.pop_front()


func _float(anchor: String, text: String, color: Color) -> void:
	var p: Vector2 = _anchors.get(anchor, size * 0.5)
	_floats.append({"pos": p + Vector2(randf_range(-25.0, 25.0), randf_range(-8.0, 8.0)), "text": text, "t": 0.0, "color": color})


func _process(delta: float) -> void:
	_time += delta
	for f in _floats:
		f.t += delta
		f.pos.y -= 45.0 * delta
	_floats = _floats.filter(func(f): return f.t < 1.4)
	_shake = move_toward(_shake, 0.0, 30.0 * delta)
	_flash_t -= delta
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for h in _hits:
			if h.rect.has_point(event.position):
				sim.push_command(h.action, h.idx)
				accept_event()
				return


# ---------------------------------------------------------------- drawing helpers

func R(x: float, y: float, w: float, h: float) -> Rect2:
	return Rect2(Vector2(x, y) * _sc, Vector2(w, h) * _sc)


func _text(pos: Vector2, text: String, fsize := 16, color := C_TEXT) -> void:
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, color)


func _box(r: Rect2, title: String, fill: Color, key := "") -> void:
	draw_rect(r, fill)
	draw_rect(r, Color(1, 1, 1, 0.25), false, 2.0)
	if key != "" and (key == hint_target or (key == _flash and _flash_t > 0.0)):
		var a := 0.5 + 0.5 * sin(_time * 6.0)
		draw_rect(r.grow(2.0), Color(1.0, 0.9, 0.2, a), false, 4.0)
	if title != "":
		_text(r.position + Vector2(6, 18), title, 15, C_DIM)


func _locked(r: Rect2, title: String, ch: int) -> void:
	_box(r, title, Color(0.2, 0.2, 0.2, 0.6))
	_text(r.position + Vector2(6, r.size.y * 0.5 + 12), "Unlocks in chapter %d" % ch, 15, C_DIM)


func _bar(r: Rect2, frac: float, color: Color) -> void:
	draw_rect(r, Color(0, 0, 0, 0.4))
	draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(frac, 0.0, 1.0), r.size.y)), color)


func _pat_color(frac: float) -> Color:
	if frac > 0.6:
		return C_GREEN
	if frac > 0.3:
		return Color(1.0, 0.85, 0.3)
	return C_RED


func _queue_dots(origin: Vector2, q: Array, ch: String, cols: int, step: float, max_show: int) -> void:
	for i in mini(q.size(), max_show):
		var e: Array = q[i]
		var frac: float = sim._frac_left(ch, e)
		var p := origin + Vector2((i % cols) * step, (i / cols) * step) * _sc.x
		var col := _pat_color(frac)
		if int(e[1]) == 1:
			draw_circle(p, 10.0 * _sc.x, C_GOLD)
		elif int(e[1]) == 2:
			draw_circle(p, 10.0 * _sc.x, Color(0.75, 0.45, 1.0))
		draw_circle(p, 7.0 * _sc.x, col)
	if q.size() > max_show:
		_text(origin + Vector2(0, (max_show / cols) * step + 10) * _sc.x, "+%d" % (q.size() - max_show), 15)


# ---------------------------------------------------------------- scene

func _draw() -> void:
	_hits.clear()
	var k := minf(size.x / BASE.x, size.y / BASE.y)
	_sc = Vector2(k, k)
	var s: Dictionary = sim.s
	var c: Dictionary = sim.chap()
	var off := Vector2.ZERO
	if _shake > 0.1:
		off = Vector2(randf_range(-_shake, _shake), randf_range(-_shake, _shake))
	draw_set_transform(off, 0.0, Vector2.ONE)
	draw_rect(Rect2(Vector2.ZERO, size), Color(str(c.color)))
	if sim.unlocked("rushes"):
		var f: float = sim.day_frac()
		if f >= 0.8:
			draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0.15, 0.35))
	_anchors["center"] = size * Vector2(0.5, 0.45)
	_draw_forest(s)
	_draw_wood(s)
	_draw_truck(s)
	_draw_shelf(s)
	_draw_oven(s)
	_draw_rack(s)
	_draw_dine(s, c)
	_draw_take(s)
	_draw_drive(s)
	_draw_delivery(s)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for fl in _floats:
		var a := clampf(1.4 - float(fl.t), 0.0, 1.0)
		var col: Color = fl.color
		col.a = a
		draw_string(font, fl.pos + Vector2(1, 1), fl.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0, 0, 0, a))
		draw_string(font, fl.pos, fl.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, col)


func _draw_forest(s: Dictionary) -> void:
	var area := R(8, 8, 300, 152)
	_box(area, "FOREST  (tap trees)", Color(0.12, 0.25, 0.12), "forest")
	_anchors["forest"] = area.get_center()
	for i in s.trees.size():
		var cell := R(14 + (i % 3) * 98, 28 + (i / 3) * 64, 92, 60)
		var t: Dictionary = s.trees[i]
		var ctr := cell.get_center()
		_anchors["tree%d" % i] = ctr - Vector2(0, 20)
		if float(t.hp) > 0.0:
			draw_rect(Rect2(ctr + Vector2(-4, 4) * _sc.x, Vector2(8, 16) * _sc.x), Color(0.45, 0.3, 0.15))
			draw_circle(ctr - Vector2(0, 6) * _sc.x, 21.0 * _sc.x, C_GOLD if t.golden else Color(0.2, 0.62, 0.25))
			_bar(Rect2(cell.position.x + 8, cell.end.y - 9, cell.size.x - 16, 6), float(t.hp) / float(t.max), C_RED)
		else:
			draw_rect(Rect2(ctr + Vector2(-10, 4) * _sc.x, Vector2(20, 10) * _sc.x), Color(0.45, 0.3, 0.15))
			_text(ctr + Vector2(-18, -4) * _sc.x, "%ds" % ceili(float(t.regrow)), 14, C_DIM)
		_hits.append({"rect": cell, "action": "chop", "idx": i})
	var n: int = sim.lv("lumberjack")
	if n > 0:
		_text(area.position + Vector2(170, 18) * _sc.x, "%d lumberjack%s" % [n, "" if n == 1 else "s"], 14, C_GREEN)


func _draw_wood(s: Dictionary) -> void:
	var r := R(314, 8, 130, 152)
	_box(r, "WOOD PILE", Color(0.3, 0.2, 0.1), "wood")
	_anchors["wood"] = r.get_center()
	var cap: float = sim.pile_cap(s.levels)
	_text(r.position + Vector2(8, 46) * _sc.x, "%d / %d" % [int(s.wood), int(cap)], 22)
	_bar(Rect2(r.position + Vector2(8, 58) * _sc.x, Vector2(114, 12) * _sc.x), float(s.wood) / cap, Color(0.75, 0.5, 0.25))
	_text(r.position + Vector2(8, 92) * _sc.x, str(sim.chap().wood_type), 15, C_DIM)
	if sim.unlocked("truck"):
		_text(r.position + Vector2(8, 114) * _sc.x, "keep %d for fuel" % int(s.wood_reserve), 14, C_DIM)
	if float(s.wood) < 1.0:
		_text(r.position + Vector2(100, 46) * _sc.x, "!", 30, C_RED)


func _draw_truck(s: Dictionary) -> void:
	var r := R(450, 8, 262, 152)
	if not sim.unlocked("truck"):
		_locked(r, "LOG TRUCK", int(sim.cfg.unlocks.truck))
		return
	_box(r, "LOG TRUCK  (tap: send now)", Color(0.22, 0.22, 0.28), "truck")
	_anchors["truck"] = r.get_center()
	var tr: Dictionary = s.truck
	var cap: float = sim.truck_cap(s.levels)
	if tr.state == "bay":
		_text(r.position + Vector2(8, 48) * _sc.x, "Loading %d / %d logs" % [int(tr.load), int(cap)], 18)
		_bar(Rect2(r.position + Vector2(8, 60) * _sc.x, Vector2(246, 12) * _sc.x), float(tr.load) / cap, Color(0.75, 0.5, 0.25))
		_text(r.position + Vector2(8, 98) * _sc.x, "Price now: %s / log" % Fmt.num(sim.wood_price()), 15, C_DIM)
		_text(r.position + Vector2(8, 120) * _sc.x, "(price drops if you sell a lot)", 13, C_DIM)
	else:
		_text(r.position + Vector2(8, 48) * _sc.x, "Away: back in %ds" % ceili(float(tr.t)), 18)
		_text(r.position + Vector2(8, 76) * _sc.x, "Pays %s on return" % Fmt.num(float(tr.pay) * sim.legacy_mult()), 16, C_GOLD)
	_hits.append({"rect": r, "action": "send_truck", "idx": -1})


func _draw_shelf(s: Dictionary) -> void:
	var r := R(8, 166, 190, 102)
	_box(r, "INGREDIENTS", Color(0.25, 0.22, 0.12), "shelf")
	_anchors["shelf"] = r.get_center()
	var cap: float = sim.shelf_cap(s.levels)
	_text(r.position + Vector2(8, 46) * _sc.x, "%d / %d" % [int(s.ingredients), int(cap)], 22)
	_bar(Rect2(r.position + Vector2(8, 56) * _sc.x, Vector2(174, 10) * _sc.x), float(s.ingredients) / cap, Color(0.5, 0.8, 0.3))
	if sim.has_supplier(s.levels):
		_text(r.position + Vector2(8, 90) * _sc.x, "Supplier auto-restocks", 14, C_GREEN)
	else:
		_text(r.position + Vector2(8, 90) * _sc.x, "Tap: buy crate (%s)" % Fmt.num(sim.crate_cost()), 14, C_DIM)
	if float(s.ingredients) < 1.0:
		_text(r.position + Vector2(160, 46) * _sc.x, "!", 30, C_RED)
	_hits.append({"rect": r, "action": "buy_crate", "idx": -1})


func _draw_oven(s: Dictionary) -> void:
	var r := R(204, 166, 270, 102)
	var title := "CAMPFIRE" if int(s.chapter) <= 2 else "OVEN"
	_box(r, title, Color(0.35, 0.15, 0.08), "oven")
	_anchors["oven"] = r.get_center()
	var slots: Array = s.oven
	var n := slots.size()
	var ct: float = sim.cook_time(s.levels)
	var w := (254.0 - 6.0 * (n - 1)) / n
	for i in n:
		var br := R(212 + i * (w + 6.0), 196, w, 26)
		var t := float(slots[i])
		if t >= 0.0:
			_bar(br, 1.0 - t / ct, Color(1.0, 0.55, 0.15))
		else:
			draw_rect(br, Color(0, 0, 0, 0.4))
	_text(r.position + Vector2(8, 78) * _sc.x, "%.1fs per dish, %d slot%s" % [ct, n, "" if n == 1 else "s"], 14, C_DIM)
	if s.event.type == "power_cut" and float(s.event.left) > 0.0:
		_text(r.position + Vector2(8, 96) * _sc.x, "POWER CUT %ds" % ceili(float(s.event.left)), 14, C_RED)
	elif int(s.rack) + sim.cooking_count() >= sim.rack_cap(s.levels):
		_text(r.position + Vector2(8, 96) * _sc.x, "Paused: rack full", 14, Color(1.0, 0.85, 0.3))


func _draw_rack(s: Dictionary) -> void:
	var r := R(480, 166, 232, 102)
	_box(r, "DISH RACK", Color(0.2, 0.2, 0.15), "rack")
	_anchors["rack"] = r.get_center()
	var cap: int = sim.rack_cap(s.levels)
	_text(r.position + Vector2(8, 44) * _sc.x, "%d / %d ready" % [int(s.rack), cap], 18)
	for i in cap:
		var p := r.position + Vector2(10 + (i % 12) * 18, 56 + (i / 12) * 18) * _sc.x
		draw_rect(Rect2(p, Vector2(14, 14) * _sc.x), Color(1.0, 0.8, 0.4) if i < int(s.rack) else Color(0, 0, 0, 0.35))


func _draw_dine(s: Dictionary, c: Dictionary) -> void:
	var area := R(8, 274, 704, 192)
	_box(area, "DINE-IN" + ("  (self-serve)" if c.self_serve else ""), Color(0.18, 0.2, 0.18), "tables")
	var qr := R(14, 296, 92, 164)
	draw_rect(qr, Color(0, 0, 0, 0.2))
	_text(qr.position + Vector2(4, 14) * _sc.x, "queue %d/%d" % [s.dine_q.size(), int(sim.cfg.dine.queue_limit)], 13, C_DIM)
	_anchors["dine_q"] = qr.get_center()
	_queue_dots(qr.position + Vector2(24, 36) * _sc.x, s.dine_q, "dine", 2, 34.0, 8)
	var p: Dictionary = s.player
	_anchors["player"] = area.position + Vector2(560, 10) * _sc.x
	if float(p.busy) > 0.0:
		_text(area.position + Vector2(470, 18) * _sc.x, "You: %s %.1fs" % [p.task, float(p.busy)], 14, C_GOLD)
	for i in s.tables.size():
		var t: Dictionary = s.tables[i]
		var cell := R(112 + (i % 5) * 119, 298 + (i / 5) * 82, 113, 76)
		_anchors["table%d" % i] = cell.get_center()
		var fill := Color(0.3, 0.33, 0.3)
		var label := "free"
		var frac := -1.0
		match str(t.st):
			"waiting_food":
				fill = Color(0.55, 0.35, 0.1)
				label = "waiting"
				frac = float(t.pat) / float(t.pmax)
			"serving":
				fill = Color(0.2, 0.35, 0.6)
				label = "serving"
			"eating":
				fill = Color(0.2, 0.5, 0.25)
				label = "eating"
				frac = float(t.t) / float(sim.cfg.dine.eat_s)
			"dirty":
				fill = Color(0.35, 0.25, 0.15)
				label = "DIRTY (tap)"
			"cleaning":
				fill = Color(0.3, 0.45, 0.55)
				label = "cleaning"
		draw_rect(cell, fill)
		if t.st != "free" and int(t.kind) == 1:
			draw_rect(cell, C_GOLD, false, 3.0)
			_text(cell.position + Vector2(70, 16) * _sc.x, "VIP", 13, C_GOLD)
		elif t.st != "free" and int(t.kind) == 2:
			draw_rect(cell, Color(0.75, 0.45, 1.0), false, 3.0)
			_text(cell.position + Vector2(56, 16) * _sc.x, "CRITIC", 13, Color(0.75, 0.45, 1.0))
		_text(cell.position + Vector2(6, 44) * _sc.x, label, 15)
		if frac >= 0.0:
			_bar(Rect2(cell.position + Vector2(6, 56) * _sc.x, Vector2(101, 8) * _sc.x), frac,
				_pat_color(frac) if t.st == "waiting_food" else C_GREEN)
		_hits.append({"rect": cell, "action": "table", "idx": i})


func _draw_take(s: Dictionary) -> void:
	var r := R(8, 472, 350, 62)
	if not sim.unlocked("take"):
		_locked(r, "TAKEAWAY", int(sim.cfg.unlocks.take))
		return
	_box(r, "", Color(0.2, 0.18, 0.25), "counter")
	var counter := R(12, 476, 92, 54)
	draw_rect(counter, Color(0.4, 0.3, 0.5))
	_text(counter.position + Vector2(4, 18) * _sc.x, "COUNTER", 13)
	var n: int = sim.lv("cashier")
	_text(counter.position + Vector2(4, 40) * _sc.x, "%d cashier%s" % [n, "" if n == 1 else "s"] if n > 0 else "tap to serve", 12, C_DIM)
	_anchors["take"] = counter.get_center()
	_anchors["take_q"] = r.get_center() + Vector2(40, 0) * _sc.x
	_queue_dots(R(122, 503, 1, 1).position, s.take_q, "take", 10, 23.0, 10)
	_text(r.position + Vector2(112, 18) * _sc.x, "takeaway queue %d/%d" % [s.take_q.size(), int(sim.cfg.take.queue_limit)], 13, C_DIM)
	_hits.append({"rect": r, "action": "serve_take", "idx": -1})


func _draw_drive(s: Dictionary) -> void:
	var r := R(8, 540, 350, 58)
	if not sim.unlocked("drive"):
		_locked(r, "DRIVE-THROUGH", int(sim.cfg.unlocks.drive))
		return
	_box(r, "", Color(0.18, 0.22, 0.25), "drive")
	_anchors["drive"] = r.get_center()
	_anchors["drive_q"] = r.get_center()
	if sim.lv("dt_crew") <= 0:
		_text(r.position + Vector2(8, 36) * _sc.x, "DRIVE-THROUGH: hire crew to open", 15, C_DIM)
		return
	var od: Dictionary = s.drive_order
	var pu: Dictionary = s.drive_pickup
	var o := R(12, 544, 70, 50)
	var pk := R(86, 544, 70, 50)
	draw_rect(o, Color(0.3, 0.4, 0.5) if not od.is_empty() else Color(0, 0, 0, 0.3))
	draw_rect(pk, (Color(0.3, 0.55, 0.3) if pu.get("food", false) else Color(0.55, 0.4, 0.2)) if not pu.is_empty() else Color(0, 0, 0, 0.3))
	_text(o.position + Vector2(4, 16) * _sc.x, "order", 13)
	_text(pk.position + Vector2(4, 16) * _sc.x, "pickup", 13)
	_queue_dots(R(176, 569, 1, 1).position, s.drive_q, "drive", 6, 28.0, 6)


func _draw_delivery(s: Dictionary) -> void:
	var r := R(364, 472, 348, 126)
	if not sim.unlocked("delivery"):
		_locked(r, "DELIVERY", int(sim.cfg.unlocks.delivery))
		return
	_box(r, "DELIVERY  board %d/%d" % [s.delivery_q.size(), int(sim.cfg.delivery.queue_limit)], Color(0.15, 0.22, 0.2), "delivery")
	_anchors["delivery"] = r.get_center()
	_anchors["delivery_q"] = r.position + Vector2(60, 40) * _sc.x
	if s.packers.is_empty() or s.bikes.is_empty():
		_text(r.position + Vector2(8, 60) * _sc.x, "Hire a packer + a bike to open", 15, C_DIM)
		return
	_queue_dots(r.position + Vector2(20, 40) * _sc.x, s.delivery_q, "delivery", 4, 26.0, 4)
	var busy := 0
	for p in s.packers:
		if float(p.busy) > 0.0:
			busy += 1
	_text(r.position + Vector2(130, 44) * _sc.x, "packing %d/%d  ready %d" % [busy, s.packers.size(), s.del_ready.size()], 14)
	for i in s.bikes.size():
		var b: Dictionary = s.bikes[i]
		var y: int = 66 + (i % 3) * 20
		var x: int = 8 + (i / 3) * 170
		var txt := "bike %d: away %ds" % [i + 1, ceili(float(b.away))] if float(b.away) > 0.0 else "bike %d: at bay" % (i + 1)
		_text(r.position + Vector2(x, y) * _sc.x, txt, 14, C_DIM)
