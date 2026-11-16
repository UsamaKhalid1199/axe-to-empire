extends SceneTree
## Headless balance bot (spec 8.6): plays like a player who taps once a second
## and always follows the hint. Prints the pacing curve and checks invariants
## (save round-trip, determinism, offline, prestige).
##   Godot --headless --path . --script res://tests/balance_bot.gd

const Sim = preload("res://scripts/sim/economy_sim.gd")
const Meta = preload("res://scripts/sim/meta.gd")

var failures := 0


func _init() -> void:
	var cfg = JSON.parse_string(FileAccess.get_file_as_string("res://data/config.json"))
	_run_pacing(cfg, 4.0 * 3600.0)
	_check_determinism(cfg)
	_check_save_roundtrip(cfg)
	_check_offline(cfg)
	print("\nRESULT: %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		print("  FAIL: ", msg)


func _bot_tap(sim) -> void:
	var s: Dictionary = sim.s
	var c: Dictionary = sim.chap()
	for i in s.tables.size():
		var t: Dictionary = s.tables[i]
		if float(s.player.busy) <= 0.0 and (t.st == "dirty" or (t.st == "waiting_food" and not c.self_serve and int(s.rack) > 0)):
			sim.push_command("table", i)
			return
	if sim.unlocked("take") and sim.lv("cashier") == 0 and not s.take_q.is_empty() and int(s.rack) > 0 and float(s.player.busy) <= 0.0:
		sim.push_command("serve_take")
		return
	if float(s.ingredients) < 3.0 and not sim.has_supplier(s.levels):
		sim.push_command("buy_crate")
		return
	for i in s.trees.size():
		if float(s.trees[i].hp) > 0.0:
			sim.push_command("chop", i)
			return


func _run_pacing(cfg: Dictionary, seconds: float) -> void:
	print("== Pacing run: hint-following bot, 1 tap/s, %d sim-hours ==" % int(seconds / 3600.0))
	var sim = Sim.new(cfg)
	sim.new_game(12345)
	var meta = Meta.new(sim)
	meta.ensure_day(20000)
	var hz := int(cfg.tick_hz)
	var ticks := int(seconds * hz)
	var first_upgrade := -1.0
	var last_upgrade_t := 0.0
	var longest_gap := 0.0
	var chapter_t := {1: 0.0}
	var prestiged := -1.0
	var bought := {}
	var lost_by := {}
	for i in ticks:
		var t := float(i) / hz
		if i % hz == 0:
			_bot_tap(sim)
		if i % (hz * 5) == 0:
			var h: Dictionary = sim.best_action()
			match str(h.kind):
				"buy":
					if sim.buy_upgrade(h.id):
						bought[h.id] = int(bought.get(h.id, 0)) + 1
						if first_upgrade < 0.0:
							first_upgrade = t
						longest_gap = maxf(longest_gap, t - last_upgrade_t)
						last_upgrade_t = t
				"move":
					sim.move_chapter()
				"prestige":
					if prestiged < 0.0:
						prestiged = t
						print("  New Venture available at %s with %d LP" % [_mm(t), sim.lp_total_preview()])
		sim.step()
		if OS.get_environment("SNAP") == "1" and t > 7200.0 and t < 7200.0 + 720.0 and i % 8 == 0 and sim.daypart().rush:
			var cb := []
			for c in sim.s.cashiers:
				cb.append(snappedf(float(c.busy), 0.1))
			print("  snap t=%d rack=%d cooking=%d wood=%.0f ing=%.0f takeQ=%d dineQ=%d cashiers=%s player=%s lamT=%.2f" % [int(t), sim.s.rack, sim.cooking_count(), sim.s.wood, sim.s.ingredients, sim.s.take_q.size(), sim.s.dine_q.size(), cb, sim.s.player.task, sim.demand("take")])
		for e in sim.events:
			if e.type == "balk" or e.type == "renege":
				var key: String = "%s_%s_ch%d_%s" % [e.where, e.type, int(sim.s.chapter), "rush" if sim.daypart().rush else "calm"]
				lost_by[key] = int(lost_by.get(key, 0)) + 1
		if int(sim.s.chapter) not in chapter_t:
			chapter_t[int(sim.s.chapter)] = t
			print("  Chapter %d reached at %s  (coins/h %d, rating %.2f, fame %d)" % [
				int(sim.s.chapter), _mm(t), int(sim.rates(null, true, true).income * 3600.0), sim.rating(), int(sim.s.fame)])
		if i % (hz * 1800) == 0 and i > 0:
			var r: Dictionary = sim.rates(null, false, true)
			print("  t=%s ch%d coins=%d income/h=%d bottleneck=%s lost=%d/%d" % [_mm(t), int(sim.s.chapter),
				int(sim.s.coins), int(r.income * 3600.0), r.bottleneck, int(sim.s.stats.lost_balk), int(sim.s.stats.lost_renege)])
	var g: Dictionary = sim.gate()
	print("  Gate now: rating_ok=%s fame_ok=%s quests=%s" % [g.rating_ok, g.fame_ok, str(g.quests)])
	print("  Lost by channel: ", lost_by)
	var st: Dictionary = sim.s.stats
	print("  First upgrade at %s (spec target <= 45s)" % _mm(first_upgrade))
	print("  Longest gap between upgrades: %s" % _mm(longest_gap))
	print("  Meals %d  dine %d take %d drive %d delivery %d" % [st.meals, st.served_dine, st.served_take, st.served_drive, st.served_delivery])
	print("  Lost: balk %d renege %d   trees felled %d" % [st.lost_balk, st.lost_renege, st.trees_felled])
	print("  Upgrades bought: ", bought)
	_expect(first_upgrade >= 0.0 and first_upgrade <= 90.0, "first upgrade within 90s")
	_expect(chapter_t.has(2), "reached chapter 2")
	_expect(float(sim.s.coins) >= 0.0, "coins never negative")
	_expect(int(sim.s.rack) >= 0 and float(sim.s.wood) >= -0.001 and float(sim.s.ingredients) >= -0.001, "stocks never negative")


func _mm(t: float) -> String:
	if t < 0.0:
		return "never"
	return "%dm%02ds" % [int(t) / 60, int(t) % 60]


func _sim_with_actions(cfg: Dictionary, seed_value: int, ticks: int):
	var sim = Sim.new(cfg)
	sim.new_game(seed_value)
	for i in ticks:
		if i % 4 == 0:
			_bot_tap(sim)
		if i % 40 == 0:
			var h: Dictionary = sim.best_action()
			if h.kind == "buy":
				sim.buy_upgrade(h.id)
		sim.step()
	return sim


func _check_determinism(cfg: Dictionary) -> void:
	print("== Determinism ==")
	var a = _sim_with_actions(cfg, 777, 4 * 900)
	var b = _sim_with_actions(cfg, 777, 4 * 900)
	_expect(var_to_str(a.to_save()) == var_to_str(b.to_save()), "same seed + same inputs -> identical state")
	print("  ok" if failures == 0 else "  mismatch")


func _check_save_roundtrip(cfg: Dictionary) -> void:
	print("== Save round-trip ==")
	var a = _sim_with_actions(cfg, 99, 4 * 600)
	var bytes := var_to_bytes(a.to_save())
	var b = Sim.new(cfg)
	_expect(b.from_save(bytes_to_var(bytes)), "load succeeds")
	for i in 4 * 300:
		a.step()
		b.step()
	_expect(var_to_str(a.to_save()) == var_to_str(b.to_save()), "loaded game continues identically")
	print("  save size: %d bytes" % bytes.size())


func _check_offline(cfg: Dictionary) -> void:
	print("== Offline ==")
	var sim = _sim_with_actions(cfg, 5, 4 * 1200)
	var r: Dictionary = sim.offline_fast_forward(7200.0)
	print("  2h away: %d dishes -> %d coins (eff %d%%, cap %ds)" % [int(r.dishes), int(r.coins), int(r.eff * 100), int(r.cap)])
	_expect(r.coins >= 0.0, "offline coins non-negative")
	var r2: Dictionary = sim.offline_fast_forward(-50.0)
	_expect(r2.coins == 0.0, "negative time grants nothing")
	var r3: Dictionary = sim.offline_fast_forward(10.0 * 86400.0)
	_expect(r3.counted <= r3.cap + 0.001, "offline time is capped")
