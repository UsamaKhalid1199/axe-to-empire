extends SceneTree
## QA tester 1: tills (background cash on each place's counter), crossing money, save/load, migration, prestige.
## Pure Game-level logic (no scene). Run: $G --headless --path . -s res://tests/qa/qa_t1_tills.gd
var fails := 0
var g


func ok(c: bool, msg: String) -> void:
	print(("PASS " if c else "FAIL ") + msg)
	if not c:
		fails += 1


func _initialize() -> void:
	_run.call_deferred()


func _full(k: int) -> Dictionary:
	var b := {"campfire": true, "tables_1": true, "shop": true, "crew_hut": true, "fire_2": true, "tables_2": true}
	if String(g.chapters[k].get("special", {}).get("type", "")) != "":
		b["special"] = true
	return b


func _venue_dict(k: int, till := 0) -> Dictionary:
	return {"built": _full(k), "crew": {"lumberjack": 3, "waiter": 2, "cook": 2}, "counter_coins": till,
		"woodpile": 20, "rack": 3, "fire": 4, "menu": 6, "dining": 2, "sign": 3, "station": 2,
		"chapter_done": true, "bigday": {"won": true}, "task_i": 13}


## Empire with chapters 0..n-1 owned, venue `at` active (fully built, active state loaded from its dict).
func _empire(n: int, at: int) -> void:
	g.prestige = 0; g.coins = 1000; g.offline_reward = 0
	g.unlocked = n
	g.venues = []
	for k in n:
		g.venues.append(_venue_dict(k))
	g.venue = at
	g._unstash(at)
	g._cc_cache.clear()
	g.cfg = g.chapter_cfg(at)
	g._rates.clear(); g._rates_t = 0.0; g._till_acc = {}
	g.refresh_stars()


func _tick(secs: float, dt := 1.0 / 60.0) -> void:
	var t := 0.0
	while t < secs - 1e-9:
		g._empire_tick(dt)
		t += dt


func _run() -> void:
	g = root.get_node("Game")
	g.set_process(false)             # we drive the ticks by hand
	g.saving_enabled = false
	g.settings.story = false

	# ------------------------------------------------ accrual rate, cap, active place
	for at in [1, 5]:
		_empire(6, at)
		var k := 0 if at != 0 else 1
		var r: float = g.venue_rate(k) * g.VENUE_EFFICIENCY
		var cap: int = g.till_cap(k)
		ok(r > 0.0, "ch%d bg rate of place %d > 0 (%.2f/s)" % [at, k, r])
		ok(cap == maxi(200, int(r * 60.0 * g.TILL_CAP_MIN)), "till_cap(%d)=%d is 20 min of the bg rate (%.0f)" % [k, cap, r * 1200.0])
		var ctr0: int = g.counter_coins
		var coins0: int = g.coins
		var fired := [0]
		var cb := func(): fired[0] += 1
		g.tills_changed.connect(cb)
		_tick(60.0)
		g.tills_changed.disconnect(cb)
		var got: int = g.till(k)
		ok(absi(got - int(r * 60.0)) <= 1, "after 60 s place %d till=%d, expected %.1f (rate*eff*60)" % [k, got, r * 60.0])
		ok(fired[0] > 0, "tills_changed fired (%d times)" % fired[0])
		ok(g.counter_coins == ctr0, "active place's counter untouched by the empire tick (%d -> %d)" % [ctr0, g.counter_coins])
		ok(g.coins == coins0, "empire tick doesn't touch the wallet (%d -> %d)" % [coins0, g.coins])
		# sum of every other place
		var sum := 0.0
		for kk in 6:
			if kk != at:
				sum += g.venue_rate(kk) * g.VENUE_EFFICIENCY
		ok(absf(sum - g.empire_rate()) < 0.01 * sum + 0.01, "empire_rate %.2f == sum of bg rates %.2f" % [g.empire_rate(), sum])
		# cap respected (tick big steps and small steps)
		_tick(30.0 * 60.0, 0.5)
		ok(g.till(k) == cap, "after 30 min place %d till=%d == cap %d" % [k, g.till(k), cap])
		_tick(60.0)
		ok(g.till(k) == cap, "stays at cap (%d)" % g.till(k))
		print("  ch%d active: place %d bg %.1f/s, cap %d, tills_waiting %d" % [at, k, r, cap, g.tills_waiting()])

	# ------------------------------------------------ frame-rate independence (30 fps phone vs big deltas)
	_empire(2, 1)
	_tick(120.0, 1.0 / 30.0)
	var a30: int = g.till(0)
	_empire(2, 1)
	_tick(120.0, 0.25)
	var a4: int = g.till(0)
	var exp120: float = g.venue_rate(0) * g.VENUE_EFFICIENCY * 120.0
	ok(absi(a30 - a4) <= 1 and absf(a30 - exp120) <= 1.5, "accrual frame-rate independent: 30fps %d, 4fps %d, expected %.1f" % [a30, a4, exp120])

	# ------------------------------------------------ low rate: fractional coins don't vanish
	_empire(2, 1)
	g.venues[0]["crew"] = {"lumberjack": 1, "waiter": 1, "cook": 0}
	g.venues[0]["built"] = {"campfire": true}
	g.venues[0]["menu"] = 0; g.venues[0]["fire"] = 0; g.venues[0]["sign"] = 0
	g._rates.clear(); g._rates_t = 0.0
	var rl: float = g.venue_rate(0) * g.VENUE_EFFICIENCY
	_tick(100.0, 1.0 / 60.0)
	ok(absf(g.till(0) - rl * 100.0) <= 1.0, "low rate %.3f/s: 100 s -> till %d (expected %.1f)" % [rl, g.till(0), rl * 100.0])

	# ------------------------------------------------ _in_background gating (phone locked)
	_empire(2, 1)
	g._in_background = true
	var t0: int = g.till(0)
	var play0: float = g.stats.play_s
	for i in 600:
		g._process(0.1)
	ok(g.till(0) == t0 and is_equal_approx(g.stats.play_s, play0), "in background: _process accrues nothing (till %d->%d)" % [t0, g.till(0)])
	g._in_background = false
	for i in 100:
		g._process(0.1)
	ok(g.till(0) > t0, "after resume accrual restarts (%d)" % g.till(0))
	# mobile notification path can't run on desktop (OS.has_feature("mobile") false): check it is guarded
	g._notification(NOTIFICATION_APPLICATION_PAUSED)
	ok(not g._in_background, "desktop: PAUSED notification doesn't set _in_background (mobile only)")
	g._notification(NOTIFICATION_APPLICATION_RESUMED)

	# ------------------------------------------------ crossing: money exact, no double pay
	_empire(3, 1)
	g.venues[0]["counter_coins"] = 500
	g.venues[2]["counter_coins"] = 700
	g.counter_coins = 300           # cash left on the counter where you are
	g.coins = 12345
	ok(g.travel(0), "travel 1 -> 0")
	ok(g.coins == 12345, "coins unchanged on crossing (%d)" % g.coins)
	ok(g.counter_coins == 500, "arrive at 0: its till 500 is now the counter (%d)" % g.counter_coins)
	ok(g.till(1) == 300, "place 1 keeps the 300 left on its counter (%d)" % g.till(1))
	ok(g.till(0) == 500, "till(active) = counter (%d)" % g.till(0))
	ok(g.tills_waiting() == 1000, "tills_waiting excludes the active place: %d (expected 300+700)" % g.tills_waiting())
	# collect it all at 0 (what collect_cash does), cross back and forth quickly: nothing more appears
	var c := int(g.counter_coins)
	g.counter_coins -= c; g.add_coins(c)
	var total0: int = g.coins + g.counter_coins + g.tills_waiting()
	var bg_expected: float = 0.0
	var ctr_from_bg := 0.0
	for i in 20:
		for dest in [1, 0]:
			g.travel(dest)
			for kk in 3:
				if kk != g.venue:
					bg_expected += g.venue_rate(kk) * g.VENUE_EFFICIENCY * 0.016
					if kk == 0:
						ctr_from_bg += g.venue_rate(kk) * g.VENUE_EFFICIENCY * 0.016
			g._empire_tick(0.016)
	var total1: int = g.coins + g.counter_coins + g.tills_waiting()
	# 40 ticks of 16 ms each, each one only for the places not active
	ok(absf(total1 - total0 - bg_expected) <= 3.0, "20 quick round trips: total cash %d -> %d, grew %d == bg accrual %.1f (no double-pay, no loss)" % [total0, total1, total1 - total0, bg_expected])
	ok(g.coins == 12345 + 500, "wallet unchanged by 40 crossings (%d)" % g.coins)
	ok(absf(g.counter_coins - ctr_from_bg) <= 1.0, "collected counter only holds what accrued while away (%d vs %.1f)" % [g.counter_coins, ctr_from_bg])

	# ------------------------------------------------ head start only once; crossing doesn't re-gift
	_empire(2, 1)
	g.unlocked = 3
	g.venues.resize(2)
	ok(g.travel(2), "first trip to new place 2")
	ok(g.built.has("campfire") and g.crew.lumberjack == 1 and g.woodpile == 12, "head start: campfire, 1 lumberjack, 12 logs")
	g.woodpile = 0
	g.travel(1); g.travel(2)
	ok(g.woodpile == 0, "head start not given again on return (woodpile %d)" % g.woodpile)
	ok(g.till(2) == 0 and g.venues[2].get("counter_coins", 0) == 0, "new place starts with empty till")

	# ------------------------------------------------ save mid-world, reload
	var keep := FileAccess.get_file_as_string(g.SAVE_PATH) if FileAccess.file_exists(g.SAVE_PATH) else ""
	var keepb := FileAccess.get_file_as_string(g.BACKUP_PATH) if FileAccess.file_exists(g.BACKUP_PATH) else ""
	_empire(4, 2)
	_tick(300.0, 0.5)
	var tills := [g.till(0), g.till(1), g.till(3)]
	g.counter_coins = 4321
	g.coins = 98765
	g.saving_enabled = true
	g.save_game()
	var dsave: Dictionary = g.to_dict()
	ok(int(dsave.get("save_ver", 0)) == g.SAVE_VER, "save has save_ver %d" % int(dsave.get("save_ver", 0)))
	g.venues = []; g.venue = 0; g.coins = 0; g.counter_coins = 0
	g.load_game()
	ok(g.venue == 2 and g.coins == 98765 and g.counter_coins == 4321, "reload: venue %d coins %d counter %d" % [g.venue, g.coins, g.counter_coins])
	ok([g.till(0), g.till(1), g.till(3)] == tills, "reload keeps tills %s (got %s)" % [tills, [g.till(0), g.till(1), g.till(3)]])
	ok(g.offline_reward == 0, "reload: no away earnings (offline_reward %d)" % g.offline_reward)
	# reload after "hours" closed: still nothing
	var dold: Dictionary = g.to_dict()
	dold.t = int(Time.get_unix_time_from_system()) - 6 * 3600
	var f := FileAccess.open(g.SAVE_PATH, FileAccess.WRITE); f.store_string(JSON.stringify(dold)); f.close()
	g.load_game()
	ok(g.offline_reward == 0 and [g.till(0), g.till(1), g.till(3)] == tills and g.coins == 98765,
		"6 h closed: no offline reward (%d), tills unchanged, coins %d" % [g.offline_reward, g.coins])

	# ------------------------------------------------ old save (no save_ver): migration
	_empire(3, 1)
	g.venues[0]["counter_coins"] = 650
	g.coins = 5000
	var d: Dictionary = g.to_dict()
	d.erase("save_ver")
	d["offline_reward"] = 2500000         # an old away-earnings payout still waiting to be claimed in that save
	d.t = int(Time.get_unix_time_from_system()) - 3 * 86400
	f = FileAccess.open(g.SAVE_PATH, FileAccess.WRITE); f.store_string(JSON.stringify(d)); f.close()
	g.load_game()
	ok(g.coins == 5000 and g.venue == 1 and g.unlocked == 3, "old save keeps progress (coins %d venue %d unlocked %d)" % [g.coins, g.venue, g.unlocked])
	ok(g.till(0) <= g.till_cap(0), "old save: till(0)=%d within cap %d" % [g.till(0), g.till_cap(0)])
	print("  old save with offline_reward=2.5M pending -> offline_reward after load = %d (offline.enabled=false)" % g.offline_reward)
	ok(g.offline_reward == 0, "old save (no save_ver) doesn't pay out a stale away-earnings pile (offline_reward=%d)" % g.offline_reward)
	# old save where the background till is far beyond the new cap (pre-v3 counter left untouched)
	d["offline_reward"] = 0
	d.venues[0]["counter_coins"] = 50000000
	f = FileAccess.open(g.SAVE_PATH, FileAccess.WRITE); f.store_string(JSON.stringify(d)); f.close()
	g.load_game()
	print("  old save till(0)=%d cap=%d" % [g.till(0), g.till_cap(0)])
	g.saving_enabled = false

	# ------------------------------------------------ prestige resets tills and neighbours
	_empire(6, 5)
	_tick(600.0, 0.5)
	ok(g.tills_waiting() > 0, "before New Empire: %d waiting" % g.tills_waiting())
	g.chapter_done = true
	g.bigday = {"won": true}
	g.start_new_empire()
	ok(g.prestige == 1 and g.venue == 0 and g.unlocked == 1 and g.venues.size() <= 1, "New Empire: prestige 1, venue 0, unlocked 1, venues %d" % g.venues.size())
	ok(g.tills_waiting() == 0 and g.counter_coins == 0 and g.coins == 0, "New Empire: tills %d, counter %d, coins %d" % [g.tills_waiting(), g.counter_coins, g.coins])
	ok(g.empire_rate() == 0.0, "New Empire: no background income (%.2f)" % g.empire_rate())
	_tick(60.0)
	ok(g.tills_waiting() == 0, "New Empire: still nothing waiting after 60 s")
	ok(g.till(1) == 0 and g.till(5) == 0, "old places' tills gone")
	ok(g.crew.lumberjack == 0 and g.built.is_empty() and g.woodpile == 0 and g.rack == 0, "venue 0 fresh: crew %s built %s" % [g.crew, g.built])
	ok(g.reno.is_empty() and g.bigday.is_empty() and g.task_i == 0, "reno/bigday/task reset")

	# restore the real save
	if keep != "":
		f = FileAccess.open(g.SAVE_PATH, FileAccess.WRITE); f.store_string(keep); f.close()
	if keepb != "":
		f = FileAccess.open(g.BACKUP_PATH, FileAccess.WRITE); f.store_string(keepb); f.close()
	print("FAILS=%d" % fails)
	quit()
