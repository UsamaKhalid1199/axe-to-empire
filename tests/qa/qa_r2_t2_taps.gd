extends SceneTree
## QA round 2, tester 2: layout audit of the HUD and every modal, without rendering.
##   $G --headless --path . -s res://tests/qa/qa_r2_t2_taps.gd [-- WxH]   (default 720x1280)
## For the HUD and each modal (chapter 1 and 4, Pro gear, long texts) it checks:
##   T  every clickable shape is at least 64 x 56 canvas px (the canvas is 720 wide)
##   O  no visible control outside a scroll list pokes past the screen edge
##   V  every clickable outside a scroll list is fully on screen
##   C  modal cards fit inside the screen height (or scroll)
## Duck-typed: no static reference to the UI / UIShape classes. Prints FAILS=n.
var fails := 0
var warns := 0
var g
var hud


func ok(c: bool, msg: String) -> void:
	print(("PASS " if c else "FAIL ") + msg)
	if not c:
		fails += 1


func warn(msg: String) -> void:
	print("WARN " + msg)
	warns += 1


func _initialize() -> void:
	_run.call_deferred()


func frames(n: int) -> void:
	for i in n:
		await process_frame


func _in_scroll(c: Node) -> bool:
	var p := c.get_parent()
	while p != null:
		if p is ScrollContainer:
			return true
		p = p.get_parent()
	return false


func _name(c: Node) -> String:
	for l in c.find_children("*", "Label", true, false):
		if l.visible and String(l.text).strip_edges() != "":
			return "'%s'" % String(l.text).replace("\n", " ").left(40)
	return String(c.name)


func _visible_in_tree(c: Control) -> bool:
	return c.is_visible_in_tree() and c.modulate.a > 0.05


func _audit(where: String, base: Node) -> void:
	var vr: Rect2 = root.get_visible_rect()
	var small := 0
	var off := 0
	var taps := 0
	for c in base.find_children("*", "Control", true, false):
		if not _visible_in_tree(c):
			continue
		var r: Rect2 = c.get_global_rect()
		if r.size.x < 1 or r.size.y < 1:
			continue
		var scrolled := _in_scroll(c)
		if c.get("clickable") == true:
			taps += 1
			if r.size.x < 64 or r.size.y < 56:
				warn("T %s: small tap target %s %.0fx%.0f" % [where, _name(c), r.size.x, r.size.y])
				small += 1
			if not scrolled and not vr.encloses(r.grow(-1)):
				ok(false, "V %s: button %s off screen %s (screen %s)" % [where, _name(c), r, vr.size])
				off += 1
		elif not scrolled and (c is Label) and String(c.text) != "" and not vr.encloses(r.grow(-2)):
			ok(false, "O %s: label %s pokes past the screen %s (screen %s)" % [where, _name(c), r, vr.size])
			off += 1
	ok(off == 0, "%s: nothing off screen (%d buttons checked)" % [where, taps])
	if small == 0:
		print("PASS %s: all tap targets >= 64x56" % where)


func _setup(k: int) -> void:
	g.venue = k; g.unlocked = k + 1; g.venues = []; g.cfg = g.chapter_cfg(k)
	g.reno = {}; g.bigday = {}; g.seen = {"task_init": true}; g.task_i = 3; g.task_base = 0; g.chapter_done = false
	g.built = {"campfire": true, "tables_1": true, "shop": true, "crew_hut": true, "fire_2": true, "tables_2": true, "special": true}
	g.crew = {"lumberjack": 3, "waiter": 2, "cook": 2}
	g.vserved = 9999; g.coins = 123456789; g.rating_hist = [4.7]; g.woodpile = 20; g.counter_coins = 0
	g.levels.tool = g.cfg.tools.size() - 1
	g.levels.bag = g.cfg.bag.size() - 1
	g.levels.boots = g.cfg.boots.size() - 1
	g.pro = {"tool": 4, "bag": 10, "boots": 1}
	while g.venues.size() < g.unlocked:
		g.venues.append({})
	for j in k:
		g.venues[j] = {"crew": {"lumberjack": 2, "waiter": 2, "cook": 1}, "built": {"campfire": true}, "counter_coins": 12345}


func _load() -> void:
	change_scene_to_file("res://scenes/main.tscn")
	await frames(2)
	while current_scene == null or current_scene.get("hud") == null or current_scene.get_node_or_null("LoadingScreen") != null \
			or current_scene.get("crossing"):
		await process_frame
	await frames(20)
	hud = current_scene.hud
	hud._story_q.clear()
	if hud.modal_kind != "":
		hud.close_modal()
	g._in_background = true
	await create_timer(0.3).timeout


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var res: String = args[0] if args.size() > 0 and args[0].contains("x") else "720x1280"   # headless defaults to a square window
	if true:
		var wh: PackedStringArray = res.split("x")
		root.size = Vector2i(int(wh[0]), int(wh[1]))
		await frames(5)
	g = root.get_node("Game")
	g.saving_enabled = false
	g.offline_reward = 0
	g.settings.story = false
	for k in [0, 1, 4, 5]:
		_setup(k)
		await _load()
		print("== chapter %d screen %s" % [k, root.get_visible_rect().size])
		_audit("ch%d HUD" % k, hud)
		for m in ["shop", "crew", "upgrades", "character", "jobs", "settings", "gate", "empire", "complete", "stats", "howto", "offline", "bigday_result"]:
			if m == "offline":
				g.offline_reward = 98765432
			if m == "bigday_result":
				hud._bd_result = [true, 64, 40]
			hud.open_modal(m)
			await create_timer(0.3).timeout
			if hud.modal == null:
				print("SKIP ch%d %s did not open" % [k, m])
				continue
			_audit("ch%d %s" % [k, m], hud.modal)
			# card height: the card must fit, or its long part must scroll
			var card: Control = hud.modal.get_node_or_null("Card")
			if card and card.get_child_count() > 0:
				var cr: Rect2 = card.get_child(0).get_global_rect()
				ok(cr.size.y <= root.get_visible_rect().size.y + 1, "C ch%d %s: card %.0f tall fits screen %.0f" % [k, m, cr.size.y, root.get_visible_rect().size.y])
			# scroll lists: is the end reachable and still on screen?
			for sc in hud.modal.find_children("*", "ScrollContainer", true, false):
				sc.scroll_vertical = 100000
				await frames(3)
				var sr: Rect2 = sc.get_global_rect()
				ok(root.get_visible_rect().encloses(sr.grow(-1)), "C ch%d %s: scroll box %s on screen" % [k, m, sr])
			hud.close_modal()
			g.offline_reward = 0
			await create_timer(0.25).timeout
	print("FAILS=%d WARNS=%d" % [fails, warns])
	quit(1 if fails > 0 else 0)
