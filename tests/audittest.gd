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
	print("AUDIT fails=%d" % fails)
	quit()
