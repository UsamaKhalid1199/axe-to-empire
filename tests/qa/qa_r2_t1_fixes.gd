extends SceneTree
## QA round 2, tester 1: targeted re-checks of round-1 fixes that need the scene.
##  1. tills_changed is throttled to ~4/s (6 places earning in the background)
##  2. guest + drive-thru car patience holds while a modal / story card is open, and resumes after
##  3. story cards: at most one per 45 s of play
## Run: $G --headless --path . -s res://tests/qa/qa_r2_t1_fixes.gd
var fails := 0
var g


func ok(c: bool, msg: String) -> void:
	print(("PASS " if c else "FAIL ") + msg)
	if not c:
		fails += 1


func _initialize() -> void:
	_run.call_deferred()


func _full(k: int) -> Dictionary:
	var b := {"campfire": true, "tables_1": true, "shop": true, "crew_hut": true, "fire_2": true, "tables_2": true}
	if String(g.chapters[k].get("special", {}).get("type", "")) != "":
		b["special"] = true
	return b


func _run() -> void:
	g = root.get_node("Game")
	g.saving_enabled = false
	g.settings.story = false            # no real story cards during the patience checks (turned on for section 3)
	var k := 1
	g.prestige = 0
	g.unlocked = 6
	g.venues = []
	for i in 6:
		var vd := {"built": _full(i), "crew": {"lumberjack": 3, "waiter": 2, "cook": 2}, "menu": 6, "fire": 6}
		g.venues.append(vd)
	g.venue = k
	g._unstash(k)
	g._cc_cache.clear()
	g.cfg = g.chapter_cfg(k)
	g.levels.station = 0
	g.woodpile = 20; g.rack = 0; g.counter_coins = 0; g.offline_reward = 0; g.sp = {}
	g.seen = {"task_init": true, "hired_any": true}
	g.task_i = 13
	g.bigday = {"won": true, "clean": true}
	change_scene_to_file("res://scenes/main.tscn")
	while current_scene == null or current_scene.get("hud") == null or current_scene.get_node_or_null("LoadingScreen") != null:
		await process_frame
	for i in 5:
		await process_frame
	var w = current_scene.world
	var hud = current_scene.hud
	if hud.modal_kind != "":
		hud.close_modal()
	hud._story_q.clear()
	await process_frame

	# --- 1. tills_changed rate
	var n := [0]
	g.tills_changed.connect(func(): n[0] += 1)
	for i in 6:
		if i != k:
			g.venues[i]["counter_coins"] = 0
	var t0 := Time.get_ticks_msec()
	await create_timer(10.0).timeout
	var secs := 10.0
	ok(n[0] > 0 and n[0] <= int(secs * 4.0) + 2, "tills_changed fired %d times in %.0f s of play (<= ~4/s)" % [n[0], secs])

	# --- 2. drive-thru car + guest patience under a modal
	var sp = w.specials
	sp._car_t = 9999.0
	for c in sp.cars:
		c.node.queue_free()
	sp.cars.clear()
	sp._spawn_car()
	sp.cars[-1].order = 4
	await create_timer(5.0).timeout
	var car: Dictionary = sp.cars[-1]
	ok(car.state == "wait", "car waiting at the window (%s)" % car.state)
	hud.open_modal("upgrades")
	var cw0: float = car.waited
	var guest = null
	for c in w.queue:
		if is_instance_valid(c) and c.state == "queue":
			guest = c
	var gw0: float = guest.waited if guest else 0.0
	await create_timer(8.0).timeout
	ok(absf(car.waited - cw0) < 0.01, "car patience holds under a modal (%.2f -> %.2f)" % [cw0, car.waited])
	if guest and is_instance_valid(guest) and guest.state == "queue":
		ok(absf(guest.waited - gw0) < 0.01, "guest patience holds under a modal (%.2f -> %.2f)" % [gw0, guest.waited])
	hud.close_modal()
	await create_timer(3.0).timeout
	ok(car.waited > cw0 + 2.0 or car.state != "wait", "car patience runs again after the modal closes (%.2f, state %s, modal '%s', world sees '%s')" % [car.waited, car.state, hud.modal_kind, w.modal_kind])
	# story card counts as a modal too
	g.settings.story = true
	hud._story_last_s = -1000.0
	g.story.emit([{"who": "mags", "text": "test card one"}])
	await create_timer(0.5).timeout
	ok(hud.modal_kind == "story", "story card opened (%s)" % hud.modal_kind)
	var cw1: float = car.waited
	await create_timer(4.0).timeout
	ok(absf(car.waited - cw1) < 0.01 or car.state != "wait", "car patience holds under a story card (%.2f -> %.2f)" % [cw1, car.waited])

	# --- 3. story pacing: the next card waits 45 s of play after the last one closed
	g.story.emit([{"who": "rosa", "text": "test card two"}])
	hud._story_q[0].text = "test card one"
	# close card one like the OK button does
	hud._story_q.pop_front()
	hud._story_last_s = hud._play_s
	hud.close_modal()
	var closed_at: float = hud._play_s
	var opened_at := -1.0
	var guard := 0.0
	while guard < 70.0:
		await create_timer(0.5).timeout
		guard += 0.5
		if hud.modal_kind == "story":
			opened_at = hud._play_s
			break
	print("INFO second story card opened %.1f s of play after the first closed" % (opened_at - closed_at))
	ok(opened_at > 0.0 and opened_at - closed_at >= 44.5, "second card waited >= 45 s (%.1f)" % (opened_at - closed_at))
	if hud.modal_kind != "":
		hud.close_modal()
	print("RESULT qa_r2_t1_fixes: %d fail(s)" % fails)
	quit()
