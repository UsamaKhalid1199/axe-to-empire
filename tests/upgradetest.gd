extends SceneTree
## Does every upgrade do what it says, and does it pay for itself?
## Part A: measures each upgrade's real effect in the running game against its label.
## Part B: runs the venue with a crew and no player for a few game minutes per config and measures
##         income per minute, then the payback time of +5 levels of each station.
## Usage: --headless -s res://tests/upgradetest.gd -- [chapter]
var fails := 0
var chap := 0


func ok(c: bool, msg: String) -> void:
	print(("PASS " if c else "FAIL ") + msg)
	if not c: fails += 1


func _initialize() -> void:
	_run.call_deferred()


func _ready_scene() -> void:
	while current_scene == null or current_scene.get("hud") == null or current_scene.get_node_or_null("LoadingScreen") != null:
		await process_frame


func _base(g, lv: Dictionary) -> void:
	g.saving_enabled = false
	g.offline_reward = 0
	g.venue = chap; g.unlocked = chap + 1; g.venues = []; g.cfg = g.chapter_cfg(chap)
	g.reno = {}; g.bigday = {}; g.seen = {"task_init": true}; g.task_i = 99; g.prestige = 0
	g.built = {"campfire": true, "tables_1": true, "shop": true, "crew_hut": true, "fire_2": true, "tables_2": true}
	if g.special_type() != "":
		g.built["special"] = true
	g.crew = {"lumberjack": 2, "waiter": 2, "cook": 1}
	g.levels = {"tool": 0, "bag": 0, "boots": 0, "fire": 0, "menu": 0, "dining": 0, "sign": 0, "station": 0}
	for k in lv:
		g.levels[k] = lv[k]
	g.vserved = 100; g.served = 100; g.rating_hist = [5.0]; g.woodpile = 20; g.rack = 0; g.counter_coins = 0
	g.coins = 0; g.settings.story = false


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	chap = int(args[0]) if args.size() > 0 else 0
	var g = root.get_node("Game")
	_base(g, {})
	change_scene_to_file("res://scenes/main.tscn")
	await _ready_scene()
	var w = current_scene.world
	var p = w.player
	current_scene.hud._story_q.clear(); current_scene.hud.close_modal()
	print("=== chapter %d: %s" % [chap + 1, g.chapter().name])

	# ---------------- Part A: effects
	# boots: top running speed per level (velocity after accelerating; no walls involved)
	var v0 := 0.0
	for lv in g.cfg.boots.size():
		g.levels.boots = lv
		p.global_position = Vector3(0, 0, 4); p.input_dir = Vector2(1, 0)
		await create_timer(0.35).timeout
		var v: float = Vector2(p._vel.x, p._vel.z).length()
		p.input_dir = Vector2.ZERO
		if lv == 0: v0 = v
		var want := float(g.cfg.boots[lv].mult)
		ok(absf(v / maxf(v0, 0.01) - want) < 0.04, "boots lv%d: speed x%.2f (label x%.2f)" % [lv, v / maxf(v0, 0.01), want])
		await create_timer(0.3).timeout
	g.levels.boots = 0
	# backpack: the stack really holds bag_cap logs
	for lv in g.cfg.bag.size():
		g.levels.bag = lv
		p.back.set_count(0)
		for i in 60:
			if p.back.count() < g.bag_cap():
				p.back.set_count(p.back.count() + 1)
		ok(g.bag_cap() == int(g.cfg.bag[lv].cap), "bag lv%d: carries %d logs" % [lv, g.bag_cap()])
	p.back.set_count(0); g.levels.bag = 4   # room for the tool test
	# tools: logs per second on one very tough tree (so the tree never runs out)
	var r0 := 0.0
	for lv in 3:
		g.levels.tool = lv
		p.equip_tool()
		p.back.set_count(0)
		var t = null
		for tr in w.trees:
			if tr.alive and tr != w.golden:
				t = tr; break
		t.hp = 100000; t.max_hp = 100000
		p.global_position = t.global_position + Vector3(1.0, 0, 0)
		await create_timer(1.0).timeout
		var c0: int = p.back.count()
		await create_timer(4.0).timeout
		var r: float = float(p.back.count() - c0) / 4.0
		var want: float = float(g.tool().dmg) / float(g.tool().interval)
		if lv == 0: r0 = r
		ok(absf(r - want) / want < 0.2, "tool %s: %.2f logs/s (label %.2f/s, x%.1f vs axe)" % [g.tool().name, r, want, r / maxf(r0, 0.01)])
		t.hp = 4; t.max_hp = 4
	g.levels.tool = 0; p.equip_tool(); p.back.set_count(0)
	# kitchen: real cook time per dish matches the label
	for lv in [0, 4, 9]:
		g.levels.fire = lv
		ok(absf(g.cook_time() - g.kitchen_cook(g.cfg, lv) / 1.3) < 0.01, "kitchen Lv %d: %.2fs per dish (1 cook)" % [lv + 1, g.cook_time()])
	g.levels.fire = 0
	# menu, dining, sign, station
	g.levels.menu = 5
	ok(g.dish_price() > int(g.menu_price(g.cfg, 0)), "menu Lv 6 raises the dish price (%d -> %d)" % [int(g.menu_price(g.cfg, 0)), g.dish_price()])
	g.levels.menu = 0
	var si0: float = w.spawn_interval()
	g.levels.sign = 10
	var si1: float = w.spawn_interval()
	ok(si1 < si0 * 0.75, "signboard Lv 11: guests every %.2fs instead of %.2fs (label +40%%)" % [si1, si0])
	g.levels.sign = 0
	g.levels.dining = 10
	ok(absf(g.dining_patience() - 1.3) < 0.001 and g.seated_tip() > float(g.cfg.customers.seated_tip), "dining Lv 11: patience x%.2f, tips %d%%" % [g.dining_patience(), int(g.seated_tip() * 100)])
	g.levels.dining = 0

	# ---------------- Part B: live income per config, crew only, player parked
	var configs := [["base", {}], ["kitchen +5", {"fire": 5}], ["menu +5", {"menu": 5}], ["dining +5", {"dining": 5}],
		["sign +5", {"sign": 5}]]
	if g.special_type() != "":
		configs.append(["station +5", {"station": 5}])
	var base_rate := 0.0
	print("     --- live crew income (no player), %s, crew 2 lumberjacks / 2 waiters / 1 cook" % g.chapter().name)
	for c in configs:
		_base(g, c[1])
		change_scene_to_file("res://scenes/main.tscn")
		await _ready_scene()
		w = current_scene.world
		current_scene.hud._story_q.clear(); current_scene.hud.close_modal()
		w.player.global_position = Vector3(-9, 0, 9)
		Engine.time_scale = 8.0
		Engine.physics_ticks_per_second = 480
		Engine.max_physics_steps_per_frame = 64
		await create_timer(60.0).timeout          # warm up 1 game minute (timers run in game time)
		var e0: int = g.coins + g.counter_coins
		var s0: int = g.served
		await create_timer(180.0).timeout         # measure 3 game minutes
		var per_min: float = float(g.coins + g.counter_coins - e0) / 3.0
		var served_min: float = float(g.served - s0) / 3.0
		Engine.time_scale = 1.0
		Engine.physics_ticks_per_second = 60
		var model: float = g.passive_rate() * 60.0
		var cost := 0
		for k in c[1]:
			var save_lv: int = g.levels[k]
			for i in int(c[1][k]):
				g.levels[k] = i
				cost += g.station_cost(k)
			g.levels[k] = save_lv
		if c[0] == "base":
			base_rate = per_min
			print("     %-11s %8s/min  %5.1f guests/min   (model %s/min)" % [c[0], _c(per_min), served_min, _c(model)])
		else:
			var gain := per_min - base_rate
			var payback := "never" if gain <= 0.0 else ("%.1f min" % (float(cost) / gain))
			print("     %-11s %8s/min  %5.1f guests/min   cost %s   gain %+.0f%%   payback %s   (model %s/min)" % [c[0], _c(per_min), served_min, _c(cost), 100.0 * gain / maxf(base_rate, 1.0), payback, _c(model)])
	print("UPGRADES chapter=%d fails=%d" % [chap + 1, fails])
	quit()


func _c(n: float) -> String:
	var v := absf(n)
	if v >= 1e6: return "$%.2fM" % (n / 1e6)
	if v >= 1e4: return "$%.1fK" % (n / 1e3)
	return "$%d" % int(n)
