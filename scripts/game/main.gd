extends Control
## Prototype shell: owns the sim, runs the fixed 4 Hz tick, save/load,
## offline earnings, and a plain unpolished UI.

const Sim = preload("res://scripts/sim/economy_sim.gd")
const Meta = preload("res://scripts/sim/meta.gd")
const WorldView = preload("res://scripts/game/world_view.gd")
const Fmt = preload("res://scripts/game/fmt.gd")

const SAVE_PATH := "user://save.bin"
const TMP_PATH := "user://save.tmp"
const BACKUP_PATH := "user://save_backup.bin"
const TABS := ["Upgrades", "Venue", "Daily", "Stats", "Debug"]

var cfg: Dictionary
var sim
var meta
var world
var speed := 1
var hint: Dictionary = {}

var _acc := 0.0
var _autosave := 0.0
var _ui_timer := 0.0
var _hint_timer := 0.0
var _tab := "Upgrades"
var _built_chapter := -1
var _hud: Label
var _hint_btn: Button
var _scroll: ScrollContainer
var _content: VBoxContainer
var _tab_btns := {}
var _refs := {}
var _overlay: Control


func _ready() -> void:
	cfg = _load_config()
	sim = Sim.new(cfg)
	meta = Meta.new(sim)
	var loaded := _load_game()
	if not loaded:
		sim.new_game(int(Time.get_unix_time_from_system()) % 2147483647)
	_build_ui()
	meta.ensure_day(Meta.day_key_now(int(cfg.daily.reset_hour)))
	if loaded:
		_check_offline()
	_stamp()
	_recompute_hint()
	_rebuild_tab()


func _load_config() -> Dictionary:
	var txt := FileAccess.get_file_as_string("res://data/config.json")
	var d = JSON.parse_string(txt)
	if typeof(d) != TYPE_DICTIONARY:
		push_error("config.json failed to parse")
		return {}
	return d


# ---------------------------------------------------------------- loop

func _process(delta: float) -> void:
	_acc += minf(delta, 0.25) * speed
	var n := 0
	while _acc >= sim.dt and n < 2048:
		sim.step()
		world.add_events(sim.events)
		_acc -= sim.dt
		n += 1
	_autosave += delta
	if _autosave >= 30.0:
		_autosave = 0.0
		_save()
	_hint_timer -= delta
	if _hint_timer <= 0.0:
		_hint_timer = 1.0
		_recompute_hint()
		if meta.ensure_day(Meta.day_key_now(int(cfg.daily.reset_hour))) and _tab == "Daily":
			_rebuild_tab()
	_ui_timer -= delta
	if _ui_timer <= 0.0:
		_ui_timer = 0.25
		if int(sim.s.chapter) != _built_chapter:
			_rebuild_tab()
		_update_ui()


func _notification(what: int) -> void:
	if sim == null:
		return
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_CLOSE_REQUEST:
			_save()
		NOTIFICATION_APPLICATION_RESUMED:
			_check_offline()
			_stamp()


# ---------------------------------------------------------------- save / offline

func _stamp() -> void:
	sim.s.last_seen = int(Time.get_unix_time_from_system())


## Atomic: write tmp, keep previous save as backup, then swap.
func _save() -> void:
	_stamp()
	var f := FileAccess.open(TMP_PATH, FileAccess.WRITE)
	if f == null:
		return
	# Binary Variant encoding: floats round-trip exactly (text saves drift by 1 ulp).
	f.store_var(sim.to_save())
	f.close()
	var dir := DirAccess.open("user://")
	if dir.file_exists("save.bin"):
		if dir.file_exists("save_backup.bin"):
			dir.remove("save_backup.bin")
		dir.rename("save.bin", "save_backup.bin")
	dir.rename("save.tmp", "save.bin")


func _load_game() -> bool:
	for path in [SAVE_PATH, BACKUP_PATH]:
		if not FileAccess.file_exists(path):
			continue
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			continue
		var d = f.get_var()
		f.close()
		if typeof(d) == TYPE_DICTIONARY and sim.from_save(d):
			return true
	return false


## Prototype uses the device clock with a rollback guard; production would
## use server time (spec 5.5 / 8.4).
func _check_offline() -> void:
	var away := int(Time.get_unix_time_from_system()) - int(sim.s.last_seen)
	if away < 60:
		return  # also covers a clock rolled backwards: grants nothing
	var r: Dictionary = sim.offline_fast_forward(float(away))
	var gift := 0.0
	if away >= 3 * 86400:
		gift = maxf(100.0, sim.rates(null, true, false).income * 7200.0)
	_show_offline(r, gift)


func _show_offline(r: Dictionary, gift: float) -> void:
	var lines := "WHILE YOU WERE AWAY (%s)\n\n" % Fmt.dur(r.away)
	if r.away > r.cap:
		lines += "Counted %s (offline cap; upgrade Night shift)\n" % Fmt.dur(r.cap)
	lines += "Your staff cooked %d dishes\nEfficiency %d%% (hire Managers for more)\n\nEarned: %s coins" % [
		int(r.dishes), int(r.eff * 100.0), Fmt.num(r.coins)]
	if r.timers > 0.0:
		lines += "\nTrucks/bikes returned: +%s" % Fmt.num(r.timers)
	if gift > 0.0:
		lines += "\n\nWelcome back gift: +%s" % Fmt.num(gift)
	var base: float = r.timers + gift
	_popup(lines, [
		["Collect " + Fmt.num(r.coins + base), func(): sim.grant(r.coins + base)],
		["Watch ad: x2  (placeholder, no real ad)", func(): sim.grant(r.coins * 2.0 + base)],
	])


func _popup(text: String, buttons: Array) -> void:
	if _overlay != null:
		_overlay.queue_free()
	_overlay = ColorRect.new()
	_overlay.color = Color(0, 0, 0, 0.65)
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_overlay)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(cc)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(620, 0)
	cc.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	panel.add_child(vb)
	var lbl := Label.new()
	lbl.text = text
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(lbl)
	for b in buttons:
		var btn := Button.new()
		btn.text = b[0]
		btn.custom_minimum_size.y = 64
		var cb: Callable = b[1]
		btn.pressed.connect(func():
			cb.call()
			_overlay.queue_free()
			_overlay = null)
		vb.add_child(btn)


# ---------------------------------------------------------------- UI build

func _build_ui() -> void:
	var th := Theme.new()
	th.default_font_size = 21
	theme = th
	var bg := ColorRect.new()
	bg.color = Color(0.1, 0.11, 0.1)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_top", _safe_top())
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	margin.add_child(root)

	_hud = Label.new()
	_hud.add_theme_font_size_override("font_size", 19)
	root.add_child(_hud)

	_hint_btn = Button.new()
	_hint_btn.custom_minimum_size.y = 58
	_hint_btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_btn.pressed.connect(_on_hint)
	root.add_child(_hint_btn)

	world = WorldView.new()
	world.sim = sim
	world.custom_minimum_size = Vector2(0, 600)
	world.size_flags_vertical = Control.SIZE_FILL
	root.add_child(world)

	var tabs := HBoxContainer.new()
	for t in TABS:
		var b := Button.new()
		b.text = t
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.y = 56
		b.pressed.connect(func(): _switch_tab(t))
		tabs.add_child(b)
		_tab_btns[t] = b
	root.add_child(tabs)

	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size.y = 300
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(_scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 6)
	_scroll.add_child(_content)


func _safe_top() -> int:
	var safe := DisplayServer.get_display_safe_area()
	var win := DisplayServer.window_get_size()
	if win.y <= 0:
		return 12
	var k := get_viewport_rect().size.y / float(win.y)
	return maxi(12, int(safe.position.y * k) + 4)


func _switch_tab(t: String) -> void:
	_tab = t
	_rebuild_tab()


func _clear_content() -> void:
	for ch in _content.get_children():
		ch.queue_free()
	_refs.clear()


func _label(text := "", fsize := 19) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_font_size_override("font_size", fsize)
	_content.add_child(l)
	return l


func _button(text: String, cb: Callable, parent: Node = null) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 60)
	b.pressed.connect(cb)
	(parent if parent != null else _content).add_child(b)
	return b


func _rebuild_tab() -> void:
	_built_chapter = int(sim.s.chapter)
	for t in _tab_btns:
		_tab_btns[t].button_pressed = (t == _tab)
	_clear_content()
	match _tab:
		"Upgrades": _build_upgrades()
		"Venue": _build_venue()
		"Daily": _build_daily()
		"Stats": _refs["stats"] = _label("", 17)
		"Debug": _build_debug()
	_update_ui()


func _build_upgrades() -> void:
	_label("Tap trees to chop, the shelf to buy ingredients, dirty tables to clean, the counter to serve, the truck to send it.", 16)
	for u in cfg.upgrades:
		if int(u.ch) > int(sim.s.chapter) + 1:
			continue
		var row := HBoxContainer.new()
		var lbl := Label.new()
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.add_theme_font_size_override("font_size", 18)
		var id: String = u.id
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(150, 64)
		btn.pressed.connect(func(): sim.push_command("buy", id))
		row.add_child(lbl)
		row.add_child(btn)
		_content.add_child(row)
		_refs[id] = {"label": lbl, "btn": btn}


func _build_venue() -> void:
	_refs["venue"] = _label("", 18)
	_refs["move"] = _button("Move", func(): sim.push_command("move"))
	_refs["prestige"] = _button("New Venture", func(): _confirm_prestige())
	var row := HBoxContainer.new()
	_content.add_child(row)
	var l := Label.new()
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(l)
	_refs["reserve"] = l
	_button(" -5 ", func(): sim.push_command("reserve", float(sim.s.wood_reserve) - 5.0), row)
	_button(" +5 ", func(): sim.push_command("reserve", float(sim.s.wood_reserve) + 5.0), row)


func _confirm_prestige() -> void:
	_popup("NEW VENTURE\n\nSell this empire for %d Legacy Points total (+%d%% income forever).\nEverything else restarts from chapter 1." % [
		sim.lp_total_preview(), int(sim.lp_total_preview() * float(cfg.prestige.per_lp) * 100.0)], [
		["Sell the empire", func():
			sim.prestige()
			_rebuild_tab()],
		["Not yet", func(): pass],
	])


func _build_daily() -> void:
	_refs["daily"] = _label("", 18)
	_refs["chest"] = _button("Claim chest", func():
		var v: float = meta.claim_chest()
		if v > 0.0:
			world.add_events([{"type": "coins", "amount": v, "where": "center"}]))
	_refs["reroll"] = _button("Reroll jobs", func():
		meta.reroll(false)
		_rebuild_tab())
	_button("Reroll via ad (placeholder, no real ad)", func():
		meta.reroll(true)
		_rebuild_tab())
	_refs["streak"] = _button("Claim streak", func():
		var msg: String = meta.claim_streak()
		if msg != "":
			_popup(msg, [["OK", func(): pass]]))


func _build_debug() -> void:
	_label("Prototype debug tools", 18)
	var row := HBoxContainer.new()
	_content.add_child(row)
	for sp in [1, 4, 16, 64]:
		var b := _button("x%d" % sp, func(): speed = sp, row)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_refs["speed"] = _label("")
	_button("+ coins (10 min of income, min 500)", func():
		sim.grant(maxf(500.0, sim.rates(null, true, true).income * 600.0)))
	_button("+ 50 fame", func(): sim.s.fame = float(sim.s.fame) + 50.0)
	_button("Rating to 5 stars", func():
		for i in 200:
			sim._push_rating(1.0))
	_button("Complete this chapter's quests", func(): _debug_complete_quests())
	_button("Simulate 2 hours away (offline earnings)", func():
		sim.s.last_seen = int(sim.s.last_seen) - 7200
		_check_offline()
		_stamp())
	_button("Simulate 4 days away (welcome back gift)", func():
		sim.s.last_seen = int(sim.s.last_seen) - 4 * 86400
		_check_offline()
		_stamp())
	_button("Skip to next daypart (+2.4 min game time)", func():
		sim.s.tick = int(sim.s.tick) + int(float(cfg.day_length_s) * 0.2 * float(cfg.tick_hz)))
	_button("Save now", func(): _save())
	_button("RESET GAME (delete save)", func():
		_popup("Delete the save and start over?", [
			["Yes, reset", func():
				DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
				DirAccess.remove_absolute(ProjectSettings.globalize_path(BACKUP_PATH))
				sim.new_game(int(Time.get_unix_time_from_system()) % 2147483647)
				meta.ensure_day(Meta.day_key_now(int(cfg.daily.reset_hour)))
				_rebuild_tab()],
			["Cancel", func(): pass]]))


func _debug_complete_quests() -> void:
	for q in sim.chap().quests:
		if q.has("counter"):
			sim.s.chapter_start[q.counter] = float(sim.s.stats[q.counter]) - float(q.target)
		else:
			sim.s.levels[q.level] = maxi(sim.lv(q.level), int(q.target))
	sim._sync()


# ---------------------------------------------------------------- UI update

func _recompute_hint() -> void:
	hint = sim.best_action()
	world.hint_target = str(hint.get("target", ""))
	var txt := ""
	match str(hint.kind):
		"buy":
			txt = "BEST NEXT: %s  (+%s coins/h)  - tap to buy" % [sim.upgrade_info(hint.id).name, Fmt.num(hint.gain)]
		"save":
			txt = "Saving for %s: %s / %s  (+%s/h)" % [sim.upgrade_info(hint.id).name, Fmt.num(sim.s.coins), Fmt.num(hint.cost), Fmt.num(hint.gain)]
		_:
			txt = str(hint.text)
	_hint_btn.text = txt


func _on_hint() -> void:
	match str(hint.get("kind", "")):
		"buy":
			sim.push_command("buy", hint.id)
		"move":
			sim.push_command("move")
		"prestige":
			_switch_tab("Venue")
		"save":
			_switch_tab("Upgrades")
		_:
			world.flash(str(hint.get("target", "")))
	_hint_timer = 0.3


func _update_ui() -> void:
	var s: Dictionary = sim.s
	var dp: Dictionary = sim.daypart()
	var mins := int(sim.day_frac() * 24.0 * 60.0)
	var extra := ""
	if float(s.event.left) > 0.0:
		extra = "  |  %s %ds" % ["POWER CUT" if s.event.type == "power_cut" else "CELEBRITY", ceili(float(s.event.left))]
	_hud.text = "Coins %s   Rating %.1f/5   Fame %d%s\nCh.%d %s - %s  |  Day %d %02d:%02d %s%s%s" % [
		Fmt.num(s.coins), sim.rating(), int(s.fame),
		("   LP %d (+%d%%)" % [int(s.legacy.lp), int(float(s.legacy.lp) * float(cfg.prestige.per_lp) * 100.0)]) if int(s.legacy.lp) > 0 else "",
		int(s.chapter), sim.chap().name, sim.venue_stage(), int(s.day) + 1, mins / 60, mins % 60, dp.name,
		"  |  Rain" if s.weather == "Rain" else "", extra]
	if speed > 1:
		_hud.text += "  |  x%d" % speed
	match _tab:
		"Upgrades": _update_upgrades()
		"Venue": _update_venue()
		"Daily": _update_daily()
		"Stats": _update_stats()
		"Debug":
			if _refs.has("speed"):
				_refs.speed.text = "Game speed: x%d" % speed


func _update_upgrades() -> void:
	for id in _refs:
		var r: Dictionary = _refs[id]
		var u: Dictionary = sim.upgrade_info(id)
		var st: Dictionary = sim.upgrade_state(id)
		var gain: float = sim.scores.get(id, 0.0)
		var best: bool = str(hint.get("id", "")) == id
		r.label.text = "%s%s  Lv %d/%d\n%s%s" % [">> " if best else "", u.name, st.level, int(u.max), u.desc,
			("  [+%s/h]" % Fmt.num(gain)) if gain >= 1.0 else ""]
		r.label.modulate = Color(1, 0.9, 0.4) if best else Color.WHITE
		if st.locked:
			r.btn.text = "Ch.%d" % int(u.ch)
			r.btn.disabled = true
		elif st.maxed:
			r.btn.text = "MAX"
			r.btn.disabled = true
		else:
			r.btn.text = Fmt.num(st.cost)
			r.btn.disabled = not st.affordable


func _update_venue() -> void:
	var s: Dictionary = sim.s
	var c: Dictionary = sim.chap()
	var g: Dictionary = sim.gate()
	var t := "CHAPTER %d: %s\nThis chapter teaches: %s\nVenue stage: %s   Wood: %s (+%d%% flavor)\n\n" % [
		int(s.chapter), c.name, c.teaches, sim.venue_stage(), c.wood_type, int(float(c.flavor) * 100.0)]
	t += "GATE TO NEXT CHAPTER (coins alone never unlock it):\n"
	t += "[%s] Rating %.1f / %.1f\n" % ["x" if g.rating_ok else " ", sim.rating(), g.rating]
	t += "[%s] Fame %d / %d\n" % ["x" if g.fame_ok else " ", int(s.fame), int(g.fame)]
	for q in g.quests:
		t += "[%s] %s  (%d/%d)\n" % ["x" if q.done else " ", q.label, mini(int(q.cur), int(q.target)), int(q.target)]
	if not g.last:
		t += "Move cost: %s coins" % Fmt.num(g.cost)
	else:
		t += "\nFinal chapter in this prototype. Meeting the gate unlocks New Venture (prestige).\nLegacy Points available: %d (have %d)" % [sim.lp_total_preview(), int(s.legacy.lp)]
	_refs.venue.text = t
	_refs.move.visible = not g.last
	_refs.move.text = "Move to chapter %d (%s)" % [int(s.chapter) + 1, Fmt.num(g.cost)]
	_refs.move.disabled = not g.can_move
	_refs.prestige.visible = g.last
	_refs.prestige.disabled = not g.can_prestige
	_refs.prestige.text = "New Venture: sell empire for %d LP" % sim.lp_total_preview()
	if sim.unlocked("truck"):
		_refs.reserve.text = "Wood kept for cooking: %d logs (the log truck sells the rest)" % int(s.wood_reserve)
	else:
		_refs.reserve.text = "Wood reserve (used once the log truck unlocks in ch.2): %d" % int(s.wood_reserve)


func _update_daily() -> void:
	var m: Dictionary = sim.s.meta
	var t := "DAILY JOBS (reset 04:00)\n"
	for j in meta.jobs():
		var p := mini(int(meta.progress(j)), int(j.target))
		t += "[%s] %s: %s  (%d/%d)\n" % ["x" if p >= int(j.target) else " ", j.tag, j.label, p, int(j.target)]
	t += "All 3 done -> chest worth ~%s coins%s\n\n" % [Fmt.num(meta.chest_value()), " (claimed)" if m.get("chest_claimed", false) else ""]
	var st: Dictionary = m.streak
	t += "LOGIN STREAK (missing a day pauses it, never resets)\n"
	for i in 7:
		t += ("[%d]" if i == int(st.idx) else " %d ") % (i + 1)
	_refs.daily.text = t
	_refs.chest.disabled = not meta.all_done() or bool(m.get("chest_claimed", false))
	_refs.reroll.text = "Reroll jobs (%d free left)" % int(m.get("rerolls", 0))
	_refs.reroll.disabled = int(m.get("rerolls", 0)) <= 0
	_refs.streak.disabled = not meta.streak_can_claim()
	_refs.streak.text = "Claim day %d streak reward (%s)" % [int(st.idx) + 1, Fmt.num(meta.streak_reward(int(st.idx)))] if meta.streak_can_claim() else "Streak reward claimed today"


func _update_stats() -> void:
	var s: Dictionary = sim.s
	var r: Dictionary = sim.rates(null, false, true)
	var st: Dictionary = s.stats
	var t := "THROUGHPUT MODEL (dishes per minute, right now)\n"
	t += "Chop %.1f (forest regrowth limit %.1f)   Cook %.1f   -> supply %.1f\n" % [r.chop * 60.0, r.forest_cap * 60.0, r.cook * 60.0, r.supply * 60.0]
	var names := {"dine": "Dine-in", "take": "Takeaway", "drive": "Drive-thru", "delivery": "Delivery"}
	for ch in sim.CHANNELS:
		var cap: float = r.caps[ch]
		var lam: float = r.lam[ch]
		if cap <= 0.0 and lam <= 0.0:
			continue
		var rho := lam / cap if cap > 0.0 else 99.0
		t += "%s: capacity %.1f/min, demand %.1f/min, load %.2f %s\n" % [names[ch], cap * 60.0, lam * 60.0, rho,
			"(queue grows)" if rho > 1.0 else ("(fun zone)" if rho >= 0.7 else "(idle)")]
	t += "Sales %.1f dishes/min  ->  ~%s coins/h\nBOTTLENECK: %s\n\n" % [r.sales * 60.0, Fmt.num(r.income * 3600.0), r.bottleneck]
	t += "Dish price %s   Wood sells at %s/log\n" % [Fmt.num(sim.dish_price(s.levels)), Fmt.num(sim.wood_price())]
	t += "Offline: cap %s, efficiency %d%%\n\n" % [Fmt.dur(sim.offline_cap_s(s.levels)), int(sim.offline_eff(s.levels) * 100.0)]
	t += "Meals %d (dine %d, take %d, drive %d, delivery %d)\n" % [st.meals, st.served_dine, st.served_take, st.served_drive, st.served_delivery]
	t += "Lost: %d balked (queue full), %d left waiting\n" % [st.lost_balk, st.lost_renege]
	t += "Trees felled %d, taps %d, truck trips %d, rushes survived %d\n" % [st.trees_felled, st.chops, st.truck_trips, st.rush_clean]
	t += "Coins from dishes %s, tips %s, truck %s, other %s\nLifetime %s" % [
		Fmt.num(st.coins_dishes), Fmt.num(st.coins_tips), Fmt.num(st.coins_truck), Fmt.num(st.coins_other), Fmt.num(s.lifetime)]
	_refs.stats.text = t
