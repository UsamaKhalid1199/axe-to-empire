extends SceneTree
## QA tester 1: every buy path charges exactly the shown price, never goes negative, never double-charges;
## rounding at chapters 5-6 / $1B+; daily jobs across crossings. Run: $G --headless --path . -s res://tests/qa/qa_t1_spend.gd
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


func _at(k: int, prestige := 0) -> void:
	g.prestige = prestige
	g.unlocked = 6
	g.venues = []
	for i in 6:
		g.venues.append({"built": _full(i), "crew": {"lumberjack": 1, "waiter": 0, "cook": 0}})
	g.venue = k
	g._unstash(k)
	g.built = {"campfire": true}
	g.pad_paid = {}
	g.crew = {"lumberjack": 0, "waiter": 0, "cook": 0}
	g.levels = {"tool": 0, "bag": 0, "boots": 0, "fire": 0, "menu": 0, "dining": 0, "sign": 0, "station": 0}
	g.pro = {"tool": 0, "bag": 0, "boots": 0}
	g.reno = {}
	g._cc_cache.clear()
	g.cfg = g.chapter_cfg(k)
	g.refresh_stars()


## Calls fn, checks the wallet moved by exactly -expect (or 0 when it should fail).
func _charge(name: String, expect: int, fn: Callable, should_ok := true) -> void:
	var c0: int = g.coins
	var r = fn.call()
	var paid: int = c0 - g.coins
	if should_ok:
		ok((r == null or r == true) and paid == expect and g.coins >= 0, "%s charges %d (paid %d, ret %s, coins %d)" % [name, expect, paid, r, g.coins])
	else:
		ok((r == null or r == false) and paid == 0 and g.coins >= 0, "%s refused without charge (paid %d, coins %d)" % [name, paid, g.coins])


func _run() -> void:
	g = root.get_node("Game")
	g.set_process(false)
	g.saving_enabled = false
	g.settings.story = false
	var W = load("res://scripts/core/wardrobe.gd")

	for k in [0, 2, 5]:
		for pr in ([0, 3] if k == 5 else [0]):
			print("--- chapter %d prestige %d" % [k, pr])
			_at(k, pr)
			# ---- build pads
			var cost: int = int(g.build_def("tables_1").cost)
			g.coins = cost / 3
			var moved: int = g.pay_pad("tables_1", cost * 10)
			ok(moved == cost / 3 and g.coins == 0 and not g.built.has("tables_1"), "pad: partial pay %d of %d, coins %d" % [moved, cost, g.coins])
			g.coins = cost * 5
			moved = g.pay_pad("tables_1", cost * 10)
			ok(moved == cost - cost / 3 and g.coins == cost * 5 - moved and g.built.has("tables_1"), "pad: rest %d, built, coins %d" % [moved, g.coins])
			ok(g.pay_pad("tables_1", 999) == 0, "pad: built pad takes nothing more")
			ok(g.pay_pad("gate", 999) == 0, "pad: gate pad never takes money")
			g.coins = 0
			ok(g.pay_pad("shop", 100) == 0 and g.coins == 0, "pad: broke -> 0")
			# ---- gear (tool/bag/boots), then Pro
			for tr in ["tool", "bag", "boots"]:
				var arr: Array = g.cfg.tools if tr == "tool" else g.cfg[tr]
				for i in arr.size() - 1:
					var nx: Dictionary = g.next_upgrade(tr)
					g.coins = int(nx.cost) - 1
					_charge("%s lv%d short by 1" % [tr, i + 1], 0, func(): return g.buy_upgrade(tr), false)
					g.coins = int(nx.cost)
					_charge("%s lv%d" % [tr, i + 1], int(nx.cost), func(): return g.buy_upgrade(tr))
				var pro_paid := 0
				for p in g.PRO_MAX:
					var nx2: Dictionary = g.next_upgrade(tr)
					ok(nx2.has("pro") and int(nx2.cost) == g.pro_cost(tr) and int(nx2.cost) % 10 == 0 and int(nx2.cost) > 0,
						"%s Pro %d price %d (multiple of 10)" % [tr, p + 1, int(nx2.cost)])
					g.coins = int(nx2.cost)
					var c0: int = g.coins
					g.buy_upgrade(tr)
					if c0 - g.coins != int(nx2.cost) or g.coins < 0:
						ok(false, "%s Pro %d charged %d, shown %d" % [tr, p + 1, c0 - g.coins, int(nx2.cost)])
					pro_paid += int(nx2.cost)
				ok(int(g.pro[tr]) == g.PRO_MAX and g.next_upgrade(tr).is_empty(), "%s Pro maxed (%d), total Pro spend %s" % [tr, g.pro[tr], pro_paid])
				g.coins = 1 << 40
				_charge("%s past Pro max" % tr, 0, func(): return g.buy_upgrade(tr), false)
			# ---- crew
			g.built = _full(k)
			for role in ["lumberjack", "waiter", "cook"]:
				var mx: int = int(g.cfg.crew[role].max)
				for i in mx:
					var cc: int = g.crew_next_cost(role)
					g.coins = cc - 1
					_charge("hire %s #%d short" % [role, i + 1], 0, func(): return g.hire(role), false)
					g.coins = cc
					_charge("hire %s #%d" % [role, i + 1], cc, func(): return g.hire(role))
				g.coins = 1 << 40
				ok(g.crew_next_cost(role) == -1, "%s full -> cost -1" % role)
				_charge("hire %s past max" % role, 0, func(): return g.hire(role), false)
			# ---- stations, renovations, rush
			for key in g.STATIONS:
				if key == "station" and g.special_type() == "":
					continue
				var lv_paid := 0
				var guard := 0
				while g.station_locked(key) != "MAX" and guard < 40:
					guard += 1
					var sc: int = g.station_cost(key)
					if sc <= 0:
						ok(false, "%s cost %d at lv %d" % [key, sc, g.levels[key]])
						break
					g.coins = sc - 1
					var cbad: int = g.coins
					g.station_upgrade(key)
					if g.coins != cbad:
						ok(false, "%s upgrade with 1 short charged %d" % [key, cbad - g.coins])
					g.coins = sc
					var c1: int = g.coins
					g.station_upgrade(key)
					if c1 - g.coins != sc:
						ok(false, "%s lv%d charged %d shown %d" % [key, g.levels[key], c1 - g.coins, sc])
					lv_paid += sc
					if not g.reno.is_empty():
						# another station is blocked while builders are busy
						var other := "menu" if key != "menu" else "fire"
						g.coins = 1 << 40
						var cb2: int = g.coins
						var blocked: bool = not g.station_upgrade(other) and g.coins == cb2
						if not blocked or guard < 6:
							ok(blocked, "%s: other station blocked during renovation" % key)
						var rc: int = g.reno_rush_cost()
						g.coins = rc
						var c2: int = g.coins
						var rushed: bool = g.reno_rush()
						var good: bool = rushed and c2 - g.coins == rc and g.reno.is_empty()
						if not good or key == "menu":
							ok(good, "%s reno rush to lv %d charged %d (shown %d)" % [key, g.levels[key] + 1, c2 - g.coins, rc])
						g.coins = 1 << 40
						var c3: int = g.coins
						var noop: bool = not g.reno_rush() and g.coins == c3
						if not noop:
							ok(false, "%s second rush charged" % key)
				ok(g.levels[key] == g.station_max() - 1, "%s maxed at shown lv %d (spent %d)" % [key, g.levels[key] + 1, lv_paid])
				g.coins = 1 << 40
				var c4: int = g.coins
				ok(not g.station_upgrade(key) and g.coins == c4, "%s past max refused" % key)
			# rush cost shrinks over time and can't be gamed below 1
			g.levels.menu = 3
			g.coins = g.station_cost("menu")
			g.station_upgrade("menu")
			var full_rc: int = g.reno_rush_cost()
			g.reno.end = int(g.reno.end) - int(g.reno_seconds(5)) / 2
			var half_rc: int = g.reno_rush_cost()
			ok(half_rc > 0 and absf(half_rc - full_rc / 2.0) <= 1.0 + full_rc * 0.02, "rush cost halves at half time (%d -> %d)" % [full_rc, half_rc])
			g.coins = half_rc - 1
			_charge("rush short by 1", 0, func(): return g.reno_rush(), false)
			g.reno = {}
			# ---- big numbers
			var big := [g.station_cost("menu"), g.dish_price(), g.pro_cost("tool"), int(g.build_def("gate").cost)]
			print("  big numbers: menu lv25 cost %d, dish %d, next Pro tool %d" % [big[0], big[1], big[2]])
			ok(big[0] > 0 and big[1] > 0 and big[2] > 0, "no overflow / zero prices")

	# ---- spend() itself
	g.coins = 100
	ok(not g.spend(101) and g.coins == 100, "spend(101) with 100 refused")
	ok(g.spend(100) and g.coins == 0, "spend all -> 0")
	g.coins = 100
	var neg: bool = g.spend(-50)
	print("  spend(-50) -> %s, coins %d" % [neg, g.coins])
	ok(g.coins == 100, "spend() with a negative amount doesn't mint cash (coins %d)" % g.coins)
	g.coins = 100

	# ---- wardrobe
	_at(0)
	for id in ["shirt_flannel_red", "shirt_denim", "pants_khaki"]:
		var p: int = W.price(id)
		g.coins = p - 1
		_charge("wardrobe %s short" % id, 0, func(): return W.buy(id), false)
		g.coins = p
		_charge("wardrobe %s" % id, p, func(): return W.buy(id))
		g.coins = p * 2
		_charge("wardrobe %s again" % id, 0, func(): return W.buy(id), false)
	g.coins = 1 << 40
	g._star_cache = 0
	_charge("wardrobe star-gated item with 0 stars", 0, func(): return W.buy("shirt_gold_flannel"), false)

	# ---- gate / next door (no fee), Big Day result (no fee)
	_at(2)
	g.built = _full(2)
	g.vserved = 9999; g.rating_hist = [5.0]; g.bigday = {"won": true}
	g.coins = int(g.cfg.gate.coins)
	g.unlocked = 3
	var cg: int = g.coins
	g.open_next_venue()
	ok(g.coins == cg and g.unlocked == 4, "gate opens without charging (coins %d -> %d, unlocked %d)" % [cg, g.coins, g.unlocked])
	g.open_next_venue()
	ok(g.coins == cg and g.unlocked == 4, "second open is a no-op")
	g.big_day_result(true, true)
	ok(g.coins == cg, "Big Day result doesn't touch the wallet")

	# ---- jobs: claim once, chest once
	_at(1)
	g.jobs_day = ""
	g.refresh_jobs()
	for j in g.jobs:
		j.prog = j.goal
	var cj: int = g.coins
	var r0: int = int(g.jobs[0].reward)
	g.claim_job(0); g.claim_job(0)
	ok(g.coins - cj == r0, "job 0 claimed once: +%d (reward %d)" % [g.coins - cj, r0])
	g.claim_job(1); g.claim_job(2)
	var cc0: int = g.coins
	var sr: int = g.streak_reward()
	g.claim_chest(); g.claim_chest()
	ok(g.coins - cc0 == sr, "chest once: +%d (shown %d)" % [g.coins - cc0, sr])
	# ---- tasks: claim once
	_at(0)
	g.task_i = 0; g.task_base = 0
	g.built = {}
	var t0: Dictionary = g.current_task()
	g.coins = 0
	g.claim_task()
	ok(g.coins == 0 and g.task_i == 0, "unfinished task can't be claimed")
	g.built = {"campfire": true}
	var tr0: int = g.task_reward(t0)
	g.claim_task()
	var after1: int = g.coins
	ok(after1 == tr0 and g.task_i == 1, "task claimed: +%d (shown %d)" % [after1, tr0])

	# ---- daily jobs across crossings (rescaled each walk)
	_at(0)
	g.jobs_day = ""
	g.refresh_jobs()
	var before: Array = []
	for j in g.jobs:
		before.append([j.id, int(j.goal), int(j.reward)])
	for i in 30:
		for k in [1, 2, 3, 4, 5, 4, 3, 2, 1, 0]:
			g.travel(k)
	var after: Array = []
	for j in g.jobs:
		after.append([j.id, int(j.goal), int(j.reward)])
	print("  jobs before %s\n  jobs after 300 walks %s" % [before, after])
	ok(before == after, "job goals/rewards stable after walking up and down the road 30x")
	# earn-job progress when walking down the road
	var ei := -1
	for i in g.jobs.size():
		if g.jobs[i].id == "earn":
			ei = i
	if ei < 0:
		g.jobs[0] = {"id": "earn", "text": "Earn $300", "goal": 300, "prog": 0, "reward": 100, "claimed": false}
		ei = 0
	g.travel(5)
	var goal5: int = int(g.jobs[ei].goal)
	g.jobs[ei].prog = int(goal5 * 0.9)
	var prog5: int = int(g.jobs[ei].prog)
	g.travel(4)
	g.travel(5)
	print("  earn job at ch5: %d/%d -> walk to ch4 and back -> %d/%d" % [prog5, goal5, int(g.jobs[ei].prog), int(g.jobs[ei].goal)])
	ok(int(g.jobs[ei].prog) == prog5, "earn-job progress survives a walk next door and back (%d -> %d)" % [prog5, int(g.jobs[ei].prog)])
	g.travel(0)
	g.jobs[ei].prog = int(g.jobs[ei].goal) / 2
	var p0: int = int(g.jobs[ei].prog)
	var gl0: int = int(g.jobs[ei].goal)
	g.travel(1)
	print("  earn job at ch0: %d/%d (%.0f%%) -> ch1: %d/%d (%.0f%%)" % [p0, gl0, 100.0 * p0 / gl0, int(g.jobs[ei].prog), int(g.jobs[ei].goal), 100.0 * int(g.jobs[ei].prog) / int(g.jobs[ei].goal)])
	print("FAILS=%d" % fails)
	quit()
