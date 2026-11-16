class_name Hud
extends CanvasLayer
## Smoked-glass + gold HUD, joystick and all modal panels.

var world: Node
var root: Control
var joy: Joystick
var coin_label: Label
var rating_label: Label
var served_label: Label
var goal_pill: UIShape
var goal_label: Label
var jobs_btn: UIShape
var map_btn: UIShape
var _map_pulse := 0.0
var jobs_badge: Label
var toast_box: UIShape
var toast_label: Label
var modal: Control
var modal_kind := ""
var _coin_shown := 0.0
var _toast_q: Array = []
var _toast_t := 0.0
var _confirm_reset := false
var fps_label: Label


func _ready() -> void:
	layer = 10
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = UI.theme()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	joy = Joystick.new()
	root.add_child(joy)
	joy.moved.connect(func(v): world.player.input_dir = v)
	joy.ui_hit = _ui_hit
	_build_top()
	_build_side()
	_build_toast()
	Game.coins_changed.connect(func(_v): _refresh_modal_soft())
	Game.rating_changed.connect(func(_v): _refresh_top())
	Game.state_changed.connect(_refresh_modal_soft)
	Game.jobs_changed.connect(_refresh_jobs_badge)
	Game.toast.connect(show_toast)
	world.zone_entered.connect(_on_zone_entered)
	world.zone_exited.connect(_on_zone_exited)
	_coin_shown = Game.coins
	if OS.is_debug_build():
		fps_label = UI.label("", 18, Color(1, 1, 1, 0.7))
		fps_label.position = Vector2(24, root.get_viewport_rect().size.y - 40)
		root.add_child(fps_label)
	_refresh_top()
	_refresh_jobs_badge()
	if Game.offline_reward > 0:
		open_modal.call_deferred("offline")
	elif Game.chapter_done:
		pass


func _ui_hit(p: Vector2) -> bool:
	if modal != null:
		return true
	for c in [jobs_btn, jobs_btn.get_parent().get_parent().get_child(1)]:
		if c is Control and c.visible and c.get_global_rect().has_point(p):
			return true
	return false


func _safe_top() -> float:
	var safe := DisplayServer.get_display_safe_area()
	var win := DisplayServer.window_get_size()
	if win.y <= 0:
		return 24.0
	var vp := root.get_viewport_rect().size
	return maxf(24.0, safe.position.y * vp.y / win.y + 10.0)


func _build_top() -> void:
	var top := MarginContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := _safe_top()
	top.add_theme_constant_override("margin_left", 22)
	top.add_theme_constant_override("margin_right", 22)
	top.add_theme_constant_override("margin_top", int(st))
	root.add_child(top)
	var col := UI.vbox(14)
	top.add_child(col)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(row)
	# coins pill
	var coin_pill := UIShape.new("glass", 32.0, Vector4(10, 8, 26, 8))
	coin_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cr := UI.hbox(10)
	cr.add_child(UI.icon("coin", 56))
	coin_label = UI.num("0", 44, Color.WHITE)
	coin_label.custom_minimum_size.x = 120
	cr.add_child(coin_label)
	coin_pill.add_child(cr)
	row.add_child(coin_pill)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)
	# rating pill
	var rp := UIShape.new("glass", 32.0, Vector4(14, 8, 22, 8))
	rp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rr := UI.hbox(8)
	rr.add_child(UI.icon("star", 44))
	rating_label = UI.num("4.5", 38, Color.WHITE)
	rr.add_child(rating_label)
	var sep := ColorRect.new()
	sep.color = Color(1, 1, 1, 0.15)
	sep.custom_minimum_size = Vector2(2, 34)
	rr.add_child(sep)
	rr.add_child(UI.icon("smile", 36))
	served_label = UI.num("0", 34, Color(1, 1, 1, 0.9))
	rr.add_child(served_label)
	rp.add_child(rr)
	row.add_child(rp)
	# goal
	var gc := CenterContainer.new()
	gc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(gc)
	goal_pill = UIShape.new("glass", 26.0, Vector4(18, 10, 26, 10))
	goal_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gr := UI.hbox(10)
	var dot := UI.icon("arrow", 30)
	dot.rotation_degrees = 0
	gr.add_child(dot)
	goal_label = UI.label("", 28, Color.WHITE, UI.font_ui(650))
	gr.add_child(goal_label)
	goal_pill.add_child(gr)
	gc.add_child(goal_pill)


func _build_side() -> void:
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 14)
	side.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	side.position = Vector2(-118, _safe_top() + 190)
	side.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(side)
	jobs_btn = _round_button("jobs", "JOBS", func(): open_modal("jobs"))
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(96, 96)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(jobs_btn)
	side.add_child(holder)
	jobs_badge = UI.num("", 24, Color.WHITE)
	jobs_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var badge := UIShape.new("red", 17.0, Vector4(0, 0, 0, 0))
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.custom_minimum_size = Vector2(34, 34)
	badge.add_child(jobs_badge)
	badge.name = "Badge"
	holder.add_child(badge)
	badge.position = Vector2(70, -10)
	badge.size = Vector2(34, 34)
	map_btn = _round_button("gate", "MAP", func(): open_modal("empire"))
	map_btn.visible = Game.unlocked > 1
	side.add_child(map_btn)
	side.add_child(_round_button("settings", "", func(): open_modal("settings")))


func _round_button(icon_name: String, text: String, cb: Callable) -> UIShape:
	var b := UIShape.new("glass", 26.0, Vector4(10, 10, 10, 8)).make_clickable()
	b.custom_minimum_size = Vector2(96, 96)
	var v := UI.vbox(0)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	var ic := UI.icon(icon_name, 56)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(ic)
	if text != "":
		v.add_child(UI.label(text, 18, Color(1, 1, 1, 0.9), UI.font_bold(), HORIZONTAL_ALIGNMENT_CENTER))
	b.add_child(v)
	b.pressed.connect(cb)
	return b


func _build_toast() -> void:
	var c := CenterContainer.new()
	c.set_anchors_preset(Control.PRESET_CENTER_TOP)
	c.position.y = _safe_top() + 200
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(c)
	toast_box = UIShape.new("gold", 24.0, Vector4(26, 12, 26, 12))
	toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_label = UI.label("", 30, UI.INK, UI.font_bold())
	toast_box.add_child(toast_label)
	c.add_child(toast_box)
	toast_box.modulate.a = 0.0


func show_toast(text: String) -> void:
	_toast_q.append(text)


func _process(delta: float) -> void:
	# animated coin counter
	var target := float(Game.coins)
	if absf(_coin_shown - target) > 0.5:
		_coin_shown = lerpf(_coin_shown, target, clampf(delta * 10.0, 0.0, 1.0))
		if absf(_coin_shown - target) < 1.0:
			_coin_shown = target
	coin_label.text = UI.fmt(round(_coin_shown))
	served_label.text = str(Game.served)
	if map_btn:
		map_btn.visible = Game.unlocked > 1
		var fresh: bool = Game.venue + 1 < Game.unlocked and (Game.venue + 1 >= Game.venues.size() or Game.venues[Game.venue + 1].is_empty())
		_map_pulse += delta
		var k := 1.0 + (0.08 * sin(_map_pulse * 6.0) if fresh else 0.0)
		map_btn.scale = Vector2(k, k)
		map_btn.pivot_offset = map_btn.size * 0.5
	if fps_label:
		fps_label.text = "%d fps" % Engine.get_frames_per_second()
	var g: String = world.objective.text
	if goal_label.text != g:
		goal_label.text = g
		goal_pill.visible = g != ""
		goal_pill.scale = Vector2(1.08, 1.08)
		goal_pill.create_tween().tween_property(goal_pill, "scale", Vector2.ONE, 0.25)
	# toasts
	_toast_t -= delta
	if _toast_t <= 0.0 and not _toast_q.is_empty():
		toast_label.text = _toast_q.pop_front()
		_toast_t = 2.2
		var tw := create_tween()
		toast_box.modulate.a = 0.0
		toast_box.scale = Vector2(0.8, 0.8)
		tw.tween_property(toast_box, "modulate:a", 1.0, 0.15)
		tw.parallel().tween_property(toast_box, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_interval(1.6)
		tw.tween_property(toast_box, "modulate:a", 0.0, 0.3)


func _refresh_top() -> void:
	rating_label.text = "%.1f" % Game.rating()


func _refresh_jobs_badge() -> void:
	var n := Game.jobs_claimable()
	var badge: Control = jobs_btn.get_parent().get_node("Badge")
	badge.visible = n > 0
	jobs_badge.text = str(n)
	if modal_kind == "jobs":
		_rebuild_modal()


# ------------------------------------------------------------------ zones -> panels

func _on_zone_entered(kind: String, _id: String) -> void:
	match kind:
		"shop", "crew", "gate":
			if modal_kind == "":
				open_modal(kind)


func _on_zone_exited(kind: String, _id: String) -> void:
	if modal_kind == kind:
		close_modal()


# ------------------------------------------------------------------ modal framework

func open_modal(kind: String) -> void:
	if modal:
		modal.queue_free()
	modal_kind = kind
	joy.release()
	joy.blocked = true
	world.player.input_dir = Vector2.ZERO
	modal = Control.new()
	modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(modal)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and kind != "offline" and kind != "complete" and kind != "empire":
			close_modal())
	modal.add_child(dim)
	_rebuild_modal()
	modal.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(modal, "modulate:a", 1.0, 0.15)
	Sfx.play("pop", -10.0, 1.3)


func close_modal() -> void:
	if modal:
		var m := modal
		var tw := create_tween()
		tw.tween_property(m, "modulate:a", 0.0, 0.12)
		tw.tween_callback(m.queue_free)
	modal = null
	modal_kind = ""
	joy.blocked = false
	_confirm_reset = false


func _refresh_modal_soft() -> void:
	if modal_kind in ["shop", "crew", "gate"]:
		_rebuild_modal()


func _rebuild_modal() -> void:
	if modal == null:
		return
	var old := modal.get_node_or_null("Card")
	if old:
		old.free()
	var center := CenterContainer.new()
	center.name = "Card"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	modal.add_child(center)
	var card := UIShape.new("glass_strong", 30.0, Vector4(26, 24, 26, 28))
	card.custom_minimum_size.x = minf(660.0, root.get_viewport_rect().size.x - 36.0)
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	center.add_child(card)
	var v := UI.vbox(16)
	card.add_child(v)
	match modal_kind:
		"shop": _shop(v)
		"crew": _crew(v)
		"jobs": _jobs(v)
		"offline": _offline(v)
		"gate": _gate(v)
		"complete": _complete(v)
		"empire": _empire(v)
		"settings": _settings(v)


func _header(v: VBoxContainer, icon_name: String, title: String, sub := "", closable := true) -> void:
	var h := UI.hbox(14)
	h.alignment = BoxContainer.ALIGNMENT_BEGIN
	h.add_child(UI.icon(icon_name, 64))
	var tv := UI.vbox(0)
	tv.add_child(UI.label(title, 46, Color.WHITE, UI.font_bold()))
	if sub != "":
		tv.add_child(UI.label(sub, 22, UI.MUTED))
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(tv)
	if closable:
		var x := UIShape.new("dark", 22.0, Vector4(16, 6, 16, 6)).make_clickable()
		x.add_child(UI.label("✕", 30, Color.WHITE, UI.font_ui(600), HORIZONTAL_ALIGNMENT_CENTER))
		x.custom_minimum_size = Vector2(60, 60)
		x.pressed.connect(close_modal)
		h.add_child(x)
	v.add_child(h)


func _row(v: VBoxContainer, icon_name: String, title: String, desc: String, stat: String, btn: UIShape) -> void:
	var r := UIShape.new("dark", 22.0, Vector4(14, 12, 14, 12))
	r.mouse_filter = Control.MOUSE_FILTER_PASS
	var h := UI.hbox(14)
	h.alignment = BoxContainer.ALIGNMENT_BEGIN
	var ib := UIShape.new("dark", 18.0, Vector4(6, 6, 6, 6))
	ib.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ib.add_child(UI.icon(icon_name, 70))
	h.add_child(ib)
	var tv := UI.vbox(2)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_child(UI.label(title, 32, Color.WHITE, UI.font_bold()))
	var d := UI.label(desc, 20, UI.MUTED)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size.x = 260
	tv.add_child(d)
	if stat != "":
		var sl := UI.label(stat, 21, UI.GOLD_LIGHT, UI.font_ui(650))
		sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sl.custom_minimum_size.x = 260
		tv.add_child(sl)
	h.add_child(tv)
	if btn:
		btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(btn)
	r.add_child(h)
	v.add_child(r)


func _price_button(cost: int, cb: Callable, label_override := "") -> UIShape:
	var b: UIShape
	if label_override != "":
		b = UI.button(label_override, "dark", "", 28, 150)
		b.disabled = true
		return b
	b = UI.button(UI.fmt(cost), "gold", "coin", 30, 150)
	b.disabled = Game.coins < cost
	b.pressed.connect(func():
		if Game.coins >= cost:
			cb.call()
			Sfx.play("build", -6.0, 1.2)
			world.fx_burst(world.player.global_position + Vector3.UP * 1.5, Color(1, 0.85, 0.4), 24)
		else:
			show_toast("Not enough coins"))
	return b


# ------------------------------------------------------------------ panels

const TOOL_ICONS := {"axe": "axe", "double_axe": "double_axe", "chainsaw": "chainsaw", "harvester": "harvester"}


func _shop(v: VBoxContainer) -> void:
	_header(v, "hammer", "Tool Shed", "Upgrades apply instantly")
	var cur: Dictionary = Game.tool()
	var nt := Game.next_upgrade("tool")
	if nt.is_empty():
		_row(v, TOOL_ICONS[cur.id], cur.name, cur.desc, "Best tool owned", _price_button(0, Callable(), "MAX"))
	else:
		_row(v, TOOL_ICONS[nt.id], nt.name, nt.desc, "Now: " + String(cur.name), _price_button(int(nt.cost), func(): Game.buy_upgrade("tool")))
	var tracks := [
		["bag", "bag", "Backpack", "Carry more logs per trip", func(d): return "%d logs" % int(d.cap)],
		["boots", "boots", "Trail boots", "Run faster", func(d): return "+%d%% speed" % int(round((float(d.mult) - 1.0) * 100))],
		["fire", "fire", "Hotter fire", "Cook dishes faster", func(d): return "%.1fs per dish" % float(d.cook)],
		["menu", "menu", "Better menu", "Each dish sells for more", func(d): return "%d coins" % int(d.price)],
	]
	for t in tracks:
		var key: String = t[0]
		var arr: Array = Game.cfg[key]
		var cur_d: Dictionary = arr[Game.levels[key]]
		var nx := Game.next_upgrade(key)
		var fmtf: Callable = t[4]
		if nx.is_empty():
			_row(v, t[1], t[2], t[3], fmtf.call(cur_d) + "  (max)", _price_button(0, Callable(), "MAX"))
		else:
			_row(v, t[1], t[2], t[3], fmtf.call(cur_d) + "  →  " + fmtf.call(nx),
				_price_button(int(nx.cost), func(): Game.buy_upgrade(key)))


func _crew(v: VBoxContainer) -> void:
	_header(v, "crew", "Hire Crew", "They keep working while you're away")
	for role in ["lumberjack", "waiter", "cook"]:
		var c: Dictionary = Game.cfg.crew[role]
		var have: int = Game.crew[role]
		var cost := Game.crew_next_cost(role)
		var btn := _price_button(cost, func(): Game.hire(role)) if cost >= 0 else _price_button(0, Callable(), "FULL")
		_row(v, role, c.name, c.desc, "Hired %d / %d" % [have, int(c.max)], btn)
	var rate := Game.passive_rate()
	var note := "Crew income while away: %s / min" % UI.fmt(rate * 60.0 * float(Game.cfg.offline.efficiency)) if rate > 0 else "Hire a lumberjack and a waiter to earn while away"
	var l := UI.label(note, 21, UI.MUTED, null, HORIZONTAL_ALIGNMENT_CENTER)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(l)


func _jobs(v: VBoxContainer) -> void:
	_header(v, "jobs", "Daily Jobs", "New jobs every day")
	for i in Game.jobs.size():
		var j: Dictionary = Game.jobs[i]
		var r := UIShape.new("dark", 22.0, Vector4(16, 14, 16, 14))
		var h := UI.hbox(14)
		h.alignment = BoxContainer.ALIGNMENT_BEGIN
		var tv := UI.vbox(8)
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tv.add_child(UI.label(j.text, 27, Color.WHITE, UI.font_ui(650)))
		var pr := UI.hbox(10)
		pr.alignment = BoxContainer.ALIGNMENT_BEGIN
		var bar := UI.progress_bar(250, 14)
		bar.max_value = j.goal
		bar.value = j.prog
		pr.add_child(bar)
		pr.add_child(UI.label("%d/%d" % [j.prog, j.goal], 20, UI.MUTED))
		tv.add_child(pr)
		h.add_child(tv)
		var b: UIShape
		if j.claimed:
			b = UI.button("DONE", "dark", "check", 26, 150)
			b.disabled = true
		elif j.prog >= j.goal:
			b = UI.button("+" + UI.fmt(j.reward), "green", "coin", 28, 150)
			var idx := i
			b.pressed.connect(func():
				Game.claim_job(idx)
				Sfx.play("cash"))
		else:
			b = UI.button(UI.fmt(j.reward), "dark", "coin", 26, 150)
			b.disabled = true
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(b)
		r.add_child(h)
		v.add_child(r)
	# streak
	var sv := UIShape.new("dark", 22.0, Vector4(16, 14, 16, 14))
	var col := UI.vbox(10)
	col.add_child(UI.label("Streak · finish all 3 jobs each day", 22, UI.MUTED))
	var dots := UI.hbox(10)
	for d in 7:
		var on := d < Game.streak
		var s := UIShape.new("gold" if on else "dark", 18.0, Vector4(0, 0, 0, 0))
		s.mouse_filter = Control.MOUSE_FILTER_IGNORE
		s.custom_minimum_size = Vector2(66, 58)
		var dl := UI.label("D%d" % (d + 1), 24, UI.INK if on else UI.MUTED, UI.font_bold(), HORIZONTAL_ALIGNMENT_CENTER)
		s.add_child(dl)
		dots.add_child(s)
	col.add_child(dots)
	var all_done := Game.jobs.all(func(x): return x.claimed)
	var chest := UI.button(("Claim chest +" + UI.fmt(Game.streak_reward())) if not Game.chest_claimed else "Chest claimed · back tomorrow",
		"gold" if all_done and not Game.chest_claimed else "dark", "chest", 26)
	chest.disabled = not all_done or Game.chest_claimed
	chest.pressed.connect(func():
		Game.claim_chest()
		Sfx.play("build"))
	col.add_child(chest)
	sv.add_child(col)
	v.add_child(sv)


func _offline(v: VBoxContainer) -> void:
	_header(v, "clock", "While you were away", "", false)
	var mins := Game.offline_seconds / 60
	var t := "%dh %02dm" % [mins / 60, mins % 60]
	v.add_child(UI.label("Your crew kept the camp running for %s." % t, 24, UI.MUTED, null, HORIZONTAL_ALIGNMENT_CENTER))
	var amt := UI.hbox(12)
	amt.add_child(UI.icon("coin", 84))
	amt.add_child(UI.num(UI.fmt(Game.offline_reward), 84, UI.GOLD_LIGHT))
	v.add_child(amt)
	v.add_child(UI.label("Away earnings run at 50%, up to 2 hours.", 20, UI.MUTED, null, HORIZONTAL_ALIGNMENT_CENTER))
	var b := UI.button("COLLECT", "gold", "", 36)
	b.pressed.connect(func():
		Game.claim_offline()
		Sfx.play("cash")
		close_modal())
	v.add_child(b)


func _gate(v: VBoxContainer) -> void:
	var last := Game.is_last_chapter()
	var nx: Dictionary = {} if last else Game.chapters[Game.venue + 1]
	if last:
		_header(v, "star", "Complete the Empire", "Finish every venue, then start a New Empire with +50% income")
	else:
		_header(v, "gate", String(nx.name), "Next venue: " + String(nx.tagline).to_lower())
	var g: Dictionary = Game.cfg.gate
	var s := Game.gate_status()
	var reqs := [
		[s.built, "Build every camp upgrade", "Tables + crew cabin"],
		[s.served, "Serve %d guests" % int(g.served), "%d / %d" % [Game.vserved, int(g.served)]],
		[s.rating, "Keep a %.1f★ rating" % float(g.rating), "%.1f now" % Game.rating()],
		[s.coins, "Save %s coins" % UI.fmt(int(g.coins)), "%s / %s" % [UI.fmt(Game.coins), UI.fmt(int(g.coins))]],
	]
	for r in reqs:
		var row := UIShape.new("dark", 20.0, Vector4(14, 10, 16, 10))
		var h := UI.hbox(14)
		h.alignment = BoxContainer.ALIGNMENT_BEGIN
		h.add_child(UI.icon("check" if r[0] else "lock", 46))
		var lab := UI.label(r[1], 26, Color.WHITE, UI.font_ui(600))
		lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(lab)
		h.add_child(UI.label(r[2], 22, UI.GREEN if r[0] else UI.MUTED, UI.font_ui(650)))
		row.add_child(h)
		v.add_child(row)
	var b := UI.button("COMPLETE THE EMPIRE" if last else "UNLOCK " + String(nx.name).to_upper(), "green", "gate", 30)
	b.disabled = not Game.gate_ready()
	b.pressed.connect(func():
		if Game.gate_ready():
			Game.open_next_venue()
			Sfx.play("build")
			open_modal("complete")
		else:
			show_toast("Finish the checklist first"))
	v.add_child(b)


func _complete(v: VBoxContainer) -> void:
	var ch: Dictionary = Game.chapter()
	var last := Game.is_last_chapter()
	_header(v, "star", "Chapter %d complete!" % (Game.venue + 1), String(ch.name) + " · mastered", false)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	var mins := int(Game.stats.play_s / 60.0)
	for s in [["Trees felled", str(int(Game.stats.trees))], ["Guests served", str(Game.served)],
			["Coins earned", UI.fmt(Game.stats.earned)], ["Time played", "%dh %02dm" % [mins / 60, mins % 60]]]:
		var c := UIShape.new("dark", 20.0, Vector4(18, 12, 18, 12))
		c.custom_minimum_size.x = 285
		var cv := UI.vbox(0)
		cv.add_child(UI.label(s[0], 20, UI.MUTED))
		cv.add_child(UI.num(s[1], 44, UI.GOLD_LIGHT))
		c.add_child(cv)
		grid.add_child(c)
	v.add_child(grid)
	var txt: String
	if last:
		txt = "You built the whole Timber Empire! Start a New Empire: everything resets, but every coin you earn is worth +50% more, forever."
	else:
		var nx: Dictionary = Game.chapters[Game.venue + 1]
		txt = "%s is open: %s. Your crew here keeps working and earns for you while you're away." % [nx.name, String(nx.tagline).to_lower()]
	var l := UI.label(txt, 22, UI.MUTED, null, HORIZONTAL_ALIGNMENT_CENTER)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(l)
	if last:
		var pb := UI.button("START NEW EMPIRE  (+50%)", "green", "star", 30)
		pb.pressed.connect(func():
			Game.start_new_empire()
			close_modal()
			get_tree().current_scene.reload_venue())
		v.add_child(pb)
	else:
		var tb := UI.button("TRAVEL NOW", "green", "gate", 34)
		tb.pressed.connect(func():
			close_modal()
			get_tree().current_scene.travel_to(Game.venue + 1))
		v.add_child(tb)
	var b := UI.button("STAY HERE", "dark", "", 28)
	b.pressed.connect(close_modal)
	v.add_child(b)


## Empire map: every chapter, its income, and travel.
func _empire(v: VBoxContainer) -> void:
	var er := Game.empire_rate() * 60.0
	var sub: String
	if er > 0:
		sub = "Background income: %s / min" % UI.fmt(er)
	else:
		sub = "Crews keep earning at half speed at venues you leave"
	_header(v, "gate", "Your Empire", sub)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(0, minf(820.0, root.get_viewport_rect().size.y - 420.0))
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var list := UI.vbox(12)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list)
	v.add_child(sc)
	for k in Game.chapters.size():
		var ch: Dictionary = Game.chapters[k]
		var btn: UIShape
		var stat: String
		if k == Game.venue:
			btn = _price_button(0, Callable(), "HERE")
			stat = "You are here"
		elif k < Game.unlocked:
			btn = UI.button("TRAVEL", "green", "", 28, 150)
			var kk := k
			btn.pressed.connect(func():
				close_modal()
				get_tree().current_scene.travel_to(kk))
			var r := Game.venue_rate(k) * 60.0 * Game.VENUE_EFFICIENCY
			stat = ("Earning %s / min" % UI.fmt(r)) if r > 0 else "Unlocked · no crew earning yet"
		else:
			btn = _price_button(0, Callable(), "LOCKED")
			stat = "Unlock at chapter %d's gate" % k
		_row(list, "lock" if k >= Game.unlocked else "star", "%d. %s" % [k + 1, ch.name], String(ch.tagline), stat, btn)
	if Game.prestige > 0:
		v.add_child(UI.label("Empire %d · income x%.1f" % [Game.prestige + 1, Game.income_mult()], 22, UI.GOLD_LIGHT, null, HORIZONTAL_ALIGNMENT_CENTER))
	var cb := UI.button("CLOSE", "dark", "", 28)
	cb.pressed.connect(close_modal)
	v.add_child(cb)


func _settings(v: VBoxContainer) -> void:
	_header(v, "settings", "Settings")
	var snd := UI.button("Sound: " + ("OFF" if Game.mute else "ON"), "dark", "", 30)
	snd.pressed.connect(func():
		Game.mute = not Game.mute
		Sfx.saw(false)
		_rebuild_modal())
	v.add_child(snd)
	if OS.has_feature("mobile") or OS.get_cmdline_user_args().has("mobile"):
		var gq := UI.button("Graphics: " + String(Game.QUALITY_NAMES[Game.quality]) + (" (auto)" if Game.quality_auto else ""), "dark", "", 30)
		gq.pressed.connect(func():
			Game.quality = (Game.quality + 2) % 3
			Game.quality_auto = false
			Game.save_game()
			get_tree().current_scene.apply_quality()
			_rebuild_modal())
		v.add_child(gq)
	var rs := UI.button("Tap again to erase everything" if _confirm_reset else "Reset progress", "red", "", 28)
	rs.pressed.connect(func():
		if _confirm_reset:
			Game.reset_all()
		else:
			_confirm_reset = true
			_rebuild_modal())
	v.add_child(rs)
	v.add_child(UI.label("Axe to Empire v" + str(ProjectSettings.get_setting("application/config/version")), 20, UI.MUTED, null, HORIZONTAL_ALIGNMENT_CENTER))
