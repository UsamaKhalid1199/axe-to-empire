extends SceneTree
## Plays chapter 1 by following the in-game objective arrow. Verifies the loop is completable
## and prints pacing. Run headless: --script res://tests/autoplay.gd -- [speed] [max_minutes]

var t_game := 0.0
var log_marks: Dictionary = {}
var stuck_t := 0.0
var detour_t := 0.0
var detour_dir := Vector2.ZERO
var check_t := 1.2
var last_dist := 999.0
var last_pos := Vector3.ZERO


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var speed := float(args[0]) if args.size() > 0 else 8.0
	var max_min := float(args[1]) if args.size() > 1 else 90.0
	var chap := int(args[2]) if args.size() > 2 else 0
	var g = root.get_node("Game")
	g.saving_enabled = false
	g.venue = chap
	g.unlocked = chap + 1
	g.venues = []
	g.vserved = 0
	g.cfg = g.chapter_cfg(chap)
	g.coins = 0; g.built = {}; g.pad_paid = {}; g.levels = {"tool": 0, "bag": 0, "boots": 0, "fire": 0, "menu": 0, "dining": 0, "sign": 0, "station": 0}
	g.reno = {}; g.bigday = {}; g.seen = {}; g.task_i = 0; g.task_base = 0; g.golden_n = 0; g.walkouts = 0
	g.crew = {"lumberjack": 0, "waiter": 0, "cook": 0}; g.woodpile = 0; g.rack = 0; g.counter_coins = 0
	g.offline_reward = 0; g.served = 0; g.rating_hist = []; g.chapter_done = false
	change_scene_to_file("res://scenes/main.tscn")
	while current_scene == null or current_scene.get("hud") == null or current_scene.get_node_or_null("LoadingScreen") != null:
		await process_frame
	for i in 10:
		await process_frame
	var main = current_scene
	var w = main.world
	var p = w.player
	Engine.time_scale = speed
	Engine.physics_ticks_per_second = int(60 * speed)
	Engine.max_physics_steps_per_frame = int(8 * speed)
	var hud = main.hud
	var m: float = g.chapter_mult(chap)
	while t_game < max_min * 60.0 and not g.chapter_done:
		await physics_frame
		var dt := 1.0 / 60.0
		t_game += dt
		_mark(g)
		if int(t_game / 120.0) != int((t_game - dt) / 120.0) and t_game >= 400:
			print("  t=%.0fs obj='%s' pile=%d back=%d bdready=%s cool=%.0f modal=%s" % [t_game, w.objective.text, g.woodpile, p.back.count(), g.big_day_ready(), w._bd_cool, hud.modal_kind])
		if int(t_game / 30.0) != int((t_game - dt) / 30.0) and t_game > 20 and t_game < 400:
			print("  t=%.0fs obj='%s' pos=%s back=%d hands=%d pile=%d rack=%d counter=%d coins=%d q=%d" % [t_game, w.objective.text, p.global_position.snapped(Vector3(0.1,0.1,0.1)), p.back.count(), p.hands.count(), g.woodpile, g.rack, w.counter_count(), g.coins, w.queue.size()] + " cust=%d served=%d" % [w.customers.size(), g.served])
			for c in w.queue:
				print("     cust slot=%d state=%s path=%d pos=%s got=%d/%d waited=%.0f" % [c.slot, c.state, c.path.size(), c.global_position.snapped(Vector3(0.1,0.1,0.1)), c.got, c.order, c.waited])
		# shopping: buy what the shop offers when standing in it
		if hud.modal_kind == "shop":
			for tr in ["tool", "bag", "boots"]:
				var n = g.next_upgrade(tr)
				if not n.is_empty() and g.coins >= int(n.cost) + 50 * m:
					g.buy_upgrade(tr)
					print("[%5.1f min] bought %s -> lv %d" % [t_game / 60.0, tr, g.levels[tr]])
			hud.close_modal()
			p.global_position += Vector3(0, 0, 1.5)
		if hud.modal_kind == "crew":
			for role in ["lumberjack", "waiter", "lumberjack", "cook", "waiter", "lumberjack", "cook"]:
				var c = g.crew_next_cost(role)
				if c >= 0 and g.coins >= c + 50 * m:
					g.hire(role)
					print("[%5.1f min] hired %s (%d)" % [t_game / 60.0, role, g.crew[role]])
			hud.close_modal()
			p.global_position += Vector3(-1.5, 0, 0)
		if hud.modal_kind == "gate":
			if g.gate_ready():
				g.open_next_venue()
			elif g.big_day_ready() and not w.bd_active and g.woodpile >= 15 and g.crew.lumberjack + g.crew.waiter >= 2 and w.start_big_day():
				print("[%5.1f min] BIG DAY started (served %d, kitchen %d, menu %d)" % [t_game / 60.0, g.vserved, g.levels.fire + 1, g.levels.menu + 1])
			hud.close_modal()
			p.global_position += Vector3(1.5, 0, -1.5)
		if hud.modal_kind in ["jobs", "offline", "settings", "complete", "story", "bigday_result", "upgrades", "character"]:
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
					print("[%5.1f min] hired %s (%d)" % [t_game / 60.0, role, g.crew[role]])
					break
		# station upgrades: keep a reserve for the next build pad
		var reserve := 0
		for b in g.cfg.builds:
			if w.pads.has(b.id) and b.id != "gate":
				reserve = maxi(reserve, int(b.cost) - int(g.pad_paid.get(b.id, 0)))
		# like a real player: the first lumberjack and waiter come before fancy upgrades
		if g.built.has("crew_hut") and (g.crew.lumberjack + g.crew.waiter) < 2:
			reserve += mini(g.crew_next_cost("lumberjack") if g.crew.lumberjack == 0 else 999999, g.crew_next_cost("waiter") if g.crew.waiter == 0 else 999999)
		if not g.reno.is_empty() and g.coins >= g.reno_rush_cost() * 3 + reserve:
			var rc: int = g.reno_rush_cost()
			if g.reno_rush():
				print("[%5.1f min] rushed renovation ($%d)" % [t_game / 60.0, rc])
		var order := ["fire", "menu", "station", "dining", "sign"]
		var ct: Dictionary = g.current_task()
		if String(ct.get("t", "")) == "level":
			order.push_front(g.station_key(String(ct.id)))
		for key in order:
			if g.station_locked(key) == "" and g.coins >= g.station_cost(key) + reserve and g.levels[key] < 14:
				g.station_upgrade(key)
				print("[%5.1f min] upgraded %s -> Lv %d%s" % [t_game / 60.0, key, g.levels[key] + 1, " (renovating)" if not g.reno.is_empty() else ""])
				break
		if w.bd_active and int(t_game * 60) % 600 == 0:
			print("     bigday left=%.0f served=%d/%d rating=%.2f walkouts=%d q=%d rack=%d" % [w.bd_left, w.bd_served, w.bd_goal(), w.bd_rating(), w.bd_walkouts, w.queue.size(), g.rack])
		var o: Dictionary = w.objective
		var target: Vector3 = o.pos
		# extra intent: visit shop / crew periodically when rich
		if g.built.has("shop") and g.coins > 400 * m and int(t_game) % 60 < 6:
			target = w.PADS.shop
		elif g.built.has("crew_hut") and g.coins > 600 * m and int(t_game) % 40 >= 20 and int(t_game) % 40 < 26:
			target = w.PADS.crew_hut
		elif target == Vector3.ZERO:
			target = w._nearest_tree_pos()
		var to: Vector3 = target - p.global_position
		to.y = 0
		var is_tree: bool = String(o.text).begins_with("Chop") or String(o.text).begins_with("Chop wood") or String(o.text) == "Keep the fire fed" or o.pos == Vector3.ZERO
		var stop_r := 1.25 if is_tree else 0.3
		if to.length() > stop_r:
			p.input_dir = Vector2(to.x, to.z).normalized()
		else:
			p.input_dir = Vector2.ZERO
		# unstick: if we stop closing in on the target, detour sideways for a moment
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
		last_pos = p.global_position
	print("RESULT chapter_done=%s time=%.1f min coins=%d served=%d rating=%.2f trees=%d walkouts=%d lost=%d golden=%d bigday_tries=%d task=%d/%d stars=%d" % [g.chapter_done, t_game / 60.0, g.coins, g.served, g.rating(), g.stats.trees, g.stats.walkouts, g.stats.lost, g.stats.golden, int(g.bigday.get("tries", 0)), g.task_i, g.tasks().size(), g.star_count()])
	Engine.time_scale = 1.0
	quit()


func _mark(g) -> void:
	for b in g.built:
		if not log_marks.has(b):
			log_marks[b] = t_game
			print("[%5.1f min] built %s (coins %d, served %d, rating %.2f)" % [t_game / 60.0, b, g.coins, g.served, g.rating()])
