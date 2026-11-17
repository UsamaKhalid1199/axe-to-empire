extends SceneTree
## New screens: HUD, upgrades, character, settings, story card, gate (Big Day), Big Day result. -- <outdir>
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var out := OS.get_cmdline_user_args()[0]
	var g = root.get_node("Game")
	g.saving_enabled = false; g.offline_reward = 0
	g.venue = 0; g.unlocked = 1; g.venues = []; g.cfg = g.chapter_cfg(0)
	g.reno = {}; g.bigday = {}; g.seen = {"task_init": true}; g.task_i = 3; g.task_base = 0
	g.built = {"campfire": true, "tables_1": true, "shop": true, "crew_hut": true, "fire_2": true, "tables_2": true}
	g.crew = {"lumberjack": 1, "waiter": 1, "cook": 0}
	g.vserved = 150; g.coins = 9000; g.rating_hist = [5.0]; g.woodpile = 20
	change_scene_to_file("res://scenes/main.tscn")
	while current_scene == null or current_scene.get("hud") == null or current_scene.get_node_or_null("LoadingScreen") != null:
		await process_frame
	var hud = current_scene.hud
	hud._story_q.clear(); hud.close_modal()
	await create_timer(3.0).timeout
	root.get_texture().get_image().save_png("%s/hud.png" % out)
	for m in ["upgrades", "character", "settings", "gate", "howto", "stats"]:
		hud.open_modal(m)
		await create_timer(0.5).timeout
		root.get_texture().get_image().save_png("%s/%s.png" % [out, m])
		hud.close_modal()
		await create_timer(0.2).timeout
	g.settings.story = true
	g.seen = {"task_init": true}
	g.fire_story("start")
	await create_timer(0.6).timeout
	root.get_texture().get_image().save_png("%s/story.png" % out)
	hud._story_q.clear(); hud.close_modal()
	current_scene.world.start_big_day()
	await create_timer(4.0).timeout
	root.get_texture().get_image().save_png("%s/bigday.png" % out)
	quit()
