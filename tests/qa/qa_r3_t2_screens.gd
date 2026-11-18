extends SceneTree
## QA round 3, tester 2: every screen and modal, rendered, at one window size, plus a layout audit.
##   $G --path . -s res://tests/qa/qa_r3_t2_screens.gd -- <outdir> <WxH> [part]
## part: all | hud | modals | flow | walk | world
## Audit per screen: tap targets < 68x60 (WARN), visible labels/buttons off screen (FAIL), one-line labels
## wider than their box (FAIL clip), clickables overlapping each other outside scroll lists (FAIL).
## Duck-typed: no static reference to the UI classes. Not headless. Prints FAILS=n.
var out := ""
var n := 0
var g
var fails := 0
var warns := 0
var tag := ""


func ok(c: bool, msg: String) -> void:
	if not c:
		print("FAIL " + msg)
		fails += 1


func warn(msg: String) -> void:
	print("WARN " + msg)
	warns += 1


func _initialize() -> void:
	_run.call_deferred()


func _wait(k: int) -> void:
	for i in k:
		await process_frame


func _shot(name: String, wait := 0.4) -> void:
	await create_timer(wait).timeout
	n += 1
	root.get_texture().get_image().save_png("%s/%s_%02d_%s.png" % [out, tag, n, name])
	print("SHOT %s_%02d_%s" % [tag, n, name])


func _full(k: int) -> Dictionary:
	var b := {"campfire": true, "tables_1": true, "shop": true, "crew_hut": true, "fire_2": true, "tables_2": true}
	if String(g.chapters[k].get("special", {}).get("type", "")) != "":
		b["special"] = true
	return b


func _setup(k: int, own := -1) -> void:
	g.venue = k; g.unlocked = (k + 1) if own < 0 else own; g.venues = []; g.cfg = g.chapter_cfg(k)
	g.reno = {}; g.bigday = {}; g.seen = {"task_init": true}; g.task_i = 2; g.task_base = 0; g.chapter_done = false
	g.built = _full(k)
	g.crew = {"lumberjack": 2, "waiter": 2, "cook": 1}
	g.vserved = 4321; g.coins = 12345678; g.rating_hist = [4.6]; g.woodpile = 12; g.counter_coins = 0
	while g.venues.size() < g.unlocked:
		g.venues.append({})
	for j in g.unlocked:
		if j != k:
			g.venues[j] = {"crew": {"lumberjack": 2, "waiter": 2, "cook": 1}, "built": _full(j), "counter_coins": int(g.till_cap(j) * 0.6)}


func _load() -> void:
	change_scene_to_file("res://scenes/main.tscn")
	await _wait(2)
	await _ready_scene()
	await _wait(20)
	var hud = current_scene.hud
	hud._story_q.clear()
	if hud.modal_kind != "":
		hud.close_modal()
	g._in_background = true
	g.tills_changed.emit()
	await create_timer(0.4).timeout


func _ready_scene() -> void:
	while current_scene == null or current_scene.get("hud") == null or current_scene.get_node_or_null("LoadingScreen") != null \
			or current_scene.get("crossing"):
		await process_frame


func _stand(x: float, z := 11.5) -> void:
	var w = current_scene.world
	w.player.global_position = Vector3(x, 0, z)
	w._cross_armed = false
	w._cam_target = w.player.global_position + Vector3(w._hud_side_shift(), 0, -0.8)
	w._place_cam(1.0)


# ------------------------------------------------------------------ audit

func _in_scroll(c: Node) -> ScrollContainer:
	var p := c.get_parent()
	while p != null:
		if p is ScrollContainer:
			return p
		p = p.get_parent()
	return null


func _name(c: Node) -> String:
	if c is Label:
		return "'%s'" % String(c.text).replace("\n", " ").left(48)
	for l in c.find_children("*", "Label", true, false):
		if l.is_visible_in_tree() and String(l.text).strip_edges() != "":
			return "'%s'" % String(l.text).replace("\n", " ").left(48)
	return String(c.name)


func _vis(c: Control) -> bool:
	if not c.is_visible_in_tree():
		return false
	var p: Node = c
	while p != null and p is CanvasItem:
		if (p as CanvasItem).modulate.a < 0.05:
			return false
		p = p.get_parent()
	return true


func audit(where: String, base: Node) -> void:
	var vr: Rect2 = root.get_visible_rect()
	var clicks: Array = []
	for c in base.find_children("*", "Control", true, false):
		if not _vis(c):
			continue
		var r: Rect2 = c.get_global_rect()
		if r.size.x < 1 or r.size.y < 1:
			continue
		var sc := _in_scroll(c)
		var visible_r := r
		if sc:
			visible_r = r.intersection(sc.get_global_rect())
			if visible_r.size.y < 2:
				continue
		if c.get("clickable") == true:
			if r.size.x < 68 or r.size.y < 60:
				warn("T %s %s: small tap target %s %.0fx%.0f" % [tag, where, _name(c), r.size.x, r.size.y])
			if not vr.encloses(visible_r.grow(-1)):
				ok(false, "V %s %s: button %s off screen %s (screen %s)" % [tag, where, _name(c), r, vr.size])
			if sc == null:
				clicks.append(c)
		elif c is Label and String(c.text).strip_edges() != "":
			if not vr.encloses(visible_r.grow(-2)):
				ok(false, "O %s %s: label %s off screen %s (screen %s)" % [tag, where, _name(c), r, vr.size])
			if c.autowrap_mode == TextServer.AUTOWRAP_OFF:
				var f: Font = c.get_theme_font("font")
				var fs: int = c.get_theme_font_size("font_size")
				var longest := 0.0
				for line in String(c.text).split("\n"):
					longest = maxf(longest, f.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
				if longest > r.size.x + 2:
					ok(false, "CLIP %s %s: label %s needs %.0f px, has %.0f" % [tag, where, _name(c), longest, r.size.x])
			# label sticking out of its button / card shape
			var p: Node = c.get_parent()
			while p != null and not (p is Control and p.get("clickable") != null and p.get_class() != "Label" and p.has_method("make_clickable")):
				p = p.get_parent()
			if p != null and p is Control and not (p as Control).get_global_rect().grow(2).encloses(r):
				ok(false, "SPILL %s %s: label %s %s spills out of its box %s" % [tag, where, _name(c), r, (p as Control).get_global_rect()])
	for i in clicks.size():
		for j in range(i + 1, clicks.size()):
			var a: Control = clicks[i]
			var b: Control = clicks[j]
			if a.is_ancestor_of(b) or b.is_ancestor_of(a):
				continue
			var ia: Rect2 = a.get_global_rect().intersection(b.get_global_rect())
			if ia.size.x > 4 and ia.size.y > 4:
				ok(false, "OVERLAP %s %s: %s %s and %s %s" % [tag, where, _name(a), a.get_global_rect(), _name(b), b.get_global_rect()])


func audit_modal(where: String) -> void:
	var hud = current_scene.hud
	if hud.modal == null:
		ok(false, "%s %s: modal did not open" % [tag, where])
		return
	audit(where, hud.modal)
	var card: Control = hud.modal.get_node_or_null("Card")
	if card and card.get_child_count() > 0:
		var cr: Rect2 = card.get_child(0).get_global_rect()
		ok(root.get_visible_rect().encloses(cr.grow(-1)), "C %s %s: card %s inside screen %s" % [tag, where, cr, root.get_visible_rect().size])
		print("CARD %s %s: %s" % [tag, where, cr])


func _open(m: String, name: String, scroll_end := false) -> void:
	var hud = current_scene.hud
	hud.open_modal(m)
	await _shot(name)
	audit_modal(name)
	if scroll_end and hud.modal:
		for sc in hud.modal.find_children("*", "ScrollContainer", true, false):
			sc.scroll_vertical = 100000
		await _shot(name + "_end", 0.3)
		audit_modal(name + "_end")


# ------------------------------------------------------------------ parts

func _hud() -> void:
	for k in g.chapters.size():
		_setup(k, mini(k + 2, g.chapters.size()))
		if k == 3:
			g.reno = {"id": "menu", "to": 9, "end": Time.get_unix_time_from_system() + 3700, "start": Time.get_unix_time_from_system()}
		await _load()
		var hud = current_scene.hud
		await _shot("hud_ch%d" % k, 0.8)
		audit("hud_ch%d" % k, hud.root)
		# the top row with a huge cash number and big served count
		if k == 5:
			g.coins = 987654321098; g.vserved = 123456
			g.coins_changed.emit(g.coins)
			hud._coin_shown = g.coins
			hud._refresh_top()
			await _shot("hud_ch5_bignums", 0.6)
			audit("hud_ch5_bignums", hud.root)


func _modals() -> void:
	for k in [0, 2, 5]:
		_setup(k, 4 if k < 4 else 6)
		g.levels.tool = g.cfg.tools.size() - 1
		g.levels.bag = g.cfg.bag.size() - 1
		g.levels.boots = g.cfg.boots.size() - 1
		g.pro = {"tool": 3, "bag": 10, "boots": 0}
		await _load()
		var hud = current_scene.hud
		await _open("shop", "ch%d_shop" % k)
		await _open("upgrades", "ch%d_upgrades" % k, true)
		hud.close_modal()
		await _open("crew", "ch%d_crew" % k)
		hud.close_modal()
		await _open("character", "ch%d_me" % k, true)
		hud._wardrobe_slot = "hat"
		hud._rebuild_modal_now()
		await _shot("ch%d_me_hat" % k)
		audit_modal("ch%d_me_hat" % k)
		hud._wardrobe_slot = "shirt"
		hud.close_modal()
		await _open("empire", "ch%d_map" % k, true)
		hud.close_modal()
		if k == 2:
			# jobs: one claimable, one done, chest ready
			if g.jobs.size() >= 3:
				g.jobs[0].prog = g.jobs[0].goal; g.jobs[0].claimed = false
				g.jobs[1].prog = g.jobs[1].goal; g.jobs[1].claimed = true
			g.streak = 4
			await _open("jobs", "jobs_mixed")
			for j in g.jobs:
				j.prog = j.goal; j.claimed = true
			g.chest_claimed = false
			hud._rebuild_modal_now()
			await _shot("jobs_chest_ready")
			audit_modal("jobs_chest_ready")
			hud.close_modal()
			await _open("settings", "settings")
			hud._confirm_reset = true
			hud._rebuild_modal_now()
			await _shot("settings_reset_confirm")
			audit_modal("settings_reset_confirm")
			hud._confirm_reset = false
			await _open("howto", "howto")
			await _open("stats", "stats")
			hud.close_modal()
			g.offline_reward = 1234567
			await _open("offline", "offline")
			g.offline_reward = 0
			hud.close_modal()
			# story cards (long and short)
			var beats: Array = []
			for ch in g.story_data.chapters.values():
				for b in ch.get("beats", []):
					beats.append(b)
			beats.sort_custom(func(a, b): return String(a.text).length() > String(b.text).length())
			hud._story_q = [beats[0], beats[beats.size() - 1]]
			hud._story_replay = true
			hud.open_modal("story")
			await _shot("story_longest")
			audit_modal("story_longest")
			hud._story_q.pop_front()
			hud._rebuild_modal_now()
			await _shot("story_short")
			audit_modal("story_short")
			hud._story_q.clear(); hud._story_replay = false
			hud.close_modal()
			# gate states
			g.bigday = {}
			await _open("gate", "gate_needs_bigday")
			world_bd_cool(7.0)
			hud._rebuild_modal_now()
			await _shot("gate_cooldown")
			audit_modal("gate_cooldown")
			world_bd_cool(0.0)
			g.bigday = {"won": true}
			hud._rebuild_modal_now()
			await _shot("gate_ready")
			audit_modal("gate_ready")
			g.chapter_done = true
			hud._rebuild_modal_now()
			await _shot("gate_done")
			audit_modal("gate_done")
			hud.close_modal()
			g.chapter_done = false
			await _open("complete", "complete_mid")
			hud.close_modal()
			# Big Day running + results
			g.bigday = {}
			current_scene.world.start_big_day()
			await _shot("bigday_running", 1.0)
			audit("bigday_running", hud.root)
			current_scene.world.bd_active = false
			hud._bd_result = [true, 64, 40]
			await _open("bigday_result", "bigday_won")
			hud._bd_result = [false, 12, 40]
			hud._rebuild_modal_now()
			await _shot("bigday_lost")
			audit_modal("bigday_lost")
			hud.close_modal()
		if k == 5:
			g.bigday = {"won": true}
			await _open("gate", "last_gate")
			await _open("complete", "last_complete")
			hud._confirm_prestige = true
			hud._rebuild_modal_now()
			await _shot("last_complete_confirm")
			audit_modal("last_complete_confirm")
			hud._confirm_prestige = false
			hud.close_modal()


func world_bd_cool(v: float) -> void:
	current_scene.world._bd_cool = v


## Big Day start through the gate: START button -> story card -> banner (story cards on).
func _flow() -> void:
	_setup(1, 2)
	g.settings.story = true
	g.seen = {"task_init": true}
	await _load()
	var hud = current_scene.hud
	hud._story_q.clear()
	hud.open_modal("gate")
	await _shot("flow_gate")
	hud._begin_big_day()
	await _shot("flow_bigday_story")
	audit_modal("flow_bigday_story")
	hud.close_modal()
	await _shot("flow_bigday_running", 1.2)
	# map during a Big Day: should be blocked
	hud.map_btn.pressed.emit()
	await _shot("flow_map_during_bd", 0.3)
	print("FLOW map during Big Day opened modal '%s'" % hud.modal_kind)
	ok(hud.modal_kind == "", "%s map is blocked during the Big Day" % tag)
	current_scene.world._bd_end(true)
	await _shot("flow_bigday_end", 0.6)
	print("FLOW after bd end modal '%s'" % hud.modal_kind)
	hud.close_modal()
	g.settings.story = false


func _walk() -> void:
	_setup(1, 3)
	await _load()
	var hud = current_scene.hud
	var w = current_scene.world
	_stand(-12.5)
	await _shot("walk_west_label", 0.8)
	_stand(12.5)
	await _shot("walk_east_label", 0.8)
	# modal open, then walking across: open the shop, then cross
	_stand(-14.2)
	await _wait(10)
	hud.open_modal("shop")
	await _shot("walk_modal_before", 0.3)
	w._cross_armed = true
	w._cross(-1)
	var t0 := Time.get_ticks_msec()
	var took := false
	while current_scene.get("crossing") or Time.get_ticks_msec() - t0 < 200:
		await process_frame
		if not took and Time.get_ticks_msec() - t0 > 160:
			took = true
			await _shot("walk_mid_dim", 0.0)
	await _shot("walk_arrival", 0.05)
	await _shot("walk_arrival_settled", 0.6)
	print("WALK venue now %d modal '%s'" % [g.venue, hud.modal_kind])
	ok(g.venue == 2, "%s walked into place 2" % tag)
	audit("walk_arrival", hud.root)
	# modal that survives a walk (settings) then walk back
	hud.close_modal()
	await _wait(5)
	_stand(14.2)
	await _wait(5)
	hud.open_modal("settings")
	current_scene.world._cross_armed = true
	current_scene.world._cross(1)
	await _wait(3)
	await _ready_scene()
	await _shot("walk_settings_kept", 0.5)
	print("WALK back venue %d modal '%s'" % [g.venue, hud.modal_kind])
	if hud.modal:
		audit_modal("walk_settings_kept")
		# tap the X: must close
		var xs: Array = hud.modal.find_children("*", "Control", true, false).filter(func(c): return c.get("clickable") == true)
		hud._close_or_back()
		await _wait(10)
		ok(hud.modal_kind == "", "%s settings closes after a walk" % tag)
	# MAP travel card
	hud.open_modal("empire")
	await create_timer(0.3).timeout
	current_scene.travel_to(2)
	hud.close_modal()
	var t1 := Time.get_ticks_msec()
	var got := false
	while (current_scene.get("crossing") or Time.get_ticks_msec() - t1 < 100) and Time.get_ticks_msec() - t1 < 5000:
		await process_frame
		if not got and Time.get_ticks_msec() - t1 > 120:
			got = true
			await _shot("map_travel_card", 0.0)
	await _shot("map_travel_arrival", 0.6)
	# double MAP travel tap: travel twice quickly
	current_scene.travel_to(0)
	current_scene.travel_to(1)
	var t2 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t2 < 4000:
		await process_frame
	await _ready_scene()
	await _shot("double_travel_end", 0.5)
	print("WALK double travel ended at venue %d" % g.venue)


func _world() -> void:
	# lake (ch 2): jetty, boat, reeds, shortened corridor; oven lane (ch 3); coin pad everywhere
	_setup(2, 4)
	await _load()
	for x in [-12.0, -6.0, 0.0, 6.0, 12.0, 18.0, 24.0, 29.0]:
		_stand(x)
		await _shot("lake_x%d" % int(x), 0.7)
	for z in [6.0, 9.0, 15.0]:
		_stand(20.0, z)
		await _shot("lake_z%d" % int(z), 0.7)
	_setup(3, 4)
	await _load()
	for x in [-10.0, -4.0, 0.0, 4.0, 10.0]:
		_stand(x, 8.0)
		await _shot("lodge_x%d" % int(x), 0.7)
	var w = current_scene.world
	print("LODGE pads: ", w.pads.keys() if w.get("pads") else "?")


func _loading() -> void:
	_setup(4, 5)
	change_scene_to_file("res://scenes/main.tscn")
	var got := 0
	var t0 := Time.get_ticks_msec()
	while got < 3 and Time.get_ticks_msec() - t0 < 20000:
		await process_frame
		if current_scene and current_scene.get_node_or_null("LoadingScreen") != null:
			await create_timer(0.25).timeout
			if current_scene.get_node_or_null("LoadingScreen") != null:
				n += 1
				root.get_texture().get_image().save_png("%s/%s_%02d_loading_%d.png" % [out, tag, n, got])
				print("SHOT loading %d" % got)
				got += 1
	await _ready_scene()
	await _wait(10)
	# new empire reload (loading card over a running place)
	current_scene.reload_venue()
	await _wait(3)
	await create_timer(0.15).timeout
	n += 1
	root.get_texture().get_image().save_png("%s/%s_%02d_loading_reload.png" % [out, tag, n])
	await _ready_scene()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	var wh: PackedStringArray = args[1].split("x")
	tag = args[1]
	root.borderless = true
	root.position = Vector2i(0, 0)
	root.size = Vector2i(int(wh[0]), int(wh[1]))
	await _wait(5)
	var part: String = args[2] if args.size() > 2 else "all"
	g = root.get_node("Game")
	g.saving_enabled = false
	g.offline_reward = 0
	g.settings.story = false
	print("R3T2 window ", DisplayServer.window_get_size(), " ui ", root.get_visible_rect().size, " part ", part)
	if part in ["all", "hud"]:
		await _hud()
	if part in ["all", "modals"]:
		await _modals()
	if part in ["all", "flow"]:
		await _flow()
	if part in ["all", "walk"]:
		await _walk()
	if part in ["all", "world"]:
		await _world()
	if part in ["all", "loading"]:
		await _loading()
	load("res://scripts/world/plot.gd").finish_jobs()
	print("FAILS=%d WARNS=%d" % [fails, warns])
	quit()
