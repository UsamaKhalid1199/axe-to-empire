extends SceneTree
## QA round 3, tester 1: economy + logic sweep without a scene (Game autoload only).
##  A. every purchase: exact charge, once, never negative, no refunds, repeated taps
##  B. tills across 4+ places: rate, cap, collection, leaving/returning keeps cash exact
##  C. save/load round trip mid-everything + old-save (save_ver < 3) migration
##  D. daily jobs / chest / streak across midnight, job rescale on travel
##  E. prestige / new empire
## MUST run with APPDATA pointed at a scratch dir (the test refuses otherwise), so user:// is never the real save:
##   APPDATA=<scratch> $G --headless --path . -s res://tests/qa/qa_r3_t1_econ.gd
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


func _fresh(k: int, prestige := 0) -> void:
	g.prestige = prestige
	g.venue = k
	g.unlocked = k + 1
	g.venues = []
	g._unstash(k)
	g.levels = {"tool": 0, "bag": 0, "boots": 0, "fire": 0, "menu": 0, "dining": 0, "sign": 0, "station": 0}
	g.pro = {"tool": 0, "bag": 0, "boots": 0}
	g._cc_cache.clear()
	g._rates.clear()
	g._till_acc.clear()
	g.cfg = g.chapter_cfg(k)
	g.coins = 0
	g.refresh_stars()


func _run() -> void:
	g = root.get_node("Game")
	var ud := OS.get_user_data_dir()
	if not ud.contains("scratchpad"):
		print("ABORT: user dir is %s (run with APPDATA pointed at a scratch dir)" % ud)
		quit(1)
		return
	g.set_process(false)
	g.saving_enabled = false
	g.settings.story = false
	_purchases()
	_tills()
	_save_load()
	_old_saves()
	_jobs()
	_prestige()
	print("RESULT qa_r3_t1_econ: %d fail(s)" % fails)
	quit()


# ------------------------------------------------------------------ A. purchases
func _purchases() -> void:
	print("--- A. purchases")
	_fresh(1)
	g.built = {"campfire": true}
	# gear
	var n: Dictionary = g.next_upgrade("tool")
	g.coins = int(n.cost) * 2 - 1
	var c0: int = g.coins
	var a: bool = g.buy_upgrade("tool")
	var b: bool = g.buy_upgrade("tool")          # second fast tap: next level costs more than what's left
	ok(a and g.coins == c0 - int(n.cost) and g.levels.tool == 1, "tool: charged exactly %d once (%d -> %d)" % [int(n.cost), c0, g.coins])
	ok(not b or g.coins >= 0, "tool: second tap without the money fails (b=%s coins=%d)" % [b, g.coins])
	g.coins = 0
	ok(not g.buy_upgrade("bag") and g.coins == 0 and g.levels.bag == 0, "bag with $0 fails, coins stay 0")
	ok(not g.spend(-50) and g.coins == 0, "spend(-50) refused")
	ok(not g.spend(1) and g.coins == 0, "spend(1) with $0 refused")
	# Pro: max the track then buy pro levels to PRO_MAX
	g.levels.boots = g.cfg.boots.size() - 1
	var paid := 0
	g.coins = 1 << 50
	var start: int = g.coins
	for i in 12:
		var nx: Dictionary = g.next_upgrade("boots")
		if nx.is_empty():
			break
		paid += int(nx.cost)
		g.buy_upgrade("boots")
	ok(g.pro.boots == g.PRO_MAX and start - g.coins == paid, "boots Pro: %d levels, charged %d total exactly" % [g.pro.boots, paid])
	ok(g.next_upgrade("boots").is_empty() and not g.buy_upgrade("boots") and start - g.coins == paid, "boots past Pro 10: refused, no charge")
	# Pro price depends on where you stand, gear is the player's: compare Camp vs Hotel
	g.pro = {"tool": 0, "bag": 0, "boots": 0}
	var costs := []
	for k in [0, 5]:
		g.venue = k
		g.cfg = g.chapter_cfg(k)
		costs.append(g.pro_cost("tool"))
	g.venue = 1
	g.cfg = g.chapter_cfg(1)
	print("INFO Pro tool lv1 price: at Forest Camp %d, at Grand Hotel %d (x%.0f) - same item, carried everywhere" % [costs[0], costs[1], float(costs[1]) / costs[0]])
	ok(costs[0] == costs[1], "Pro gear costs the same wherever you buy it (else: travel to the Camp to buy Pro x420 cheaper)")
	# crew
	g.built = _full(1)
	g.coins = 0
	var crew_paid := 0
	g.coins = 1 << 40
	start = g.coins
	for role in ["lumberjack", "waiter", "cook"]:
		for i in 5:
			var cc: int = g.crew_next_cost(role)
			if cc < 0:
				break
			crew_paid += cc
			ok(g.hire(role), "hire %s #%d for %d" % [role, g.crew[role], cc])
		ok(not g.hire(role), "hire %s past max refused" % role)
	ok(start - g.coins == crew_paid, "crew charged exactly the listed costs (%d)" % crew_paid)
	# hire with cost-1 coins
	g.crew = {"lumberjack": 0, "waiter": 0, "cook": 0}
	g.coins = g.crew_next_cost("waiter") - 1
	ok(not g.hire("waiter") and g.crew.waiter == 0 and g.coins >= 0, "hire with cost-1 refused")
	# station levels: instant, milestone (renovation), builders busy, rush
	g.levels.fire = 0
	g.reno = {}
	g.coins = 1 << 40
	start = g.coins
	var sp_paid := 0
	for i in 3:
		sp_paid += g.station_cost("fire")
		g.station_upgrade("fire")
	ok(g.levels.fire == 3 and start - g.coins == sp_paid, "kitchen Lv1->4 instant, charged %d exactly" % sp_paid)
	var c4: int = g.station_cost("fire")
	var before: int = g.coins
	ok(g.station_upgrade("fire") and not g.reno.is_empty() and g.levels.fire == 3 and before - g.coins == c4, "kitchen Lv5 starts a renovation, charged %d once" % c4)
	before = g.coins
	ok(not g.station_upgrade("fire") and not g.station_upgrade("menu") and g.coins == before, "during a renovation: same/other station refused (Renovating/Builders busy), no charge")
	var rc: int = g.reno_rush_cost()
	before = g.coins
	ok(g.reno_rush() and g.reno.is_empty() and g.levels.fire == 4 and before - g.coins == rc, "rush: charged %d once, level applied" % rc)
	before = g.coins
	ok(not g.reno_rush() and g.coins == before, "rush with no renovation: refused, no charge")
	# renovation rush when you can't afford it
	g.station_upgrade("menu"); g.station_upgrade("menu"); g.station_upgrade("menu"); g.station_upgrade("menu")
	ok(not g.reno.is_empty(), "menu Lv5 renovating")
	g.coins = 0
	ok(not g.reno_rush() and g.coins == 0 and not g.reno.is_empty(), "rush with $0 refused")
	g.reno = {}
	# build pads: paid in chunks, never more than the cost or than your cash
	_fresh(2)
	g.built = {"campfire": true}
	var bd: Dictionary = g.build_def("tables_1")
	var cost := int(bd.cost)
	g.coins = cost + 777
	var moved := 0
	var guard := 0
	while not g.built.has("tables_1") and guard < 10000:
		moved += g.pay_pad("tables_1", 97)
		guard += 1
	ok(moved == cost and g.coins == 777 and not g.pad_paid.has("tables_1"), "pad tables_1: moved %d == cost %d, $777 left" % [moved, cost])
	ok(g.pay_pad("tables_1", 1000) == 0 and g.coins == 777, "paying into a built pad moves nothing")
	g.coins = 50
	var m2: int = g.pay_pad("shop", 1000)
	ok(m2 == 50 and g.coins == 0 and int(g.pad_paid.shop) == 50, "partial pay with $50: moved 50, coins 0")
	ok(g.pay_pad("shop", 1000) == 0 and g.coins == 0, "pay with $0: nothing")
	ok(g.pay_pad("gate", 1000) == 0, "gate pad takes no money")
	# leaving a half-paid pad and returning keeps the partial payment
	g.unlocked = 4
	g.coins = 0
	g.travel(1)
	g.travel(2)
	ok(int(g.pad_paid.get("shop", 0)) == 50, "half-paid pad keeps its $50 after travel away and back")
	# gate: no fee, idempotent
	_fresh(0)
	g.built = _full(0)
	g.vserved = 9999
	g.rating_hist = [5.0]
	g.bigday = {"won": true}
	g.coins = int(g.cfg.gate.coins)
	before = g.coins
	g.open_next_venue()
	ok(g.unlocked == 2 and g.coins == before and g.chapter_done, "gate: opens, no fee")
	g.open_next_venue()
	ok(g.unlocked == 2 and g.coins == before, "gate twice: no change")
	# wardrobe
	var cat: Array = Wardrobe.catalog()
	var item: Dictionary = {}
	for it in cat:
		if int(it.get("price", 0)) > 0 and int(it.get("stars", 0)) == 0 and not String(it.id) in g.profile.owned:
			item = it
			break
	if not item.is_empty():
		g.coins = int(item.price) * 2
		before = g.coins
		ok(Wardrobe.buy(item.id) and g.coins == before - int(item.price), "wardrobe %s charged %d once" % [item.id, int(item.price)])
		ok(not Wardrobe.buy(item.id) and g.coins == before - int(item.price), "wardrobe rebuy refused")
	var star_item := {}
	for it in cat:
		if int(it.get("stars", 0)) > 0:
			star_item = it
			break
	if not star_item.is_empty():
		g.bigday = {}
		g.venues = []
		g.unlocked = 1
		g.refresh_stars()
		print("INFO total stars %d, item %s needs %d" % [g.total_stars(), star_item.id, int(star_item.stars)])
		g.coins = 1 << 40
		before = g.coins
		ok(not Wardrobe.buy(star_item.id) and g.coins == before, "star-gated item refused without stars")


# ------------------------------------------------------------------ B. tills
func _setup_empire(n: int) -> void:
	_fresh(0)
	g.unlocked = n
	for k in n:
		var cc: Dictionary = g.chapter_cfg(k)
		var bk := _full(k)
		if k < n - 1:
			bk["gate"] = true        # a finished place has its gate open (load repairs it otherwise)
		var d := {"built": bk, "crew": {"lumberjack": 3, "waiter": 2, "cook": 2}, "counter_coins": 0,
			"fire": 9, "menu": 9, "dining": 4, "sign": 4, "station": 4 if k > 0 else 0, "bigday": {"won": true}, "chapter_done": k < n - 1,
			"task_i": 13, "rating_hist": [5.0], "vserved": 500}
		g.venues.append(d)
	g.venue = n - 1
	g._unstash(n - 1)
	g.cfg = g.chapter_cfg(n - 1)
	g._cc_cache.clear()
	g._rates.clear()
	g.refresh_stars()
	g._rates_t = 0.0


func _tick(secs: float, step := 1.0) -> void:
	var t := 0.0
	while t < secs:
		g._empire_tick(step)
		t += step


func _total() -> int:
	var t: int = g.coins + g.counter_coins
	for k in g.venues.size():
		if k != g.venue:
			t += int(g.venues[k].get("counter_coins", 0))
	return t


func _tills() -> void:
	print("--- B. tills")
	_setup_empire(5)
	var rates := []
	for k in 5:
		rates.append(g.venue_rate(k) * g.VENUE_EFFICIENCY)
	print("INFO background rates/min: %s" % str(rates.map(func(r): return int(r * 60))))
	_tick(600.0)          # 10 min
	for k in 4:
		var want := int(rates[k] * 600.0)
		var have: int = g.till(k)
		ok(absi(have - want) <= 2, "till %d after 10 min: %d ~ rate*600 %d" % [k, have, want])
	_tick(1200.0)         # 30 min total: capped at 20 min
	for k in 4:
		ok(g.till(k) == g.till_cap(k) and absi(g.till_cap(k) - int(rates[k] * 1200.0)) <= 2, "till %d capped at 20 min: %d (cap %d)" % [k, g.till(k), g.till_cap(k)])
	ok(g.till(4) == g.counter_coins, "active place's till is its live counter")
	# 60 fps small steps: no loss to rounding
	_setup_empire(4)
	_tick(60.0, 1.0 / 60.0)
	for k in 3:
		var want := int(g.venue_rate(k) * g.VENUE_EFFICIENCY * 60.0)
		ok(absi(g.till(k) - want) <= 2, "60 fps: till %d after 60 s = %d ~ %d" % [k, g.till(k), want])
	# walking around with no time passing never makes or loses cash
	_setup_empire(5)
	_tick(900.0)
	var tot := _total()
	var seq := [3, 2, 1, 0, 1, 4, 0, 4, 2, 2, 3, 1]
	for k in seq:
		g.travel(k)
	ok(_total() == tot, "12 trips with no time passing: total cash+tills unchanged (%d vs %d)" % [_total(), tot])
	# collect at a place (what collect_cash does), leave, return: the till restarts from 0
	g.travel(1)
	var till1: int = g.counter_coins
	ok(till1 > 0, "arriving at place 2: its till %d is on the counter" % till1)
	var c0: int = g.coins
	g.add_coins(g.counter_coins)
	g.counter_coins = 0
	ok(g.coins == c0 + till1, "collected %d" % till1)
	g.travel(4)
	ok(g.till(1) == 0, "after collecting and leaving, place 2's till is 0 (no duplicate)")
	_tick(60.0)
	ok(g.till(1) > 0 and g.till(1) <= int(g.venue_rate(1) * g.VENUE_EFFICIENCY * 60.0) + 2, "place 2 accrues again from 0: %d" % g.till(1))
	# a pile bigger than the cap (left uncollected when walking off) is kept, not trimmed
	g.travel(2)
	g.counter_coins = g.till_cap(2) * 3
	var big: int = g.counter_coins
	g.travel(4)
	_tick(120.0)
	ok(g.till(2) == big, "an uncollected pile above the cap is kept as-is (%d)" % g.till(2))
	# tills don't grow while the app is closed: load computes nothing
	ok(not bool(g.cfg.offline.enabled), "offline.enabled is false")
	# empire_rate matches the sum of tills accrual
	_setup_empire(6)
	var er: float = g.empire_rate()
	var s := 0.0
	for k in 5:
		s += g.venue_rate(k) * g.VENUE_EFFICIENCY
	ok(absf(er - s) < 0.01, "empire_rate %.2f == sum of background rates %.2f" % [er, s])
	# a renovation at a place you're not at completes there, raising its till rate
	g.venues[0]["reno"] = {"id": "menu", "end": g.now() - 1, "to": 10}
	var r_before: float = g.venue_rate(0)
	g._reno_tick()
	ok(int(g.venues[0].menu) == 10 and g.venues[0].reno.is_empty() and g.venue_rate(0) > r_before, "background renovation finished, rate %.1f -> %.1f" % [r_before, g.venue_rate(0)])


# ------------------------------------------------------------------ C. save / load
func _write_save(d: Dictionary) -> void:
	var f := FileAccess.open(g.SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()


func _deep_eq(a, b, path := "") -> String:
	if (a is int or a is float) and (b is int or b is float):
		return "" if absf(float(a) - float(b)) < 0.001 else "%s: %s != %s" % [path, a, b]
	if a is Dictionary and b is Dictionary:
		for k in a:
			if not b.has(k):
				return "%s.%s missing after load" % [path, k]
			var r := _deep_eq(a[k], b[k], "%s.%s" % [path, k])
			if r != "":
				return r
		for k in b:
			if not a.has(k):
				return "%s.%s appeared after load" % [path, k]
		return ""
	if a is Array and b is Array:
		if a.size() != b.size():
			return "%s: size %d != %d" % [path, a.size(), b.size()]
		for i in a.size():
			var r := _deep_eq(a[i], b[i], "%s[%d]" % [path, i])
			if r != "":
				return r
		return ""
	return "" if a == b else "%s: %s != %s" % [path, a, b]


func _save_load() -> void:
	print("--- C. save/load")
	_setup_empire(4)
	_tick(400.0)
	g.coins = 123456
	g.counter_coins = 777
	g.pro = {"tool": 3, "bag": 2, "boots": 1}
	g.levels.tool = 3; g.levels.bag = 4; g.levels.boots = 3
	g.levels.menu = 4
	g.reno = {"id": "menu", "end": g.now() + 500, "to": 4}
	g.venues[1]["reno"] = {"id": "fire", "end": g.now() + 900, "to": 9}
	g.sp = {"away": 12.5, "paid": 900, "raft": 0}
	g.bigday = {"won": false, "tries": 2}
	g.pad_paid = {"tables_2": 333}
	g.built.erase("tables_2")
	g.task_i = 5; g.task_base = 40; g.vserved = 77; g.golden_n = 2
	g.stats.earned = 999999
	g.refresh_jobs()
	g.job_progress("chop", 3)
	var before: Variant = g.to_dict()
	before.erase("t")
	_write_save(g.to_dict())
	# scramble
	g.coins = 0; g.venues = []; g.venue = 0; g.unlocked = 1; g.pro = {"tool": 0, "bag": 0, "boots": 0}; g.reno = {}; g.sp = {}
	g.counter_coins = 0; g.built = {}; g.pad_paid = {}; g.jobs = []
	g.load_game()
	var after: Variant = g.to_dict()
	after.erase("t")
	var diff := _deep_eq(before, after, "save")
	ok(diff == "", "round trip mid-everything (4 places, tills, reno here + away, raft out, partial pad, pro gear, jobs): %s" % (diff if diff != "" else "identical"))
	ok(g.till(0) > 0 and g.till(0) == int(before.venues[0].counter_coins), "tills survive the save (%d)" % g.till(0))
	ok(g.offline_reward == 0, "no away payout on load (offline_reward %d)" % g.offline_reward)
	# load immediately after a walk swap (Game.travel saves; we emulate the file it writes)
	g.travel(2)
	g.refresh_stars()        # stars are derived; load recomputes them
	var t_dict: Variant = g.to_dict()
	t_dict.erase("t")
	_write_save(g.to_dict())
	g.venue = 0; g.venues = []
	g.load_game()
	var t_after: Variant = g.to_dict()
	t_after.erase("t")
	var d2 := _deep_eq(t_dict, t_after, "save")
	ok(d2 == "" and g.venue == 2, "load right after a walk swap: %s" % (d2 if d2 != "" else "identical, venue 3"))
	# an old save stamped long ago: with offline disabled, still nothing paid
	var oldd: Variant = g.to_dict()
	oldd["t"] = int(Time.get_unix_time_from_system()) - 86400 * 3
	_write_save(oldd)
	g.load_game()
	ok(g.offline_reward == 0, "save from 3 days ago: no away payout (%d)" % g.offline_reward)


func _old_saves() -> void:
	print("--- C2. old saves")
	# save_ver 2 one-world-era save: unlocked 3, at ch2, an away pile pending, gates charged (no gate_refund)
	_setup_empire(3)
	g.coins = 5000
	var d: Variant = g.to_dict()
	d.erase("save_ver")
	d.erase("gate_refund")
	d["offline_reward"] = 45000
	_write_save(d)
	g.coins = 0
	g.load_game()
	var refund: int = int(g.chapter_cfg(0).gate.coins) + int(g.chapter_cfg(1).gate.coins)
	ok(g.offline_reward == 0, "save_ver<3: pending away pile dropped (offline_reward %d)" % g.offline_reward)
	ok(g.coins == 5000 + refund and g.refund_note == refund, "pre-fix save: gate fees %d refunded once (coins %d)" % [refund, g.coins])
	_write_save(g.to_dict())
	g.load_game()
	ok(g.coins == 5000 + refund, "refund not paid twice on the next load (coins %d)" % g.coins)
	# very old save: no lv2, no venues, chapter_done at the camp
	var vo := {"v": 2, "coins": 100, "served": 300, "built": {"campfire": true, "tables_1": true, "shop": true, "crew_hut": true, "fire_2": true, "tables_2": true},
		"pad_paid": {}, "levels": {"tool": 2, "bag": 3, "boots": 2, "fire": 3, "menu": 2}, "crew": {"lumberjack": 2, "waiter": 1, "cook": 1},
		"rating_hist": [4.5], "stats": {"trees": 10, "logs": 50, "served": 300, "earned": 30000, "sold": 5, "play_s": 3600.0},
		"chapter_done": true, "ftue": 9, "woodpile": 10, "rack": 2, "counter_coins": 40, "jobs_day": "2026-01-01", "jobs": [],
		"streak": 3, "streak_last_day": "2026-01-01", "chest_claimed": false, "mute": false, "t": 1700000000}
	_write_save(vo)
	g.venues = []; g.venue = 0; g.unlocked = 1; g.reno = {}; g.bigday = {}
	g.load_game()
	ok(g.unlocked == 2 and g.levels.fire == 14 and g.levels.menu == 4 and g.bigday.get("won", false) and g.built.has("gate"), "pre-empire save: unlocked 2, kitchen->Lv15 idx 14, menu idx 4, Big Day won (%d %d %d)" % [g.unlocked, g.levels.fire, g.levels.menu])
	ok(g.coins == 100 + int(g.chapter_cfg(0).gate.coins), "pre-empire save: camp gate fee refunded (%d)" % g.coins)
	ok(g.task_i >= g.tasks().size(), "pre-empire finished camp: task chain marked done (%d)" % g.task_i)
	# corrupt main + backup -> keep copy fallback is covered by qa_r2_t1_save; just make sure garbage doesn't crash
	var f := FileAccess.open(g.SAVE_PATH, FileAccess.WRITE)
	f.store_string("{not json")
	f.close()
	g.load_game()
	ok(true, "garbage main save: load_game survives")


# ------------------------------------------------------------------ D. daily jobs across midnight
func _jobs() -> void:
	print("--- D. jobs")
	_fresh(0)
	g.built = {"campfire": true}
	g.jobs_day = ""
	g.streak = 0; g.streak_last_day = ""; g.chest_day = ""; g.chest_claimed = false
	g.refresh_jobs()
	ok(g.jobs.size() == 3, "3 jobs today")
	for j in g.jobs:
		j.prog = j.goal
	var c0: int = g.coins
	var rsum := 0
	for i in 3:
		rsum += int(g.jobs[i].reward)
		g.claim_job(i)
		g.claim_job(i)          # double tap
	ok(g.coins == c0 + rsum, "3 jobs paid once each (+%d)" % rsum)
	ok(g.streak == 1, "streak 1 after all three (%d)" % g.streak)
	var chest: int = g.streak_reward()
	c0 = g.coins
	g.claim_chest(); g.claim_chest()
	ok(g.coins == c0 + chest and g.chest_claimed, "chest paid once (+%d)" % chest)
	# same day: refresh does nothing
	g.refresh_jobs()
	ok(g.jobs.all(func(x): return x.claimed) and g.chest_claimed, "same-day refresh keeps claimed state")
	# next day (clock can't move: yesterday's dates are written into the save fields instead)
	g.jobs_day = "2000-01-01"
	g.chest_day = "2000-01-01"
	g.streak_last_day = "2000-01-01"
	g.refresh_jobs()
	ok(not g.chest_claimed and g.jobs.all(func(x): return not x.claimed), "new day: fresh jobs, chest closed")
	for j in g.jobs:
		j.prog = j.goal
	for i in 3:
		g.claim_job(i)
	ok(g.streak == 2, "streak 2 next day (%d)" % g.streak)
	# completed but unclaimed at midnight: lost on rollover
	g.jobs_day = "2000-01-02"
	g.jobs[0].claimed = false
	var lost_reward: int = g.jobs[0].reward
	g.refresh_jobs()
	ok(g.jobs.all(func(x): return int(x.prog) == 0), "INFO: a job done but not claimed before midnight is dropped on rollover (reward %d)" % lost_reward)
	# skipped days: streak pauses, chest wraps after 7
	g.streak = 7
	g.streak_last_day = "1999-01-01"
	g.jobs_day = "2000-01-03"
	g.refresh_jobs()
	for j in g.jobs:
		j.prog = j.goal
	for i in 3:
		g.claim_job(i)
	ok(g.streak == 1, "after day 7 the streak wraps to 1 (%d)" % g.streak)
	# job reward rescale on travel: no drift after bouncing between scales
	_setup_empire(6)
	g.jobs_day = ""
	g.refresh_jobs()
	var r0: Array = g.jobs.map(func(j): return int(j.reward))
	var goal0: Array = g.jobs.map(func(j): return int(j.goal))
	for i in 20:
		g.travel(0); g.travel(3); g.travel(1); g.travel(5)
	var r1: Array = g.jobs.map(func(j): return int(j.reward))
	ok(r0 == r1 and goal0 == g.jobs.map(func(j): return int(j.goal)), "jobs bounced 80 trips: rewards %s -> %s, goals stable" % [r0, r1])
	# claim at the cheapest place vs the dearest: the same job pays x420 more at the Hotel
	g.travel(0)
	var at_camp: int = g.jobs[0].reward
	g.travel(5)
	print("INFO the same daily job pays %d at the Camp, %d at the Hotel (claims follow where you stand)" % [at_camp, g.jobs[0].reward])
	# earn job: the goal shrinks x420 at the Camp; finish it there and bring it back
	if not g.jobs.any(func(x): return x.id == "earn"):
		g.jobs[2] = {"id": "earn", "text": "Earn $126000", "goal": 126000, "prog": 0, "reward": 96600, "claimed": false}
	for j in g.jobs:
		if j.id == "earn":
			j.prog = 0
			var hotel_goal := int(j.goal)
			g.travel(0)
			var camp_goal := int(j.goal)
			g.add_coins(camp_goal)
			g.travel(5)
			print("INFO earn job: Hotel goal %d, at the Camp %d; earning %d at the Camp then walking back -> %d/%d, reward %d" % [hotel_goal, camp_goal, camp_goal, j.prog, j.goal, j.reward])
			ok(camp_goal == hotel_goal, "earn job goal doesn't shrink at the Camp (%d vs %d)" % [camp_goal, hotel_goal])
			j.prog = 0
	# earn job progress kept as a fraction on travel
	for j in g.jobs:
		if j.id == "earn":
			j.prog = j.goal / 2
			g.travel(0)
			ok(absf(float(j.prog) / float(j.goal) - 0.5) < 0.02, "earn job keeps 50%% on travel (%d/%d)" % [j.prog, j.goal])
			g.travel(5)


# ------------------------------------------------------------------ E. prestige
func _prestige() -> void:
	print("--- E. prestige")
	_setup_empire(6)
	_tick(600.0)
	g.coins = 5_000_000
	g.chapter_done = false
	g.start_new_empire()
	ok(g.prestige == 0 and g.unlocked == 6, "new empire refused before the Hotel's gate is opened")
	g.chapter_done = true
	g.profile.owned.append("hat_cowboy_test")
	g.pro = {"tool": 4, "bag": 4, "boots": 4}
	g.refresh_jobs()
	for j in g.jobs:
		j.prog = j.goal
	for i in 3:
		g.claim_job(i)
	g.claim_chest()
	var streak_before: int = g.streak
	g.start_new_empire()
	ok(g.prestige == 1 and g.unlocked == 1 and g.venue == 0 and g.coins == 0 and g.venues.is_empty(), "new empire: prestige 1, back at the Camp, $0")
	ok(g.tills_waiting() == 0 and g.counter_coins == 0, "tills cleared")
	ok(g.pro.tool == 0 and g.levels.tool == 0 and g.crew.lumberjack == 0 and g.built.is_empty(), "gear, crew and builds reset")
	ok("hat_cowboy_test" in g.profile.owned, "outfits kept")
	ok(absf(g.income_mult() - 1.5) < 0.001, "income x1.5")
	ok(g.streak == streak_before and g.chest_claimed, "streak kept, chest stays claimed today")
	var reclaim: Variant = g.jobs.filter(func(x): return not x.claimed).size()
	ok(reclaim == 0, "daily jobs already claimed today are not handed out again by the reset (%d unclaimed fresh jobs)" % reclaim)
	g.start_new_empire()
	ok(g.prestige == 1, "second new empire right away refused")
