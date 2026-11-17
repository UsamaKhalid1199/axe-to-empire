extends SceneTree
## QA1: economy numbers + logic checks on the Game autoload (no scene).
var fails := 0
func ok(c: bool, msg: String) -> void:
	print(("PASS " if c else "FAIL ") + msg)
	if not c: fails += 1

func _initialize() -> void:
	_run.call_deferred()

func _reset(g, k: int) -> void:
	g.venue = k; g.unlocked = k + 1; g.venues = []; g.prestige = 0
	g.coins = 0; g.built = {}; g.pad_paid = {}; g.reno = {}; g.bigday = {}; g.seen = {}
	g.levels = {"tool": 0, "bag": 0, "boots": 0, "fire": 0, "menu": 0, "dining": 0, "sign": 0, "station": 0}
	g.crew = {"lumberjack": 0, "waiter": 0, "cook": 0}
	g._cc_cache.clear(); g._star_cache = 0
	g.cfg = g.chapter_cfg(k)

func _run() -> void:
	var g = root.get_node("Game")
	g.saving_enabled = false
	var UIc = load("res://scripts/ui/ui.gd")
	print("=== per-chapter cost table ===")
	for k in 6:
		_reset(g, k)
		var c: Dictionary = g.cfg
		var bsum := 0
		var bl := []
		for b in c.builds:
			bsum += int(b.cost); bl.append("%s=%d" % [b.id, int(b.cost)])
		var csum := 0
		for r in c.crew:
			for x in c.crew[r].costs: csum += int(x)
		var ssum := 0.0
		var lvl24 := {}
		for key in g.STATIONS:
			if key == "station" and g.special_type() == "": continue
			var s := 0
			for lv in 24:
				g.levels[key] = lv
				s += g.station_cost(key)
			lvl24[key] = s
			ssum += s
			g.levels[key] = 0
		print("ch%d m=%d builds=%d [%s] crew=%d stations(all 1->25)=%d gate=%d dish0=%d log=%d golden=%d task_r1=%d" % [k, g.chapter_mult(k), bsum, ", ".join(bl), csum, ssum, int(c.gate.coins), g.dish_price(), int(c.log_sell_price), int(round(15 * g.dish_price())), g.task_reward({"r": 1})])
		# full crew passive rate with all built, stations 0 / 14 / 24
		g.built = {"campfire": true, "tables_1": true, "tables_2": true, "fire_2": true, "shop": true, "crew_hut": true, "special": true}
		g.crew = {"lumberjack": 3, "waiter": 2, "cook": 2}
		for L in [0, 14, 24]:
			for key in g.STATIONS: g.levels[key] = L
			print("   stations=%d passive=%.1f/s (%.0f/min) dish=%d  offline 1h@25%%=%d  cost next menu=%d" % [L, g.passive_rate(), g.passive_rate() * 60, g.dish_price(), int(g.passive_rate() * 3600 * 0.25), g.station_cost("menu") if L < 24 else -1])
	print("=== jobs reward formula ===")
	for k in [0, 2, 5]:
		for mlv in [0, 10, 24]:
			_reset(g, k)
			g.levels.menu = mlv
			g.jobs_day = ""
			g.stats.play_s = 0.0
			g.refresh_jobs()
			var s := []
			for j in g.jobs: s.append("%s goal=%d reward=%d" % [j.id, j.goal, j.reward])
			print("  ch%d menu=%d : %s" % [k, mlv, " | ".join(s)])
	# force an 'earn' job and compare reward with goal
	_reset(g, 0)
	var found := false
	for day in 30:
		g.jobs_day = ""
		g.stats.play_s = 1800.0 * 10
		g.levels.menu = 0
		g.refresh_jobs()
		for j in g.jobs:
			if j.id == "earn":
				found = true
				ok(int(j.reward) <= int(j.goal), "earn job reward (%d) should not exceed coins earned for it (%d)" % [j.reward, j.goal])
		if found: break
	print("=== spend / pay_pad guards ===")
	_reset(g, 0)
	g.coins = 10
	ok(not g.spend(11) and g.coins == 10, "can't spend more than you have")
	ok(g.pay_pad("campfire", 999) == 10 and g.coins == 0 and int(g.pad_paid.campfire) == 10, "pad takes only what you have")
	g.coins = 100
	g.pay_pad("campfire", 999)
	ok(g.coins == 86 and g.built.has("campfire") and not g.pad_paid.has("campfire"), "pad completes exactly at cost (coins=%d)" % g.coins)
	ok(g.pay_pad("campfire", 5) == 0 and g.coins == 86, "built pad takes nothing")
	# gate pad has cost 0: pay_pad('gate') would complete the gate without the checklist
	_reset(g, 0)
	g.pay_pad("gate", 1)
	ok(not g.built.has("gate"), "pay_pad('gate') must not mark the gate built without gate_ready (built gate=%s)" % g.built.has("gate"))
	print("=== station upgrade / reno ===")
	_reset(g, 0)
	g.built = {"campfire": true}
	g.coins = 10_000_000
	for i in 3: g.station_upgrade("fire")
	ok(g.levels.fire == 3, "3 instant levels (lv=%d)" % g.levels.fire)
	var c4: int = g.station_cost("fire")
	var before: int = g.coins
	ok(g.station_upgrade("fire") and g.levels.fire == 3 and not g.reno.is_empty(), "milestone level starts reno")
	ok(before - g.coins == c4, "reno charged once")
	ok(not g.station_upgrade("fire") and not g.station_upgrade("menu"), "builders busy while renovating")
	var rc: int = g.reno_rush_cost()
	print("  rush cost at start=%d (paid %d)" % [rc, c4])
	before = g.coins
	ok(g.reno_rush() and g.levels.fire == 4 and g.reno.is_empty() and before - g.coins == rc, "rush finishes and charges once")
	ok(not g.reno_rush(), "no second rush")
	# max level
	g.levels.fire = 23
	g.reno = {}
	ok(g.station_upgrade("fire"), "upgrade 24->25 allowed")
	print("  reno after to-25 = %s, lock=%s" % [g.reno, g.station_locked("fire")])
	g.reno_rush()
	ok(g.levels.fire == 24 and g.station_locked("fire") == "MAX", "level 25 is max")
	print("=== tasks / claims ===")
	_reset(g, 0)
	g.task_i = 0
	g.built = {"campfire": true}
	g.coins = 0
	var r: int = g.task_reward(g.current_task())
	g.claim_task(); var a: int = g.coins
	print("  task0 reward=%d coins=%d task_i=%d" % [r, a, g.task_i])
	ok(a == r, "task paid once")
	# jobs double claim
	g.jobs = [{"id": "chop", "text": "x", "goal": 1, "prog": 1, "reward": 100, "claimed": false}, {"id": "sell", "text": "y", "goal": 1, "prog": 1, "reward": 100, "claimed": false}, {"id": "earn", "text": "z", "goal": 1, "prog": 1, "reward": 100, "claimed": false}]
	g.coins = 0; g.streak = 0; g.streak_last_day = ""; g.chest_claimed = false
	g.claim_job(0); g.claim_job(0); g.claim_job(1); g.claim_job(2)
	ok(g.coins == 300 and g.streak == 1, "jobs paid once each, streak 1 (coins=%d streak=%d)" % [g.coins, g.streak])
	g.claim_chest(); g.claim_chest()
	ok(g.coins == 350, "chest paid once (%d)" % g.coins)
	# offline claim
	g.offline_reward = 500; g.coins = 0
	g.claim_offline(); g.claim_offline()
	ok(g.coins == 500, "offline claim once")
	print("=== offline numbers ===")
	_reset(g, 0)
	g.built = {"campfire": true, "tables_1": true, "tables_2": true, "fire_2": true, "shop": true, "crew_hut": true}
	g.crew = {"lumberjack": 3, "waiter": 2, "cook": 2}
	g.offline_reward = 0
	var now := int(Time.get_unix_time_from_system())
	g._compute_offline(now - 10 * 3600)
	print("  ch1 full crew, 10h away -> reward=%d seconds=%d cap_h=%.1f" % [g.offline_reward, g.offline_seconds, g.offline_cap_hours()])
	g._compute_offline(now - 10 * 3600)
	print("  computing twice (e.g. resume + cold load) -> reward=%d" % g.offline_reward)
	g.offline_reward = 0
	g._compute_offline(now + 5000)
	ok(g.offline_reward == 0, "clock rollback gives nothing")
	print("=== UI.cash formatting ===")
	for n in [0, 999, 1000, 9999, 10000, 999949, 999999, 1000000, 59_990_000, 1_250_000_000, 9_000_000_000_000]:
		print("  %d -> %s" % [n, UIc.cash(n)])
	print("=== prestige ===")
	_reset(g, 5)
	g.chapter_done = true
	g.coins = 5_000_000; g.offline_reward = 1234
	g.start_new_empire()
	print("  after new empire: coins=%d offline_reward=%d prestige=%d mult=%.2f dish=%d jobs=%s" % [g.coins, g.offline_reward, g.prestige, g.income_mult(), g.dish_price(), str(g.jobs.map(func(j): return j.reward))])
	print("=== star mult ===")
	_reset(g, 0)
	g._star_cache = 18
	print("  18 stars -> star_mult %.2f" % g.star_mult())
	print("FAILS=%d" % fails)
	quit()
