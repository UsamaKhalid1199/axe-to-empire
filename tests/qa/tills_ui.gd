extends SceneTree
## "Cash waiting" chip and the map's till rows.
## Run: godot --headless --path . -s res://tests/qa/tills_ui.gd
## The chip names the place with the most cash on its counter, hides at 0 and during a Big Day,
## a tap opens the map, the map shows each place's till and cap, and the chip stays clear of the
## goal pill, the task card, the side buttons and the Big Day banner.
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


func settle() -> void:
	await create_timer(0.35).timeout      # the HUD batches till updates 4x a second


func tap(c: Control) -> void:
	var pos: Vector2 = root.get_final_transform() * c.get_global_rect().get_center()
	for down in [true, false]:
		var t := InputEventScreenTouch.new()
		t.index = 0
		t.position = pos
		t.pressed = down
		Input.parse_input_event(t)
		await frames(3)


func _find_text(n: Node, txt: String) -> Node:
	if n is Label and String(n.text).contains(txt):
		return n
	for c in n.get_children():
		var f := _find_text(c, txt)
		if f:
			return f
	return null


func set_tills(a: int, b: int) -> void:
	g.venues[0]["counter_coins"] = a
	g.venues[2]["counter_coins"] = b
	g.tills_changed.emit()
	await settle()


func _run() -> void:
	g = root.get_node("Game")
	g.saving_enabled = false
	g.offline_reward = 0
	g.settings.story = false
	g.venue = 1; g.unlocked = 3; g.venues = []; g.cfg = g.chapter_cfg(1)
	g.reno = {}; g.bigday = {}; g.seen = {"task_init": true}; g.task_i = 0; g.task_base = 0
	g.built = {"campfire": true, "tables_1": true, "shop": true, "crew_hut": true, "fire_2": true, "tables_2": true, "special": true}
	g.crew = {"lumberjack": 1, "waiter": 1, "cook": 1}
	g.coins = 5000
	change_scene_to_file("res://scenes/main.tscn")
	while current_scene == null or current_scene.get("hud") == null or current_scene.get_node_or_null("LoadingScreen") != null:
		await process_frame
	await frames(10)
	hud = current_scene.hud
	w = current_scene.world
	hud._story_q.clear()
	if hud.modal_kind != "":
		hud.close_modal()
	g._in_background = true             # freeze background income so the amounts stay put
	# two other places you own, with crews (so they have a rate and a cap)
	while g.venues.size() < 3:
		g.venues.append({})
	var crew := {"crew": {"lumberjack": 2, "waiter": 2, "cook": 1}, "built": {"campfire": true, "tables_1": true, "crew_hut": true}}
	g.venues[0] = crew.duplicate(true)
	g.venues[2] = crew.duplicate(true)
	g.venues[2]["built"]["special"] = true

	await set_tills(0, 0)
	ok(g.tills_waiting() == 0 and not hud.till_chip.visible, "chip hidden when nothing is waiting")

	await set_tills(12300, 800)
	ok(hud.till_chip.visible, "chip shows when cash is waiting")
	ok(hud.till_k == 0, "chip points at the place with the most (k=%d)" % hud.till_k)
	ok(hud.till_label.text == "$12.3K waiting at Forest Camp", "chip text: '%s'" % hud.till_label.text)

	await set_tills(12300, 20000)
	ok(hud.till_k == 2 and hud.till_label.text == "$20K waiting at Lakeside Diner", "chip follows the biggest till: '%s'" % hud.till_label.text)

	# layout: clear of the goal pill, the task card, every side button and the Big Day banner
	var cr: Rect2 = hud.till_chip.get_global_rect()
	ok(cr.size.y >= 64.0, "chip is a big enough tap target (%.0f px tall)" % cr.size.y)
	ok(cr.end.x <= hud._vw() and cr.position.x >= 0.0, "chip fits on screen (%s)" % cr)
	var others := {"goal pill": hud.goal_pill, "task card": hud.task_card, "Big Day banner": hud.bd_banner}
	for holder in hud.jobs_btn.get_parent().get_parent().get_children():
		for c in [holder] + holder.get_children():
			if c is Control and c.has_signal("pressed") and c.visible:
				others["side button " + str(c.get_instance_id())] = c
	for nm in others:
		var o: Control = others[nm]
		ok(not cr.intersects(o.get_global_rect()), "chip clear of %s (%s vs %s)" % [nm, cr, o.get_global_rect()])

	# tap -> map
	await tap(hud.till_chip)
	ok(hud.modal_kind == "empire", "tapping the chip opens the map (modal=%s)" % hud.modal_kind)
	await frames(3)
	ok(not hud.till_chip.visible, "chip hidden while a modal is open")
	var t0 = hud.modal.find_child("Till0", true, false)
	var t2 = hud.modal.find_child("Till2", true, false)
	ok(t0 != null and t2 != null, "map has a till row for each other place")
	ok(hud.modal.find_child("Till1", true, false) == null, "no till row for the place you're at")
	if t0 and t2:
		var l0: String = t0.get_node("TillText").text
		var l2: String = t2.get_node("TillText").text
		var cap0: int = g.till_cap(0)
		# (a till at or over its cap reads "$X · FULL", like the chip, instead of an over-the-cap "$X / $cap")
		var want0: bool = l0.contains("FULL") if 12300 >= cap0 else l0.contains(_cash(cap0))
		ok(l0.contains("$12.3K") and want0, "map row 1 till: '%s' (cap %d)" % [l0, cap0])
		ok(l2.contains("$20K"), "map row 3 till: '%s'" % l2)
		var bar: ProgressBar = t2.get_child(1)
		ok(is_equal_approx(bar.value, 20000.0) or bar.value == bar.max_value, "row 3 bar shows the till (%s / %s)" % [bar.value, bar.max_value])
	ok(_find_text(hud.modal, "while you play") != null, "map says 'earns ... while you play'")
	ok(_find_text(hud.modal, "away") == null, "map no longer talks about being away")
	ok(_find_text(hud.modal, "TRAVEL") != null, "fast-travel buttons kept")
	# the open map updates its rows in place when a till changes
	await set_tills(5000, 20000)
	if t0:
		ok(String(t0.get_node("TillText").text).contains("$5,000"), "open map row updates in place: '%s'" % t0.get_node("TillText").text)
	hud.close_modal()
	await settle()
	ok(hud.till_chip.visible and hud.till_k == 2, "chip back after closing the map")

	# Big Day: hidden, and a tap can't open the map
	w._bd_cool = 0.0
	var started: bool = w.start_big_day()
	if not started:
		w.bd_active = true
	await frames(3)
	ok(not hud.till_chip.visible, "chip hidden during a Big Day")
	hud.till_chip.pressed.emit()
	await frames(2)
	ok(hud.modal_kind != "empire", "chip can't open the map during a Big Day")
	w.bd_active = false
	await settle()
	ok(hud.till_chip.visible, "chip returns after the Big Day")

	await set_tills(0, 0)
	ok(not hud.till_chip.visible and hud.till_k == -1, "chip hides again at 0")
	print("TILLS fails=%d" % fails)
	quit()


func _cash(n: float) -> String:
	var v := absf(n)
	for u in [[1e15, "Q"], [1e12, "T"], [1e9, "B"], [1e6, "M"]]:
		if v >= u[0]:
			var s := "%.2f" % (n / u[0])
			return "$" + s.rstrip("0").rstrip(".") + u[1]
	if v >= 10_000:
		var s := "%.1f" % (n / 1000.0)
		return "$" + (s.rstrip("0").rstrip(".") if s.contains(".") else s) + "K"
	if v >= 1000:
		return "$%d,%03d" % [int(n) / 1000, int(n) % 1000]
	return "$" + str(int(n))
