extends RefCounted
## Daily jobs and the 7-day streak (spec 7.1-7.2). State lives in sim.s.meta.

const Rng = preload("res://scripts/sim/rng.gd")
const TEMPLATES := [
	{"id": "meals", "counter": "meals", "label": "Serve %d meals", "ch": 1, "tier": "easy", "share": "all"},
	{"id": "upgrades", "counter": "upgrades_bought", "label": "Buy %d upgrades", "ch": 1, "tier": "easy", "fixed": 4},
	{"id": "trees", "counter": "trees_felled", "label": "Fell %d trees", "ch": 1, "tier": "medium", "fixed": 8},
	{"id": "dine", "counter": "served_dine", "label": "Serve %d dine-in customers", "ch": 1, "tier": "medium", "share": "dine"},
	{"id": "take", "counter": "served_take", "label": "Serve %d takeaway orders", "ch": 2, "tier": "medium", "share": "take"},
	{"id": "truck", "counter": "truck_trips", "label": "Send the log truck %d times", "ch": 2, "tier": "medium", "fixed": 3},
	{"id": "drive", "counter": "served_drive", "label": "Serve %d drive-through cars", "ch": 4, "tier": "medium", "share": "drive"},
	{"id": "delivery", "counter": "served_delivery", "label": "Complete %d deliveries", "ch": 4, "tier": "medium", "share": "delivery"},
]

var sim


func _init(p_sim) -> void:
	sim = p_sim


## Day key changes at local reset_hour (04:00). Prototype uses the device
## clock; production should use server time (spec 8.4).
static func day_key_now(reset_hour: int) -> int:
	var unix := Time.get_unix_time_from_system()
	var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	return int(floor((unix + bias - reset_hour * 3600) / 86400.0))


## Returns true when a new day started (new jobs generated).
func ensure_day(day_key: int) -> bool:
	var m: Dictionary = sim.s.meta
	if not m.has("streak"):
		m["streak"] = {"idx": 0, "last_claim": -99999}
	if int(m.get("day_key", -99999)) == day_key:
		return false
	m["day_key"] = day_key
	m["rerolls"] = int(sim.cfg.daily.free_rerolls)
	m["salt"] = 0
	m["chest_claimed"] = false
	m["jobs"] = _generate(day_key, 0)
	return true


func _generate(day_key: int, salt: int) -> Array:
	var rng = Rng.new()
	rng.seed_with((int(sim.s.seed) ^ (day_key * 2654435761)) + salt * 97)
	var ch := int(sim.s.chapter)
	var pool := TEMPLATES.filter(func(t): return int(t.ch) <= ch)
	var easy := pool.filter(func(t): return t.tier == "easy")
	var medium := pool.filter(func(t): return t.tier == "medium")
	var picks := []
	# 1 easy (normal play), 1 medium (a specific channel), 1 nudge (least-used system)
	picks.append(easy[int(rng.randf01() * easy.size())])
	var mid: Dictionary = medium[int(rng.randf01() * medium.size())]
	picks.append(mid)
	var rest := medium.filter(func(t): return t.id != mid.id)
	rest.sort_custom(func(a, b): return float(sim.s.stats[a.counter]) < float(sim.s.stats[b.counter]))
	picks.append(rest[0] if not rest.is_empty() else easy[0])
	var r: Dictionary = sim.rates(null, true, true)
	var jobs := []
	var tags := ["Easy", "Medium", "Try this"]
	for i in picks.size():
		var t: Dictionary = picks[i]
		var target := 0
		if t.has("fixed"):
			target = int(t.fixed)
		else:
			# Sized from the player's own rate: about 6 minutes of play (spec 7.1).
			var per_s: float = r.sales if t.share == "all" else r.dishes[t.share] / sim.dishes_per_order(t.share)
			target = maxi(5, int(round(per_s * 60.0 * 6.0)))
		jobs.append({"id": t.id, "counter": t.counter, "label": t.label % target, "target": target,
			"base": float(sim.s.stats[t.counter]), "tag": tags[i]})
	return jobs


func jobs() -> Array:
	return sim.s.meta.get("jobs", [])


func progress(j: Dictionary) -> float:
	return float(sim.s.stats[j.counter]) - float(j.base)


func all_done() -> bool:
	for j in jobs():
		if progress(j) < float(j.target):
			return false
	return not jobs().is_empty()


func chest_value() -> float:
	return maxf(50.0, sim.rates(null, true, false).income * 60.0 * float(sim.cfg.daily.chest_minutes))


func claim_chest() -> float:
	var m: Dictionary = sim.s.meta
	if bool(m.get("chest_claimed", false)) or not all_done():
		return 0.0
	var v := chest_value()
	m.chest_claimed = true
	sim.grant(v)
	return v


func reroll(by_ad: bool) -> bool:
	var m: Dictionary = sim.s.meta
	if not by_ad:
		if int(m.rerolls) <= 0:
			return false
		m.rerolls = int(m.rerolls) - 1
	m.salt = int(m.salt) + 1
	m.jobs = _generate(int(m.day_key), int(m.salt))
	return true


## Missing a day pauses the streak; it never resets (spec 7.2).
func streak_can_claim() -> bool:
	return int(sim.s.meta.streak.last_claim) != int(sim.s.meta.day_key)


func streak_reward(idx: int) -> float:
	var per_min: float = maxf(1.0, sim.rates(null, true, false).income * 60.0)
	return maxf(20.0, per_min * float(sim.cfg.streak.minutes_per_day) * (idx + 1))


func claim_streak() -> String:
	var st: Dictionary = sim.s.meta.streak
	if not streak_can_claim():
		return ""
	var idx := int(st.idx)
	var v := streak_reward(idx)
	sim.grant(v)
	st.idx = (idx + 1) % 7
	st.last_claim = int(sim.s.meta.day_key)
	if idx == 6:
		return "Day 7: Golden Axe skin (cosmetic placeholder) + coins"
	return "Day %d reward" % (idx + 1)
