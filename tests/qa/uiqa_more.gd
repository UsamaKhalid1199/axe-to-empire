extends SceneTree
## QA3 extra visual sweep. -- <outdir>
var out := ""
var n := 0


func _initialize() -> void:
	_run.call_deferred()


func _shot(name: String, wait := 0.45) -> void:
	await create_timer(wait).timeout
	n += 1
	root.get_texture().get_image().save_png("%s/%02d_%s.png" % [out, n, name])


func _setup(g, k: int) -> void:
	g.venue = k; g.unlocked = k + 1; g.venues = []; g.cfg = g.chapter_cfg(k)
	g.reno = {}; g.bigday = {}; g.seen = {"task_init": true}; g.task_i = 0; g.task_base = 0
	g.built = {"campfire": true, "tables_1": true, "shop": true, "crew_hut": true, "fire_2": true, "tables_2": true, "special": true}
	g.crew = {"lumberjack": 1, "waiter": 1, "cook": 1}
	g.vserved = 40; g.coins = 9876543210; g.rating_hist = [3.2]; g.woodpile = 20


func _load_scene() -> void:
	change_scene_to_file("res://scenes/main.tscn")
	var shots := 0
	while current_scene == null or current_scene.get("hud") == null or current_scene.get_node_or_null("LoadingScreen") != null:
		await process_frame
		if current_scene != null and current_scene.get_node_or_null("LoadingScreen") != null and shots < 2:
			shots += 1
			await _shot("loading", 0.3)


func _run() -> void:
	out = OS.get_cmdline_user_args()[0]
	var g = root.get_node("Game")
	g.saving_enabled = false; g.offline_reward = 0
	g.settings.story = true
	for k in [0, 2, 3, 5]:
		_setup(g, k)
		if k == 5:
			g.prestige = 2
		await _load_scene()
		var hud = current_scene.hud
		var w = current_scene.world
		hud._story_q.clear(); hud.close_modal()
		# gameplay: let customers arrive
		await _shot("ch%d_play" % k, 6.0)
		# real toasts from code
		for t in ["Room service paid +12.3K", String(g.chapter().get("group", "")),
				"%s reached level %d!" % [String(g.station_def("station").name), 20], "Job done: Sell 20 logs at the truck"]:
			hud._toast_q.clear(); hud._toast_t = 0.0
			hud.show_toast(t)
			await _shot("ch%d_toast" % k)
		g.task_i = 4; g.task_changed.emit()
		await _shot("ch%d_task4" % k)
		for m in ["gate", "upgrades", "empire", "complete", "crew"]:
			hud.open_modal(m)
			await _shot("ch%d_%s" % [k, m])
			hud.close_modal()
		# longest story beat
		var ch: Dictionary = g.story_data.chapters.get(String(g.chapter().id), {})
		var best: Dictionary = {}
		for b in ch.get("beats", []):
			if best.is_empty() or String(b.text).length() > String(best.text).length():
				best = b
		hud._story_q = [best, best]
		hud.open_modal("story")
		await _shot("ch%d_storylong" % k)
		hud._story_q.clear(); hud.close_modal()
		w.start_big_day()
		await _shot("ch%d_bigday" % k)
		w.bd_active = false
		hud._bd_result = [true, 44, 44]
		g.bigday = {"won": true, "clean": false}
		hud.open_modal("bigday_result")
		await _shot("ch%d_bdwon" % k)
		hud.close_modal()
		g.bigday = {}
	# offline modal
	g.offline_reward = 1234567; g.offline_seconds = 3 * 3600 + 7 * 60
	var hud2 = current_scene.hud
	hud2.open_modal("offline")
	await _shot("offline")
	g.offline_reward = 0
	hud2.close_modal()
	# jobs claimable
	if g.jobs.size() >= 3:
		g.jobs[0].prog = g.jobs[0].goal; g.jobs[0].claimed = true
		g.jobs[1].prog = g.jobs[1].goal; g.jobs[1].claimed = false
		g.streak = 6
	hud2.open_modal("jobs")
	await _shot("jobs_claimable")
	hud2.close_modal()
	# character wardrobe, scrolled, each slot
	for slot in ["shirt", "hat", "pants"]:
		hud2._wardrobe_slot = slot
		hud2.open_modal("character")
		await create_timer(0.3).timeout
		var sc: ScrollContainer = hud2.modal.find_children("*", "ScrollContainer", true, false)[0]
		sc.scroll_vertical = 100000
		await _shot("char_%s_scrolled" % slot)
		hud2.close_modal()
	# settings with mobile graphics row + confirm reset
	hud2._confirm_reset = true
	hud2.open_modal("settings")
	await _shot("settings_confirm")
	hud2.close_modal()
	# reno chip with long-hours text and upgrades renovating
	g.reno = {"id": "station", "end": g.now() + 7000, "to": 19}
	g.task_changed.emit()
	await _shot("reno_last")
	hud2.open_modal("upgrades")
	await _shot("upgrades_reno")
	hud2.close_modal()
	quit()
