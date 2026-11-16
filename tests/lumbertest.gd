extends SceneTree
## Woodpile full + 1 lumberjack: he must sell logs at the truck and earn coins.
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var g = root.get_node("Game")
	g.saving_enabled = false; g.offline_reward = 0
	g.built = {"campfire": true, "tables_1": true, "shop": true, "crew_hut": true}
	g.crew = {"lumberjack": 1, "waiter": 0, "cook": 0}
	g.woodpile = int(g.cfg.woodpile_cap); g.coins = 0; g.counter_coins = 0; g.rack = 0
	change_scene_to_file("res://scenes/main.tscn")
	while current_scene == null or current_scene.get("hud") == null or current_scene.get_node_or_null("LoadingScreen") != null:
		await process_frame
	var w = current_scene.world
	w.player.global_position = Vector3(8, 0, -8)
	Engine.time_scale = 8.0
	var states := {}
	var sold0: int = g.stats.sold
	for i in 60 * 70:
		await process_frame
		g.woodpile = int(g.cfg.woodpile_cap)   # kitchen never needs wood in this test
		for c in w.get_children():
			if c.get("role") == "lumberjack":
				states[c.state] = true
		if g.stats.sold - sold0 >= 8:
			break
	print("LUMBER states=", states.keys(), " sold=", g.stats.sold - sold0, " coins=", g.coins)
	quit()
