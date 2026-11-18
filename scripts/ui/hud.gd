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
var _confirm_prestige := false
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
var _story_q: Array = []          # story cards waiting (consecutive lines by one speaker are one card)
var _story_showing := false
var _story_replay := false        # Settings > Story: show the whole chapter back to back
var _story_last_s := -1000.0      # _play_s when the last story card closed
var _play_s := 0.0                # seconds of play since this HUD was built
var _ui_tap_ms := -100000         # last touch/click anywhere: no story card pops right under a finger
const STORY_GAP_S := 45.0         # at most one story card per this much play
const STORY_TAP_GUARD_MS := 500
var _bd_result: Array = []
var till_chip: UIShape            # "$12.3K waiting at Forest Camp": opens the map
var till_label: Label
var till_k := -1                  # place the chip points at (-1: nothing waiting)
var _till_dirty := true
var _till_venue := -1
var _toast_holder: Control


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
	_build_till_chip()
	Game.tills_changed.connect(func(): _till_dirty = true)
	Game.state_changed.connect(func(): _till_dirty = true)
	Game.story.connect(_on_story)
	Game.task_changed.connect(_refresh_task)
	Game.offline_ready.connect(func():
		if modal_kind == "":
			open_modal("offline"))
	world.big_day_finished.connect(func(won, served, goal):
		_bd_result = [won, served, goal]
		open_modal("bigday_result"))
	Game.coins_changed.connect(func(_v): _on_coins_for_modal())
	Game.rating_changed.connect(func(_v): _refresh_top())
	Game.state_changed.connect(_refresh_modal_soft)
	Game.jobs_changed.connect(_refresh_jobs_badge)
	Game.toast.connect(show_toast)
	world.zone_entered.connect(_on_zone_entered)
	world.zone_exited.connect(_on_zone_exited)
	_coin_shown = Game.coins
	if OS.is_debug_build():
		fps_label = UI.label("", 18, Color(1, 1, 1, 0.7))
		fps_label.position = Vector2(24, root.get_viewport_rect().size.y - 96)
		root.add_child(fps_label)
	_refresh_top()
	_refresh_task()
	_refresh_jobs_badge()
	if Game.offline_reward > 0:
		open_modal.call_deferred("offline")
	elif Game.chapter_done:
		pass


func _side_button_at(p: Vector2) -> UIShape:
	for holder in jobs_btn.get_parent().get_parent().get_children():
		for c in [holder] + holder.get_children():
			if c is UIShape and c.is_visible_in_tree() and c.get_global_rect().has_point(p):
				return c
	return null


func _ui_hit(p: Vector2) -> bool:
	if modal != null:
		return true
	for c in jobs_btn.get_parent().get_parent().get_children() + [task_btn, task_card, reno_chip, till_chip]:
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
	map_btn = _round_button("gate", "MAP", func():
		if world.bd_active:
			show_toast("Finish the Big Day first!")
		else:
			open_modal("empire"))
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
	var c := Control.new()          # plain holder; the box is centred by hand so long text can't push it off-screen
	c.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	c.position.y = _safe_top() + 330
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(c)
	_toast_holder = c
	toast_box = UIShape.new("gold", 24.0, Vector4(26, 12, 26, 12))
	toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_label = UI.label("", 30, UI.INK, UI.font_bold(), HORIZONTAL_ALIGNMENT_CENTER)
	toast_box.add_child(toast_label)
	c.add_child(toast_box)
	toast_box.modulate.a = 0.0


## Width of the HUD in UI pixels (what anchors and positions use).
func _vw() -> float:
	return get_viewport().get_visible_rect().size.x


func show_toast(text: String) -> void:
	_toast_q.append(text)


func _process(delta: float) -> void:
	_play_s += delta
	# animated coin counter
	var target := float(Game.coins)
	if absf(_coin_shown - target) > 0.5:
		_coin_shown = lerpf(_coin_shown, target, clampf(delta * 10.0, 0.0, 1.0))
		if absf(_coin_shown - target) < 1.0:
			_coin_shown = target
	coin_label.text = UI.cash(round(_coin_shown))
	served_label.text = UI.fmt(Game.served)
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
		UI.fit(goal_label, _vw() - 140.0, 28, 20)
		goal_pill.reset_size()
		goal_pill.visible = g != ""
		goal_pill.scale = Vector2(1.08, 1.08)
		goal_pill.create_tween().tween_property(goal_pill, "scale", Vector2.ONE, 0.25)
	# a lost touch release (app paused mid-tap) must not freeze modal refreshes
	if _fingers > 0 and Time.get_ticks_msec() - _finger_ms > 4000:
		_fingers = 0
		if _rebuild_pending and modal:
			_rebuild_pending = false
			_rebuild_modal_now()
	# toasts
	_toast_t -= delta
	if _toast_t <= 0.0 and not _toast_q.is_empty():
		toast_label.text = _toast_q.pop_front()
		UI.fit(toast_label, _vw() - 300.0, 30, 24)   # clear of the side buttons
		UI.balance(toast_label)                       # no lone last word on its own line
		toast_box.size = Vector2.ZERO
		toast_box.size = toast_box.get_combined_minimum_size()
		toast_box.position = Vector2((_vw() - toast_box.size.x) * 0.5, 0.0)
		# below the left column (task card, renovation chip, cash-waiting chip) so it never hides them
		var ty := _safe_top() + 330.0
		for ch in [task_card, reno_chip, till_chip]:
			if ch and ch.visible:
				ty = maxf(ty, ch.position.y + ch.size.y + 12.0)
		_toast_holder.position.y = ty
		toast_box.pivot_offset = toast_box.size * 0.5
		_toast_t = 2.2 + 0.03 * maxf(0.0, toast_label.text.length() - 30.0)
		var tw := create_tween()
		toast_box.modulate.a = 0.0
		toast_box.scale = Vector2(0.8, 0.8)
		tw.tween_property(toast_box, "modulate:a", 1.0, 0.15)
		tw.parallel().tween_property(toast_box, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_interval(_toast_t - 0.6)
		tw.tween_property(toast_box, "modulate:a", 0.0, 0.3)


func _refresh_top() -> void:
	rating_label.text = "%.1f" % Game.rating()


func _refresh_jobs_badge() -> void:
	var n := Game.jobs_claimable()
	var badge: Control = jobs_btn.get_parent().get_node("Badge")
	badge.visible = n > 0
	jobs_badge.text = str(n)
	if modal_kind == "jobs":
		_safe_rebuild()


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
	if kind == "jobs":
		Game.refresh_jobs()             # roll over to today's jobs if the day changed
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
	_modal_opened_ms = Time.get_ticks_msec()
	_dim_down = false
	dim.gui_input.connect(func(e):
		if kind in ["offline", "complete", "empire", "story", "bigday_result"]:
			return
		var is_press: bool = (e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT) or (e is InputEventScreenTouch and e.index >= 1)
		if not is_press:
			return
		if e.pressed:
			_dim_down = Time.get_ticks_msec() - _modal_opened_ms > 300
		elif _dim_down:
			_dim_down = false
			var hit := _side_button_at(dim.get_global_transform() * e.position)
			if hit:
				close_modal()
				hit.pressed.emit()
			else:
				_close_or_back())
	modal.add_child(dim)
	_rebuild_queued = false
	_rebuild_modal_now()
	modal.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(modal, "modulate:a", 1.0, 0.15)
	Sfx.play("pop", -10.0, 1.3)


func close_modal() -> void:
	if modal:
		var m := modal
		m.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for cc in m.find_children("*", "Control", true, false):
			cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var tw := create_tween()
		tw.tween_property(m, "modulate:a", 0.0, 0.12)
		tw.tween_callback(m.queue_free)
	modal = null
	modal_kind = ""
	joy.blocked = false
	_confirm_reset = false
	_confirm_prestige = false
	if _story_q.is_empty():
		_story_replay = false
	if not _story_q.is_empty():
		_next_story.call_deferred()
	elif Game.offline_reward > 0:
		(func(): if modal_kind == "" and Game.offline_reward > 0: open_modal("offline")).call_deferred()


func _refresh_modal_soft() -> void:
	if modal_kind in ["shop", "crew", "gate", "upgrades", "character", "bigday_result"]:
		_safe_rebuild()


## Rebuilding frees the buttons, so never do it while a finger is down (the tap would be lost).
func _safe_rebuild() -> void:
	if _fingers > 0:
		_rebuild_pending = true
	else:
		_rebuild_modal_now()


## Cash changes many times a second: only flip price buttons on/off, no rebuild.
func _on_coins_for_modal() -> void:
	for pb in _price_btns:
		if is_instance_valid(pb[0]):
			pb[0].disabled = Game.coins < int(pb[1])
	if modal_kind == "gate" and Time.get_ticks_msec() - _gate_refresh_ms > 1000:
		_gate_refresh_ms = Time.get_ticks_msec()
		_safe_rebuild()


var _fingers := 0
var _finger_ms := 0
var _rebuild_pending := false
var _price_btns: Array = []
var _gate_refresh_ms := 0
var _modal_opened_ms := 0
var _dim_down := false


func _input(e: InputEvent) -> void:
	if e is InputEventScreenTouch or (e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT):
		_ui_tap_ms = Time.get_ticks_msec()
	if e is InputEventScreenTouch:
		_fingers = maxi(0, _fingers + (1 if e.pressed else -1))
		_finger_ms = Time.get_ticks_msec()
		if not e.pressed and _fingers == 0 and _rebuild_pending:
			_rebuild_pending = false
			(func(): if modal: _rebuild_modal_now()).call_deferred()    # after the button has seen the release


var _rebuild_queued := false


## Rebuild the open modal at the end of this frame. Button handlers call this, so the button that
## is still emitting `pressed` is never freed under its own signal.
func _rebuild_modal() -> void:
	if _rebuild_queued:
		return
	_rebuild_queued = true
	_rebuild_modal_now.call_deferred()


func _rebuild_modal_now() -> void:
	_rebuild_queued = false
	if modal == null:
		return
	var old := modal.get_node_or_null("Card")
	var scroll := -1
	if old:
		var sc: Array = old.find_children("*", "ScrollContainer", true, false)
		if not sc.is_empty():
			scroll = sc[0].scroll_vertical
		old.free()
	_price_btns.clear()
	if scroll > 0:
		_restore_scroll.call_deferred(scroll)
	var center := CenterContainer.new()
	center.name = "Card"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	modal.add_child(center)
	var card := UIShape.new("glass_strong", 30.0, Vector4(26, 24, 26, 28))
	card.custom_minimum_size.x = minf(660.0, root.get_viewport_rect().size.x - 36.0)
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	card.clip_contents = false
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
	var tl := UI.label(title, 46, Color.WHITE, UI.font_bold())
	tv.add_child(tl)
	if sub != "":
		var sl := UI.label(sub, 22, UI.MUTED)
		sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sl.custom_minimum_size.x = 120
		tv.add_child(sl)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(tv)
	if closable:
		var x := UIShape.new("dark", 22.0, Vector4(16, 6, 16, 6)).make_clickable()
		x.add_child(UI.label("✕", 30, Color.WHITE, UI.font_ui(600), HORIZONTAL_ALIGNMENT_CENTER))
		x.custom_minimum_size = Vector2(84, 84)
		x.pressed.connect(_close_or_back)
		h.add_child(x)
	v.add_child(h)


## ✕ on a Settings sub-screen (How to play, Stats) goes back to Settings; elsewhere it closes.
func _close_or_back() -> void:
	if modal_kind in ["howto", "stats"]:
		open_modal("settings")
	else:
		close_modal()


func _row(v: VBoxContainer, icon_name: String, title: String, desc: String, stat: String, btn: UIShape, extra: Control = null) -> void:
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
	if extra:
		tv.add_child(extra)
	h.add_child(tv)
	if btn:
		btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(btn)
	r.add_child(h)
	v.add_child(r)


## A scroll area only as tall as what it holds (no empty half-card), up to `cap`.
func _fit_scroll(sc: ScrollContainer, cap: float) -> void:
	if not is_instance_valid(sc) or sc.get_child_count() == 0:
		return
	var h: float = (sc.get_child(0) as Control).get_combined_minimum_size().y
	sc.custom_minimum_size.y = minf(cap, h + 4.0)
	# wrapped labels only know their real height once laid out at the card's width: measure again
	await get_tree().process_frame
	if is_instance_valid(sc) and sc.get_child_count() > 0:
		h = (sc.get_child(0) as Control).get_combined_minimum_size().y
		sc.custom_minimum_size.y = minf(cap, h + 4.0)


func _restore_scroll(v: int) -> void:
	if modal == null:
		return
	var card := modal.get_node_or_null("Card")
	if card:
		var sc: Array = card.find_children("*", "ScrollContainer", true, false)
		if not sc.is_empty():
			await get_tree().process_frame
			if is_instance_valid(sc[0]):
				sc[0].scroll_vertical = v


func _price_button(cost: int, cb: Callable, label_override := "") -> UIShape:
	var b: UIShape
	if label_override != "":
		b = UI.button(label_override, "dark", "", 28, 150)
		b.disabled = true
		return b
	b = UI.button(UI.cash(cost), "gold", "", 30, 150)
	b.disabled = Game.coins < cost
	_price_btns.append([b, cost])
	b.pressed.connect(func():
		if Game.coins >= cost:
			cb.call()
			Sfx.play("build", -6.0, 1.2)
			world.fx_burst(world.player.global_position + Vector3.UP * 1.5, Color(1, 0.85, 0.4), 24)
		else:
			show_toast("Not enough cash"))
	return b


# ------------------------------------------------------------------ panels

## The star rules, worded once (game_state.gd _stars_of is the truth).
const STAR3_HOW := "Star 3: win the Big Day with no walkouts and get every station to Lv 15+"
const STAR_RULES := "Star 1: win the Big Day.  Star 2: serve twice the gate's guests with a 4.5★ rating.  " + STAR3_HOW + ".  Each star: +4% income everywhere."

const TOOL_ICONS := {"axe": "axe", "double_axe": "double_axe", "chainsaw": "chainsaw", "harvester": "harvester"}


func _shop(v: VBoxContainer) -> void:
	_header(v, "hammer", "Tool Shed", "Upgrades apply instantly")
	_gear_rows(v, true)
	var ub := UI.button("KITCHEN, MENU & STATION UPGRADES", "dark", "upgrade", 24)
	ub.pressed.connect(func(): open_modal("upgrades"))
	v.add_child(ub)


## Tool, backpack and boots rows (normal levels, then Pro levels, then MAX). The shop and the ME screen share
## these so both always show the same thing. Away from the shed (`at_shop` false) the next tool needs the shed built.
func _gear_rows(v: VBoxContainer, at_shop: bool) -> void:
	var cur: Dictionary = Game.tool()
	var nt := Game.next_upgrade("tool")
	var tp: int = Game.pro.tool
	var tname: String = String(cur.name) + (" Pro %d" % tp if tp > 0 else "")
	if nt.is_empty():
		_row(v, TOOL_ICONS[cur.id], tname, cur.desc, "Best tool, fully tuned", _price_button(0, Callable(), "MAX"))
	elif not at_shop and not Game.built.has("shop"):
		var nname: String = (String(cur.name) + " Pro %d" % int(nt.pro)) if nt.has("pro") else String(nt.name)
		_row(v, TOOL_ICONS[cur.id], tname, cur.desc, "Next: %s · build the %s" % [nname, String(Game.build_def("shop").name).to_lower()], _price_button(0, Callable(), "LOCKED"))
	elif nt.has("pro"):
		_row(v, TOOL_ICONS[cur.id], String(cur.name) + " Pro %d" % int(nt.pro), "Tune your tool: +10% chop speed",
			"+%d%% speed  →  +%d%%" % [10 * tp, 10 * int(nt.pro)], _price_button(int(nt.cost), func(): Game.buy_upgrade("tool")))
	else:
		_row(v, TOOL_ICONS[nt.id], nt.name, nt.desc, "Now: " + String(cur.name), _price_button(int(nt.cost), func(): Game.buy_upgrade("tool")))
	var tracks := [
		["bag", "bag", "Backpack", "Carry more logs per trip", func(d): return "%d logs" % int(d.cap)],
		["boots", "boots", "Trail boots", "Run faster", func(d): return "+%d%% speed" % int(round((float(d.mult) - 1.0) * 100))],
	]
	var pro_txt := {"bag": func(n): return "%d logs" % (int(Game.cfg.bag[Game.cfg.bag.size() - 1].cap) + 6 * n),
		"boots": func(n): return "+%d%% speed" % int(round((float(Game.cfg.boots[Game.cfg.boots.size() - 1].mult) - 1.0 + 0.04 * n) * 100))}
	for t in tracks:
		var key: String = t[0]
		var arr: Array = Game.cfg[key]
		var cur_d: Dictionary = arr[Game.levels[key]]
		var nx := Game.next_upgrade(key)
		var fmtf: Callable = t[4]
		var pn: int = Game.pro[key]
		if nx.is_empty():
			_row(v, t[1], t[2] + " Pro %d" % pn, t[3], pro_txt[key].call(pn) + "  (max)", _price_button(0, Callable(), "MAX"))
		elif nx.has("pro"):
			_row(v, t[1], t[2] + " Pro %d" % int(nx.pro), t[3], pro_txt[key].call(pn) + "  →  " + pro_txt[key].call(int(nx.pro)),
				_price_button(int(nx.cost), func(): Game.buy_upgrade(key)))
		else:
			_row(v, t[1], t[2], t[3], fmtf.call(cur_d) + "  →  " + fmtf.call(nx),
				_price_button(int(nx.cost), func(): Game.buy_upgrade(key)))


func _crew(v: VBoxContainer) -> void:
	_header(v, "crew", "Hire Crew", "They work while you play")
	for role in ["lumberjack", "waiter", "cook"]:
		var c: Dictionary = Game.cfg.crew[role]
		var have: int = Game.crew[role]
		var cost := Game.crew_next_cost(role)
		var btn := _price_button(cost, func(): Game.hire(role)) if cost >= 0 else _price_button(0, Callable(), "FULL")
		_row(v, role, c.name, c.desc, "Hired %d / %d" % [have, int(c.max)], btn)
	var rate := Game.passive_rate()
	var note := ("Crew income: %s / min while you play. When you're next door, it waits on this counter." % UI.cash(rate * 60.0)) if rate > 0 else "Hire a lumberjack and a waiter. They keep this place earning while you play, even when you're next door."
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
		pr.add_child(UI.label("%s/%s" % [UI.fmt(j.prog), UI.fmt(j.goal)], 20, UI.MUTED))
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
	_header(v, "clock", "Welcome back", "", false)
	var wl := UI.label("Here's your cash, ready to collect.", 24, UI.MUTED, null, HORIZONTAL_ALIGNMENT_CENTER)
	wl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(wl)
	var amt := UI.hbox(12)
	amt.add_child(UI.icon("coin", 84))
	amt.add_child(UI.num(UI.cash(Game.offline_reward), 84, UI.CASH))
	v.add_child(amt)
	var al := UI.label("Your places earn while you play. Each one's cash waits on its own counter until you come by.", 20, UI.MUTED, null, HORIZONTAL_ALIGNMENT_CENTER)
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
		_header(v, "star", "Complete the Empire", "Finish every place, then start a New Empire with +50% income")
	else:
		_header(v, "gate", String(nx.name), "The land next door: " + String(nx.tagline).to_lower())
	var g: Dictionary = Game.cfg.gate
	var s := Game.gate_status()
	var need_built: Array = ["tables_2", "crew_hut"] + (["special"] if Game.special_type() != "" else [])
	var reqs := [
		[s.built, "Build every upgrade here", "%d / %d" % [need_built.filter(func(id): return Game.built.has(id)).size(), need_built.size()]],
		[s.served, "Serve %s guests" % UI.fmt(int(g.served)), "%s / %s" % [UI.fmt(mini(Game.vserved, int(g.served))), UI.fmt(int(g.served))]],
		[s.rating, "Keep a %.1f★ rating" % float(g.rating), "%.1f now" % Game.rating()],
		[s.coins, "Save %s (you keep it)" % UI.cash(int(g.coins)), "%s / %s" % [UI.cash(mini(Game.coins, int(g.coins))), UI.cash(int(g.coins))]],
		[s.bigday, "Win the Big Day: " + String(Game.big_day_def().get("name", "")), "WON" if s.bigday else ("ready" if s.built else "build first")],
	]
	for r in reqs:
		var row := UIShape.new("dark", 20.0, Vector4(14, 10, 16, 10))
		var h := UI.hbox(14)
		h.alignment = BoxContainer.ALIGNMENT_BEGIN
		h.add_child(UI.icon("check" if r[0] else ("bigday" if r[2] == "ready" else "lock"), 46))
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
Serve %d guests in %d:%02d. More than %d walkouts and it's over. %s" % [String(bdd.name), String(bdd.desc), int(bdd.goal), int(bdd.seconds) / 60, int(bdd.seconds) % 60, int(bdd.get("max_walkouts", 10)), STAR3_HOW + "." if replay else "Tip: fill the woodpile and the rack first!"], 22, UI.GOLD_LIGHT, null, HORIZONTAL_ALIGNMENT_CENTER)
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
	if Game.chapter_done:
		# road already open: send the player on (or to the New Empire screen in the last chapter)
		var go := UI.button("START A NEW EMPIRE" if last else "GO TO " + String(nx.name).to_upper(), "green", "gate", 30)
		go.pressed.connect(func():
			if last:
				open_modal("complete")
			else:
				close_modal()
				get_tree().current_scene.travel_to(Game.venue + 1))
		v.add_child(go)
		return
	if not last:
		var gl := UI.label("Open it to expand next door. %s keeps working while you play there." % String(Game.chapter().name), 21, UI.MUTED, null, HORIZONTAL_ALIGNMENT_CENTER)
		gl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(gl)
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
	var nstars := Game.star_count()
	_header(v, "star", "Chapter %d complete!" % (Game.venue + 1), String(ch.name) + (" · mastered" if nstars >= 3 else ""), false)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	var mins := int(Game.stats.play_s / 60.0)
	for s in [["Guests served here", UI.fmt(Game.vserved)], ["Stars here", "%d / 3" % nstars],
			["Cash earned (all)", UI.cash(Game.stats.earned)], ["Time played (all)", "%dh %02dm" % [mins / 60, mins % 60]]]:
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
		txt = "You bought the land next door: %s, %s. New there: the %s. Your %s comes with you. %s keeps working while you play, and its cash waits on its counter." % [nx.name, String(nx.tagline).to_lower(), String(nx.get("special", {}).get("name", "")).to_lower(), UI.cash(Game.coins), String(ch.name)]
	var l := UI.label(txt, 22, UI.MUTED, null, HORIZONTAL_ALIGNMENT_CENTER)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(l)
	if nstars < 3 and not _confirm_prestige:
		var sl := UI.label(STAR_RULES, 19, UI.GOLD_LIGHT, null, HORIZONTAL_ALIGNMENT_CENTER)
		sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(sl)
	if last and not _confirm_prestige:
		var pb := UI.button("START NEW EMPIRE  (+50%)", "green", "star", 30)
		pb.pressed.connect(func():
			_confirm_prestige = true
			_rebuild_modal())
		v.add_child(pb)
	elif last:
		var warn := UI.label("This erases every place you own, with its buildings, crew and cash. You keep your outfits and the +50% bonus. Are you sure?", 22, UI.RED, null, HORIZONTAL_ALIGNMENT_CENTER)
		warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(warn)
		var rr := UI.hbox(12)
		var keep := UI.button("Keep playing", "green", "", 26)
		keep.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		keep.pressed.connect(func():
			_confirm_prestige = false
			_rebuild_modal())
		var go := UI.button("Start over", "red", "", 26)
		go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		go.pressed.connect(func():
			_confirm_prestige = false
			Game.start_new_empire()
			close_modal()
			get_tree().current_scene.reload_venue())
		rr.add_child(keep)
		rr.add_child(go)
		v.add_child(rr)
	else:
		var tb := UI.button("GO NEXT DOOR", "green", "gate", 34)
		tb.pressed.connect(func():
			close_modal()
			get_tree().current_scene.travel_to(Game.venue + 1))
		v.add_child(tb)
	if _confirm_prestige:
		return                 # "Keep playing" / "Start over" are the only choices while confirming
	var b := UI.button("STAY HERE", "dark", "", 28)
	b.pressed.connect(close_modal)
	v.add_child(b)


## Empire map: every place on the road, the cash waiting on its counter, what it earns, and fast travel.
func _empire(v: VBoxContainer) -> void:
	_map_tills.clear()
	var er := Game.empire_rate() * 60.0
	var waiting := Game.tills_waiting()
	var sub: String
	if waiting > 0:
		sub = "%s waiting on your counters. Go there to collect it." % UI.cash(waiting)
	elif er > 0:
		sub = "Your other places: earns %s while you play" % _per_min(er)
	else:
		sub = "Your places keep working while you play"
	_header(v, "gate", "Your Empire", sub)
	var sc := ScrollContainer.new()
	var cap := minf(1000.0, root.get_viewport_rect().size.y - 500.0)
	sc.custom_minimum_size = Vector2(0, cap)
	_fit_scroll.call_deferred(sc, cap)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var list := UI.vbox(12)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list)
	v.add_child(sc)
	for k in Game.chapters.size():
		var ch: Dictionary = Game.chapters[k]
		var btn: UIShape
		var stat: String
		var extra: Control = null
		if k == Game.venue:
			btn = _price_button(0, Callable(), "HERE")
			var pr := Game.passive_rate() * 60.0
			stat = ("You are here · earns %s while you play" % _per_min(pr)) if pr > 0 else "You are here · hire crew to earn"
		elif k < Game.unlocked:
			btn = UI.button("TRAVEL", "green", "", 28, 150)
			var kk := k
			btn.pressed.connect(func():
				close_modal()
				get_tree().current_scene.travel_to(kk))
			var r := Game.venue_rate(k) * 60.0 * Game.VENUE_EFFICIENCY
			stat = ("Earns %s while you play" % _per_min(r)) if r > 0 else "Hire crew there to earn"
			if r > 0 or Game.till(k) > 0:      # no crew and nothing waiting: no empty $0 meter
				extra = _till_meter(k)
		else:
			btn = _price_button(0, Callable(), "LOCKED")
			stat = "The land next door: open it at %s's gate" % String(Game.chapters[k - 1].name) if k == Game.unlocked \
				else "Further down the road"
		var desc := String(ch.tagline)
		if ch.has("special"):
			desc += " · New: " + String(ch.special.name)
		if k < Game.unlocked:
			var st: Array = Game.stars(k)
			stat += "   " + "".join(st.map(func(x): return "★" if x else "☆"))
		_row(list, "lock" if k >= Game.unlocked else "star", "%d. %s" % [k + 1, ch.name], desc, stat, btn, extra)
	if Game.prestige > 0:
		v.add_child(UI.label("Empire %d · income x%.1f" % [Game.prestige + 1, Game.income_mult()], 22, UI.GOLD_LIGHT, null, HORIZONTAL_ALIGNMENT_CENTER))
	var cb := UI.button("CLOSE", "dark", "", 28)
	cb.pressed.connect(close_modal)
	v.add_child(cb)


var _map_tills: Array = []          # [k, Label, ProgressBar] of the open map, updated in place


## "$1,240 / $3,600" ("... · FULL" when the counter is full) with a fill bar: place k's counter and how much it holds.
func _till_meter(k: int) -> Control:
	var col := UI.vbox(4)
	col.name = "Till%d" % k
	var l := UI.label("", 21, UI.CASH, UI.font_ui(650))
	l.name = "TillText"
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 200
	col.add_child(l)
	var bar := UI.progress_bar(200, 10)
	var fg := StyleBoxFlat.new()
	fg.bg_color = UI.CASH
	fg.set_corner_radius_all(5)
	bar.add_theme_stylebox_override("fill", fg)
	col.add_child(bar)
	_map_tills.append([k, l, bar])
	_set_till_meter(k, l, bar)
	return col


func _set_till_meter(k: int, l: Label, bar: ProgressBar) -> void:
	var t := Game.till(k)
	var cap := Game.till_cap(k)
	l.text = ("%s / %s" % [UI.cash(t), UI.cash(cap)]) + (" · FULL" if t >= cap else "")
	bar.max_value = maxi(1, cap)
	bar.value = t


func _refresh_map_tills() -> void:
	for m in _map_tills:
		if is_instance_valid(m[1]):
			_set_till_meter(m[0], m[1], m[2])


## "$1,746/min" that never wraps between the amount and "/min" (word joiners).
func _per_min(per_min: float) -> String:
	return UI.cash(per_min) + "\u2060/\u2060min"


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
	task_btn = UI.button("", "green", "", 24, 130)
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
	reno_chip.custom_minimum_size.y = 64          # it's a button: keep it a full tap target
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
	task_prog.text = ("%s/%s" % [UI.fmt(p[0]), UI.fmt(p[1])]) if p[1] > 1 else ""
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
		bd_info.text = "Served %d / %d   ·   Walkouts %d / %d" % [world.bd_served, world.bd_goal(), world.bd_walkouts, world.bd_max_walkouts()]
		bd_bar.max_value = world.bd_goal()
		bd_bar.value = world.bd_served
	till_chip.visible = till_k >= 0 and not bd_on and modal_kind == ""
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
	if Game.venue != _till_venue:          # walked over to another place: its till is now the counter
		_till_venue = Game.venue
		_till_dirty = true
	if _till_dirty:
		_refresh_till_chip()
	_place_till_chip()
	if not _story_q.is_empty() and modal_kind == "":
		_next_story()


# ------------------------------------------------------------------ cash waiting at your other places

func _build_till_chip() -> void:
	till_chip = UIShape.new("glass", 22.0, Vector4(14, 8, 18, 8))
	till_chip.make_clickable()
	till_chip.name = "TillChip"
	till_chip.custom_minimum_size = Vector2(0, 66)
	till_chip.pressed.connect(func():
		if world.bd_active:
			return
		open_modal("empire"))
	var h := UI.hbox(10)
	h.alignment = BoxContainer.ALIGNMENT_BEGIN
	h.add_child(UI.icon("coin", 38))
	till_label = UI.label("", 24, UI.CASH, UI.font_ui(650))
	h.add_child(till_label)
	h.add_child(UI.label("›", 30, Color(1, 1, 1, 0.7), UI.font_bold()))
	till_chip.add_child(h)
	root.add_child(till_chip)
	till_chip.visible = false
	_refresh_till_chip()


## The place with the most cash on its counter (not the one you're at), or -1.
func _richest_till() -> int:
	var best := -1
	var amt := 0
	for k in Game.unlocked:
		if k == Game.venue:
			continue
		var t := Game.till(k)
		if t > amt:
			amt = t
			best = k
	return best


## Called on tills_changed / state_changed / arriving somewhere (batched to 4x a second), not every frame.
func _refresh_till_chip() -> void:
	_till_dirty = false
	if modal_kind == "empire":
		_refresh_map_tills()
	till_k = _richest_till() if Game.tills_waiting() > 0 else -1
	if till_k < 0:
		till_chip.visible = false
		return
	var txt := "%s waiting at %s" % [UI.cash(Game.till(till_k)), String(Game.chapters[till_k].name)]
	if till_label.text != txt:
		till_label.text = txt
		UI.fit(till_label, _till_max_w(), 24, 18)
		till_chip.size = Vector2.ZERO
		till_chip.reset_size()
	_place_till_chip()


## Room left of the side buttons (they sit 118 px in from the right edge).
func _till_max_w() -> float:
	# side column, left margin, gap, chip padding, coin icon, two gaps, the arrow
	return _vw() - 118.0 - 18.0 - 14.0 - 32.0 - 38.0 - 20.0 - 14.0


## Under the task card (and the renovation chip when it shows).
func _place_till_chip() -> void:
	var y := task_card.position.y + task_card.size.y + 10.0
	if reno_chip.visible:
		y = reno_chip.position.y + reno_chip.size.y + 10.0
	till_chip.position = Vector2(18, y)


func _clock(secs: int) -> String:
	if secs >= 3600:
		return "%dh %02dm" % [secs / 3600, (secs % 3600) / 60]
	return "%d:%02d" % [secs / 60, secs % 60]


# ------------------------------------------------------------------ Big Day banner

func _build_bd_banner() -> void:
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_TOP_WIDE)
	cc.position.y = _safe_top() + 156
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(cc)
	bd_banner = UIShape.new("gold", 24.0, Vector4(22, 10, 22, 12))
	bd_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := UI.vbox(4)
	bd_title = UI.label("", 30, UI.INK, UI.font_bold(), HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(bd_title)
	bd_bar = UI.progress_bar(380, 14)
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
	_header(v, "trophy" if won else "clock", ("Big Day won: %s" if won else "%s: not this time") % String(bdd.get("name", "Big Day")),
		"Served %d of %d" % [_bd_result[1], _bd_result[2]] if _bd_result.size() > 2 else "", false)
	var st: Array = Game.stars()
	var row := UI.hbox(18)
	for i in 3:
		var l := UI.label("★" if st[i] else "☆", 84, UI.GOLD_LIGHT if st[i] else UI.MUTED, UI.font_bold())
		row.add_child(l)
	v.add_child(row)
	var txt: String
	if won:
		txt = "Big Day won! You can buy the land next door: unlock it at the gate."
		if Game.is_last_chapter():
			txt = "The critic loved it. Finish the empire at the gate!"
		if not Game.stars()[2]:
			txt += " " + STAR3_HOW + "."
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
	_story_q.append_array(_merge_beats(beats))
	if modal_kind == "":
		_next_story.call_deferred()


## Lines in a row by the same speaker become one card.
func _merge_beats(beats: Array) -> Array:
	var out: Array = []
	for b in beats:
		if not out.is_empty() and String(out[-1].who) == String(b.who):
			var m: Dictionary = out[-1].duplicate()
			m.text = String(m.text) + "\n\n" + String(b.text)
			out[-1] = m
		else:
			out.append(b)
	return out


## Shows the next queued story card when it's a good moment: no modal, no finger down or just lifted,
## not walking, and at most one card per STORY_GAP_S of play. Polled from _tick_overlays, so a card
## that has to wait simply shows later.
func _next_story() -> void:
	if _story_q.is_empty() or modal_kind != "":
		return
	if not _story_replay:
		if joy.active or _fingers > 0 or Time.get_ticks_msec() - _ui_tap_ms < STORY_TAP_GUARD_MS:
			return
		if _play_s - _story_last_s < STORY_GAP_S:
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
	var more := _story_replay and _story_q.size() > 1
	var nb := UI.button("NEXT" if more else "OK", "gold", "", 30)
	nb.pressed.connect(func():
		_story_q.pop_front()
		if more:
			_rebuild_modal()
		else:
			_story_last_s = _play_s
			if _story_q.is_empty():
				_story_replay = false
			close_modal())
	v.add_child(nb)


# ------------------------------------------------------------------ station upgrades

const STATION_ICONS := {"fire": "fire", "menu": "menu", "dining": "smile", "sign": "sign", "station": "upgrade"}
const SPECIAL_ICONS := {"drive_thru": "truck", "raft": "log", "fireplace": "fire", "bell": "bigday", "van": "truck"}


func _station_effect(key: String, lv: int) -> String:
	match key:
		"fire": return "%.1fs per dish" % Game.kitchen_cook(Game.cfg, lv)
		"menu": return "%s a dish" % UI.cash(roundf(Game.menu_price(Game.cfg, lv) * Game.sign_price() * Game.income_mult() * Game.star_mult()))
		"dining": return ("+%d%% patience, " % (3 * lv) if lv > 0 else "") + "%d%% tips" % int(round((float(Game.cfg.customers.seated_tip) + 0.03 * lv) * 100))
		"sign": return "+%d%% guests, +%d%% price" % [4 * lv, 2 * lv] if lv > 0 else "Base guests and price"
		"station": return ("+%d%% station pay" % (4 * lv) if lv > 0 else "Base pay") + (" · crew helps" if lv >= 4 else "")
	return ""


func _upgrades(v: VBoxContainer) -> void:
	var st: Array = Game.stars()
	_header(v, "upgrade", "Upgrades", String(Game.chapter().name) + "   " + "".join(st.map(func(x): return "★" if x else "☆")))
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(0, minf(900.0, root.get_viewport_rect().size.y - 470.0))
	_fit_scroll.call_deferred(sc, minf(900.0, root.get_viewport_rect().size.y - 470.0))
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
			if lock.length() >= 14:
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
		var ic: String = SPECIAL_ICONS.get(Game.special_type(), "upgrade") if key == "station" else STATION_ICONS.get(key, "star")
		_row(list, ic, title, String(d.desc), stat, btn)
	var info := UI.label(STAR_RULES, 19, UI.MUTED, null, HORIZONTAL_ALIGNMENT_CENTER)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(info)


# ------------------------------------------------------------------ character: gear + wardrobe

var _wardrobe_slot := "shirt"


func _character(v: VBoxContainer) -> void:
	_header(v, "character", "Your Lumberjack", "Empire %d · %d ★ · %s served" % [Game.prestige + 1, Game.total_stars(), UI.fmt(Game.served)])
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(0, minf(940.0, root.get_viewport_rect().size.y - 430.0))
	_fit_scroll.call_deferred(sc, minf(940.0, root.get_viewport_rect().size.y - 430.0))
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var list := UI.vbox(12)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list)
	v.add_child(sc)
	list.add_child(UI.label("GEAR", 24, UI.GOLD_LIGHT, UI.font_bold()))
	_gear_rows(list, false)
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
			stat = "Needs %d ★" % int(it.stars) if int(it.get("stars", 0)) > Game.total_stars() else ""
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
	var b := UI.button("ON" if on else "OFF", "green" if on else "dark", "", 28, 132)
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
		var gq := UI.button("Graphics: " + String(Game.QUALITY_NAMES[Game.quality]) + (" (auto)" if Game.quality_auto else "") + "  ›", "dark", "", 28)
		gq.pressed.connect(func():
			Game.quality = (Game.quality + 1) % 3
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
	if _confirm_reset:
		var warn := UI.label("Erase ALL progress, cash, crew and outfits? This can't be undone.", 22, UI.RED, null, HORIZONTAL_ALIGNMENT_CENTER)
		warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(warn)
		var rr := UI.hbox(12)
		var cancel := UI.button("Keep my game", "green", "", 26)
		cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cancel.pressed.connect(func():
			_confirm_reset = false
			_rebuild_modal())
		var erase := UI.button("Erase", "red", "", 26)
		erase.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		erase.pressed.connect(func(): Game.reset_all())
		rr.add_child(cancel)
		rr.add_child(erase)
		v.add_child(rr)
	else:
		var rs := UI.button("Reset progress", "red", "", 26)
		rs.pressed.connect(func():
			_confirm_reset = true
			_rebuild_modal())
		v.add_child(rs)
	var cr := UI.label("Axe to Empire v%s · BigoSoft\nFonts: Inter, Barlow Condensed (OFL)" % str(ProjectSettings.get_setting("application/config/version")), 18, UI.MUTED, null, HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(cr)


func _replay_story() -> void:
	var ch: Dictionary = Game.story_data.chapters.get(String(Game.chapter().id), {})
	var beats: Array = []
	for b in ch.get("beats", []):
		if b.on == "start" or Game.seen.has(b.on + ":1") or Game.seen.keys().any(func(k): return String(k).begins_with(String(b.on) + ":")):
			beats.append(b)
	_story_q = _merge_beats(beats)
	_story_replay = true
	_next_story()


func _howto(v: VBoxContainer) -> void:
	_header(v, "info", "How to play")
	for line in [
		["axe", "Stand next to a tree to chop. Logs stack on your back."],
		["log", "Drop logs on the woodpile; the kitchen cooks with them. Sell extra logs at the truck."],
		["dish", "Carry dishes from the rack to the counter. Guests pay; collect the cash pile."],
		["smile", "Serve fast: happy guests pay +20%, guests you serve in person pay +25%. Slow service and they walk out."],
		["upgrade", "UPGRADE levels the kitchen, menu, dining and signboard up to Lv 25. Big levels take time to build."],
		["crew", "Hire crew to help. They're slower than you, so you earn the most when you serve guests yourself."],
		["bigday", "Build everything, then win the Big Day at the gate to buy the land next door."],
		["gate", "It's one road: walk over to your other places, or tap MAP to jump there."],
		["coin", "Your other places keep earning while you play. Their cash waits on their counters (up to %d min). Go there to collect it." % int(Game.TILL_CAP_MIN)],
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
			["Trees felled", UI.fmt(Game.stats.trees)], ["Golden trees", UI.fmt(int(Game.stats.get("golden", 0)))],
			["Walkouts", UI.fmt(int(Game.stats.get("walkouts", 0)))], ["Lost to full lines", UI.fmt(int(Game.stats.get("lost", 0)))],
			["Big Days won", UI.fmt(int(Game.stats.get("bigdays", 0)))], ["Stars", "%d / %d" % [Game.total_stars(), Game.chapters.size() * 3]],
			["Logs sold", UI.fmt(Game.stats.sold)], ["Time played", "%dh %02dm" % [mins / 60, mins % 60]]]:
		var c := UIShape.new("dark", 18.0, Vector4(16, 10, 16, 10))
		c.custom_minimum_size.x = 288
		var cv := UI.vbox(0)
		cv.add_child(UI.label(s[0], 19, UI.MUTED))
		cv.add_child(UI.num(s[1], 38, UI.GOLD_LIGHT))
		c.add_child(cv)
		grid.add_child(c)
	v.add_child(grid)
