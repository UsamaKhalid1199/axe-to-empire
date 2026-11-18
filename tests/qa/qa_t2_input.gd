extends SceneTree
## QA tester 2: touch input for the one-road world, with simulated screen touches.
##   $G --headless --path . -s res://tests/qa/qa_t2_input.gd
## Covers: cash chip tap -> map; map TRAVEL row tap; a drag that starts on TRAVEL only scrolls; HERE/LOCKED rows
## do nothing; the joystick does not start on the chip; walking (joystick) into a FOR SALE fence opens the gate
## prompt and pushing on the barrier explains why; walking (joystick) across an owned edge switches place and
## does not bounce straight back.
var fails := 0
var hud
var g
var w
var toasts: Array = []


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


func tap(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	touch(p, true)
	await frames(3)
	touch(p, false)
	await frames(3)


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
	await frames(3)


func _setup(k: int, unlocked: int) -> void:
	g.venue = k; g.unlocked = unlocked; g.venues = []; g.cfg = g.chapter_cfg(k)
	g.reno = {}; g.bigday = {}; g.seen = {"task_init": true}; g.task_i = 0; g.task_base = 0; g.chapter_done = false
	g.built = _full(k)
	g.crew = {"lumberjack": 1, "waiter": 1, "cook": 1}
	g.coins = 5000; g.vserved = 10
	while g.venues.size() < unlocked:
		g.venues.append({})
	for j in unlocked:
		if j != k:
			g.venues[j] = {"crew": {"lumberjack": 2, "waiter": 2, "cook": 1}, "built": _full(j), "counter_coins": 900 + 100 * j}


func _button_in(row_title: String, label: String) -> Control:
	# the UIShape button whose label reads `label`, in the map row titled `row_title`
	for l in hud.modal.find_children("*", "Label", true, false):
		if String(l.text) == row_title:
			var row: Node = l
			for i in 6:
				row = row.get_parent()
				for b in row.find_children("*", "Label", true, false):
					if String(b.text) == label:
						var p: Node = b
						while p and not p.has_signal("pressed"):
							p = p.get_parent()
						if p:
							return p
	return null


## Hold the joystick in direction dir (screen px) for secs, then let go.
func walk(dir: Vector2, secs: float) -> void:
	var start := Vector2(360, hud._vw() * 0 + root.get_visible_rect().size.y - 300)
	touch(start, true, 0)
	await frames(2)
	drag(start + dir, dir, 0)
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(secs * 1000.0):
		await process_frame
		if current_scene.get("crossing"):
			break
	touch(start + dir, false, 0)
	await frames(3)


func _run() -> void:
	root.size = Vector2i(720, 1600)
	await frames(3)
	print("INFO window ", DisplayServer.window_get_size(), " ui ", root.get_visible_rect().size)
	g = root.get_node("Game")
	g.saving_enabled = false
	g.offline_reward = 0
	g.settings.story = false
	g.toast.connect(func(m): toasts.append(String(m)))

	# ---------------- 1. chip and map rows: Roadside Shack, camp (east) and lake (west) owned
	_setup(1, 3)
	change_scene_to_file("res://scenes/main.tscn")
	await _scene_ready()
	g._in_background = true
	g.tills_changed.emit()
	await create_timer(0.4).timeout
	ok(hud.till_chip.visible, "chip visible with cash waiting ('%s')" % hud.till_label.text)
	# a touch on the chip must not also start the joystick
	var cp: Vector2 = hud.till_chip.get_global_rect().get_center()
	touch(cp, true)
	await frames(3)
	ok(not hud.joy.active, "joystick does not grab a touch that lands on the chip")
	touch(cp, false)
	await frames(4)
	ok(hud.modal_kind == "empire", "chip tap opens the map (modal='%s')" % hud.modal_kind)
	await create_timer(0.3).timeout
	# HERE and LOCKED do nothing
	var here := _button_in("2. Roadside Shack", "HERE")
	ok(here != null, "map has a HERE button on the current place")
	if here:
		await tap(here)
		ok(hud.modal_kind == "empire" and g.venue == 1, "tapping HERE keeps the map open and stays put")
	var locked := _button_in("4. Mountain Lodge", "LOCKED")
	ok(locked != null, "map has LOCKED on a place not bought")
	if locked:
		await tap(locked)
		ok(hud.modal_kind == "empire" and g.venue == 1, "tapping LOCKED does nothing")
	# tap target sizes in the map
	var travel := _button_in("1. Forest Camp", "TRAVEL")
	ok(travel != null, "map has TRAVEL on Forest Camp")
	if travel:
		var r: Rect2 = travel.get_global_rect()
		ok(r.size.y >= 64.0 and r.size.x >= 120.0, "TRAVEL is a big enough target (%s)" % r.size)
		# a drag that starts on TRAVEL scrolls the list instead of travelling
		var c := r.get_center()
		touch(c, true)
		await frames(2)
		for i in 8:
			drag(c + Vector2(0, -15 * (i + 1)), Vector2(0, -15))
			await frames(1)
		touch(c + Vector2(0, -120), false)
		await frames(6)
		ok(hud.modal_kind == "empire" and g.venue == 1, "drag starting on TRAVEL does not travel (venue=%d modal=%s)" % [g.venue, hud.modal_kind])
		var sc: Array = hud.modal.find_children("*", "ScrollContainer", true, false)
		print("INFO map scroll after drag: ", sc[0].scroll_vertical if not sc.is_empty() else -1)
		# the same drag starting on a row's text (not a button) does scroll
		var desc: Control = null
		for l in hud.modal.find_children("*", "Label", true, false):
			if String(l.text).begins_with("Smash burgers"):
				desc = l
		if desc and not sc.is_empty():
			var d0: Vector2 = desc.get_global_rect().get_center()
			touch(d0, true)
			await frames(2)
			for i in 8:
				drag(d0 + Vector2(0, -15 * (i + 1)), Vector2(0, -15))
				await frames(1)
			touch(d0 + Vector2(0, -120), false)
			await frames(6)
			print("INFO map scroll after a drag on row text: %d (max %d)" % [sc[0].scroll_vertical, sc[0].get_v_scroll_bar().max_value - sc[0].size.y])
		# scroll back and tap TRAVEL for real
		if not sc.is_empty():
			sc[0].scroll_vertical = 0
		await frames(4)
		travel = _button_in("1. Forest Camp", "TRAVEL")
		await tap(travel)
		await _scene_ready()
		ok(g.venue == 0, "tapping TRAVEL goes to Forest Camp (venue=%d)" % g.venue)
		var px: float = w.player.global_position.x
		ok(px < -10.0 and absf(w.player.global_position.z - 11.5) < 1.5, "MAP trip from the shack (west) arrives on the road at the west edge (x=%.1f)" % px)
		ok(not w.player.global_position.x < -15.5, "arrival is inside the plot")

	# ---------------- 2. FOR SALE fence: Roadside Shack, lake not bought, gate pad up
	_setup(1, 2)
	g.vserved = 9999
	change_scene_to_file("res://scenes/main.tscn")
	await _scene_ready()
	ok(w.fence_zone != null, "FOR SALE neighbour has a gate prompt at the fence (pads.gate=%s)" % w.pads.has("gate"))
	w.player.global_position = Vector3(-11.0, 0, 11.5)
	w._cam_target = w.player.global_position
	await frames(5)
	toasts.clear()
	await walk(Vector2(-90, 0), 2.5)
	await create_timer(0.6).timeout
	print("INFO after walking west: x=%.2f modal='%s' toasts=%s" % [w.player.global_position.x, hud.modal_kind, toasts])
	ok(w.player.global_position.x > -15.6, "the barrier stops the player at the FOR SALE edge (x=%.2f)" % w.player.global_position.x)
	ok(hud.modal_kind == "gate", "stopping at the fence opens the gate prompt (modal='%s')" % hud.modal_kind)
	if hud.modal_kind != "":
		var close_btn: Control = null
		for b in hud.modal.find_children("*", "Control", true, false):
			if b.has_signal("pressed") and b.get_global_rect().size.x < 120 and b.get_global_rect().position.y < hud.modal.get_global_rect().size.y * 0.5:
				close_btn = b
				break
		if close_btn:
			await tap(close_btn)
		else:
			hud.close_modal()
		await frames(5)
	ok(hud.modal_kind == "", "gate prompt closes with X")
	# keep pushing on the barrier: a toast explains why
	await walk(Vector2(-90, 0), 1.5)
	await create_timer(0.3).timeout
	var said := toasts.filter(func(m): return m.contains("for sale"))
	ok(not said.is_empty(), "pushing on the barrier explains it (toasts=%s, modal='%s')" % [toasts, hud.modal_kind])

	# ---------------- 3. walk across an owned edge with the joystick, then turn round
	_setup(1, 3)
	change_scene_to_file("res://scenes/main.tscn")
	await _scene_ready()
	w.player.global_position = Vector3(-12.5, 0, 11.5)
	await frames(5)
	await walk(Vector2(-90, 0), 4.0)
	await _scene_ready()
	ok(g.venue == 2, "walking west off the road enters the Lakeside Diner (venue=%d)" % g.venue)
	print("INFO arrived at x=%.2f armed=%s last_cross_ms=%.0f" % [w.player.global_position.x, w._cross_armed, current_scene.last_cross_ms])
	# immediately walk back east: must not bounce until stepping inside and back out
	await walk(Vector2(90, 0), 0.3)
	ok(g.venue == 2 and not current_scene.crossing, "no instant bounce back after arriving (venue=%d)" % g.venue)
	await walk(Vector2(-90, 0), 0.8)          # step inside first (the edge re-arms 1.2 m in)
	await walk(Vector2(90, 0), 4.0)
	await _scene_ready()
	ok(g.venue == 1, "walking back east returns to the shack (venue=%d)" % g.venue)

	load("res://scripts/world/plot.gd").finish_jobs()
	print("RESULT qa_t2_input fails=%d" % fails)
	quit(1 if fails > 0 else 0)
