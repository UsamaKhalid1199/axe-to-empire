extends SceneTree
## Visual QA: pushes the longest real texts through every HUD surface, per chapter. -- <outdir>
## Run at several phone resolutions, e.g. --resolution 360x800 and 540x1200.
var out := ""
var n := 0


func _initialize() -> void:
	_run.call_deferred()


func _shot(name: String) -> void:
	await create_timer(0.45).timeout
	n += 1
	root.get_texture().get_image().save_png("%s/%02d_%s.png" % [out, n, name])


func _run() -> void:
	out = OS.get_cmdline_user_args()[0]
	var g = root.get_node("Game")
	g.saving_enabled = false; g.offline_reward = 0
	g.settings.story = true
	for k in [1, 4]:
		g.venue = k; g.unlocked = k + 1; g.venues = []; g.cfg = g.chapter_cfg(k)
		g.reno = {}; g.bigday = {}; g.seen = {"task_init": true}; g.task_i = 0; g.task_base = 0
		g.built = {"campfire": true, "tables_1": true, "shop": true, "crew_hut": true, "fire_2": true, "tables_2": true, "special": true}
		g.crew = {"lumberjack": 1, "waiter": 1, "cook": 1}
		g.vserved = 9999; g.coins = 123456789; g.rating_hist = [5.0]; g.woodpile = 20
		change_scene_to_file("res://scenes/main.tscn")
		while current_scene == null or current_scene.get("hud") == null or current_scene.get_node_or_null("LoadingScreen") != null:
			await process_frame
		var hud = current_scene.hud
		var w = current_scene.world
		hud._story_q.clear(); hud.close_modal()
		# longest toasts
		for t in ["New place! Your $123.4M came with you, and your crew set up the grill",
				"Gate fees refunded: +$20,000. Your savings now always come with you!",
				"Not enough cash: serve guests, then come back to build",
				String(g.special_def().get("intro", ""))]:
			if t != "":
				hud._toast_q.clear(); hud._toast_t = 0.0
				hud.show_toast(t)
				await _shot("ch%d_toast" % k)
		# every task in the chapter's job chain (card) + a long objective in the pill
		for i in g.tasks().size():
			g.task_i = i
			g.task_changed.emit()
			if i % 4 == 0:
				await _shot("ch%d_task%d" % [k, i])
		g.reno = {"id": "station", "end": g.now() + 7000, "to": 19}
		g.task_changed.emit()
		w._bd_cool = 0.0
		await _shot("ch%d_reno" % k)
		g.reno = {}
		for m in ["gate", "upgrades", "character", "settings", "jobs", "crew", "shop", "empire", "complete", "stats", "howto"]:
			hud.open_modal(m)
			await _shot("ch%d_%s" % [k, m])
			hud.close_modal()
		# story cards: longest beat of the chapter
		g.seen = {"task_init": true}
		g.fire_story("start")
		await _shot("ch%d_story" % k)
		hud._story_q.clear(); hud.close_modal()
		w.start_big_day()
		await _shot("ch%d_bigday" % k)
		w.bd_active = false
		hud._bd_result = [false, 12, 30]
		hud.open_modal("bigday_result")
		await _shot("ch%d_bdresult" % k)
		hud.close_modal()
	quit()
