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
var stars_label: Label
var task_card: UIShape
var task_title: Label
var task_bar: ProgressBar
var task_prog: Label
var task_btn: UIShape
var task_icon: TextureRect
var reno_chip: UIShape
var reno_label: Label
var bd_banner: UIShape
var bd_title: Label
var bd_info: Label
var bd_bar: ProgressBar
var _story_q: Array = []
var _story_showing := false
var _bd_result: Array = []


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
	_build_task_card()
	_build_bd_banner()
	Game.story.connect(_on_story)
	Game.task_changed.connect(_refresh_task)
	Game.offline_ready.connect(func():
		if modal_kind == "":
			open_modal("offline"))
	world.big_day_finished.connect(func(won, served, goal):
		_bd_result = [won, served, goal]
		open_modal("bigday_result"))
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
	_refresh_task()
	_refresh_jobs_badge()
	if Game.offline_reward > 0:
		open_modal.call_deferred("offline")
	elif Game.chapter_done:
		pass


func _ui_hit(p: Vector2) -> bool:
	if modal != null:
		return true
	for c in jobs_btn.get_parent().get_parent().get_children() + [task_btn, task_card]:
		if c is Control and c.is_visible_in_tree() and c.get_global_rect().has_point(p):
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
	coin_label = UI.num("0", 44, UI.CASH)
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
	var sep2 := ColorRect.new()
	sep2.color = Color(1, 1, 1, 0.15)
	sep2.custom_minimum_size = Vector2(2, 34)
	rr.add_child(sep2)
	rr.add_child(UI.icon("trophy", 34))
	stars_label = UI.num("0", 34, UI.GOLD_LIGHT)
	rr.add_child(stars_label)
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
	side.add_child(_round_button("upgrade", "UPGRADE", func(): open_modal("upgrades")))
	side.add_child(_round_button("character", "ME", func(): open_modal("character")))
	map_btn = _round_button("gate", "MAP", func(): open_modal("empire"))
	map_btn.visible = Game.unlocked > 1
	side.add_child(map_btn)
	side.add_child(_round_button("settings", "", func(): open_modal("settings")))


func _round_button(icon_name: String, text: String, cb: Callable) -> UIShape:
	var b := UIShape.new("glass", 26.0, Vector4(10, 10, 10, 8)).make_clickable()
	b.custom_minimum_size = Vector2(96, 96)
	var v := UI.vbox(0)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	var ic := UI.icon(icon_name if ResourceLoader.exists("res://assets/icons/%s.svg" % icon_name) else "star", 56)
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
	c.position.y = _safe_top() + 330
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
	coin_label.text = UI.cash(round(_coin_shown))
	served_label.text = str(Game.served)
	stars_label.text = str(Game.total_stars())
	_tick_overlays()
	if map_btn:
		map_btn.visible = Game.unlocked > 1
		var fresh: bool = Game.venue + 1 < Game.unlocked and (Game.venue + 1 >= Game.venues.size() or Game.venues[Game.venue + 1].is_empty())
		_map_pulse += delta
		var k := 1.0 + (0.08 * sin(_map_pulse * 6.0) if fresh else 0.0)
		map_btn.scale = Vector2(k, k)
		map_btn.pivot_offset = map_btn.size * 0.5
	if fps_label:
		fps_label.visible = Game.settings.get("show_fps", false) or OS.get_cmdline_user_args().has("fps")
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
		if e is InputEventMouseButton and e.pressed and not kind in ["offline", "complete", "empire", "story", "bigday_result"]:
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
	if not _story_q.is_empty():
		_next_story.call_deferred()
	elif Game.offline_reward > 0:
		(func(): if modal_kind == "" and Game.offline_reward > 0: open_modal("offline")).call_deferred()


func _refresh_modal_soft() -> void:
	if modal_kind in ["shop", "crew", "gate", "upgrades", "character"]:
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
		"upgrades": _upgrades(v)
		"character": _character(v)
		"story": _story(v)
		"bigday_result": _bigday_result(v)
		"howto": _howto(v)
		"stats": _stats(v)


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
	b = UI.button(UI.cash(cost), "gold", "", 30, 150)
	b.disabled = Game.coins < cost
	b.pressed.connect(func():
		if Game.coins >= cost:
			cb.call()
			Sfx.play("build", -6.0, 1.2)
			world.fx_burst(world.player.global_position + Vector3.UP * 1.5, Color(1, 0.85, 0.4), 24)
		else:
			show_toast("Not enough cash"))
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
	var ub := UI.button("KITCHEN, MENU & STATION UPGRADES", "dark", "upgrade", 24)
	ub.pressed.connect(func(): open_modal("upgrades"))
	v.add_child(ub)


func _crew(v: VBoxContainer) -> void:
	_header(v, "crew", "Hire Crew", "They keep working while you're away")
	for role in ["lumberjack", "waiter", "cook"]:
		var c: Dictionary = Game.cfg.crew[role]
		var have: int = Game.crew[role]
		var cost := Game.crew_next_cost(role)
		var btn := _price_button(cost, func(): Game.hire(role)) if cost >= 0 else _price_button(0, Callable(), "FULL")
		_row(v, role, c.name, c.desc, "Hired %d / %d" % [have, int(c.max)], btn)
	var rate := Game.passive_rate()
	var note := ("Crew income while away: %s / min (up to %s h)" % [UI.cash(rate * 60.0 * float(Game.cfg.offline.efficiency)), _hours(Game.offline_cap_hours())]) if rate > 0 else "Hire a lumberjack and a waiter to earn while away"
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
			b = UI.button("+" + UI.cash(j.reward), "green", "", 28, 150)
			var idx := i
			b.pressed.connect(func():
				Game.claim_job(idx)
				Sfx.play("cash"))
		else:
			b = UI.button(UI.cash(j.reward), "dark", "", 26, 150)
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
	var chest := UI.button(("Claim chest +" + UI.cash(Game.streak_reward())) if not Game.chest_claimed else "Chest claimed · back tomorrow",
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
	amt.add_child(UI.num(UI.cash(Game.offline_reward), 84, UI.CASH))
	v.add_child(amt)
	var al := UI.label("Away, your crew earns at %d%%, for up to %s hours. Play to earn far more: guests pay more when you serve them yourself." % [int(float(Game.cfg.offline.efficiency) * 100), _hours(Game.offline_cap_hours())], 20, UI.MUTED, null, HORIZONTAL_ALIGNMENT_CENTER)
	al.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(al)
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
	var need_built: Array = ["tables_2", "crew_hut"] + (["special"] if Game.special_type() != "" else [])
	var reqs := [
		[s.built, "Build every camp upgrade", "%d / %d" % [need_built.filter(func(id): return Game.built.has(id)).size(), need_built.size()]],
		[s.served, "Serve %d guests" % int(g.served), "%d / %d" % [Game.vserved, int(g.served)]],
		[s.rating, "Keep a %.1f★ rating" % float(g.rating), "%.1f now" % Game.rating()],
		[s.coins, "Save %s" % UI.cash(int(g.coins)), "%s / %s" % [UI.cash(Game.coins), UI.cash(int(g.coins))]],
		[s.bigday, "Win the Big Day: " + String(Game.big_day_def().get("name", "")), "WON" if s.bigday else ("ready" if s.built else "build first")],
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
	if Game.big_day_replayable():
		var replay: bool = Game.bigday.get("won", false)
		var bdd: Dictionary = Game.big_day_def()
		var info := UI.label("%s: %s
Serve %d guests in %d:%02d. More than %d walkouts and it's over.
%s" % [String(bdd.name), String(bdd.desc), int(bdd.goal), int(bdd.seconds) / 60, int(bdd.seconds) % 60, int(bdd.get("max_walkouts", 10)), "Replay it with no walkouts to earn the third star." if replay else "Tip: fill the woodpile and the rack first!"], 22, UI.GOLD_LIGHT, null, HORIZONTAL_ALIGNMENT_CENTER)
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(info)
		var cool: float = world._bd_cool
		var sb := UI.button((("REPLAY FOR STAR 3" if replay else "START " + String(bdd.name).to_upper())) if cool <= 0.0 else "Ready again in %ds" % ceili(cool), "gold", "bigday", 30)
		sb.disabled = cool > 0.0
		sb.pressed.connect(func():
			if world.start_big_day():
				close_modal()
				Game.fire_story("bigday_start"))
		v.add_child(sb)
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
			["Cash earned", UI.cash(Game.stats.earned)], ["Time played", "%dh %02dm" % [mins / 60, mins % 60]]]:
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
		txt = "You built the whole Timber Empire! Start a New Empire in a new valley: everything resets, but every dollar you earn is worth +50% more, forever."
	else:
		var nx: Dictionary = Game.chapters[Game.venue + 1]
		txt = "%s is open: %s. New there: %s. It's a brand-new place, so you build it up from scratch, but your %s comes with you, and your crew here keeps earning for you." % [nx.name, String(nx.tagline).to_lower(), String(nx.get("special", {}).get("name", "")).to_lower(), UI.cash(Game.coins)]
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
		sub = "Background income: %s / min" % UI.cash(er)
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
			stat = ("Earning %s / min" % UI.cash(r)) if r > 0 else "Unlocked · no crew earning yet"
		else:
			btn = _price_button(0, Callable(), "LOCKED")
			stat = "Unlock at chapter %d's gate" % k
		var desc := String(ch.tagline)
		if ch.has("special"):
			desc += " · New: " + String(ch.special.name)
		if k < Game.unlocked:
			var st: Array = Game.stars(k)
			stat += "   " + "".join(st.map(func(x): return "★" if x else "☆"))
		_row(list, "lock" if k >= Game.unlocked else "star", "%d. %s" % [k + 1, ch.name], desc, stat, btn)
	if Game.prestige > 0:
		v.add_child(UI.label("Empire %d · income x%.1f" % [Game.prestige + 1, Game.income_mult()], 22, UI.GOLD_LIGHT, null, HORIZONTAL_ALIGNMENT_CENTER))
	var cb := UI.button("CLOSE", "dark", "", 28)
	cb.pressed.connect(close_modal)
	v.add_child(cb)



func _hours(h: float) -> String:
	return ("%d" % int(h)) if is_equal_approx(h, roundf(h)) else ("%.1f" % h)


func _icon_or(name: String, fallback: String, px: int) -> TextureRect:
	return UI.icon(name if ResourceLoader.exists("res://assets/icons/%s.svg" % name) else fallback, px)


# ------------------------------------------------------------------ chapter task card (always on screen)

func _build_task_card() -> void:
	task_card = UIShape.new("glass", 22.0, Vector4(12, 10, 12, 10))
	task_card.position = Vector2(18, _safe_top() + 150)
	task_card.custom_minimum_size = Vector2(430, 0)
	root.add_child(task_card)
	var h := UI.hbox(10)
	h.alignment = BoxContainer.ALIGNMENT_BEGIN
	task_icon = _icon_or("task", "jobs", 44)
	h.add_child(task_icon)
	var col := UI.vbox(4)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	task_title = UI.label("", 22, Color.WHITE, UI.font_ui(650))
	task_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	task_title.custom_minimum_size.x = 230
	col.add_child(task_title)
	var pr := UI.hbox(8)
	pr.alignment = BoxContainer.ALIGNMENT_BEGIN
	task_bar = UI.progress_bar(150, 10)
	pr.add_child(task_bar)
	task_prog = UI.label("", 18, UI.MUTED)
	pr.add_child(task_prog)
	col.add_child(pr)
	h.add_child(col)
	task_btn = UI.button("", "green", "", 22, 110)
	task_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	task_btn.pressed.connect(func():
		if Game.task_done():
			var r := Game.task_reward(Game.current_task())
			Game.claim_task()
			Sfx.play("cash")
			world.fx_burst(world.player.global_position + Vector3.UP * 1.6, Color(0.5, 0.95, 0.55), 30)
			show_toast("Task complete! +" + UI.cash(r)))
	h.add_child(task_btn)
	task_card.add_child(h)
	reno_chip = UIShape.new("dark", 18.0, Vector4(12, 6, 14, 6))
	reno_chip.make_clickable()
	reno_chip.pressed.connect(func(): open_modal("upgrades"))
	var rh := UI.hbox(8)
	rh.add_child(_icon_or("timer", "clock", 30))
	reno_label = UI.label("", 20, Color.WHITE, UI.font_ui(600))
	rh.add_child(reno_label)
	reno_chip.add_child(rh)
	root.add_child(reno_chip)
	reno_chip.visible = false


func _refresh_task() -> void:
	if task_card == null:
		return
	var t := Game.current_task()
	if t.is_empty():
		task_title.text = "Chapter tasks done! Earn ★★★ in UPGRADE"
		task_bar.visible = false
		task_prog.text = ""
		task_btn.visible = false
		return
	var p := Game.task_progress(t)
	task_title.text = "TASK %d/%d · %s" % [Game.task_i + 1, Game.tasks().size(), Game.task_text(t)]
	task_bar.visible = true
	task_bar.max_value = p[1]
	task_bar.value = p[0]
	task_prog.text = "%d/%d" % p if p[1] > 1 else ""
	task_btn.visible = true
	var done: bool = p[0] >= p[1]
	UI.set_button_text(task_btn, ("CLAIM " if done else "") + UI.cash(Game.task_reward(t)))
	task_btn.disabled = not done
	task_btn.modulate = Color.WHITE if done else Color(1, 1, 1, 0.55)


var _ov_t := 0.0


## Per-frame light work: task progress, renovation timer, Big Day banner.
func _tick_overlays() -> void:
	_ov_t -= get_process_delta_time()
	var bd_on: bool = world.bd_active
	bd_banner.visible = bd_on
	task_card.visible = not bd_on and modal_kind == ""
	if bd_on:
		var left := maxi(0, ceili(world.bd_left))
		bd_title.text = "%s · %d:%02d" % [String(world.bd.get("name", "")).to_upper(), left / 60, left % 60]
		bd_info.text = "Served %d / %d   ·   walkouts %d / %d" % [world.bd_served, world.bd_goal(), world.bd_walkouts, world.bd_max_walkouts()]
		bd_bar.max_value = world.bd_goal()
		bd_bar.value = world.bd_served
	if _ov_t > 0.0:
		return
	_ov_t = 0.25
	_refresh_task()
	if Game.task_done():
		var k := 1.0 + 0.05 * sin(Time.get_ticks_msec() * 0.008)
		task_btn.scale = Vector2(k, k)
		task_btn.pivot_offset = task_btn.size * 0.5
	else:
		task_btn.scale = Vector2.ONE
	reno_chip.visible = not Game.reno.is_empty() and not bd_on and modal_kind == ""
	if reno_chip.visible:
		var l := Game.reno_left()
		reno_label.text = "%s → Lv %d · %s" % [String(Game.station_def(Game.reno.id).name), int(Game.reno.to) + 1, _clock(l)]
		reno_chip.position = Vector2(18, task_card.position.y + task_card.size.y + 10)


func _clock(secs: int) -> String:
	if secs >= 3600:
		return "%dh %02dm" % [secs / 3600, (secs % 3600) / 60]
	return "%d:%02d" % [secs / 60, secs % 60]


# ------------------------------------------------------------------ Big Day banner

func _build_bd_banner() -> void:
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_TOP_WIDE)
	cc.position.y = _safe_top() + 140
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(cc)
	bd_banner = UIShape.new("gold", 24.0, Vector4(22, 10, 22, 12))
	bd_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := UI.vbox(4)
	bd_title = UI.label("", 30, UI.INK, UI.font_bold(), HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(bd_title)
	bd_bar = UI.progress_bar(420, 14)
	var fg := StyleBoxFlat.new()
	fg.bg_color = Color("#3E9B4F")
	fg.set_corner_radius_all(7)
	bd_bar.add_theme_stylebox_override("fill", fg)
	v.add_child(bd_bar)
	bd_info = UI.label("", 20, UI.INK, UI.font_ui(650), HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(bd_info)
	bd_banner.add_child(v)
	cc.add_child(bd_banner)
	bd_banner.visible = false


func _bigday_result(v: VBoxContainer) -> void:
	var won: bool = _bd_result[0] if _bd_result.size() > 0 else false
	var bdd: Dictionary = Game.big_day_def()
	_header(v, "trophy" if won else "clock", ("%s won!" if won else "%s: not this time") % String(bdd.get("name", "Big Day")),
		"Served %d of %d" % [_bd_result[1], _bd_result[2]] if _bd_result.size() > 2 else "", false)
	var st: Array = Game.stars()
	var row := UI.hbox(18)
	for i in 3:
		var l := UI.label("★" if st[i] else "☆", 84, UI.GOLD_LIGHT if st[i] else UI.MUTED, UI.font_bold())
		row.add_child(l)
	v.add_child(row)
	var txt: String
	if won:
		txt = "Big Day won! The road to the next place is open: unlock it at the gate."
		if Game.is_last_chapter():
			txt = "The critic loved it. Finish the empire at the gate!"
		if not Game.bigday.get("clean", false):
			txt += " Win it with no walkouts for the third star."
	else:
		txt = "Upgrade the kitchen and menu, hire help, stock the rack, then try again."
	var tl := UI.label(txt, 22, UI.MUTED, null, HORIZONTAL_ALIGNMENT_CENTER)
	tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(tl)
	var b := UI.button("CONTINUE", "green" if won else "dark", "", 30)
	b.pressed.connect(close_modal)
	v.add_child(b)


# ------------------------------------------------------------------ story cards

func _on_story(beats: Array) -> void:
	if not Game.settings.get("story", true):
		return
	_story_q.append_array(beats)
	if modal_kind == "":
		_next_story.call_deferred()


func _next_story() -> void:
	if _story_q.is_empty() or modal_kind != "":
		return
	open_modal("story")


func _story(v: VBoxContainer) -> void:
	if _story_q.is_empty():
		close_modal.call_deferred()
		return
	var b: Dictionary = _story_q[0]
	var who := String(b.who)
	var ch := Game.character(who)
	var h := UI.hbox(18)
	h.alignment = BoxContainer.ALIGNMENT_BEGIN
	var pf := UIShape.new("dark", 70.0, Vector4(6, 6, 6, 6))
	pf.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pf.add_child(_icon_or("portrait_" + who, "smile", 136))
	h.add_child(pf)
	var tv := UI.vbox(2)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_child(UI.label(String(ch.name), 40, UI.GOLD_LIGHT if who != "victor" else Color("#C9CED6"), UI.font_bold()))
	tv.add_child(UI.label(String(ch.role), 22, UI.MUTED))
	h.add_child(tv)
	v.add_child(h)
	var tx := UI.label("“" + String(b.text) + "”", 28, Color.WHITE, UI.font_ui(520))
	tx.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tx.custom_minimum_size.x = 560
	v.add_child(tx)
	var nb := UI.button("NEXT" if _story_q.size() > 1 else "OK", "gold", "", 30)
	nb.pressed.connect(func():
		_story_q.pop_front()
		if _story_q.is_empty():
			close_modal()
		else:
			_rebuild_modal())
	v.add_child(nb)


# ------------------------------------------------------------------ station upgrades

const STATION_ICONS := {"fire": "fire", "menu": "menu", "dining": "smile", "sign": "star", "station": "upgrade"}


func _station_effect(key: String, lv: int) -> String:
	match key:
		"fire": return "%.1fs per dish" % Game.kitchen_cook(Game.cfg, lv)
		"menu": return "%s a dish" % UI.cash(roundf(Game.menu_price(Game.cfg, lv) * Game.income_mult()))
		"dining": return "+%d%% patience, %d%% tips" % [2 * lv, int(round((float(Game.cfg.customers.seated_tip) + 0.01 * lv) * 100))]
		"sign": return "+%d%% guests" % (4 * lv)
		"station": return "+%d%% station pay%s" % [4 * lv, " · crew helps" if lv >= 4 else ""]
	return ""


func _upgrades(v: VBoxContainer) -> void:
	var st: Array = Game.stars()
	_header(v, "upgrade", "Upgrades", String(Game.chapter().name) + "   " + "".join(st.map(func(x): return "★" if x else "☆")))
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(0, minf(900.0, root.get_viewport_rect().size.y - 470.0))
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var list := UI.vbox(12)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list)
	v.add_child(sc)
	if not Game.reno.is_empty():
		var rr := UIShape.new("gold", 20.0, Vector4(16, 10, 16, 10))
		var rh := UI.hbox(12)
		rh.add_child(_icon_or("timer", "clock", 46))
		var rl := UI.label("Renovating %s → Lv %d · %s left" % [String(Game.station_def(Game.reno.id).name), int(Game.reno.to) + 1, _clock(Game.reno_left())], 23, UI.INK, UI.font_bold())
		rl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rh.add_child(rl)
		var rush := UI.button("FINISH " + UI.cash(Game.reno_rush_cost()), "green", "", 22, 150)
		rush.disabled = Game.coins < Game.reno_rush_cost()
		rush.pressed.connect(func():
			if Game.reno_rush():
				Sfx.play("build")
				_rebuild_modal())
		rh.add_child(rush)
		rr.add_child(rh)
		list.add_child(rr)
	for key in Game.STATIONS:
		if key == "station" and Game.special_type() == "":
			continue
		var d := Game.station_def(key)
		var lv: int = Game.levels[key]
		var lock := Game.station_locked(key)
		var title := "%s  ·  Lv %d" % [String(d.name) if key != "station" else String(Game.special_def().get("name", d.name)), lv + 1]
		var stat := _station_effect(key, lv)
		var btn: UIShape
		if lock == "MAX":
			btn = _price_button(0, Callable(), "MAX")
		elif lock != "":
			btn = _price_button(0, Callable(), lock if lock.length() < 14 else "LOCKED")
			stat += "\n" + lock
		else:
			stat += "  →  " + _station_effect(key, lv + 1)
			var secs := Game.reno_seconds(lv + 2)
			if secs > 0:
				stat += "\nRenovation: takes " + _clock(secs) + " (big boost)"
			var kk: String = key
			btn = _price_button(Game.station_cost(key), func():
				if Game.station_upgrade(kk):
					_rebuild_modal())
		_row(list, STATION_ICONS.get(key, "star"), title, String(d.desc), stat, btn)
	var info := UI.label("★ Big Day won   ★ 4.5★ rating held   ★ every station Lv 15 + a Big Day with no walkouts.\nEvery star: +4% income everywhere.", 19, UI.MUTED, null, HORIZONTAL_ALIGNMENT_CENTER)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(info)


# ------------------------------------------------------------------ character: gear + wardrobe

var _wardrobe_slot := "shirt"


func _character(v: VBoxContainer) -> void:
	_header(v, "character", "Your Lumberjack", "Empire %d · %d ★ · %s served" % [Game.prestige + 1, Game.total_stars(), UI.fmt(Game.served)])
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(0, minf(940.0, root.get_viewport_rect().size.y - 430.0))
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var list := UI.vbox(12)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list)
	v.add_child(sc)
	list.add_child(UI.label("GEAR", 24, UI.GOLD_LIGHT, UI.font_bold()))
	var cur: Dictionary = Game.tool()
	var nt := Game.next_upgrade("tool")
	if nt.is_empty():
		_row(list, TOOL_ICONS[cur.id], cur.name, cur.desc, "Best tool owned", _price_button(0, Callable(), "MAX"))
	elif not Game.built.has("shop"):
		_row(list, TOOL_ICONS[cur.id], cur.name, cur.desc, "Next: %s · build the %s" % [nt.name, String(Game.build_def("shop").name).to_lower()], _price_button(0, Callable(), "LOCKED"))
	else:
		_row(list, TOOL_ICONS[nt.id], nt.name, nt.desc, "Now: " + String(cur.name), _price_button(int(nt.cost), func(): Game.buy_upgrade("tool")))
	for t in [["bag", "bag", "Backpack", "Carry more logs per trip", func(d): return "%d logs" % int(d.cap)],
			["boots", "boots", "Trail boots", "Run faster", func(d): return "+%d%% speed" % int(round((float(d.mult) - 1.0) * 100))]]:
		var key: String = t[0]
		var nx := Game.next_upgrade(key)
		var cd: Dictionary = Game.cfg[key][Game.levels[key]]
		var fmtf: Callable = t[4]
		if nx.is_empty():
			_row(list, t[1], t[2], t[3], fmtf.call(cd) + "  (max)", _price_button(0, Callable(), "MAX"))
		else:
			_row(list, t[1], t[2], t[3], fmtf.call(cd) + "  →  " + fmtf.call(nx), _price_button(int(nx.cost), func(): Game.buy_upgrade(key)))
	if not ClassDB.class_exists("Wardrobe") and not ResourceLoader.exists("res://scripts/core/wardrobe.gd"):
		return
	list.add_child(UI.label("WARDROBE", 24, UI.GOLD_LIGHT, UI.font_bold()))
	var tabs := UI.hbox(10)
	for slot in ["shirt", "hat", "pants"]:
		var tb := UI.button(slot.to_upper(), "gold" if slot == _wardrobe_slot else "dark", "", 24, 140)
		var ss: String = slot
		tb.pressed.connect(func():
			_wardrobe_slot = ss
			_rebuild_modal())
		tabs.add_child(tb)
	list.add_child(tabs)
	var W = load("res://scripts/core/wardrobe.gd")
	for it in W.items_for(_wardrobe_slot):
		var id := String(it.id)
		var sw := ColorRect.new()
		var c: Array = it.get("color", [0.5, 0.5, 0.5])
		sw.color = Color(float(c[0]), float(c[1]), float(c[2]))
		sw.custom_minimum_size = Vector2(54, 54)
		var b: UIShape
		var stat := ""
		if W.equipped(_wardrobe_slot) == id:
			b = _price_button(0, Callable(), "WEARING")
		elif W.owned(id):
			b = UI.button("WEAR", "green", "", 26, 150)
			b.pressed.connect(func():
				W.equip(id)
				Sfx.play("pop")
				_rebuild_modal())
		else:
			var why: String = W.can_buy(id)
			var price := int(it.get("price", 0))
			stat = ("Needs %d ★  ·  " % int(it.stars) if int(it.get("stars", 0)) > 0 else "") + (UI.cash(price) if price > 0 else "Free")
			if why != "" and why.begins_with("Need") and why.contains("★"):
				b = _price_button(0, Callable(), "%d ★" % int(it.stars))
			else:
				b = UI.button(UI.cash(price) if price > 0 else "GET", "gold", "", 26, 150)
				b.disabled = why != ""
				b.pressed.connect(func():
					if W.buy(id):
						Sfx.play("cash")
						_rebuild_modal()
					else:
						show_toast(W.can_buy(id)))
		var r := UIShape.new("dark", 20.0, Vector4(14, 10, 14, 10))
		var h := UI.hbox(14)
		h.alignment = BoxContainer.ALIGNMENT_BEGIN
		h.add_child(sw)
		var tv := UI.vbox(2)
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tv.add_child(UI.label(String(it.name), 28, Color.WHITE, UI.font_bold()))
		if stat != "":
			tv.add_child(UI.label(stat, 20, UI.MUTED))
		h.add_child(tv)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(b)
		r.add_child(h)
		list.add_child(r)


# ------------------------------------------------------------------ settings, how to play, stats

func _toggle(v: VBoxContainer, icon_name: String, text: String, on: bool, cb: Callable) -> void:
	var r := UIShape.new("dark", 20.0, Vector4(14, 8, 14, 8))
	var h := UI.hbox(14)
	h.alignment = BoxContainer.ALIGNMENT_BEGIN
	h.add_child(_icon_or(icon_name, "settings", 44))
	var l := UI.label(text, 28, Color.WHITE, UI.font_ui(600))
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	var b := UI.button("ON" if on else "OFF", "green" if on else "dark", "", 26, 120)
	b.pressed.connect(func():
		cb.call()
		Game.save_game()
		Sfx.play("click")
		_rebuild_modal())
	h.add_child(b)
	r.add_child(h)
	v.add_child(r)


func _settings(v: VBoxContainer) -> void:
	_header(v, "settings", "Settings")
	_toggle(v, "sound", "Sound effects", not Game.mute, func():
		Game.mute = not Game.mute
		AudioServer.set_bus_mute(0, Game.mute)
		Sfx.saw(false))
	_toggle(v, "vibrate", "Vibration", Game.settings.get("vibration", true), func(): Game.settings.vibration = not Game.settings.get("vibration", true))
	_toggle(v, "book", "Story cards", Game.settings.get("story", true), func(): Game.settings.story = not Game.settings.get("story", true))
	_toggle(v, "stats", "Show FPS", Game.settings.get("show_fps", false), func(): Game.settings.show_fps = not Game.settings.get("show_fps", false))
	if OS.has_feature("mobile") or OS.get_cmdline_user_args().has("mobile"):
		var gq := UI.button("Graphics: " + String(Game.QUALITY_NAMES[Game.quality]) + (" (auto)" if Game.quality_auto else ""), "dark", "", 28)
		gq.pressed.connect(func():
			Game.quality = (Game.quality + 2) % 3
			Game.quality_auto = false
			Game.save_game()
			get_tree().current_scene.apply_quality()
			_rebuild_modal())
		v.add_child(gq)
	var row := UI.hbox(10)
	for it in [["How to play", "info", "howto"], ["Stats", "stats", "stats"], ["Story", "book", "replay"]]:
		var b := UI.button(it[0], "dark", "", 24, 0)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var kind: String = it[2]
		b.pressed.connect(func():
			if kind == "replay":
				close_modal()
				_replay_story()
			else:
				open_modal(kind))
		row.add_child(b)
	v.add_child(row)
	var rs := UI.button("Tap again to erase everything" if _confirm_reset else "Reset progress", "red", "", 26)
	rs.pressed.connect(func():
		if _confirm_reset:
			Game.reset_all()
		else:
			_confirm_reset = true
			_rebuild_modal())
	v.add_child(rs)
	var cr := UI.label("Axe to Empire v%s · BigoSoft\nMusic-free build · Fonts: Inter, Barlow Condensed (OFL)" % str(ProjectSettings.get_setting("application/config/version")), 18, UI.MUTED, null, HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(cr)


func _replay_story() -> void:
	var ch: Dictionary = Game.story_data.chapters.get(String(Game.chapter().id), {})
	var beats: Array = []
	for b in ch.get("beats", []):
		if b.on == "start" or Game.seen.has(b.on + ":1") or Game.seen.keys().any(func(k): return String(k).begins_with(String(b.on) + ":")):
			beats.append(b)
	_story_q.append_array(beats)
	_next_story()


func _howto(v: VBoxContainer) -> void:
	_header(v, "info", "How to play")
	for line in [
		["axe", "Stand next to a tree to chop. Logs stack on your back."],
		["log", "Drop logs on the woodpile; the kitchen cooks with them. Sell extra logs at the truck."],
		["dish", "Carry dishes from the rack to the counter. Guests pay; collect the cash pile."],
		["smile", "Serve fast: happy guests pay +20%, guests you serve in person pay +25%. Slow service and they walk out."],
		["upgrade", "UPGRADE levels the kitchen, menu, dining and signboard up to Lv 25. Big levels take time to build."],
		["crew", "Hire crew to keep things running while you're away. They're slower than you, so the empire grows fastest when you play."],
		["bigday", "Build everything, then start the Big Day at the gate to unlock the next place."],
		["trophy", "Earn 3 stars per place for permanent income bonuses."],
	]:
		var h := UI.hbox(14)
		h.alignment = BoxContainer.ALIGNMENT_BEGIN
		h.add_child(_icon_or(line[0], "star", 48))
		var l := UI.label(line[1], 22, Color.WHITE)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 520
		h.add_child(l)
		v.add_child(h)


func _stats(v: VBoxContainer) -> void:
	_header(v, "stats", "Your Stats")
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	var mins := int(Game.stats.play_s / 60.0)
	for s in [["Cash earned", UI.cash(Game.stats.earned)], ["Guests served", UI.fmt(Game.stats.served)],
			["Trees felled", UI.fmt(Game.stats.trees)], ["Golden trees", str(int(Game.stats.get("golden", 0)))],
			["Walkouts", str(int(Game.stats.get("walkouts", 0)))], ["Lost to full lines", str(int(Game.stats.get("lost", 0)))],
			["Big Days won", str(int(Game.stats.get("bigdays", 0)))], ["Stars", "%d / %d" % [Game.total_stars(), Game.chapters.size() * 3]],
			["Logs sold", UI.fmt(Game.stats.sold)], ["Time played", "%dh %02dm" % [mins / 60, mins % 60]]]:
		var c := UIShape.new("dark", 18.0, Vector4(16, 10, 16, 10))
		c.custom_minimum_size.x = 288
		var cv := UI.vbox(0)
		cv.add_child(UI.label(s[0], 19, UI.MUTED))
		cv.add_child(UI.num(s[1], 38, UI.GOLD_LIGHT))
		c.add_child(cv)
		grid.add_child(c)
	v.add_child(grid)
