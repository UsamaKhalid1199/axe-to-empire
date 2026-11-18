extends SceneTree
## Visual QA: pushes the longest real texts through every HUD surface, per chapter. -- <outdir>
## Run at several phone resolutions, e.g. --resolution 720x1600 -- <outdir> 720x1600 (the second arg forces the
## exact window size even past the monitor height), then 1080x2400, 1080x1920, 720x1280.
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
	# optional exact window size: -- <outdir> 1080x2400. Windows clamps --resolution to the monitor, so a
	# borderless window is resized after start (that one may be bigger than the screen).
	if OS.get_cmdline_user_args().size() > 1:
		var wh: PackedStringArray = OS.get_cmdline_user_args()[1].split("x")
		root.borderless = true
		root.position = Vector2i(0, 0)
		root.size = Vector2i(int(wh[0]), int(wh[1]))
		for i in 5:
			await process_frame
		print("UIQA window ", DisplayServer.window_get_size(), " ui ", root.get_visible_rect().size)
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
		# the places you own before this one have crews and cash waiting on their counters
		while g.venues.size() < k:
			g.venues.append({})
		for j in k:
			g.venues[j] = {"crew": {"lumberjack": 2, "waiter": 2, "cook": 1}, "built": {"campfire": true, "tables_1": true, "crew_hut": true, "special": true},
				"counter_coins": 98765432 if j == 0 else 1234 * (j + 1)}
		g._in_background = true
		g.tills_changed.emit()
		await _shot("ch%d_tillchip" % k)
		# longest toasts
		for t in ["Welcome next door! Your $123.4M came with you, and your crew set up the grill.",
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
		hud._toast_q.clear(); hud._toast_t = 0.0
		hud.show_toast("Welcome next door! Your $123.4M came with you, and your crew set up the grill.")
		await _shot("ch%d_reno_toast" % k)
		g.reno = {}
		for m in ["gate", "upgrades", "character", "settings", "jobs", "crew", "shop", "empire", "complete", "stats", "howto", "offline"]:
			if m == "offline":
				g.offline_reward = 4567890; g.offline_seconds = 7380
			hud.open_modal(m)
			await _shot("ch%d_%s" % [k, m])
			if m in ["upgrades", "character", "empire"]:       # scrolled to the bottom too
				var sc: Array = hud.modal.find_children("*", "ScrollContainer", true, false)
				if not sc.is_empty():
					sc[0].scroll_vertical = 100000
					await _shot("ch%d_%s_end" % [k, m])
			if m == "settings":
				hud._confirm_reset = true; hud._rebuild_modal()
				await _shot("ch%d_settings_reset" % k)
			hud.close_modal()
			g.offline_reward = 0
		# last chapter: the "Start new empire" confirmation
		if k == 4:
			var keep := [g.venue, g.chapter_done]
			g.venue = g.chapters.size() - 1; g.chapter_done = true
			hud.open_modal("complete")
			await _shot("last_complete")
			hud._confirm_prestige = true; hud._rebuild_modal()
			await _shot("last_complete_confirm")
			hud.open_modal("gate")
			await _shot("last_gate")
			hud.close_modal()
			g.venue = keep[0]; g.chapter_done = keep[1]
		# story cards: longest beat of the chapter
		g.seen = {"task_init": true}
		g.fire_story("start")
		await _shot("ch%d_story" % k)
		if hud.modal_kind == "story" and hud._story_q.size() > 1:
			hud._story_q.pop_front(); hud._rebuild_modal()
			await _shot("ch%d_story2" % k)
		hud._story_q.clear(); hud.close_modal()
		w.start_big_day()
		await _shot("ch%d_bigday" % k)
		w.bd_active = false
		hud._bd_result = [false, 12, 30]
		hud.open_modal("bigday_result")
		await _shot("ch%d_bdresult" % k)
		g.bigday = {"won": true}
		hud._bd_result = [true, 34, 30]
		hud.open_modal("bigday_result")
		await _shot("ch%d_bdresult_won" % k)
		g.bigday = {}
		hud.close_modal()
	quit()
