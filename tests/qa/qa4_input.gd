extends SceneTree
## QA #4: touch/tap reliability on HUD buttons and modal close X.
## Run: godot --headless --path . -s res://tests/qa/qa4_input.gd
var fails := 0
var hud
var g


func ok(c: bool, msg: String) -> void:
	print(("PASS " if c else "FAIL ") + msg)
	if not c:
		fails += 1


func _initialize() -> void:
	_run.call_deferred()


func frames(n: int) -> void:
	for i in n:
		await process_frame


func touch(idx: int, pos: Vector2, down: bool) -> void:
	var t := InputEventScreenTouch.new()
	t.index = idx
	t.position = pos
	t.pressed = down
	Input.parse_input_event(t)


func tap(pos: Vector2, idx := 0, hold := 3) -> void:
	touch(idx, pos, true)
	await frames(hold)
	touch(idx, pos, false)
	await frames(2)


func center(c: Control) -> Vector2:
	# canvas (UI) coords -> window coords the input system expects
	return root.get_final_transform() * c.get_global_rect().get_center()


func find_x() -> Control:
	if hud.modal == null:
		return null
	for n in hud.modal.find_children("*", "Label", true, false):
		if n.text == "✕":
			return n.get_parent()
	return null


func settle() -> void:
	if hud.modal_kind != "":
		hud.close_modal()
	await create_timer(0.3).timeout


func _run() -> void:
	g = root.get_node("Game")
	g.saving_enabled = false
	g.offline_reward = 0
	g.settings.story = false
	change_scene_to_file("res://scenes/main.tscn")
	while current_scene == null or current_scene.get("hud") == null or current_scene.get_node_or_null("LoadingScreen") != null:
		await process_frame
	await frames(20)
	hud = current_scene.hud
	hud._story_q.clear()
	await settle()
	print("viewport visible rect ", root.get_visible_rect(), " final xf ", root.get_final_transform(), " win ", DisplayServer.window_get_size(), " emulate_mouse_from_touch=", Input.emulate_mouse_from_touch)
	var kinds := ["shop", "crew", "upgrades", "character", "jobs", "settings"]
	var cc := [0]
	g.coins_changed.connect(func(_v): cc[0] += 1)
	print("INFO save loaded: venue=%d unlocked=%d empire_rate=%.1f/s" % [g.venue, g.unlocked, g.empire_rate()])
	cc[0] = 0
	await create_timer(5.0).timeout
	print("INFO LIVE: coins_changed fired %d times in 5 s (~%.1f per frame at 60fps)" % [cc[0], cc[0] / 300.0])
	# A0: live income, X on each modal (this is the player's real state)
	for k in kinds:
		hud.open_modal(k)
		await create_timer(0.25).timeout
		var x0 := find_x()
		cc[0] = 0
		await tap(center(x0), 0, 6)   # ~100 ms finger contact
		ok(hud.modal_kind == "", "A0 LIVE income: tap X closes '%s' (coins_changed during tap=%d)" % [k, cc[0]])
		await settle()
	g._in_background = true          # pause empire income for the controlled tests below
	cc[0] = 0
	await create_timer(3.0).timeout
	print("INFO QUIET: coins_changed in 3 s with empire paused: %d" % cc[0])

	# A: baseline — tap X on each modal
	for k in kinds:
		hud.open_modal(k)
		await create_timer(0.25).timeout
		var x := find_x()
		if x == null:
			print("  (no X in ", k, ")")
			await settle()
			continue
		await tap(center(x))
		ok(hud.modal_kind == "", "A baseline: tap X closes '%s'" % k)
		await settle()

	# B: coins change (crew/customer/empire income) between finger-down and finger-up on X
	for k in ["shop", "crew", "upgrades", "character"]:
		hud.open_modal(k)
		await create_timer(0.25).timeout
		var x := find_x()
		var p := center(x)
		touch(0, p, true)
		await frames(3)
		g.add_coins(5)            # what sell_log_from / card_paid / _empire_tick do mid-tap
		await frames(2)
		touch(0, p, false)
		await frames(2)
		ok(hud.modal_kind == "", "B: tap X on '%s' while coins change mid-tap (still open=%s)" % [k, hud.modal_kind])
		await settle()

	# B2: a price/buy button during coin change
	g.coins = 100000
	hud.open_modal("upgrades")
	await create_timer(0.25).timeout
	var before: int = g.coins
	var btn: Control = null
	for n in hud.modal.find_children("*", "UIShape", true, false):
		if n.clickable and not n.disabled and n != find_x() and n.is_visible_in_tree() and root.get_visible_rect().has_point(n.get_global_rect().get_center()):
			btn = n
			break
	if btn:
		var bp := center(btn)
		touch(0, bp, true)
		await frames(3)
		g.add_coins(5)
		await frames(2)
		touch(0, bp, false)
		await frames(2)
		ok(g.coins < before, "B2: buy button in upgrades works while coins change mid-tap (coins %d -> %d)" % [before, g.coins])
	await settle()

	# C: joystick thumb held (finger 0), modal opens, X tapped with finger 1
	touch(0, Vector2(360, 1100), true)
	await frames(3)
	hud.open_modal("settings")
	await create_timer(0.25).timeout
	var xc := center(find_x())
	await tap(xc, 1)
	ok(hud.modal_kind == "", "C: second finger taps X while thumb still on screen")
	touch(0, Vector2(360, 1100), false)
	await frames(3)
	await settle()
	# C2: same with a side button (run with thumb, tap JOBS with other thumb)
	touch(0, Vector2(360, 1100), true)
	await frames(3)
	await tap(center(hud.jobs_btn), 1)
	ok(hud.modal_kind == "jobs", "C2: second finger taps JOBS while running (kind='%s')" % hud.modal_kind)
	touch(0, Vector2(360, 1100), false)
	await frames(3)
	await settle()

	# D: tap a side button right after closing a modal (old modal still fading, 0.12 s)
	hud.open_modal("settings")
	await create_timer(0.25).timeout
	await tap(center(find_x()), 0, 2)
	ok(hud.modal_kind == "", "D: X closed settings")
	await tap(center(hud.jobs_btn), 0, 2)
	ok(hud.modal_kind == "jobs", "D: JOBS tapped ~4 frames after closing a modal opens jobs (kind='%s')" % hud.modal_kind)
	await settle()

	# E: double-tap a side button
	await tap(center(hud.jobs_btn), 0, 2)
	await tap(center(hud.jobs_btn), 0, 2)
	await create_timer(0.3).timeout
	ok(hud.modal_kind == "jobs", "E: double-tap JOBS leaves jobs open (kind='%s')" % hud.modal_kind)
	await settle()

	# F: tap X during the 0.15 s open fade
	hud.open_modal("settings")
	await frames(2)
	await tap(center(find_x()), 0, 2)
	ok(hud.modal_kind == "", "F: tap X during open fade")
	await settle()

	# H: X with 100 ms contact, income live, jobs modal (jobs_changed via 'earn' job)
	g._in_background = false
	print("INFO jobs: ", g.jobs.map(func(j): return j.id))
	hud.open_modal("jobs")
	await create_timer(0.25).timeout
	await tap(center(find_x()), 0, 6)
	ok(hud.modal_kind == "", "H LIVE: X on jobs with income live")
	await settle()
	# G: how often does the shop modal rebuild during normal play (crew working)?
	g.crew = {"lumberjack": 2, "waiter": 1, "cook": 1}
	var n := [0]
	g.coins_changed.connect(func(_v): n[0] += 1)
	await create_timer(10.0).timeout
	print("INFO coins_changed in 10 s of ch1 play with crew: ", n[0], "  empire_rate=", g.empire_rate())
	print("DONE fails=", fails)
	quit(fails)
