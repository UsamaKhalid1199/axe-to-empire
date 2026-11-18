extends SceneTree
## QA round 3, tester 2: can the player get everywhere? (headless, input_dir steering, real physics)
##   $G --headless --path . -s res://tests/qa/qa_r3_t2_nav.gd
## Per chapter: walk onto the coin pad from 4 sides (cash collected?), onto the pile / rack / counter zones,
## a grid of camp spots where the player is boxed in (cannot move 0.3 m in any of 8 directions), and walking the
## whole road edge to edge (the lake corridor at the Lakeside Diner). Prints FAILS=n.
var fails := 0
var g
var w


func ok(c: bool, msg: String) -> void:
	print(("PASS " if c else "FAIL ") + msg)
	if not c:
		fails += 1


func _initialize() -> void:
	_run.call_deferred()


func frames(n: int) -> void:
	for i in n:
		await process_frame


func phys(n: int) -> void:
	for i in n:
		await physics_frame


func _full(k: int) -> Dictionary:
	var b := {"campfire": true, "tables_1": true, "shop": true, "crew_hut": true, "fire_2": true, "tables_2": true}
	if String(g.chapters[k].get("special", {}).get("type", "")) != "":
		b["special"] = true
	return b


func _scene_ready() -> void:
	await frames(2)
	while current_scene == null or current_scene.get("hud") == null or current_scene.get_node_or_null("LoadingScreen") != null \
			or current_scene.get("crossing"):
		await process_frame
	await frames(10)
	w = current_scene.world
	current_scene.hud._story_q.clear()
	if current_scene.hud.modal_kind != "":
		current_scene.hud.close_modal()


func _put(p: Vector3) -> void:
	w.player.global_position = p
	w.player._vel = Vector3.ZERO
	w.player.input_dir = Vector2.ZERO
	w._cross_armed = false


## Steer toward `to` for up to secs; returns the closest distance reached.
func _go(to: Vector3, secs: float) -> float:
	var best := 999.0
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(secs * 1000.0):
		var d: Vector3 = to - w.player.global_position
		d.y = 0
		best = minf(best, d.length())
		if d.length() < 0.15:
			break
		var v := Vector2(d.x, d.z).normalized()
		w.player.input_dir = v
		await physics_frame
		if current_scene.get("crossing"):
			break
	w.player.input_dir = Vector2.ZERO
	return best


func _run() -> void:
	root.size = Vector2i(720, 1600)
	g = root.get_node("Game")
	g.saving_enabled = false
	g.offline_reward = 0
	g.settings.story = false
	for k in g.chapters.size():
		g.venue = k; g.unlocked = k + 1; g.venues = []; g.cfg = g.chapter_cfg(k)
		g.reno = {}; g.bigday = {}; g.seen = {"task_init": true}; g.task_i = 0; g.task_base = 0; g.chapter_done = false
		g.built = _full(k)
		g.crew = {"lumberjack": 0, "waiter": 0, "cook": 0}
		g.coins = 1000; g.vserved = 10; g.woodpile = 0
		while g.venues.size() < g.unlocked:
			g.venues.append({})
		for j in k:
			g.venues[j] = {"crew": {"lumberjack": 1}, "built": _full(j), "counter_coins": 0}
		change_scene_to_file("res://scenes/main.tscn")
		await _scene_ready()
		g._in_background = true
		var name := String(g.chapters[k].name)
		var cp: Vector3 = w.COIN_POS
		# coin pad from 4 sides
		for side in [Vector3(0, 0, 2.2), Vector3(2.2, 0, 0), Vector3(0, 0, -2.2), Vector3(-2.2, 0, 0)]:
			_put(cp + side)
			await phys(3)
			var start: Vector3 = w.player.global_position
			g.counter_coins = 400
			var c0: int = g.coins
			var best := await _go(cp, 2.5)
			await phys(30)
			var got: int = g.coins - c0
			ok(got > 0 or best < 0.7, "%s: coin pad from %s (start %s): closest %.2f m, collected $%d" % [name, side, start, best, got])
		# zones
		for z in [["pile", w.pile_zone], ["rack", w.rack_zone], ["serve", w.serve_zone], ["sell", w.sell_zone]]:
			if z[1] == null:
				continue
			var zp: Vector3 = z[1].global_position
			_put(zp + Vector3(0, 0, 2.5))
			await phys(3)
			var b2 := await _go(zp, 3.0)
			ok(b2 < 0.8, "%s: reach %s zone from the south (closest %.2f m)" % [name, z[0], b2])
		# boxed-in spots on a 0.5 m grid of the camp (x -7..8, z -3.5..10)
		var boxed: Array = []
		var x := -7.0
		while x <= 8.0:
			var z := -3.5
			while z <= 10.0:
				_put(Vector3(x, 0, z))
				await phys(2)
				var p0: Vector3 = w.player.global_position
				if p0.distance_to(Vector3(x, 0, z)) > 0.3:
					z += 0.5
					continue        # pushed out of a collider: not a spot you can stand
				var free := 0
				for a in 8:
					var dv := Vector2(cos(a * TAU / 8.0), sin(a * TAU / 8.0))
					_put(p0)
					w.player.input_dir = dv
					await phys(8)
					w.player.input_dir = Vector2.ZERO
					if w.player.global_position.distance_to(p0) > 0.3:
						free += 1
						break
				if free == 0:
					boxed.append(Vector2(x, z))
				z += 0.5
			x += 0.5
		ok(boxed.is_empty(), "%s: no boxed-in spots in the camp %s" % [name, str(boxed.slice(0, 12))])
		# behind the cookers: walk from between/behind them to the counter
		var fp: Array = w.FIRE_POS
		var behind: Vector3 = (fp[0] + fp[1]) * 0.5 + Vector3(0, 0, -1.4)
		_put(behind)
		await phys(3)
		var b3 := await _go(w.COUNTER_POS + Vector3(0, 0, -1.2), 4.0)
		print("INFO %s: from behind the cookers %s straight to the rack side: closest %.2f m" % [name, behind, b3])
		# the whole road, west edge -> east edge
		var we: float = load("res://scripts/world/plot.gd").west(k)
		var ee: float = load("res://scripts/world/plot.gd").east(k)
		_put(Vector3(we + 1.5, 0, 11.5))
		await phys(3)
		var t0 := Time.get_ticks_msec()
		w.player.input_dir = Vector2(1, 0)
		var maxx := -100.0
		while Time.get_ticks_msec() - t0 < 12000:
			await physics_frame
			maxx = maxf(maxx, w.player.global_position.x)
			if maxx > ee - 1.4:
				break
		w.player.input_dir = Vector2.ZERO
		ok(maxx > ee - 1.4, "%s: walked the road from the west edge to x=%.1f (east edge %.1f)" % [name, maxx, ee])
	load("res://scripts/world/plot.gd").finish_jobs()
	print("FAILS=%d" % fails)
	quit(1 if fails > 0 else 0)
