extends SceneTree
## One road: neighbour plots west/east, walking across the road boundary, locked plots block, till labels,
## Big Day blocks, MAP arrival, the lakeshore road. Run: $G --headless --path . -s res://tests/qa/world_strip.gd
var fails := 0
var g
var toasts: Array = []


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


## Walks the player along the road in direction dx until the venue changes or `secs` pass.
func _walk(dx: float, secs: float) -> bool:
	var v0: int = g.venue
	var t := 0.0
	while t < secs:
		var w = current_scene.world
		if w != null and is_instance_valid(w) and w.player != null and not current_scene.crossing:
			if g.venue != v0:
				break
			w.player.input_dir = Vector2(dx, 0)
		await physics_frame
		t += 1.0 / float(Engine.physics_ticks_per_second)
	await _ready_scene()
	await _wait(2)
	var w2 = current_scene.world
	if w2 and w2.player:
		w2.player.input_dir = Vector2.ZERO
	return g.venue != v0


func _place(x: float) -> void:
	var w = current_scene.world
	w.player.global_position = Vector3(x, 0, 11.5)
	w._cross_armed = true
	await _wait(3)


func _full(k: int) -> Dictionary:
	var b := {"campfire": true, "tables_1": true, "shop": true, "crew_hut": true, "fire_2": true, "tables_2": true}
	if String(g.chapters[k].get("special", {}).get("type", "")) != "":
		b["special"] = true
	return b


func _run() -> void:
	g = root.get_node("Game")
	g.saving_enabled = false
	g.offline_reward = 0
	g.settings.story = false
	g.toast.connect(func(t): toasts.append(String(t)))
	# chapter 0 built up, chapter 1 active, chapter 2 for sale
	g.coins = 0; g.served = 0; g.pad_paid = {}; g.chapter_done = false; g.prestige = 0
	g.venue = 0; g.unlocked = 2; g.venues = []; g.vserved = 0; g.cfg = g.chapter_cfg(0)
	g.reno = {}; g.bigday = {}; g.seen = {"task_init": true}; g.task_i = 0; g.task_base = 0; g.golden_n = 0
	g.built = _full(0)
	g.crew = {"lumberjack": 2, "waiter": 1, "cook": 1}
	g.woodpile = 10; g.counter_coins = 0
	g.levels = {"tool": 3, "bag": 2, "boots": 1, "fire": 0, "menu": 0, "dining": 0, "sign": 0, "station": 0}
	g.jobs_day = ""; g.refresh_jobs()
	ok(g.travel(1), "start: travel state to chapter 1")
	g.built = _full(1)
	g.crew = {"lumberjack": 1, "waiter": 1, "cook": 0}
	g.venues[0]["counter_coins"] = 777
	g.coins = 4242
	change_scene_to_file("res://scenes/main.tscn")
	await _ready_scene()
	await _wait(3)
	var w = current_scene.world
	var Plot = load("res://scripts/world/plot.gd")

	# ---------- neighbours exist, west and east
	ok(w.nb_plots.has(-1) and w.nb_plots.has(1), "both neighbours exist (sides=%s)" % [w.nb_plots.keys()])
	var west = w.nb_plots.get(-1)
	var east = w.nb_plots.get(1)
	ok(west != null and west.k == 2 and west.position.x < -15.0, "west neighbour is chapter 2 at x=%.1f" % (west.position.x if west else 0.0))
	ok(east != null and east.k == 0 and east.position.x > 15.0, "east neighbour is chapter 0 at x=%.1f" % (east.position.x if east else 0.0))
	ok(west != null and not west.owned, "chapter 2 (west) is for sale")
	ok(east != null and east.visited and east.baked.mesh != null and east.baked.mesh.get_surface_count() <= 3,
		"chapter 0 (east) shows its camp, baked into %d surfaces" % (east.baked.mesh.get_surface_count() if east and east.baked.mesh else -1))
	ok(west != null and west.till_label.text.contains("FOR SALE"), "west label says FOR SALE (%s)" % (west.till_label.text.replace("\n", " / ") if west else ""))
	ok(absf(east.position.x - Plot.offset(1, 0)) < 0.01 and absf(Plot.offset(1, 0) - 31.0) < 0.01, "standard plots are 31 m apart")
	# road clear of edge forest where it runs on
	var on_road := 0
	for n in w.get_tree().get_nodes_in_group("edge_forest"):
		if not w.is_ancestor_of(n):
			continue
		var mm: MultiMesh = n.multimesh
		for i in mm.instance_count:
			var p: Vector3 = mm.get_instance_transform(i).origin
			if absf(p.x) > 15.0 and absf(p.z - 11.5) < 3.5:
				on_road += 1
	ok(on_road == 0, "no edge-forest tree on the road beyond the plot edges (%d)" % on_road)

	# ---------- till labels update
	var UIs = load("res://scripts/ui/ui.gd")
	g.venues[0]["counter_coins"] = 50
	g.tills_changed.emit()
	await _wait(1)
	ok(east.till_label.text.contains(UIs.cash(g.till(0))) and east.pile_label.visible,
		"east till label shows chapter 0's waiting cash %d (%s)" % [g.till(0), east.till_label.text.replace("\n", " / ")])
	var mm_before: int = east.coins_mm.visible_instance_count
	g.venues[0]["counter_coins"] = 150
	g.tills_changed.emit()
	await _wait(1)
	ok(east.till_label.text.contains(UIs.cash(g.till(0))) and east.pile_label.text == UIs.cash(g.till(0)),
		"till label follows tills_changed (%s)" % east.till_label.text.replace("\n", " / "))
	ok(east.coins_mm.visible_instance_count > mm_before, "cash pile grows (%d -> %d)" % [mm_before, east.coins_mm.visible_instance_count])
	g.venues[0]["counter_coins"] = 4321
	g.tills_changed.emit()

	# ---------- a locked neighbour blocks, with the gate prompt at its fence
	await _wait(2)
	ok(w.fence_zone != null and w.fence_zone.kind == "gate", "FOR SALE fence has a gate prompt (gate pad up: %s)" % w.pads.has("gate"))
	await _place(-12.5)
	toasts.clear()
	var moved := await _walk(-1.0, 2.0)
	w = current_scene.world
	ok(not moved and g.venue == 1, "walking west into the FOR SALE plot does not leave chapter 1")
	ok(w.player.global_position.x > -15.2, "blocked at the fence (x=%.2f)" % w.player.global_position.x)
	ok(toasts.any(func(t): return t.contains("for sale")), "toast explains it (%s)" % [toasts])

	# ---------- Big Day blocks the way east
	await _place(12.5)
	w.bd_active = true
	w.bd = {"goal": 9999, "seconds": 999, "max_walkouts": 999}
	w.bd_left = 999.0
	toasts.clear()
	moved = await _walk(1.0, 2.0)
	ok(not moved and g.venue == 1, "no crossing during a Big Day")
	ok(toasts.has("Finish the Big Day first!"), "Big Day toast (%s)" % [toasts])
	w.bd_active = false
	w.bd = {}

	# ---------- walk east into chapter 0: switches venue, keeps cash, arrives at the west edge facing in
	await _place(12.5)
	w.player.back.set_count(5)
	var coins0: int = g.coins
	moved = await _walk(1.0, 4.0)
	w = current_scene.world
	ok(moved and g.venue == 0, "walked east into chapter 0 (venue=%d)" % g.venue)
	ok(g.coins == coins0, "cash kept (%d -> %d)" % [coins0, g.coins])
	ok(g.counter_coins >= 4321, "chapter 0's waiting cash is now its counter cash (%d)" % g.counter_coins)
	var pp: Vector3 = w.player.global_position
	ok(pp.x < -13.0 and pp.x > -15.2 and absf(pp.z - 11.5) < 2.2, "arrived at chapter 0's west road edge (%.2f, %.2f)" % [pp.x, pp.z])
	ok(absf(wrapf(w.player.rig.rotation.y - PI / 2, -PI, PI)) < 0.6, "facing east, into the plot (yaw %.2f)" % w.player.rig.rotation.y)
	ok(w.player.back.count() == 5, "logs on the back came along (%d)" % w.player.back.count())
	ok(current_scene.get_node_or_null("LoadingScreen") == null, "no loading screen for a walk")
	print("INFO crossing build %.1f ms" % current_scene.last_cross_ms)
	ok(w.nb_plots.has(-1) and w.nb_plots[-1].k == 1 and w.nb_plots[-1].visited and not w.nb_plots.has(1),
		"in chapter 0: chapter 1 is the west neighbour, nothing east")
	# the coin zone collects it
	ok(w.coin_stack.count() > 0, "cash pile on the counter on arrival (%d bills)" % w.coin_stack.count())

	# ---------- and back west into chapter 1 (arrival at its east edge)
	moved = await _walk(-1.0, 1.0)
	ok(not moved, "no ping-pong: standing at the edge right after arriving does not cross back at once")
	await _place(-12.0)
	moved = await _walk(-1.0, 4.0)
	w = current_scene.world
	ok(moved and g.venue == 1, "walked west back into chapter 1")
	pp = w.player.global_position
	ok(pp.x > 13.0 and pp.x < 15.2, "arrived at chapter 1's east edge (x=%.2f)" % pp.x)
	ok(g.coins == coins0, "cash still kept (%d)" % g.coins)

	# ---------- opening the gate turns the FOR SALE plot into yours (no rebuild)
	g.unlocked = 3
	g.state_changed.emit()
	await _wait(2)
	ok(w.nb_plots[-1].owned and not w.nb_plots[-1].visited and w.fence_zone == null, "gate opened: west plot is yours, fence prompt gone")

	# ---------- MAP travel still works and arrives on the road at the side you came from
	current_scene.travel_to(0)
	await _wait(5)
	await _ready_scene()
	await _wait(2)
	w = current_scene.world
	ok(g.venue == 0, "MAP travel to chapter 0")
	pp = w.player.global_position
	ok(absf(pp.x + 11.0) < 0.5 and absf(pp.z - 11.5) < 0.5, "MAP arrival from the west at (%.1f, %.1f)" % [pp.x, pp.z])
	current_scene.travel_to(2)
	await _wait(5)
	await _ready_scene()
	await _wait(2)
	w = current_scene.world
	ok(g.venue == 2 and g.built.has("campfire"), "MAP travel to new chapter 2 (head start)")
	pp = w.player.global_position
	ok(absf(pp.x - 11.0) < 0.5, "MAP arrival from the east at x=%.1f" % pp.x)

	# ---------- the lakeshore road: chapter 2 runs on to x=43.5, its east neighbour starts there
	ok(absf(Plot.east(2) - 43.5) < 0.01 and w.nb_plots.has(1) and absf(w.nb_plots[1].position.x - 59.0) < 0.01,
		"lake plot runs on along the shore (east edge 43.5, chapter 1 at x=%.1f)" % w.nb_plots[1].position.x)
	await _place(30.0)
	moved = await _walk(1.0, 6.0)
	w = current_scene.world
	ok(moved and g.venue == 1, "walked the lakeshore road east into chapter 1")
	pp = w.player.global_position
	ok(pp.x < -13.0, "arrived at chapter 1's west edge (x=%.2f)" % pp.x)
	ok(w.nb_plots[-1].k == 2 and absf(w.nb_plots[-1].position.x + 59.0) < 0.01, "lake plot drawn west of chapter 1 at x=-59")
	await _place(-12.0)
	moved = await _walk(-1.0, 4.0)
	w = current_scene.world
	pp = w.player.global_position
	ok(moved and g.venue == 2 and pp.x > 42.0 and pp.x < 43.4, "walked west into the lake plot, arriving at its road end (x=%.2f)" % pp.x)

	Plot.finish_jobs()
	print("WORLD_STRIP fails=%d" % fails)
	quit(1 if fails > 0 else 0)
