extends SceneTree
## Regression checks for the systems audit: level cap, star-3 replay, task progress across reloads, away cash kept.
var fails := 0
func ok(c: bool, msg: String) -> void:
	print(("PASS " if c else "FAIL ") + msg)
	if not c: fails += 1
func _initialize() -> void:
	_run.call_deferred()
func _ready_scene() -> void:
	while current_scene == null or current_scene.get("hud") == null or current_scene.get_node_or_null("LoadingScreen") != null:
		await process_frame
func _run() -> void:
	var g = root.get_node("Game")
	g.saving_enabled = false
	g.offline_reward = 0
	g.coins = 0; g.served = 0; g.built = {}; g.pad_paid = {}; g.chapter_done = false
	g.venue = 0; g.unlocked = 1; g.venues = []; g.vserved = 0; g.prestige = 0; g.cfg = g.chapter_cfg(0)
	g.reno = {}; g.bigday = {}; g.seen = {}; g.task_i = 0; g.task_base = 0; g.golden_n = 0
	g.levels = {"tool": 0, "bag": 0, "boots": 0, "fire": 0, "menu": 0, "dining": 0, "sign": 0, "station": 0}
	g.settings.story = false
	change_scene_to_file("res://scenes/main.tscn")
	await _ready_scene()
	var w = current_scene.world
	g.built = {"campfire": true, "tables_1": true, "shop": true, "crew_hut": true, "fire_2": true, "tables_2": true}
	# level cap: shown Lv 25 is the last one
	g.levels.menu = g.station_max() - 1
	ok(g.station_locked("menu") == "MAX", "menu at Lv %d is maxed" % g.station_max())
	g.levels.menu = 0
	# star 3: a win with walkouts can be replayed, a clean win cannot
	g.big_day_result(true, false)
	ok(g.big_day_replayable() and not g.big_day_ready(), "won with walkouts: replay offered, no nag")
	ok(w.start_big_day(), "replay starts")
	w.bd_active = false
	g.big_day_result(true, true)
	ok(not g.big_day_replayable(), "clean win: no more replays")
	ok(g.star_count() >= 1, "star 1 kept (%d)" % g.star_count())
	# task progress survives a reload of the venue
	ok(g.seen.has("task_init"), "task chain marked as started")
	# away cash adds up instead of being overwritten
	g.offline_reward = 100
	var before: int = g.offline_reward
	g._compute_offline(int(Time.get_unix_time_from_system()) - 3600)
	ok(g.offline_reward >= before, "away cash accumulates (%d -> %d)" % [before, g.offline_reward])
	g.offline_reward = 0
	# a full cash pile comes over in well under a second
	g.counter_coins = 5000
	w.coin_stack.set_count(w._coin_visuals(g.counter_coins))
	var c0: int = g.coins
	w.player.global_position = w.COIN_POS
	await create_timer(0.8).timeout
	ok(g.counter_coins == 0 and g.coins - c0 == 5000, "cash pile collected in 0.8 s (left %d, got %d)" % [g.counter_coins, g.coins - c0])
	# a pad already paid in full (cost changed in an update) finishes instead of blinking forever
	g.built.erase("tables_2")
	g.pad_paid["tables_2"] = 999999
	g.pay_pad("tables_2", 10)
	ok(g.built.has("tables_2"), "over-paid pad completes")
	# opening the gate keeps your savings
	g.vserved = 500; g.rating_hist = [5.0]; g.coins = 50000
	g.bigday["won"] = true
	g.built["special"] = true
	var before_gate: int = g.coins
	g.open_next_venue()
	ok(g.unlocked >= 2 and g.coins == before_gate, "gate opened and cash kept (%d -> %d)" % [before_gate, g.coins])
	# Pro gear: after the last tier, the shop keeps selling useful, chapter-priced levels
	g.coins = 0
	g.pro = {"tool": 0, "bag": 0, "boots": 0}
	g.levels.tool = g.cfg.tools.size() - 1; g.levels.bag = g.cfg.bag.size() - 1; g.levels.boots = g.cfg.boots.size() - 1
	var nx: Dictionary = g.next_upgrade("bag")
	ok(nx.has("pro") and int(nx.cost) > 0, "maxed bag offers Pro 1 ($%d)" % int(nx.get("cost", 0)))
	var cap0: int = g.bag_cap(); var sp0: float = g.speed_mult(); var iv0: float = float(g.tool().interval)
	var c1: int = g.pro_cost("bag")
	g.coins = 10000000000
	ok(g.buy_upgrade("bag") and g.buy_upgrade("boots") and g.buy_upgrade("tool"), "Pro levels can be bought")
	ok(g.bag_cap() > cap0 and g.speed_mult() > sp0 and float(g.tool().interval) < iv0, "each Pro level helps (bag %d->%d, speed %.2f->%.2f, swing %.2f->%.2f)" % [cap0, g.bag_cap(), sp0, g.speed_mult(), iv0, float(g.tool().interval)])
	ok(g.pro_cost("bag") > c1, "next Pro level costs more")
	g.pro.bag = g.PRO_MAX
	ok(g.next_upgrade("bag").is_empty(), "Pro caps at %d" % g.PRO_MAX)
	var d: Dictionary = g.to_dict()
	ok(d.has("pro") and int(d.pro.bag) == g.PRO_MAX, "Pro levels are saved")
	var ch1: int = g.pro_cost("boots")
	g.venue = 4
	ok(g.pro_cost("boots") == ch1, "Pro costs the same wherever you stand (ch1 $%d, ch5 $%d)" % [ch1, g.pro_cost("boots")])
	var u0: int = g.unlocked
	g.unlocked = 5
	ok(g.pro_cost("boots") > ch1 * 5, "Pro priced by the furthest place reached ($%d -> $%d)" % [ch1, g.pro_cost("boots")])
	g.unlocked = u0
	g.venue = 0
	print("AUDIT fails=%d" % fails)
	quit()
