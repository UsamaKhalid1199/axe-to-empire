extends SceneTree
## QA2: real-boot save tests. Modes (after --): old1 | old2 | mid | boot | jobs
## old1/old2/mid write a save and quit; boot starts main.tscn from that save and reports.
var g
var fails := 0
func ok(c: bool, msg: String) -> void:
	print(("PASS " if c else "FAIL ") + msg)
	if not c: fails += 1
func _initialize() -> void:
	_run.call_deferred()
func _ready_scene() -> void:
	while current_scene == null or current_scene.get("hud") == null or current_scene.get_node_or_null("LoadingScreen") != null:
		await process_frame
func _wait(n: int) -> void:
	for i in n: await process_frame

func _write(d: Dictionary) -> void:
	var f := FileAccess.open("user://save_v2.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save_v2.bak"))

func _base() -> Dictionary:
	return {"v": 2, "coins": 500, "served": 300, "built": {}, "pad_paid": {}, "levels": {"tool": 2, "bag": 1, "boots": 1, "fire": 2, "menu": 3},
		"crew": {"lumberjack": 2, "waiter": 1, "cook": 1}, "rating_hist": [5, 5, 4], "stats": {"trees": 50, "logs": 300, "served": 300, "earned": 9000, "sold": 10, "play_s": 3600.0},
		"chapter_done": false, "ftue": 99, "woodpile": 10, "rack": 2, "counter_coins": 40, "jobs_day": "2020-01-01", "jobs": [], "streak": 1,
		"streak_last_day": "", "chest_claimed": false, "t": int(Time.get_unix_time_from_system()) - 30}

func _run() -> void:
	g = root.get_node("Game")
	var mode: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "boot"
	if mode == "old1":
		var d := _base()
		d.chapter_done = true
		d.built = {"campfire": true, "tables_1": true, "shop": true, "crew_hut": true, "fire_2": true, "tables_2": true, "gate": true}
		_write(d)
		print("WROTE old1")
		quit(); return
	if mode == "old2":
		var d := _base()
		d.venue = 1; d.unlocked = 3; d.vserved = 20; d.prestige = 0
		d.built = {"campfire": true, "tables_1": true}
		d.levels = {"tool": 2, "bag": 1, "boots": 1, "fire": 1, "menu": 1}
		d.venues = [
			{"built": {"campfire": true, "tables_1": true, "shop": true, "crew_hut": true, "fire_2": true, "tables_2": true, "gate": true},
			 "pad_paid": {}, "crew": {"lumberjack": 3, "waiter": 2, "cook": 1}, "woodpile": 5, "rack": 0, "counter_coins": 7,
			 "rating_hist": [5], "vserved": 400, "chapter_done": true, "fire": 3, "menu": 2, "sp": {}},
			{"built": {"campfire": true}, "pad_paid": {}, "crew": {"lumberjack": 1}, "woodpile": 0, "rack": 0, "counter_coins": 0,
			 "rating_hist": [], "vserved": 0, "chapter_done": true, "fire": 0, "menu": 0, "sp": {}},
		]
		d.chapter_done = true
		_write(d)
		print("WROTE old2")
		quit(); return
	if mode == "jobs":
		g.saving_enabled = false
		g.venue = 5; g.cfg = g.chapter_cfg(5); g.unlocked = 6; g.chapter_done = true
		g.jobs_day = ""; g.refresh_jobs()
		print("JOBS at ch6: " + str(g.jobs.map(func(j): return [j.id, j.goal, j.reward])))
		g.start_new_empire()
		print("JOBS after New Empire (ch1, coins %d): %s" % [g.coins, str(g.jobs.map(func(j): return [j.id, j.goal, j.reward]))])
		g.jobs_day = ""; g.refresh_jobs()
		print("JOBS fresh ch1: " + str(g.jobs.map(func(j): return [j.id, j.goal, j.reward])))
		quit(); return
	# ---- boot (and optional mid save writer)
	print("BOOT venue=%d unlocked=%d coins=%d refund_note=%d offline=%d chapter_done=%s" % [g.venue, g.unlocked, g.coins, g.refund_note, g.offline_reward, g.chapter_done])
	print("BOOT levels=%s built=%s crew=%s bigday=%s task_i=%d reno=%s" % [g.levels, g.built.keys(), g.crew, g.bigday, g.task_i, g.reno])
	for k in g.venues.size():
		var v: Dictionary = g.venues[k]
		print("BOOT venue[%d] fire=%s menu=%s bigday=%s chapter_done=%s stars=%s" % [k, v.get("fire"), v.get("menu"), v.get("bigday"), v.get("chapter_done"), g.stars(k)])
	change_scene_to_file("res://scenes/main.tscn")
	await _ready_scene()
	await _wait(10)
	var w = current_scene.world
	var hud = current_scene.hud
	print("BOOT objective='%s' arrow=%s task='%s' modal=%s pads=%s" % [w.objective.text, w.arrow.visible, hud.task_title.text, hud.modal_kind, w.pads.keys()])
	if mode == "mid":
		# mid-state at the active venue: reno + Big Day running + gate modal open, then save and stop saving
		g.reno = {"id": "menu", "end": g.now() + 600, "to": 9}
		g.built.merge({"campfire": true, "tables_1": true, "shop": true, "crew_hut": true, "fire_2": true, "tables_2": true, "special": true})
		w._rebuild_all(false)
		var started: bool = w.start_big_day()
		hud.open_modal("gate")
		await _wait(3)
		g.save_game()
		g.saving_enabled = false
		print("MID saved: bd started=%s modal=%s venue=%d reno=%s" % [started, hud.modal_kind, g.venue, g.reno])
		quit(); return
	# travel to every unlocked venue that is new, then back to the first
	for k in g.unlocked:
		if k != g.venue:
			current_scene.travel_to(k)
			await _wait(5); await _ready_scene(); await _wait(10)
			w = current_scene.world; hud = current_scene.hud
			print("TRAVEL %d: built=%s crew=%s levels=%s bigday=%s stars=%s objective='%s' task='%s'" % [k + 1, g.built.keys(), g.crew, [g.levels.fire, g.levels.menu], g.bigday, g.stars(), w.objective.text, hud.task_title.text])
	g.saving_enabled = false
	print("BOOT done coins=%d" % g.coins)
	quit()
