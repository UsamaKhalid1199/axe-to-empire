extends SceneTree
## QA t2/t3 UI fixes:
##   $G --headless --path . -s res://tests/qa/ui_fixes_t2.gd
## ME screen with gear in Pro and at Pro max; drags that start on a button (or a row) scroll the list on touch and
## never press the button, while a still tap still clicks; map card width, no-crew rows and the short till text;
## GO TO on a finished gate travels; New Empire confirm has no third button; "mastered" only with 3 stars;
## thousands separators; ✕ on Stats / How to play goes back to Settings; story cards are paced; toasts wrap evenly.
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


func tap(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	touch(p, true)
	await frames(3)
	touch(p, false)
	await frames(3)


## Finger down at p, slide up by `dist` px in steps, lift.
func swipe(p: Vector2, dist: float) -> void:
	touch(p, true)
	await frames(2)
	var steps := 10
	for i in steps:
		drag(p + Vector2(0, -dist * (i + 1) / steps), Vector2(0, -dist / steps))
		await frames(1)
	touch(p + Vector2(0, -dist), false)
	await frames(4)


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


func _labels(n: Node) -> Array:
	return n.find_children("*", "Label", true, false)


func _find_text(n: Node, part: String) -> Label:
	for l in _labels(n):
		if String(l.text).contains(part):
			return l
	return null


func _button_with(n: Node, text: String) -> Control:
	for l in _labels(n):
		if String(l.text) == text:
			var p: Node = l
			while p and not p.has_signal("pressed"):
				p = p.get_parent()
			if p:
				return p
	return null


func _scroll() -> ScrollContainer:
	var sc: Array = hud.modal.find_children("*", "ScrollContainer", true, false)
	return sc[0] if not sc.is_empty() else null


func _card() -> Control:
	return hud.modal.get_node("Card").get_child(0)


func _run() -> void:
	root.size = Vector2i(720, 1280)
	await frames(3)
	g = root.get_node("Game")
	g.saving_enabled = false
	g.offline_reward = 0
	g.settings.story = false

	# ---------------- 1. ME screen with every gear track in Pro, then at Pro max
	_setup(1, 3)
	change_scene_to_file("res://scenes/main.tscn")
	await _scene_ready()
	var vw: float = root.get_visible_rect().size.x
	for case in [3, g.PRO_MAX]:
		g.levels.tool = g.cfg.tools.size() - 1; g.levels.bag = g.cfg.bag.size() - 1; g.levels.boots = g.cfg.boots.size() - 1
		g.pro = {"tool": case, "bag": case, "boots": case}
		for key in ["tool", "bag", "boots"]:
			var nx: Dictionary = g.next_upgrade(key)
			ok(nx.has("pro") if case < g.PRO_MAX else nx.is_empty(), "%s next upgrade at pro %d: %s" % [key, case, nx])
		hud.open_modal("character")
		await frames(4)
		ok(hud.modal_kind == "character", "ME opens with gear at Pro %d" % case)
		ok(_find_text(hud.modal, "WARDROBE") != null, "ME at Pro %d: wardrobe section present (gear rows didn't abort the build)" % case)
		var n_items := 0
		for l in _labels(hud.modal):
			if String(l.text) in ["WEARING", "WEAR"] or String(l.text).begins_with("$") or String(l.text).ends_with("★"):
				n_items += 1
		ok(n_items >= 3, "ME at Pro %d: wardrobe rows listed (%d buttons)" % [case, n_items])
		ok(_find_text(hud.modal, "Backpack Pro") != null and _find_text(hud.modal, "Trail boots Pro") != null, "ME at Pro %d: bag and boots rows show Pro levels" % case)
		var pro_tool := _find_text(hud.modal, " Pro ")
		ok(pro_tool != null, "ME at Pro %d: tool row shows its Pro level" % case)
		if case == g.PRO_MAX:
			ok(_button_with(hud.modal, "MAX") != null, "ME at Pro max: MAX buttons")
		# the shop shows the same gear rows
		var me_titles: Array = []
		for l in _labels(hud.modal):
			if String(l.text).contains(" Pro "):
				me_titles.append(String(l.text))
		hud.open_modal("shop")
		await frames(3)
		var shop_titles: Array = []
		for l in _labels(hud.modal):
			if String(l.text).contains(" Pro "):
				shop_titles.append(String(l.text))
		ok(me_titles == shop_titles, "shop and ME show the same gear rows (%s vs %s)" % [me_titles, shop_titles])
		hud.close_modal()
		await frames(3)
	g.levels.tool = 0; g.levels.bag = 0; g.levels.boots = 0; g.pro = {"tool": 0, "bag": 0, "boots": 0}

	# ---------------- 2. touch drags in the ME list (wardrobe rows and buttons)
	g.coins = 1_000_000_000
	hud.open_modal("character")
	await create_timer(0.4).timeout
	var sc := _scroll()
	ok(sc != null and sc.get_v_scroll_bar().max_value > sc.size.y + 50, "ME list is longer than its window")
	var target: Control = null
	for b in hud.modal.find_children("*", "Control", true, false):
		if b.has_signal("pressed") and b.get("clickable") and sc.get_global_rect().encloses(b.get_global_rect()) \
				and b.get_global_rect().position.y > sc.get_global_rect().position.y + sc.size.y * 0.5:
			target = b
			break
	ok(target != null, "found a button low in the ME list")
	if target:
		var presses := [0]
		target.pressed.connect(func(): presses[0] += 1)
		var s0: int = sc.scroll_vertical
		await swipe(target.get_global_rect().get_center(), 200.0)
		ok(sc.scroll_vertical > s0 + 100, "a touch drag that starts on a button scrolls the list (%d -> %d)" % [s0, sc.scroll_vertical])
		ok(presses[0] == 0 and hud.modal_kind == "character", "...and doesn't press the button (presses=%d, modal=%s)" % [presses[0], hud.modal_kind])
	# a drag on a plain wardrobe row (not a button) scrolls too
	sc.scroll_vertical = 0
	await frames(3)
	var row: Control = null
	for l in _labels(hud.modal):
		if String(l.text) == "Red Flannel" or String(l.text) == "Forest Hoodie":
			row = l
			break
	if row:
		var s1: int = sc.scroll_vertical
		await swipe(row.get_global_rect().get_center() + Vector2(-60, 0), 200.0)
		ok(sc.scroll_vertical > s1 + 100, "a touch drag on a wardrobe row scrolls the list (%d -> %d)" % [s1, sc.scroll_vertical])
	else:
		ok(false, "wardrobe row label found")
	# a still tap on a tab still clicks
	var hat := _button_with(hud.modal, "HAT")
	if hat:
		sc.ensure_control_visible(hat)
		await frames(4)
		await tap(hat)
		await frames(3)
		ok(hud._wardrobe_slot == "hat", "a still tap on HAT still clicks (slot=%s)" % hud._wardrobe_slot)
	hud._wardrobe_slot = "shirt"
	hud.close_modal()
	await frames(3)

	# ---------------- 3. map: card width, no-crew rows, short till text
	g.venues[0]["counter_coins"] = 98_765_432
	g.venues[2] = {"crew": {"lumberjack": 0, "waiter": 0, "cook": 0}, "built": {"campfire": true}, "counter_coins": 0}
	g._in_background = true
	g.tills_changed.emit()
	hud.open_modal("empire")
	await create_timer(0.4).timeout
	var cr: Rect2 = _card().get_global_rect()
	ok(cr.position.x >= 0.0 and cr.end.x <= vw + 0.5, "map card fits the screen (%s, screen %.0f)" % [cr, vw])
	var t0 = hud.modal.find_child("Till0", true, false)
	ok(t0 != null and not String(t0.get_node("TillText").text).contains("Cash waiting"), "till text is short: '%s'" % (t0.get_node("TillText").text if t0 else ""))
	ok(hud.modal.find_child("Till2", true, false) == null, "no till meter for a place with no crew")
	ok(_find_text(hud.modal, "Hire crew there to earn") != null, "no-crew place says 'Hire crew there to earn'")
	var earns := _find_text(hud.modal, "Earns $")
	ok(earns != null and String(earns.text).contains("while you play"), "map rows say 'Earns $X/min while you play'")
	ok(_find_text(hud.modal, "crew makes") == null, "no second wording for the rate")
	hud.close_modal()
	await frames(3)

	# ---------------- 4. complete screen + New Empire confirm, number formatting
	g.vserved = 9999
	hud.open_modal("complete")
	await frames(3)
	ok(_find_text(hud.modal, "9,999") != null, "guests served here uses a thousands separator")
	ok(_find_text(hud.modal, "mastered") == null, "0/3 stars: not 'mastered'")
	ok(_find_text(hud.modal, "Star 3: win the Big Day with no walkouts and get every station to Lv 15+") != null, "complete screen states the star rules")
	hud.close_modal()
	var keep := [g.venue, g.chapter_done]
	g.venue = g.chapters.size() - 1; g.chapter_done = true
	hud.open_modal("complete")
	await frames(3)
	hud._confirm_prestige = true
	hud._rebuild_modal()
	await frames(3)
	ok(_button_with(hud.modal, "STAY HERE") == null and _button_with(hud.modal, "Start over") != null, "New Empire confirm shows only Keep playing / Start over")
	hud.close_modal()
	g.venue = keep[0]; g.chapter_done = keep[1]
	await frames(3)

	# ---------------- 5. one wording for star 3 (upgrades footer)
	hud.open_modal("upgrades")
	await frames(3)
	ok(_find_text(hud.modal, "Star 3: win the Big Day with no walkouts and get every station to Lv 15+") != null, "upgrades footer uses the shared star wording")
	hud.close_modal()
	await frames(3)

	# ---------------- 6. ✕ on Stats / How to play goes back to Settings
	for sub in ["stats", "howto"]:
		hud.open_modal("settings")
		await create_timer(0.35).timeout
		hud.open_modal(sub)
		await create_timer(0.35).timeout
		var x := _button_with(hud.modal, "✕")
		ok(x != null, "%s has a ✕" % sub)
		if x:
			await tap(x)
			await frames(4)
		ok(hud.modal_kind == "settings", "✕ on %s returns to Settings (modal=%s)" % [sub, hud.modal_kind])
		hud.close_modal()
		await frames(3)

	# ---------------- 7. toasts wrap evenly
	hud._toast_q.clear(); hud._toast_t = 0.0
	hud.show_toast("Welcome next door! Your $123.4M came with you, and your crew set up the grill.")
	await frames(3)
	var tl: Label = hud.toast_label
	var maxw: float = vw - 300.0
	ok(tl.get_line_count() >= 2 and tl.custom_minimum_size.x < maxw, "long toast wraps at a balanced width (%.0f < %.0f, %d lines)" % [tl.custom_minimum_size.x, maxw, tl.get_line_count()])
	ok(hud.toast_box.get_global_rect().end.x <= vw and hud.toast_box.position.x >= 0, "toast fits on screen")

	# ---------------- 8. story cards are paced: one card, then a wait
	g.settings.story = true
	hud._story_last_s = -1000.0
	hud._ui_tap_ms = -100000
	hud._on_story([{"who": "mags", "text": "One."}, {"who": "mags", "text": "Two."}, {"who": "doyle", "text": "Three."}])
	await create_timer(0.6).timeout
	ok(hud.modal_kind == "story", "first story card shows (modal=%s)" % hud.modal_kind)
	ok(_find_text(hud.modal, "One.") != null and _find_text(hud.modal, "Two.") != null, "same speaker's lines share one card")
	var okb := _button_with(hud.modal, "OK")
	ok(okb != null, "card has OK (not NEXT)")
	if okb:
		await tap(okb)
	await create_timer(0.8).timeout
	ok(hud.modal_kind == "" and hud._story_q.size() == 1, "next card waits (modal=%s, queued=%d)" % [hud.modal_kind, hud._story_q.size()])
	hud._story_last_s = hud._play_s - 46.0
	hud._ui_tap_ms = Time.get_ticks_msec()
	await create_timer(0.3).timeout
	ok(hud.modal_kind == "", "no story card right after a tap")
	await create_timer(0.6).timeout
	ok(hud.modal_kind == "story", "after the gap the next card shows (modal=%s)" % hud.modal_kind)
	hud._story_q.clear()
	hud.close_modal()
	g.settings.story = false
	await frames(3)

	# ---------------- 9. GO TO <next place> on a finished gate travels there
	g.chapter_done = true
	g.unlocked = 3
	hud.open_modal("gate")
	await frames(3)
	var go := _button_with(hud.modal, "GO TO " + String(g.chapters[2].name).to_upper())
	ok(go != null, "finished gate shows GO TO %s" % String(g.chapters[2].name).to_upper())
	if go:
		await tap(go)
		await _scene_ready()
		ok(g.venue == 2, "GO TO travels next door (venue=%d)" % g.venue)

	load("res://scripts/world/plot.gd").finish_jobs()
	print("RESULT ui_fixes_t2 fails=%d" % fails)
	quit(1 if fails > 0 else 0)
