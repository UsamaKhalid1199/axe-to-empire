extends SceneTree
## QA round 4: pads work when the player's body stands on their edge, and a part-paid pad finishes.
## On the phone the campfire pad took $20 of $24 and then never the last $4: the player stood with their body on
## the pad but their origin just outside it. Every pad now counts Zone.REACH past its edge; where two pads'
## margins meet, only the closest one is active.
## Run: $G --headless --path . -s res://tests/qa/qa_r4_pads.gd
var fails := 0
var g


func ok(c: bool, msg: String) -> void:
	print(("PASS " if c else "FAIL ") + msg)
	if not c:
		fails += 1


func _initialize() -> void:
	_run.call_deferred()


func _wait(n: int) -> void:
	for i in n:
		await process_frame


func _secs(s: float) -> void:
	await create_timer(s).timeout


func _ready_scene() -> void:
	while current_scene == null or current_scene.get("hud") == null or current_scene.get_node_or_null("LoadingScreen") != null \
			or current_scene.get("crossing"):
		await process_frame


func _stand(p: Vector3) -> void:
	var w = current_scene.world
	w.player.global_position = p
	w.player.input_dir = Vector2.ZERO
	w.player._vel = Vector3.ZERO
	await _wait(2)


func _run() -> void:
	g = root.get_node("Game")
	g.saving_enabled = false
	g.offline_reward = 0
	g.settings.story = false
	g.coins = 20; g.served = 0; g.pad_paid = {}; g.chapter_done = false; g.prestige = 0
	g.venue = 0; g.unlocked = 1; g.venues = []; g.vserved = 0; g.cfg = g.chapter_cfg(0)
	g.reno = {}; g.bigday = {}; g.seen = {"task_init": true}; g.task_i = 0; g.task_base = 0; g.golden_n = 0
	g.built = {}
	g.crew = {"lumberjack": 0, "waiter": 0, "cook": 0}
	g.woodpile = 0; g.counter_coins = 0; g.rack = 0
	g.levels = {"tool": 0, "bag": 0, "boots": 0, "fire": 0, "menu": 0, "dining": 0, "sign": 0, "station": 0}
	change_scene_to_file("res://scenes/main.tscn")
	await _ready_scene()
	await _wait(5)
	var w = current_scene.world
	var cost := int(g.build_def("campfire").cost)
	var pad = w.pads.get("campfire")
	ok(pad != null, "campfire pad is there (cost %d)" % cost)
	# body on the pad's south edge, origin 0.3 m outside it
	var edge: Vector3 = pad.global_position + Vector3(0, 0, pad.size.y * 0.5 + 0.3)
	await _stand(edge)
	await _secs(2.5)
	var paid := int(g.pad_paid.get("campfire", 0))
	ok(paid == 20 and g.coins == 0, "standing on the pad's edge pays what you have (%d of %d paid, coins %d)" % [paid, cost, g.coins])
	# the cash arrives while still standing there (e.g. a sale): the last part goes in without stepping off
	g.coins = 10
	g.coins_changed.emit(g.coins)
	await _secs(2.0)
	ok(g.built.has("campfire"), "part-paid pad finishes while you stay on it (built=%s, coins %d)" % [g.built.has("campfire"), g.coins])
	ok(g.coins == 10 - (cost - 20), "only the rest was taken (coins %d)" % g.coins)
	# a body further out does not count
	await _wait(5)
	w = current_scene.world
	var shop_pad = w.pads.get("shop")
	if shop_pad == null:
		for z in w.zones:
			if z.kind == "build":
				shop_pad = z
				break
	if shop_pad:
		g.coins = 0
		await _stand(shop_pad.global_position + Vector3(shop_pad.size.x * 0.5 + 0.7, 0, 0))
		await _wait(5)
		ok(not shop_pad.occupied, "0.7 m off a pad does not count")
		await _stand(shop_pad.global_position + Vector3(shop_pad.size.x * 0.5 + 0.35, 0, 0))
		await _wait(5)
		ok(shop_pad.occupied, "0.35 m off a pad's edge (body on it) counts")
	# rack and serve pads are 5 cm apart: in the gap (and on their margins) only the closest one is active
	w = current_scene.world
	var rz = w.rack_zone
	var sz = w.serve_zone
	ok(rz != null and sz != null, "rack and serve pads exist")
	var gap_z: float = (rz.global_position.z + rz.size.y * 0.5 + sz.global_position.z - sz.size.y * 0.5) * 0.5
	await _stand(Vector3(rz.global_position.x, 0, gap_z - 0.01))
	await _wait(4)
	ok(rz.occupied and not sz.occupied, "nearer the rack: only the rack pad is active (rack %s, serve %s)" % [rz.occupied, sz.occupied])
	await _stand(Vector3(rz.global_position.x, 0, gap_z + 0.2))
	await _wait(4)
	ok(sz.occupied and not rz.occupied, "inside the serve pad: only it is active, not the rack's margin (rack %s, serve %s)" % [rz.occupied, sz.occupied])
	var cz = w.coin_zone
	await _stand(cz.global_position + Vector3(-cz.size.x * 0.5 - 0.3, 0, 0))     # off the coin pad, toward the serve pad
	await _wait(4)
	var active := 0
	for z in w.zones:
		if z.occupied:
			active += 1
	ok(active == 1, "between the serve and coin pads only one pad is active (%d)" % active)

	load("res://scripts/world/plot.gd").finish_jobs()
	print("RESULT qa_r4_pads fails=%d" % fails)
	quit(1 if fails > 0 else 0)
