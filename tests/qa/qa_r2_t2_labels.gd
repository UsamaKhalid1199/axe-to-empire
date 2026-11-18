extends SceneTree
## QA round 2, tester 2: where the neighbour's "WALK TO ..." / "FOR SALE" label lands on screen while the player
## walks along the road toward each edge (camera left to follow normally). Flags a label that runs under the HUD's
## right-hand button column or past the screen edge while it is on screen.
##   $G --headless --path . -s res://tests/qa/qa_r2_t2_labels.gd [-- WxH]
## Projection only (no rendering needed). Duck-typed: no static reference to UI classes. Prints FAILS=n.
var fails := 0
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


func _full(k: int) -> Dictionary:
	var b := {"campfire": true, "tables_1": true, "shop": true, "crew_hut": true, "fire_2": true, "tables_2": true}
	if String(g.chapters[k].get("special", {}).get("type", "")) != "":
		b["special"] = true
	return b


func _setup(k: int) -> void:
	g.venue = k; g.unlocked = k + 1; g.venues = []; g.cfg = g.chapter_cfg(k)
	g.reno = {}; g.bigday = {}; g.seen = {"task_init": true}; g.task_i = 2; g.task_base = 0; g.chapter_done = false
	g.built = _full(k)
	g.crew = {"lumberjack": 1, "waiter": 1, "cook": 1}
	g.vserved = 40; g.coins = 250000; g.rating_hist = [4.6]; g.woodpile = 12; g.counter_coins = 0
	while g.venues.size() < g.unlocked:
		g.venues.append({})
	for j in k:
		g.venues[j] = {"crew": {"lumberjack": 1, "waiter": 1, "cook": 1}, "built": _full(j), "counter_coins": 123456}


func _load() -> void:
	change_scene_to_file("res://scenes/main.tscn")
	await frames(2)
	while current_scene == null or current_scene.get("hud") == null or current_scene.get_node_or_null("LoadingScreen") != null \
			or current_scene.get("crossing"):
		await process_frame
	await frames(20)
	current_scene.hud._story_q.clear()
	if current_scene.hud.modal_kind != "":
		current_scene.hud.close_modal()
	g._in_background = true


## Screen rect of a billboard Label3D (approximate: its text box at its pixel size, projected at its centre depth).
func _label_rect(cam: Camera3D, l: Label3D) -> Rect2:
	var sz: Vector2 = l.font.get_multiline_string_size(l.text, HORIZONTAL_ALIGNMENT_CENTER, -1, l.font_size) * l.pixel_size
	var c := l.global_position
	var right := cam.global_transform.basis.x
	var up := cam.global_transform.basis.y
	var a := cam.unproject_position(c - right * sz.x * 0.5 + up * sz.y * 0.5)
	var b := cam.unproject_position(c + right * sz.x * 0.5 - up * sz.y * 0.5)
	return Rect2(Vector2(minf(a.x, b.x), minf(a.y, b.y)), (b - a).abs())


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var res: String = args[0] if args.size() > 0 and args[0].contains("x") else "720x1280"   # headless defaults to a square window
	if true:
		var wh: PackedStringArray = res.split("x")
		root.size = Vector2i(int(wh[0]), int(wh[1]))
		await frames(5)
	print("LABELS screen ", root.get_visible_rect().size)
	g = root.get_node("Game")
	g.saving_enabled = false
	g.offline_reward = 0
	g.settings.story = false
	for k in g.chapters.size():
		_setup(k)
		await _load()
		var w = current_scene.world
		var hud = current_scene.hud
		var col: Control = hud.jobs_btn.get_parent().get_parent()
		var vr: Rect2 = root.get_visible_rect()
		var col_r: Rect2 = col.get_global_rect()
		for side in w.nb_plots:
			var np = w.nb_plots[side]
			var l: Label3D = np.till_label
			if l == null:
				continue
			# Plot.west/east, without a static reference to Plot (it needs the Game autoload to compile)
			var water: bool = g.chapters[k].get("theme", {}).get("water", false)
			var edge: float = -15.5 if side < 0 else (43.5 if water else 15.5)
			var worst := ""
			for d in [9.0, 8.0, 7.0, 6.0, 5.0, 4.0, 3.0, 2.0, 1.2]:
				w._cross_armed = false
				w.player.global_position = Vector3(edge - side * d, 0, 11.5)
				await create_timer(0.7).timeout       # the follow camera settles
				if hud.modal_kind != "":
					hud.close_modal()
					await create_timer(0.3).timeout
				if w.cam.is_position_behind(l.global_position):
					continue
				var r := _label_rect(w.cam, l)
				if not r.intersects(vr):
					continue
				var under := r.intersects(col_r)
				var off := not vr.encloses(r.grow(-4))
				var s := " d=%.1f:%s%s(x %.0f..%.0f)" % [d, "under-buttons " if under else "", "clipped " if off else "", r.position.x, r.end.x]
				# a label sliding in from the screen edge while the edge is still far is normal; under the buttons is
				# never fine, and once the player is at the edge (d <= 2 m) the whole label must be readable
				if under or (off and d <= 2.0):
					worst += s
				elif off:
					print("INFO ch%d %s label sliding in:%s" % [k, "west" if side < 0 else "east", s])
			ok(worst == "", "ch%d %s label '%s' clear of the button column (and whole at the edge) while walking up%s" % [
				k, "west" if side < 0 else "east", l.text.replace("\n", " / "), worst])
	print("FAILS=%d" % fails)
	quit(1 if fails > 0 else 0)
