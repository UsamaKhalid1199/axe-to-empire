extends SceneTree
## QA tester 1: is a till worth visiting at each chapter? (cap vs local income, walk cost)
## Uses the end-of-chapter state the autoplay bot reaches (full build, full crew, stations ~Lv 13).
## Run: $G --headless --path . -s res://tests/qa/qa_t1_pacing.gd
var g


func _initialize() -> void:
	_run.call_deferred()


func _full(k: int) -> Dictionary:
	var b := {"campfire": true, "tables_1": true, "shop": true, "crew_hut": true, "fire_2": true, "tables_2": true}
	if String(g.chapters[k].get("special", {}).get("type", "")) != "":
		b["special"] = true
	return b


func _vd(k: int, lv: int, crew: Dictionary) -> Dictionary:
	return {"built": _full(k), "crew": crew.duplicate(), "fire": lv, "menu": lv, "dining": lv, "sign": lv,
		"station": lv, "chapter_done": true, "bigday": {"won": true}}


func _run() -> void:
	g = root.get_node("Game")
	g.set_process(false)
	g.saving_enabled = false
	var full := {"lumberjack": 3, "waiter": 2, "cook": 2}
	var half := {"lumberjack": 1, "waiter": 1, "cook": 0}
	print("k = active chapter; prev = the place next door you came from (finished: full crew, stations Lv 13)")
	print("cols: crew $/min here | prev bg $/min | prev till cap | cap in min of local crew income | walk-over round trip ~ 15 s = min of local")
	for at in range(1, 6):
		for case in ["early (here: 1 LJ + 1 waiter, Lv1)", "late (here: full crew, Lv13)"]:
			g.prestige = 0
			g.unlocked = at + 1
			g.venues = []
			for k in at:
				g.venues.append(_vd(k, 12, full))
			var here: Dictionary = _vd(at, 0 if case.begins_with("early") else 12, half if case.begins_with("early") else full)
			g.venues.append(here)
			g.venue = at
			g._unstash(at)
			g._cc_cache.clear()
			g.cfg = g.chapter_cfg(at)
			g._star_cache = 2 * at
			var local: float = g.passive_rate() * 60.0
			var prev := at - 1
			var bg: float = g.venue_rate(prev) * g.VENUE_EFFICIENCY * 60.0
			var cap: int = g.till_cap(prev)
			var all_bg := 0.0
			var all_cap := 0
			for k in at:
				all_bg += g.venue_rate(k) * g.VENUE_EFFICIENCY * 60.0
				all_cap += g.till_cap(k)
			print("ch%d %-36s local %10.0f/min | prev bg %9.0f/min | cap %10d | cap = %5.1f min local | all tills cap %10d (%5.1f min), all bg %5.0f%% of local" % [
				at, case, local, bg, cap, cap / maxf(1.0, local), all_cap, all_cap / maxf(1.0, local), 100.0 * all_bg / maxf(1.0, local)])
	quit()
