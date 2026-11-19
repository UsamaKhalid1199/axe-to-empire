extends SceneTree
## QA round 4: the Android back button never quits at once. It closes the open card first; with nothing open it
## asks "Leave the game?" (Keep playing / Quit). Drives main.gd's handler (NOTIFICATION_WM_GO_BACK_REQUEST).
## Also: the "Drag to move" hint stays until the player has walked a few metres, and golden-tree / job prompts
## wait until the first build (the campfire) is done.
## Run: $G --headless --path . -s res://tests/qa/qa_r4_back.gd
var fails := 0
var g


func ok(c: bool, msg: String) -> void:
	print(("PASS " if c else "FAIL ") + msg)
	if not c:
		fails += 1


func _initialize() -> void:
	_run.call_deferred()


func _wait(n: int) -> void:
	for i in n:
		await process_frame


func _ready_scene() -> void:
	while current_scene == null or current_scene.get("hud") == null or current_scene.get_node_or_null("LoadingScreen") != null \
			or current_scene.get("crossing"):
		await process_frame


func _back() -> void:
	current_scene.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await _wait(6)


func _run() -> void:
	g = root.get_node("Game")
	g.saving_enabled = false
	g.offline_reward = 0
	g.settings.story = true
	g.coins = 20; g.served = 0; g.pad_paid = {}; g.chapter_done = false; g.prestige = 0
	g.venue = 0; g.unlocked = 1; g.venues = []; g.vserved = 0; g.cfg = g.chapter_cfg(0)
	g.reno = {}; g.bigday = {}; g.seen = {"task_init": true}; g.task_i = 0; g.task_base = 0; g.golden_n = 0
	g.built = {}
	g.crew = {"lumberjack": 0, "waiter": 0, "cook": 0}
	g.woodpile = 0; g.counter_coins = 0; g.rack = 0
	g.levels = {"tool": 0, "bag": 0, "boots": 0, "fire": 0, "menu": 0, "dining": 0, "sign": 0, "station": 0}
	ok(ProjectSettings.get_setting("application/config/quit_on_go_back", true) == false, "project: quit_on_go_back is off")
	change_scene_to_file("res://scenes/main.tscn")
	await _ready_scene()
	await _wait(5)
	ok(not is_quit_on_go_back(), "the tree does not quit on back")
	var hud = current_scene.hud
	var w = current_scene.world

	# ---- a story card: back closes it (and the next card, if any, follows)
	hud._story_last_s = -1000.0
	g.story.emit([{"on": "start", "who": "mags", "text": "Chop wood, keep the fire going."},
		{"on": "start", "who": "doyle", "text": "Ranger Doyle here."}])
	var guard := 0
	while hud.modal_kind == "" and guard < 200:
		await _wait(1)
		guard += 1
	ok(hud.modal_kind == "story", "a story card shows ('%s')" % hud.modal_kind)
	var cards := 0
	while hud.modal_kind == "story" and cards < 6:
		await _back()
		cards += 1
		await create_timer(0.3).timeout
		# (the next card waits for the story spacing: skip it for the test)
		hud._story_last_s = -1000.0
		await _wait(3)
	ok(hud.modal_kind == "" and cards >= 1, "back closes the story card (%d closed, now '%s', %d queued)" % [cards, hud.modal_kind, hud._story_q.size()])
	g.settings.story = false
	hud._story_q.clear()
	if hud.modal_kind != "":
		hud.close_modal()
	await _wait(5)

	# ---- nothing open: back asks before leaving
	await _back()
	ok(hud.modal_kind == "quit", "back with nothing open asks 'Leave the game?' ('%s')" % hud.modal_kind)
	var texts: Array = []
	for l in hud.modal.find_children("*", "Label", true, false):
		texts.append(String(l.text))
	var joined := " | ".join(texts)
	ok(joined.contains("Leave the game?") and joined.contains("KEEP PLAYING") and joined.contains("QUIT"), "the prompt offers Keep playing / Quit (%s)" % joined)
	await _back()
	ok(hud.modal_kind == "", "back again keeps playing (closes the prompt)")

	# ---- a menu: back closes it; a Settings sub-screen goes back to Settings first
	hud.open_modal("shop")
	await _wait(3)
	await _back()
	ok(hud.modal_kind == "", "back closes the tool shed")
	hud.open_modal("settings")
	await _wait(3)
	hud.open_modal("howto")
	await _wait(3)
	await _back()
	ok(hud.modal_kind == "settings", "back on How to play returns to Settings ('%s')" % hud.modal_kind)
	await _back()
	ok(hud.modal_kind == "", "back on Settings closes it")
	hud.open_modal("empire")
	await _wait(3)
	await _back()
	ok(hud.modal_kind == "", "back closes the MAP")

	# ---- new player: golden-tree / job prompts wait for the first build
	hud._toast_q.clear()
	g.toast.emit("A golden tree appeared!")
	g.toast.emit("Job done: Chop 10 trees")
	g.toast.emit("Sell logs at the truck")
	await _wait(2)
	var q: Array = hud._toast_q.duplicate()
	ok(not q.any(func(t): return String(t).contains("golden") or String(t).begins_with("Job done")), "before the campfire: golden/job toasts are held (%s)" % [q])
	ok(hud._held_toasts.size() == 2, "and kept for later (%d held)" % hud._held_toasts.size())
	g.coins = 100
	g.pay_pad("campfire", 1000)
	await _wait(3)
	ok(g.built.has("campfire"), "campfire built")
	ok(hud._held_toasts.is_empty(), "after the first build the held prompts come (%d left held)" % hud._held_toasts.size())

	# ---- "Drag to move" stays after a touch until the player has walked a few metres
	hud.joy.hint_alpha = 1.0
	hud._hint_walked = 0.0
	hud._hint_last = Vector3.INF
	w = current_scene.world
	var ev := InputEventScreenTouch.new()
	ev.index = 0
	ev.pressed = true
	ev.position = Vector2(360, 900)
	hud.joy._input(ev)
	ev = InputEventScreenTouch.new()
	ev.index = 0
	ev.pressed = false
	ev.position = Vector2(360, 900)
	hud.joy._input(ev)
	await _wait(5)
	ok(hud.joy.hint_alpha > 0.9, "a touch alone keeps the hint (alpha %.2f)" % hud.joy.hint_alpha)
	w.player.global_position = Vector3(0, 0, 0.5)
	await _wait(3)
	var t := 0.0
	while t < 2.0:
		w.player.input_dir = Vector2(1, 0) if int(t * 2.0) % 2 == 0 else Vector2(-1, 0)
		await physics_frame
		t += 1.0 / float(Engine.physics_ticks_per_second)
	w.player.input_dir = Vector2.ZERO
	await create_timer(0.8).timeout
	ok(hud._hint_walked >= 3.0 and hud.joy.hint_alpha <= 0.01, "after walking %.1f m the hint is gone (alpha %.2f)" % [hud._hint_walked, hud.joy.hint_alpha])

	load("res://scripts/world/plot.gd").finish_jobs()
	print("RESULT qa_r4_back fails=%d" % fails)
	quit(1 if fails > 0 else 0)
