extends SceneTree
## QA round 3, tester 2: touches on every scrolling list and modal, with simulated screen touches (headless).
##   $G --headless --path . -s res://tests/qa/qa_r3_t2_input.gd [-- WxH]
## ME screen / upgrades / map: a drag that starts on a button scrolls and does not press it; buttons inside the
## list still tap after scrolling; tapping the dim closes; side button while a modal is open; the gate START
## button flow with story cards on; double taps on TRAVEL, START, X, COLLECT, CLAIM; modal open then walking.
## Duck-typed. Prints FAILS=n.
var fails := 0
var hud
var g
var w


func ok(c: bool, msg: String) -> void:
	print(("PASS " if c else "FAIL ") + msg)
	if not c:
		fails += 1


func _initialize() -> void:
	_run.call_deferred()


func frames(n: int) -> void:
	for i in n:
		await process_frame


func _win(p: Vector2) -> Vector2:
	return root.get_final_transform() * p


func touch(pos: Vector2, down: bool, idx := 0) -> void:
	var t := InputEventScreenTouch.new()
	t.index = idx
	t.position = _win(pos)
	t.pressed = down
	Input.parse_input_event(t)


func drag(pos: Vector2, rel: Vector2, idx := 0) -> void:
	var d := InputEventScreenDrag.new()
	d.index = idx
	d.position = _win(pos)
	d.relative = rel
	Input.parse_input_event(d)


func tap_at(p: Vector2) -> void:
	touch(p, true)
	await frames(3)
	touch(p, false)
	await frames(3)


func tap(c: Control) -> void:
	await tap_at(c.get_global_rect().get_center())


func double_tap(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	touch(p, true)
	await frames(2)
	touch(p, false)
	await frames(4)     # ~65 ms at 60 fps: a fast double tap
	touch(p, true)
	await frames(2)
	touch(p, false)
	await frames(4)


func swipe(from: Vector2, dy: float) -> void:
	touch(from, true)
	await frames(2)
	var steps := 10
	for i in steps:
		drag(from + Vector2(0, dy * (i + 1) / steps), Vector2(0, dy / steps))
		await frames(1)
	touch(from + Vector2(0, dy), false)
	await frames(6)


func _full(k: int) -> Dictionary:
	var b := {"campfire": true, "tables_1": true, "shop": true, "crew_hut": true, "fire_2": true, "tables_2": true}
	if String(g.chapters[k].get("special", {}).get("type", "")) != "":
		b["special"] = true
	return b


func _scene_ready() -> void:
	await frames(2)
	while current_scene == null or current_scene.get("hud") == null or current_scene.get_node_or_null("LoadingScreen") != null \
			or current_scene.get("crossing"):
		await process_frame
	await frames(10)
	hud = current_scene.hud
	w = current_scene.world
	hud._story_q.clear()
	if hud.modal_kind != "":
		hud.close_modal()
	await create_timer(0.4).timeout


func _setup(k: int, unlocked: int) -> void:
	g.venue = k; g.unlocked = unlocked; g.venues = []; g.cfg = g.chapter_cfg(k)
	g.reno = {}; g.bigday = {}; g.seen = {"task_init": true}; g.task_i = 0; g.task_base = 0; g.chapter_done = false
	g.built = _full(k)
	g.crew = {"lumberjack": 1, "waiter": 1, "cook": 1}
	g.coins = 50_000_000; g.vserved = 9999; g.rating_hist = [4.7]
	while g.venues.size() < unlocked:
		g.venues.append({})
	for j in unlocked:
		if j != k:
			g.venues[j] = {"crew": {"lumberjack": 2, "waiter": 2, "cook": 1}, "built": _full(j), "counter_coins": 900 + 100 * j}


func _btn(label: String, under: Node = null) -> Control:
	var base: Node = under if under else hud.modal
	for l in base.find_children("*", "Label", true, false):
		if String(l.text) == label and l.is_visible_in_tree():
			var p: Node = l
			while p and not p.has_signal("pressed"):
				p = p.get_parent()
			if p:
				return p
	return null


func _scroll() -> ScrollContainer:
	var sc: Array = hud.modal.find_children("*", "ScrollContainer", true, false)
	return sc[0] if not sc.is_empty() else null


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var res: String = args[0] if args.size() > 0 and args[0].contains("x") else "720x1600"
	var wh: PackedStringArray = res.split("x")
	root.size = Vector2i(int(wh[0]), int(wh[1]))
	await frames(3)
	print("INFO window ", DisplayServer.window_get_size(), " ui ", root.get_visible_rect().size)
	g = root.get_node("Game")
	g.saving_enabled = false
	g.offline_reward = 0
	g.settings.story = false

	_setup(2, 4)
	g.levels.tool = g.cfg.tools.size() - 1
	g.levels.bag = g.cfg.bag.size() - 1
	g.levels.boots = g.cfg.boots.size() - 1
	g.pro = {"tool": 3, "bag": 10, "boots": 0}
	change_scene_to_file("res://scenes/main.tscn")
	await _scene_ready()
	g._in_background = true

	# ---------------- ME screen: scroll by dragging from a price button, then tap a wardrobe tab
	await tap(hud.map_btn.get_parent().get_child(2))      # ME (third side button)
	ok(hud.modal_kind == "character", "ME side button opens the character screen (%s)" % hud.modal_kind)
	await create_timer(0.3).timeout
	var sc := _scroll()
	ok(sc != null, "ME screen has a scroll list")
	var coins0: int = g.coins
	var pb: Control = null
	for b in hud.modal.find_children("*", "Control", true, false):
		if b.get("clickable") == true and _in(b, sc) and b.get("disabled") == false:
			var t := ""
			for l in b.find_children("*", "Label", true, false):
				t = String(l.text)
			if t.begins_with("$"):
				pb = b
				break
	if pb:
		await swipe(pb.get_global_rect().get_center(), -300)
		ok(g.coins == coins0, "drag starting on a price button in ME does not buy (coins %d -> %d)" % [coins0, g.coins])
		ok(sc.scroll_vertical > 50, "drag on ME list scrolls it (scroll=%d)" % sc.scroll_vertical)
	else:
		print("INFO no enabled price button in ME list")
	await swipe(sc.get_global_rect().get_center(), -900)
	print("INFO ME scroll after 2nd swipe: %d" % sc.scroll_vertical)
	var hat := _btn("HAT")
	if hat and sc.get_global_rect().encloses(hat.get_global_rect()):
		await tap(hat)
		await frames(4)
		ok(hud._wardrobe_slot == "hat", "HAT tab taps after scrolling (slot=%s)" % hud._wardrobe_slot)
		var sc2 := _scroll()
		print("INFO ME scroll after tab rebuild: %d (was %d)" % [sc2.scroll_vertical if sc2 else -1, sc.scroll_vertical if is_instance_valid(sc) else -1])
	else:
		print("INFO HAT tab not visible inside the list after scrolling; scrolling to it")
		if hat:
			sc.ensure_control_visible(hat)
			await frames(4)
			await tap(hat)
			await frames(4)
			ok(hud._wardrobe_slot == "hat", "HAT tab taps (slot=%s)" % hud._wardrobe_slot)
	# a WEAR / buy item inside the list
	var wear := _btn("WEAR")
	if wear:
		var sc3 := _scroll()
		sc3.ensure_control_visible(wear)
		await frames(4)
		await tap(wear)
		await frames(6)
		print("INFO WEAR tapped; WEARING now shows: ", _btn("WEARING") != null)
	hud._wardrobe_slot = "shirt"
	# dim tap closes
	await tap_at(Vector2(360, 30))
	await frames(10)
	ok(hud.modal_kind == "", "tapping the dim above the ME card closes it (%s)" % hud.modal_kind)

	# ---------------- Upgrades: scroll from a price button
	hud.open_modal("upgrades")
	await create_timer(0.4).timeout
	sc = _scroll()
	print("INFO upgrades has scroll: ", sc != null)
	if sc:
		var lv0: Dictionary = g.vstation_levels() if g.has_method("vstation_levels") else {}
		var up: Control = null
		for b in hud.modal.find_children("*", "Control", true, false):
			if b.get("clickable") == true and _in(b, sc) and b.get("disabled") == false:
				up = b
				break
		var c0: int = g.coins
		if up:
			await swipe(up.get_global_rect().get_center(), -200)
			ok(g.coins == c0, "drag from an upgrade price button does not buy")
	# side button tap while a modal is open: closes and opens that one
	var jobs_c: Vector2 = hud.jobs_btn.get_global_rect().get_center()
	await tap_at(jobs_c)
	await frames(10)
	ok(hud.modal_kind == "jobs", "JOBS side button while Upgrades is open switches to Jobs (%s)" % hud.modal_kind)
	# X closes
	var x := _btn("✕")
	if x:
		await double_tap(x)
		await frames(10)
		ok(hud.modal_kind == "", "double-tapping X closes cleanly (%s)" % hud.modal_kind)
		ok(not hud.joy.blocked, "joystick unblocked after closing")

	# ---------------- modal open, then try to walk: joystick blocked
	hud.open_modal("crew")
	await create_timer(0.3).timeout
	var p0: Vector3 = w.player.global_position
	var start := Vector2(200, root.get_visible_rect().size.y - 200)
	touch(start, true)
	await frames(2)
	drag(start + Vector2(-80, 0), Vector2(-80, 0))
	await create_timer(0.5).timeout
	touch(start + Vector2(-80, 0), false)
	await frames(4)
	ok(w.player.global_position.distance_to(p0) < 0.2, "player does not walk while a modal is open (moved %.2f)" % w.player.global_position.distance_to(p0))
	print("INFO after dragging on the dim the modal is '%s'" % hud.modal_kind)
	if hud.modal_kind != "":
		hud.close_modal()
	await frames(10)

	# ---------------- map: double tap TRAVEL
	hud.open_modal("empire")
	await create_timer(0.4).timeout
	var tr := _btn("TRAVEL")
	ok(tr != null, "map has TRAVEL")
	var v0: int = g.venue
	if tr:
		var sc4 := _scroll()
		sc4.ensure_control_visible(tr)
		await frames(4)
		await double_tap(tr)
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 4000:
			await process_frame
		await _scene_ready()
		print("INFO double-tap TRAVEL: venue %d -> %d" % [v0, g.venue])
		ok(g.venue != v0, "TRAVEL works")
	# ---------------- gate START with story on: the real buttons
	_setup(1, 2)
	g.settings.story = true
	g.seen = {"task_init": true}
	change_scene_to_file("res://scenes/main.tscn")
	await _scene_ready()
	hud._story_q.clear()
	hud.open_modal("gate")
	await create_timer(0.4).timeout
	var st: Control = null
	for b in hud.modal.find_children("*", "Control", true, false):
		if b.get("clickable") == true:
			for l in b.find_children("*", "Label", true, false):
				if String(l.text).begins_with("START"):
					st = b
	ok(st != null, "gate has a START button")
	if st:
		await double_tap(st)
		await frames(10)
		print("INFO after START (double tap): modal '%s' bd_active %s story_q %d" % [hud.modal_kind, w.bd_active, hud._story_q.size()])
		if hud.modal_kind == "story":
			ok(not w.bd_active, "Big Day clock waits for the story card")
			var okb := _btn("OK")
			if okb == null:
				okb = _btn("NEXT")
			await double_tap(okb)
			await frames(10)
			print("INFO after OK: modal '%s' bd_active %s" % [hud.modal_kind, w.bd_active])
		ok(w.bd_active, "Big Day running after START")
		ok(hud.modal_kind == "", "no modal left over the Big Day (%s)" % hud.modal_kind)
		# MAP during the Big Day
		await tap(hud.map_btn)
		await frames(6)
		ok(hud.modal_kind == "", "MAP blocked during Big Day")
		# walk the player east during the Big Day: crossing blocked
	g.settings.story = false

	# ---------------- offline COLLECT double tap
	if hud.modal_kind != "":
		hud.close_modal()
	w.bd_active = false
	await frames(5)
	g.offline_reward = 1000
	var c1: int = g.coins
	hud.open_modal("offline")
	await create_timer(0.4).timeout
	var col := _btn("COLLECT")
	await double_tap(col)
	await frames(10)
	ok(g.coins - c1 == 1000, "double-tapping COLLECT pays once (+%d)" % (g.coins - c1))
	ok(hud.modal_kind == "", "COLLECT closes")

	# ---------------- confirm screens: does the destructive button land where the first button was?
	# (no tap on the destructive one: reset_all deletes the save file)
	await _confirm_overlap("settings", "Reset progress", "Erase")
	_setup(5, 6)
	g.bigday = {"won": true}
	g.chapter_done = true
	await _confirm_overlap("complete", "START NEW EMPIRE  (+50%)", "Start over")

	load("res://scripts/world/plot.gd").finish_jobs()
	print("FAILS=%d" % fails)
	quit(1 if fails > 0 else 0)


func _confirm_overlap(kind: String, first: String, danger: String) -> void:
	if hud.modal_kind != "":
		hud.close_modal()
	await frames(5)
	hud.open_modal(kind)
	await create_timer(0.4).timeout
	var a := _btn(first)
	if a == null:
		ok(false, "%s: no '%s' button" % [kind, first])
		return
	var ra: Rect2 = a.get_global_rect()
	await tap(a)
	await frames(4)
	var b := _btn(danger)
	if b == null:
		ok(false, "%s: no '%s' after tapping '%s'" % [kind, danger, first])
		return
	var rb: Rect2 = b.get_global_rect()
	# the click area of a button is its rect grown by 24 px (ui_shape.gd), so a second tap anywhere on `first`
	# that lands in `danger` grown by 24 presses it
	var hit := ra.intersection(rb.grow(24.0))
	print("INFO %s: '%s' %s, then '%s' %s, overlap %s" % [kind, first, ra, danger, rb, hit.size])
	ok(hit.size.x < 1 or hit.size.y < 1, "%s: a quick second tap on '%s' cannot press '%s' (overlap %.0fx%.0f px)" % [kind, first, danger, hit.size.x, hit.size.y])
	hud._confirm_reset = false
	hud._confirm_prestige = false
	hud.close_modal()
	await frames(5)


func _in(c: Node, sc: Node) -> bool:
	return sc != null and sc.is_ancestor_of(c)
