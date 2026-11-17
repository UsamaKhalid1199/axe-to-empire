extends SceneTree
## Signature stations, one per chapter 2-6: build it, use it as the player, then let the crew run it.
## Usage: --script res://tests/specialtest.gd -- <chapter index 1..5>
var fails := 0


func ok(c: bool, what: String) -> void:
	print(("PASS " if c else "FAIL ") + what)
	if not c:
		fails += 1


func _initialize() -> void:
	_run.call_deferred()


func _ready_scene() -> void:
	while current_scene == null or current_scene.get("hud") == null or current_scene.get_node_or_null("LoadingScreen") != null:
		await process_frame
	for i in 3:
		await process_frame


func _run() -> void:
	var k := int(OS.get_cmdline_user_args()[0]) if OS.get_cmdline_user_args().size() > 0 else 1
	var g = root.get_node("Game")
	g.saving_enabled = false
	g.offline_reward = 0
	g.venue = k
	g.unlocked = k + 1
	g.cfg = g.chapter_cfg(k)
	g.built = {"campfire": true, "tables_1": true, "shop": true, "special": true}
	g.crew = {"lumberjack": 0, "waiter": 0, "cook": 0}
	g.sp = {}
	g.woodpile = 10
	g.coins = 100000
	change_scene_to_file("res://scenes/main.tscn")
	await _ready_scene()
	var w = current_scene.world
	var p = w.player
	var sp = w.specials
	var t: String = g.special_type()
	print("CHAPTER ", k, " ", g.chapter().name, " special=", t)
	ok(sp.built and sp.zone != null, "station built with a zone")
	ok(sp.pad_pos().distance_to(sp.zone.global_position) < 0.01, "zone sits on the pad spot")
	# nothing overlaps the camp's other stations
	for other in w.zones:
		if other != sp.zone and other.kind != "special":
			var d := Vector2(other.global_position.x - sp.zone.global_position.x, other.global_position.z - sp.zone.global_position.z)
			if absf(d.x) < (other.size.x + sp.zone.size.x) * 0.5 and absf(d.y) < (other.size.y + sp.zone.size.y) * 0.5:
				ok(false, "zone overlaps " + other.kind)
	var c0: int = g.coins
	p.global_position = sp.zone.global_position
	match t:
		"drive_thru":
			sp._car_t = 9999.0
			sp._spawn_car()
			sp.cars[0].order = 3
			await create_timer(4.0).timeout
			ok(sp.cars[0].state == "wait", "car pulled up to the window")
			ok(sp.dish_need() == 3, "station wants the car's 3 dishes")
			p.hands.set_count(4)
			var s0: int = g.vserved
			await create_timer(3.0).timeout
			ok(p.hands.count() == 1, "player handed 3 dishes through the window (left %d)" % p.hands.count())
			ok(g.vserved == s0 + 3, "3 guests counted as served")
			var want := int(round(3 * g.dish_price() * 1.5))
			ok(g.coins - c0 == want, "car paid 1.5x by card (%d, want %d)" % [g.coins - c0, want])
		"raft":
			p.back.set_count(16)
			await create_timer(2.5).timeout
			ok(float(g.sp.get("away", 0.0)) > 0.0, "full raft sailed to the sawmill")
			ok(p.back.count() == 0, "logs went from the back onto the raft")
			g.sp["away"] = 0.3
			await create_timer(1.0).timeout
			var want := 16 * int(g.cfg.log_sell_price) * 3
			ok(g.coins - c0 == want, "raft paid 3x the truck price (%d, want %d)" % [g.coins - c0, want])
			# crew: lumberjacks send surplus to the raft when the woodpile is full
			g.woodpile = int(g.cfg.woodpile_cap)
			w.pile.set_count(g.woodpile)
			g.rack = int(g.cfg.rack_cap)          # kitchen is stocked, so the pile stays full
			w.rack_stack.set_count(g.rack)
			g.crew.lumberjack = 2
			g.state_changed.emit()
			p.global_position = Vector3(0, 0, 2)
			Engine.time_scale = 4.0
			await create_timer(60.0 * 4.0 / 4.0).timeout
			Engine.time_scale = 1.0
			ok(int(g.sp.get("raft", 0)) > 0 or float(g.sp.get("away", 0.0)) > 0.0, "lumberjacks loaded the raft (raft=%s away=%s)" % [g.sp.get("raft"), g.sp.get("away")])
		"fireplace":
			ok(is_equal_approx(w.price_mult(), 1.0), "cold lodge: normal prices")
			p.back.set_count(6)
			await create_timer(1.5).timeout
			ok(int(g.sp.get("fuel", 0)) == 6, "6 logs in the fireplace")
			ok(is_equal_approx(w.price_mult(), 1.5) and w.patience_mult() > 1.0, "warm lodge: +50% and more patience")
			g.sp["fuel"] = 1
			sp._burn_t = sp.BURN_S - 0.1
			await create_timer(0.5).timeout
			ok(int(g.sp.get("fuel", 0)) == 0 and is_equal_approx(w.price_mult(), 1.0), "fire burns out, prices drop back")
			# crew feeds a cold fireplace once the woodpile has some
			g.woodpile = 20
			w.pile.set_count(20)
			g.crew.lumberjack = 2
			g.state_changed.emit()
			p.global_position = Vector3(0, 0, 2)
			Engine.time_scale = 4.0
			await create_timer(60.0).timeout
			Engine.time_scale = 1.0
			ok(int(g.sp.get("fuel", 0)) > 0, "lumberjacks fed the fireplace (fuel=%d)" % int(g.sp.get("fuel", 0)))
		"bell":
			await create_timer(1.0).timeout
			ok(sp.rush_active(), "standing on the bell starts a rush")
			ok(is_equal_approx(w.price_mult(), 2.0) and w.spawn_interval() < 4.0, "rush: x2 prices, guests flood in (%.1fs)" % w.spawn_interval())
			ok(w.objective.text.begins_with("FAIR RUSH"), "objective shows the rush")
			p.global_position = Vector3(0, 0, 2)
			g.sp["rush"] = 0.2
			await create_timer(1.0).timeout
			ok(not sp.rush_active() and float(g.sp.get("cd", 0.0)) > 60.0, "rush ends, bell cools down")
			p.global_position = sp.zone.global_position
			await create_timer(1.0).timeout
			ok(not sp.rush_active(), "cannot ring again during the cooldown")
		"van":
			p.hands.set_count(4)
			await create_timer(1.5).timeout
			ok(int(g.sp.get("van", 0)) == 4, "4 dishes loaded into the van")
			p.global_position = Vector3(0, 0, 2)
			await create_timer(9.0).timeout
			ok(float(g.sp.get("away", 0.0)) > 0.0, "van left with a partial load after waiting")
			var paid: int = int(g.sp.get("paid", 0))
			ok(paid == int(round(4 * g.dish_price() * 2.0)), "delivery is worth 2x (%d)" % paid)
			g.sp["away"] = 0.3
			var c1: int = g.coins
			await create_timer(1.0).timeout
			ok(g.coins - c1 == paid, "van came back and paid")
			var vips := 0
			for i in 400:
				if sp.roll_vip():
					vips += 1
			ok(vips > 40 and vips < 110, "about 1 in 6 hotel guests is a VIP (%d/400)" % vips)
			# waiters use the van when the counter is stocked
			g.crew.waiter = 2
			g.rack = 12
			w.rack_stack.set_count(12)
			g.state_changed.emit()
			Engine.time_scale = 4.0
			await create_timer(40.0).timeout
			Engine.time_scale = 1.0
			ok(int(g.sp.get("van", 0)) > 0 or float(g.sp.get("away", 0.0)) > 0.0, "waiters loaded the van")
	# crew income bonus for background venues
	var base: float = g._rate(2, 2, 1, {"campfire": true, "tables_1": true, "tables_2": true, "fire_2": true}, 1, 1, g.cfg)
	var with_sp: float = g.passive_rate() if false else base * g._special_mult(k, {"special": true})
	ok(with_sp > base, "built station boosts crew income (x%.2f)" % (with_sp / maxf(base, 0.001)))
	print("SPECIAL %s fails=%d" % [t, fails])
	quit()
