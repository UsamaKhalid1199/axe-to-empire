extends SceneTree
## QA round 3, tester 1: the autoplay bot (tests/autoplay.gd) chained through the chapters the way a player
## goes: win the Big Day, open the gate, travel next door (head start, cash and gear carried), keep going.
## Prints per-chapter time, coins, served, lost passers, walkouts, Big Day tries, arrival interval vs kitchen,
## and the tills waiting at the places behind you.
## Run headless: $G --headless --path . -s res://tests/qa/qa_r3_t1_chain.gd -- [speed] [max_min_per_chapter] [last_chapter]

var t_game := 0.0
var t_ch := 0.0
var stuck_t := 0.0
var detour_t := 0.0
var detour_dir := Vector2.ZERO
var check_t := 1.2
var ready_wait := 0.0
var last_dist := 999.0
var log_marks: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var speed := float(args[0]) if args.size() > 0 else 8.0
	var max_min := float(args[1]) if args.size() > 1 else 80.0
	var last_ch := int(args[2]) if args.size() > 2 else 5
	var start_ch := int(args[3]) if args.size() > 3 else 0
	var g = root.get_node("Game")
	g.saving_enabled = false
	g.prestige = 0
	g.venue = 0
	g.unlocked = 1
	g.venues = []
	g._unstash(0)
	g.levels = {"tool": 0, "bag": 0, "boots": 0, "fire": 0, "menu": 0, "dining": 0, "sign": 0, "station": 0}
	g.pro = {"tool": 0, "bag": 0, "boots": 0}
	g._cc_cache.clear()
	g.cfg = g.chapter_cfg(0)
	g.coins = 0; g.served = 0; g.offline_reward = 0
	g.stats = {"trees": 0, "logs": 0, "served": 0, "earned": 0, "sold": 0, "play_s": 0.0, "lost": 0, "walkouts": 0, "golden": 0, "bigdays": 0}
	g.settings.story = false
	if start_ch > 0:
		# arrive at start_ch the way a player does: every place before it finished (crew hired, stations ~Lv 10,
		# Big Day won), gear bought (gear prices don't scale), the last gate's savings goal in cash
		for k in start_ch:
			var bb := {"campfire": true, "tables_1": true, "shop": true, "crew_hut": true, "fire_2": true, "tables_2": true, "gate": true}
			if String(g.chapters[k].get("special", {}).get("type", "")) != "":
				bb["special"] = true
			g.venues.append({"built": bb, "crew": {"lumberjack": 3, "waiter": 2, "cook": 2}, "fire": 9, "menu": 9, "dining": 5, "sign": 5,
				"station": 4 if k > 0 else 0, "bigday": {"won": true}, "chapter_done": true, "task_i": 13, "rating_hist": [4.6], "vserved": 600})
		g.venues.append({})
		g.unlocked = start_ch + 1
		g.venue = start_ch
		g._unstash(start_ch)
		g.cfg = g.chapter_cfg(start_ch)
		g._head_start()
		g.levels.tool = 2 if start_ch == 1 else 3
		g.levels.bag = 3 if start_ch == 1 else 4
		g.levels.boots = 2 if start_ch == 1 else 3
		g.coins = int(g.chapter_cfg(start_ch - 1).gate.coins)
		g._rates.clear()
		g._rates_t = 0.0
	g.jobs_day = ""
	g.refresh_jobs()
	g.refresh_stars()
	change_scene_to_file("res://scenes/main.tscn")
	while current_scene == null or current_scene.get("hud") == null or current_scene.get_node_or_null("LoadingScreen") != null:
		await process_frame
	for i in 10:
		await process_frame
	var main = current_scene
	Engine.time_scale = speed
	Engine.physics_ticks_per_second = int(60 * speed)
	Engine.max_physics_steps_per_frame = int(8 * speed)
	var summary: Array = []
	for chap in range(start_ch, last_ch + 1):
		if g.venue != chap:
			print("STALL: expected venue %d, at %d" % [chap, g.venue])
			break
		var w = main.world
		var p = w.player
		var hud = main.hud
		var m: float = g.chapter_mult(chap)
		t_ch = 0.0
		log_marks.clear()
		var lost0: int = g.stats.lost
		var wo0: int = g.stats.walkouts
		var served0: int = g.vserved
		var coins0: int = g.coins
		var earned0: int = g.stats.earned
		var bd_t := -1.0
		var max_spawn := 0.0
		var min_spawn := 999.0
		var samp_n := 0
		var samp_sum := 0.0
		var q_full_t := 0.0
		print("=== chapter %d (%s) start: coins %d, tools %d/%d/%d pro %s, crew %s, built %s" % [chap + 1, g.chapters[chap].name, g.coins, g.levels.tool, g.levels.bag, g.levels.boots, g.pro, g.crew, g.built.keys()])
		while t_ch < max_min * 60.0 and not g.chapter_done:
			await physics_frame
			var dt := 1.0 / 60.0
			t_ch += dt
			t_game += dt
			for b in g.built:
				if not log_marks.has(b):
					log_marks[b] = t_ch
					print("[%5.1f min] built %s (coins %d, served %d, rating %.2f)" % [t_ch / 60.0, b, g.coins, g.vserved, g.rating()])
			if w.queue.size() >= w.max_queue():
				q_full_t += dt
			if int(t_ch / 60.0) != int((t_ch - dt) / 60.0):
				var si: float = w.spawn_interval()
				samp_n += 1
				samp_sum += si
				max_spawn = maxf(max_spawn, si)
				min_spawn = minf(min_spawn, si)
				if int(t_ch / 60.0) % 5 == 0:
					print("  [%4.0f min] coins=%d served=%d lost=%d walkouts=%d q=%d/%d spawn=%.2fs cook=%.2fs fires=%d rate=%.1f/s tills=%d obj='%s' lv=%s crew=%s" % [t_ch / 60.0, g.coins, g.vserved - served0, g.stats.lost - lost0, g.stats.walkouts - wo0, w.queue.size(), w.max_queue(), si, g.cook_time(), w.fires.size(), g.passive_rate(), g.tills_waiting(), w.objective.text, [g.levels.fire, g.levels.menu, g.levels.dining, g.levels.sign, g.levels.station], g.crew])
			if hud.modal_kind == "shop":
				for tr in ["tool", "bag", "boots"]:
					var n = g.next_upgrade(tr)
					if not n.is_empty() and g.coins >= int(n.cost) + 50 * m:
						g.buy_upgrade(tr)
						print("[%5.1f min] bought %s -> lv %d pro %d" % [t_ch / 60.0, tr, g.levels[tr], g.pro[tr]])
				hud.close_modal()
				p.global_position += Vector3(0, 0, 1.5)
			if hud.modal_kind == "crew":
				for role in ["lumberjack", "waiter", "lumberjack", "cook", "waiter", "lumberjack", "cook"]:
					var c = g.crew_next_cost(role)
					if c >= 0 and g.coins >= c + 50 * m:
						g.hire(role)
				hud.close_modal()
				p.global_position += Vector3(-1.5, 0, 0)
			if hud.modal_kind == "gate":
				if g.gate_ready():
					g.open_next_venue()
					print("[%5.1f min] GATE opened" % [t_ch / 60.0])
				elif g.big_day_ready() and not w.bd_active and g.woodpile >= 15 and (g.crew.lumberjack + g.crew.waiter >= 2 or ready_wait > 120.0) and w.start_big_day():
					if bd_t < 0.0:
						bd_t = t_ch
					print("[%5.1f min] BIG DAY started (served %d, kitchen %d, menu %d, goal %d in %ds)" % [t_ch / 60.0, g.vserved, g.levels.fire + 1, g.levels.menu + 1, w.bd_goal(), int(w.bd_left)])
				if hud.modal_kind != "":
					hud.close_modal()
				p.global_position += Vector3(1.5, 0, -1.5)
			if hud.modal_kind in ["jobs", "offline", "settings", "complete", "story", "bigday_result", "upgrades", "character", "empire"]:
				hud._story_q.clear()
				hud.close_modal()
			for i in g.jobs.size():
				g.claim_job(i)
			if g.task_done():
				g.claim_task()
			if g.built.has("crew_hut"):
				for role in ["lumberjack", "waiter", "lumberjack", "cook", "waiter"]:
					var cc = g.crew_next_cost(role)
					if cc >= 0 and g.coins >= cc and (g.crew[role] == 0 or g.coins >= cc * 2):
						g.hire(role)
						print("[%5.1f min] hired %s (%d)" % [t_ch / 60.0, role, g.crew[role]])
						break
			var reserve := 0
			for b in g.cfg.builds:
				if w.pads.has(b.id) and b.id != "gate":
					reserve = maxi(reserve, int(b.cost) - int(g.pad_paid.get(b.id, 0)))
			if g.built.has("crew_hut") and (g.crew.lumberjack + g.crew.waiter) < 2:
				reserve += mini(g.crew_next_cost("lumberjack") if g.crew.lumberjack == 0 else 999999, g.crew_next_cost("waiter") if g.crew.waiter == 0 else 999999)
			if not g.reno.is_empty() and g.coins >= g.reno_rush_cost() * 3 + reserve:
				g.reno_rush()
			var order := ["fire", "menu", "station", "dining", "sign"]
			var ct: Dictionary = g.current_task()
			if String(ct.get("t", "")) == "level":
				order.push_front(g.station_key(String(ct.id)))
			for key in order:
				if g.station_locked(key) == "" and g.coins >= g.station_cost(key) + reserve and g.levels[key] < 14:
					g.station_upgrade(key)
					break
			if w.bd_active and int(t_ch * 60) % 900 == 0:
				print("     bigday left=%.0f served=%d/%d rating=%.2f walkouts=%d/%d q=%d rack=%d pile=%d" % [w.bd_left, w.bd_served, w.bd_goal(), w.bd_rating(), w.bd_walkouts, w.bd_max_walkouts(), w.queue.size(), g.rack, g.woodpile])
			ready_wait = ready_wait + dt if g.big_day_ready() and not w.bd_active else 0.0
			var o: Dictionary = w.objective
			var target: Vector3 = o.pos
			if g.built.has("shop") and g.coins > 400 * m and int(t_ch) % 60 < 6:
				target = w.PADS.shop
			elif g.built.has("crew_hut") and g.coins > 600 * m and int(t_ch) % 40 >= 20 and int(t_ch) % 40 < 26:
				target = w.PADS.crew_hut
			elif target == Vector3.ZERO:
				target = w._nearest_tree_pos()
			var to: Vector3 = target - p.global_position
			to.y = 0
			var is_tree: bool = String(o.text).begins_with("Chop") or String(o.text) == "Keep the fire fed" or o.pos == Vector3.ZERO
			var stop_r := 1.25 if is_tree else 0.3
			p.input_dir = Vector2(to.x, to.z).normalized() if to.length() > stop_r else Vector2.ZERO
			detour_t -= dt
			if detour_t > 0.0:
				p.input_dir = detour_dir
			else:
				check_t -= dt
				if check_t <= 0.0:
					check_t = 1.2
					var dnow := to.length()
					if p.input_dir != Vector2.ZERO and dnow > last_dist - 0.3:
						var side := Vector2(-to.z, to.x).normalized() * (1.0 if randf() < 0.5 else -1.0)
						detour_dir = (side + Vector2(to.x, to.z).normalized() * -0.3).normalized()
						detour_t = 0.9
					last_dist = dnow
		var row := "CHAPTER %d %s: done=%s time=%.1f min (Big Day first try at %.1f min, tries %d) coins %d->%d earned %d served=%d lost=%d (%.0f%% of arrivals) walkouts=%d spawn avg %.2fs [%.2f..%.2f] queue-full %.0f%% of time, crew %s lv %s tills_waiting=%d stars=%d" % [
			chap + 1, g.chapters[chap].name, g.chapter_done, t_ch / 60.0, bd_t / 60.0, int(g.bigday.get("tries", 0)), coins0, g.coins,
			g.stats.earned - earned0, g.vserved - served0, g.stats.lost - lost0,
			100.0 * float(g.stats.lost - lost0) / maxf(1.0, float(g.stats.lost - lost0 + g.vserved - served0)),
			g.stats.walkouts - wo0, samp_sum / maxf(1.0, samp_n), min_spawn, max_spawn, 100.0 * q_full_t / maxf(1.0, t_ch), g.crew,
			[g.levels.fire, g.levels.menu, g.levels.dining, g.levels.sign, g.levels.station], g.tills_waiting(), g.star_count()]
		print(row)
		summary.append(row)
		if not g.chapter_done or chap >= last_ch or chap + 1 >= g.chapters.size():
			break
		# travel next door the way the "GO NEXT DOOR" button does
		if hud.modal_kind != "":
			hud._story_q.clear()
			hud.close_modal()
		var tills_before: int = g.tills_waiting()
		main.travel_to(chap + 1)
		var guard := 0
		while (main.crossing or g.venue != chap + 1) and guard < 4000:
			await process_frame
			guard += 1
		for i in 10:
			await process_frame
		print("TRAVEL to %d: tills before %d, head start built=%s lj=%d pile=%d" % [chap + 2, tills_before, g.built.keys(), g.crew.lumberjack, g.woodpile])
	print("===== SUMMARY (speed %.0f)" % speed)
	for r in summary:
		print(r)
	print("total game time %.1f min, coins %d, earned %d, lost %d, walkouts %d" % [t_game / 60.0, g.coins, g.stats.earned, g.stats.lost, g.stats.walkouts])
	Engine.time_scale = 1.0
	quit()
