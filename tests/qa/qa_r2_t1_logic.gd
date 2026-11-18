extends SceneTree
## QA round 2, tester 1: game-logic sweep without a scene.
##  A. stars 1-3 rules vs the HUD's STAR rule text
##  B. task chain 1..13 per chapter: every task completable from its own progress source, build prerequisites
##  C. daily jobs + streak chest across midnight (date faked through jobs_day / streak_last_day / chest_day)
##  D. Big Day result / replay rules
##  E. large values (prestige 5, chapter 6, everything maxed)
##  F. reset_all leftovers vs the "Erase ALL progress, cash, crew and outfits" promise
##  G. renovation finishing while you're at another place
## Run: $G --headless --path . -s res://tests/qa/qa_r2_t1_logic.gd
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
	g.cfg = g.chapter_cfg(k)
	g.coins = 0
	g.refresh_stars()


func _run() -> void:
	g = root.get_node("Game")
	g.set_process(false)
	g.saving_enabled = false
	g.settings.story = false
	_stars()
	_tasks()
	_jobs_midnight()
	_bigday()
	_large()
	_reset()
	_reno_away()
	print("RESULT qa_r2_t1_logic: %d fail(s)" % fails)
	quit()


# ------------------------------------------------------------------ A. stars
func _stars() -> void:
	print("--- A. stars")
	var src := FileAccess.get_file_as_string("res://scripts/ui/hud.gd")
	var re := RegEx.create_from_string("const STAR3_HOW := \"([^\"]*)\"")
	var m := re.search(src)
	var how := m.get_string(1) if m else ""
	print("INFO STAR3_HOW = '%s'" % how)
	ok(how.contains("no walkouts") and how.contains("15"), "STAR3_HOW names the clean win and Lv 15")
	for k in 6:
		_fresh(k)
		g.built = _full(k)
		var has_sp: bool = g.special_type() != ""
		g.bigday = {"won": true, "clean": true}
		for key in g.STATIONS:
			g.levels[key] = 14
		ok(g.stars() == [true, false, true], "ch%d: won + clean + all Lv15 -> star 1 and 3 (%s)" % [k, g.stars()])
		g.levels.station = 13
		var s3: bool = g.stars()[2]
		ok(s3 == (not has_sp), "ch%d: signature station Lv14 -> star 3 %s (special %s)" % [k, s3, has_sp])
		g.levels.station = 14
		g.levels.dining = 13
		ok(not g.stars()[2], "ch%d: dining Lv14 -> no star 3" % k)
		g.levels.dining = 14
		g.bigday = {"won": true}
		ok(not g.stars()[2], "ch%d: won with walkouts -> no star 3" % k)
		g.bigday = {"clean": true}
		ok(g.stars() == [false, false, false], "ch%d: clean flag without a win gives nothing" % k)
		# star 2: twice the gate's guests at 4.5+, latched
		g.bigday = {"won": true}
		g.vserved = int(g.cfg.gate.served) * 2 - 1
		g.rating_hist = [5.0, 4.0]
		g.refresh_stars()
		ok(not g.stars()[1], "ch%d: one guest short of 2x gate (%d) -> no star 2" % [k, int(g.cfg.gate.served) * 2])
		g.vserved += 1
		g.refresh_stars()
		ok(g.stars()[1], "ch%d: 2x gate guests at 4.5 -> star 2" % k)
		g.rating_hist = [1.0]
		g.refresh_stars()
		ok(g.stars()[1], "ch%d: star 2 kept after the rating drops" % k)
		# background view of the same venue agrees
		g._stash()
		g.venues.append({})
		var vk := k
		var act: Array = g.stars()
		g.venue = (k + 1) % 6 if k < 5 else 0
		var bg: Array = g.stars(vk)
		g.venue = vk
		ok(bg == act, "ch%d: stars seen from another place %s == live %s" % [k, bg, act])


# ------------------------------------------------------------------ B. tasks
func _tasks() -> void:
	print("--- B. task chains")
	for k in 6:
		_fresh(k)
		if k > 0:
			g._head_start()
		var ts: Array = g.tasks()
		ok(ts.size() == 13, "ch%d has 13 tasks (%d)" % [k, ts.size()])
		var reward_sum := 0
		for i in ts.size():
			var t: Dictionary = ts[i]
			ok(g.task_i == i, "ch%d task %d current" % [k, i + 1])
			var txt: String = g.task_text(t)
			var pre: Array = g.task_progress(t)
			var already: bool = g.task_done()
			if already:
				print("INFO ch%d task %d '%s' is already done when it comes up (progress %s)" % [k, i + 1, txt, pre])
			match String(t.t):
				"build":
					ok(g.build_available(t.id) or g.built.has(t.id), "ch%d task %d '%s': pad available when the task comes up (requires %s, built %s)" % [k, i + 1, txt, g.build_def(t.id).get("requires"), g.built.keys()])
					g.coins += int(g.build_def(t.id).cost)
					g.pay_pad(t.id, int(g.build_def(t.id).cost))
				"serve":
					g.vserved += int(t.n)
				"hire":
					var c: int = g.crew_next_cost(t.id)
					g.coins += maxi(c, 0)
					g.hire(t.id)
				"level":
					var key: String = g.station_key(t.id)
					var guard := 0
					while int(g.levels[key]) + 1 < int(t.n) and guard < 40:
						guard += 1
						var why: String = g.station_locked(key)
						if why != "":
							ok(false, "ch%d task %d '%s': station locked: %s" % [k, i + 1, txt, why])
							break
						g.coins += g.station_cost(key)
						g.station_upgrade(key)
						if not g.reno.is_empty():
							g.reno.end = 0
							g._reno_tick()
				"golden":
					g.golden_n += 1
				"bigday":
					ok(g.big_day_ready(), "ch%d task 13: Big Day ready when the task comes up (gate built %s)" % [k, g.gate_status().built])
					g.big_day_result(true, false)
			ok(txt != "" and g.task_done(), "ch%d task %d '%s' completes from its progress source (%s)" % [k, i + 1, txt, g.task_progress(t)])
			var r: int = g.task_reward(t)
			var c0: int = g.coins
			g.claim_task()
			ok(g.coins - c0 == r and r > 0, "ch%d task %d pays %d" % [k, i + 1, g.coins - c0])
			reward_sum += r
		ok(g.task_i == 13 and g.current_task().is_empty() and not g.task_done(), "ch%d chain finished (task_i %d)" % [k, g.task_i])
		print("INFO ch%d task rewards total %d (dish %d)" % [k, reward_sum, g.dish_price()])


# ------------------------------------------------------------------ C. jobs at midnight
func _done_all() -> void:
	for j in g.jobs:
		j.prog = j.goal


func _jobs_midnight() -> void:
	print("--- C. daily jobs across midnight")
	_fresh(0)
	g.built = _full(0)
	var today: String = g._today()
	var yesterday := "1999-12-31"
	# normal day 1 -> day 2 (refresh happens on the new day)
	g.streak = 0; g.streak_last_day = ""; g.chest_day = ""; g.jobs_day = ""
	g.refresh_jobs()
	g.jobs_day = yesterday           # these are "yesterday's" jobs, claimed yesterday
	_done_all()
	for i in 3:
		g.claim_job(i)
	g.streak_last_day = yesterday    # (claimed yesterday)
	g.chest_claimed = false
	g.claim_chest()
	g.chest_day = yesterday
	ok(g.streak == 1, "day 1: all jobs claimed -> streak 1")
	g.refresh_jobs()                 # a new day
	ok(g.jobs_day == today and not g.chest_claimed and g.jobs.all(func(j): return not j.claimed), "day 2: new jobs, chest closed again")
	_done_all()
	for i in 3:
		g.claim_job(i)
	ok(g.streak == 2, "day 2: streak 2 (%d)" % g.streak)
	var c0: int = g.coins
	g.claim_chest()
	ok(g.coins > c0, "day 2 chest paid")

	# the jobs list was opened before midnight and the last job / chest is claimed just after midnight
	g.streak = 3; g.streak_last_day = yesterday.replace("31", "30"); g.chest_day = ""; g.jobs_day = ""
	g.refresh_jobs()
	g.jobs_day = yesterday           # rolled yesterday, still on screen
	g.chest_claimed = false
	_done_all()
	for i in 3:
		g.claim_job(i)               # 00:01: yesterday's jobs finished
	var s_after_old: int = g.streak
	c0 = g.coins
	g.claim_chest()                  # 00:01: yesterday's chest
	var chest_old: int = g.coins - c0
	print("INFO yesterday's set claimed after midnight: streak %d, streak_last_day %s, chest +%d, chest_day %s" % [g.streak, g.streak_last_day, chest_old, g.chest_day])
	g.refresh_jobs()                 # today's jobs (next open)
	_done_all()
	for i in 3:
		g.claim_job(i)
	ok(g.streak == s_after_old + 1, "finishing today's set after claiming yesterday's just past midnight still counts today for the streak (streak %d, expected %d)" % [g.streak, s_after_old + 1])
	c0 = g.coins
	g.claim_chest()
	ok(g.coins > c0, "today's chest can be opened after yesterday's chest was opened just past midnight (paid %d, chest_claimed %s)" % [g.coins - c0, g.chest_claimed])

	# streak cycles 1..7 and the chest pays the matching reward
	g.streak = 7
	g.streak_last_day = yesterday
	g.jobs_day = ""
	g.chest_day = ""
	g.refresh_jobs()
	_done_all()
	for i in 3:
		g.claim_job(i)
	ok(g.streak == 1, "streak wraps 7 -> 1 (%d)" % g.streak)
	# a missed day pauses the streak (no reset)
	g.streak = 4; g.streak_last_day = "1999-01-01"; g.jobs_day = ""
	g.refresh_jobs()
	_done_all()
	for i in 3:
		g.claim_job(i)
	ok(g.streak == 5, "a missed day pauses the streak: 4 -> 5 (%d)" % g.streak)
	# claiming twice / unfinished
	g.jobs_day = ""
	g.refresh_jobs()
	c0 = g.coins
	g.claim_job(0)
	ok(g.coins == c0, "unfinished job can't be claimed")
	g.jobs[0].prog = g.jobs[0].goal
	g.claim_job(0)
	var once: int = g.coins - c0
	g.claim_job(0)
	ok(g.coins - c0 == once and once > 0, "job pays once (%d)" % once)
	g.claim_chest()
	ok(g.coins - c0 == once, "chest closed until all three jobs are claimed")


# ------------------------------------------------------------------ D. Big Day rules
func _bigday() -> void:
	print("--- D. Big Day result / replay")
	for k in 6:
		_fresh(k)
		g.built = _full(k)
		ok(g.big_day_ready() and g.big_day_replayable(), "ch%d fully built: Big Day ready" % k)
		g.built.erase("tables_2")
		ok(not g.big_day_ready() and not g.big_day_replayable(), "ch%d without tables_2: not ready" % k)
		g.built["tables_2"] = true
		if g.special_type() != "":
			g.built.erase("special")
			ok(not g.big_day_ready(), "ch%d without its signature station: not ready" % k)
			g.built["special"] = true
		g.big_day_result(false, false)
		ok(not g.bigday.get("won", false) and int(g.bigday.tries) == 1 and g.star_count() == 0, "ch%d lost: no star, tries 1" % k)
		g.big_day_result(true, false)
		ok(g.bigday.won and not g.bigday.get("clean", false) and g.big_day_replayable() and not g.big_day_ready(), "ch%d won with walkouts: replayable for star 3" % k)
		g.big_day_result(false, false)
		ok(g.bigday.won, "ch%d losing a replay keeps star 1" % k)
		g.big_day_result(true, true)
		ok(g.bigday.clean and not g.big_day_replayable(), "ch%d clean replay: no more replays" % k)
		ok(not g.stars()[2], "ch%d clean but stations < 15: no star 3 yet" % k)
		for key in g.STATIONS:
			g.levels[key] = 14
		g.refresh_stars()
		ok(g.stars()[2], "ch%d stations reach 15 later: star 3" % k)
		ok(g.gate_status().bigday, "ch%d gate sees the Big Day won" % k)


# ------------------------------------------------------------------ E. large values
func _large() -> void:
	print("--- E. prestige 5, chapter 6, maxed")
	_fresh(5, 5)
	g.unlocked = 6
	g.venues = []
	for i in 6:
		var vd := {"built": _full(i), "crew": {"lumberjack": 3, "waiter": 2, "cook": 2}, "bigday": {"won": true, "clean": true, "star2": true}, "vserved": 99999}
		for key in g.STATIONS:
			vd[key] = 24
		g.venues.append(vd)
	g._unstash(5)
	g.levels = {"tool": g.cfg.tools.size() - 1, "bag": g.cfg.bag.size() - 1, "boots": g.cfg.boots.size() - 1, "fire": 24, "menu": 24, "dining": 24, "sign": 24, "station": 24}
	g.pro = {"tool": 10, "bag": 10, "boots": 10}
	g.refresh_stars()
	var vals := {"dish_price": g.dish_price(), "task_reward(13)": g.task_reward({"r": 30}), "streak_reward": g.streak_reward(),
		"station_cost(lv24)": g.station_cost("menu"), "passive/s": int(g.passive_rate()), "empire/s": int(g.empire_rate()),
		"till_cap(0)": g.till_cap(0), "golden": int(round(float(g.cfg.golden.reward_dishes) * g.dish_price())), "total_stars": g.total_stars()}
	g.levels.menu = 23
	vals["station_cost(lv23)"] = g.station_cost("menu")
	g.levels.menu = 24
	for tr in ["tool", "bag", "boots"]:
		g.pro[tr] = 9
		vals["pro_cost_" + tr] = g.pro_cost(tr)
		g.pro[tr] = 10
	g.jobs_day = ""
	g.stats.play_s = 1e7
	g.refresh_jobs()
	for j in g.jobs:
		vals["job_" + String(j.id)] = [int(j.goal), int(j.reward)]
	print("INFO %s" % vals)
	var good := true
	for key in vals:
		var v = vals[key]
		var arr: Array = v if v is Array else [v]
		for x in arr:
			if int(x) <= 0 or int(x) > 1 << 52:
				good = false
				print("  bad %s = %s" % [key, x])
	ok(good, "all prices / rewards positive and well inside 2^52")
	g.coins = (1 << 53) - 10
	var c0: int = g.coins
	g.add_coins(1 << 40)
	ok(g.coins == c0 + (1 << 40), "add_coins at 2^53 stays exact (int64)")
	var txt := JSON.stringify(g.to_dict())
	var back = JSON.parse_string(txt)
	print("INFO coins %d -> JSON round trip %d (diff %d)" % [g.coins, int(back.coins), int(back.coins) - g.coins])
	var sc0: float = g._progress_score({"prestige": 5, "stats": {"earned": 10_000_000_000}, "unlocked": 6})
	var sc1: float = g._progress_score({"prestige": 5, "stats": {"earned": 10_000_000_001}, "unlocked": 6})
	ok(sc1 > sc0, "progress score still tells $1 of lifetime cash apart at prestige 5 (%.1f vs %.1f)" % [sc0, sc1])
	g.coins = 0


# ------------------------------------------------------------------ F. reset_all leftovers
func _reset() -> void:
	print("--- F. reset_all")
	_fresh(2, 1)
	g.profile = {"owned": ["shirt_orange", "hat_none", "hat_hardhat", "pants_dark", "SOMETHING_BOUGHT"], "equipped": {"shirt": "shirt_orange", "hat": "hat_hardhat", "pants": "pants_dark"}}
	g.streak = 5
	g.offline_reward = 777
	g.coins = 123
	g.reset_all()
	ok(g.coins == 0 and g.prestige == 0 and g.unlocked == 1 and g.venue == 0, "reset: cash, prestige and places gone")
	ok(not g.profile.owned.has("SOMETHING_BOUGHT"), "reset erases bought outfits as the confirm text promises ('Erase ALL progress, cash, crew and outfits') (owned %s)" % [g.profile.owned])
	print("INFO reset leaves offline_reward %d (unreachable today: offline is disabled and old piles are dropped on load)" % g.offline_reward)
	print("INFO after reset: streak %d, settings kept %s" % [g.streak, g.settings])
	g.profile = {"owned": ["shirt_orange", "hat_none", "hat_hardhat", "pants_dark"], "equipped": {"shirt": "shirt_orange", "hat": "hat_hardhat", "pants": "pants_dark"}}
	g.offline_reward = 0


# ------------------------------------------------------------------ G. renovation while away
func _reno_away() -> void:
	print("--- G. renovation finishing at another place")
	_fresh(0)
	g.unlocked = 2
	g.built = _full(0)
	g.crew = {"lumberjack": 3, "waiter": 2, "cook": 2}
	g.levels.menu = 3
	g.coins = g.station_cost("menu")
	ok(g.station_upgrade("menu") and not g.reno.is_empty(), "menu Lv5 renovation started at ch0")
	var r_before: float = g.passive_rate()
	g.travel(1)
	g.venues[0].reno.end = 0              # finished while you're next door
	g._reno_tick()
	g._refresh_rates()
	var lv0 := int(g.venues[0].menu)
	var rate_now: float = g.venue_rate(0)
	print("INFO renovation done while away: ch0 menu idx %d, bg rate %.2f/s (before %.2f/s)" % [lv0, rate_now, r_before])
	ok(lv0 == 4, "a renovation that finished while you're elsewhere applies to that place's level (menu idx %d) and its background income" % lv0)
	g.travel(0)
	for i in 3:
		g._reno_tick()
	ok(g.levels.menu == 4 and g.reno.is_empty(), "on return the level is applied")
