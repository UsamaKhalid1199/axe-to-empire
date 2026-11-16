extends RefCounted
## Core economy simulation: the single source of truth (spec 2.1).
## - Fixed 4 Hz ticks, deterministic seeded RNG.
## - All state lives in the plain dictionary `s`, which is saved as-is.
## - Never touches nodes/scenes, so the balance bot and offline maths run the
##   exact same code as the game.
## - Player taps arrive as commands and are applied at the start of a tick.

const Rng = preload("res://scripts/sim/rng.gd")
const SAVE_VERSION := 1
const CHANNELS := ["dine", "take", "drive", "delivery"]
const STAT_KEYS := ["meals", "served_dine", "served_take", "served_drive", "served_delivery",
	"trees_felled", "chops", "truck_trips", "upgrades_bought", "lost_balk", "lost_renege",
	"rush_clean", "coins_dishes", "coins_tips", "coins_truck", "coins_other", "crates_bought",
	"supplier_used"]

var cfg: Dictionary
var dt: float
var rng = Rng.new()
var s: Dictionary = {}
var events: Array = []        # visual events emitted during the last step (not saved)
var scores: Dictionary = {}   # upgrade id -> coins/hour gain (from the last hint pass)
var _cmds: Array = []
var _upg: Dictionary = {}


func _init(config: Dictionary) -> void:
	cfg = config
	dt = 1.0 / float(cfg.tick_hz)
	for u in cfg.upgrades:
		_upg[u.id] = u


# ---------------------------------------------------------------- lifecycle

func new_game(seed_value: int, legacy: Dictionary = {}) -> void:
	var st := {}
	for k in STAT_KEYS:
		st[k] = 0.0
	if legacy.is_empty():
		legacy = {"lp": 0, "runs": 0, "lifetime_all": 0.0}
	s = {
		"version": SAVE_VERSION, "seed": seed_value, "rng": seed_value, "tick": 0, "day": -1,
		"weather": "Clear", "event": {"type": "", "left": 0.0, "at": -1.0, "done": true},
		"chapter": 1, "coins": float(cfg.start.coins), "lifetime": 0.0, "legacy": legacy,
		"levels": {}, "wood": float(cfg.start.wood), "wood_reserve": 10.0,
		"ingredients": float(cfg.start.ingredients), "rack": 0, "oven": [],
		"trees": [], "since_golden": 0,
		"truck": {"state": "bay", "load": 0.0, "t": 0.0, "pay": 0.0}, "sold_recent": 0.0,
		"dine_q": [], "tables": [], "waiters": [],
		"take_q": [], "cashiers": [],
		"drive_q": [], "drive_order": {}, "drive_pickup": {},
		"delivery_q": [], "packers": [], "del_ready": [], "bikes": [],
		"player": {"busy": 0.0, "task": "", "idx": -1, "kind": 0, "frac": 1.0},
		"ring": [], "ring_idx": 0, "ring_sum": 0.0, "fame": 0.0,
		"stats": st, "chapter_start": st.duplicate(),
		"rush": {"active": false, "lost": 0.0, "served": 0.0},
		"last_seen": 0, "meta": {},
	}
	rng.seed_with(seed_value)
	for i in int(cfg.trees.count):
		s.trees.append(_new_tree(false))
	_sync()


func to_save() -> Dictionary:
	s.rng = rng.state
	return s.duplicate(true)


func from_save(d: Dictionary) -> bool:
	if not d.has("version") or int(d.version) > SAVE_VERSION:
		return false
	# Migrations go here: if int(d.version) < 2: ...
	s = d
	rng.state = int(s.rng)
	for k in STAT_KEYS:
		if not s.stats.has(k):
			s.stats[k] = 0.0
	_sync()
	return true


## Grow arrays to match purchased levels (stations/staff are data, not nodes).
func _sync() -> void:
	while s.oven.size() < oven_slots(s.levels):
		s.oven.append(-1.0)
	while s.tables.size() < tables_count(s.levels):
		s.tables.append(_free_table())
	_grow(s.waiters, lv("helper"), {"busy": 0.0, "task": "", "idx": -1})
	_grow(s.cashiers, lv("cashier"), {"busy": 0.0, "kind": 0, "frac": 1.0})
	_grow(s.packers, lv("packers"), {"busy": 0.0, "kind": 0, "frac": 1.0})
	_grow(s.bikes, lv("bikes"), {"away": 0.0, "pay": 0.0, "kind": 0, "frac": 1.0})


func _grow(arr: Array, n: int, tmpl: Dictionary) -> void:
	while arr.size() < n:
		arr.append(tmpl.duplicate())


func _free_table() -> Dictionary:
	return {"st": "free", "t": 0.0, "pat": 0.0, "pmax": 1.0, "kind": 0}


func _new_tree(golden: bool) -> Dictionary:
	var hp := float(cfg.trees.hp) * (3.0 if golden else 1.0)
	return {"hp": hp, "max": hp, "golden": golden, "regrow": 0.0}


# ---------------------------------------------------------------- derived values

func lv(id: String) -> int:
	return int(s.levels.get(id, 0))


func _l(L: Dictionary, id: String) -> int:
	return int(L.get(id, 0))


func chap() -> Dictionary:
	return cfg.chapters[clampi(int(s.chapter), 1, cfg.chapters.size()) - 1]


func unlocked(system: String) -> bool:
	return int(s.chapter) >= int(cfg.unlocks.get(system, 1))


## Every 10 levels x2, every 25 levels an extra x1.5 (spec 5.2).
static func milestone(l: int) -> float:
	return pow(2.0, floor(l / 10.0)) * pow(1.5, floor(l / 25.0))


func axe_damage(L: Dictionary) -> float:
	var l := _l(L, "axe")
	return float(cfg.axe_damage) * (1.0 + 0.25 * l) * milestone(l)

func lj_dps(L: Dictionary) -> float:
	var l := _l(L, "lj_speed")
	return float(cfg.lumberjack.damage) * (1.0 + 0.2 * l) * milestone(l) / float(cfg.lumberjack.interval_s)

## Saplings speed regrowth (spec 3.3). Regrowth caps wood income no matter
## how many lumberjacks you hire.
func regrow_time(L: Dictionary) -> float:
	return float(cfg.trees.regrow_s) / (1.0 + 0.25 * _l(L, "saplings"))

func cook_time(L: Dictionary) -> float:
	var l := _l(L, "campfire")
	return float(cfg.cook.time_s) / ((1.0 + 0.12 * l) * milestone(l))

func oven_slots(L: Dictionary) -> int:
	return int(cfg.cook.slots) + _l(L, "oven_slots")

func rack_cap(L: Dictionary) -> int:
	return int(cfg.rack_cap) + 2 * _l(L, "rack")

func pile_cap(L: Dictionary) -> float:
	return float(cfg.wood.pile_cap) + 20.0 * _l(L, "pile")

func shelf_cap(L: Dictionary) -> float:
	return float(cfg.ingredients.shelf_cap) + 15.0 * _l(L, "shelf")

func tables_count(L: Dictionary) -> int:
	return int(cfg.dine.tables) + _l(L, "seats")

func waiter_speed(L: Dictionary) -> float:
	var l := _l(L, "waiter_speed")
	return (1.0 + 0.15 * l) * milestone(l)

func truck_cap(L: Dictionary) -> float:
	return float(cfg.truck.capacity) + 15.0 * _l(L, "truck_cap")

func dt_speed(L: Dictionary) -> float:
	var l := _l(L, "dt_crew")
	return 0.0 if l <= 0 else (1.0 + 0.1 * (l - 1)) * milestone(l)

func marketing_mult(L: Dictionary) -> float:
	return 1.0 + 0.15 * _l(L, "marketing")

func menu_mult(L: Dictionary) -> float:
	var l := _l(L, "menu")
	return (1.0 + 0.1 * l) * milestone(l)

func offline_cap_s(L: Dictionary) -> float:
	return (float(cfg.offline.base_cap_h) + _l(L, "offline_cap")) * 3600.0

func offline_eff(L: Dictionary) -> float:
	return minf(1.0, float(cfg.offline.base_eff) + 0.1 * _l(L, "manager"))

func has_supplier(L: Dictionary) -> bool:
	return _l(L, "supplier") >= 1

func legacy_mult() -> float:
	return 1.0 + float(cfg.prestige.per_lp) * float(s.legacy.lp)

func dishes_per_order(ch: String) -> float:
	return float(cfg[ch].dishes)

## Price = recipe x (1 + flavor) x (1 + 0.1 decor) x menu (spec 5.3)
func dish_price(L: Dictionary) -> float:
	var c := chap()
	return float(c.price) * (1.0 + float(c.flavor)) * (1.0 + 0.1 * _l(L, "decor")) * menu_mult(L)

func price_for(ch: String, kind: int, L = null) -> float:
	if L == null:
		L = s.levels
	var p := dish_price(L) * float(cfg[ch].rev_mult)
	if kind == 1:
		p *= float(cfg.vip.pay_mult)
	return p

func ingredient_unit_cost(L: Dictionary) -> float:
	var u := float(cfg.ingredients.crate_cost) * float(chap().ing_mult) / float(cfg.ingredients.crate_size)
	return u * float(cfg.ingredients.supplier_markup) if has_supplier(L) else u

func crate_cost() -> float:
	return float(cfg.ingredients.crate_cost) * float(chap().ing_mult)

func patience_max(ch: String, kind: int) -> float:
	var p := float(cfg[ch].patience_s) * (1.0 + 0.05 * lv("decor"))
	if kind == 1:
		p *= float(cfg.vip.patience_mult)
	return p

## P_wood = P_base x (1 - 0.4 x S/(S+K)); S decays exponentially (spec 3.2).
func wood_price() -> float:
	var sr := float(s.sold_recent)
	var k := float(cfg.wood.sell_k)
	return float(cfg.wood.sell_price) * float(chap().wood_price_mult) * (1.0 - 0.4 * sr / (sr + k))

func cooking_count() -> int:
	var n := 0
	for t in s.oven:
		if float(t) >= 0.0:
			n += 1
	return n


# ---------------------------------------------------------------- time of day

func day_ticks() -> int:
	return int(float(cfg.day_length_s) * float(cfg.tick_hz))

func day_index() -> int:
	return int(s.tick) / day_ticks()

func day_frac() -> float:
	return float(int(s.tick) % day_ticks()) / float(day_ticks())

func daypart() -> Dictionary:
	if not unlocked("rushes"):
		return {"name": "Open all day", "mult": 1.0, "rush": false}
	var f := day_frac()
	var cur: Dictionary = cfg.dayparts[0]
	for d in cfg.dayparts:
		if f >= float(d.start):
			cur = d
	return cur

func avg_daypart_mult() -> float:
	if not unlocked("rushes"):
		return 1.0
	var total := 0.0
	var parts: Array = cfg.dayparts
	for i in parts.size():
		var end := 1.0 if i == parts.size() - 1 else float(parts[i + 1].start)
		total += float(parts[i].mult) * (end - float(parts[i].start))
	return total


# ---------------------------------------------------------------- demand & rating

func channel_open(ch: String, L = null) -> bool:
	if L == null:
		L = s.levels
	match ch:
		"dine":
			return true
		"take":
			return unlocked("take")
		"drive":
			return unlocked("drive") and _l(L, "dt_crew") >= 1
		"delivery":
			return unlocked("delivery") and _l(L, "packers") >= 1 and _l(L, "bikes") >= 1
	return false

## lambda = base x (1 + 0.1 rating) x marketing x daypart x weather (spec 4.1)
func demand(ch: String, L = null, avg := false) -> float:
	if L == null:
		L = s.levels
	if not channel_open(ch, L):
		return 0.0
	var lam := float(cfg.demand_base[ch]) * float(chap().demand_mult) * (1.0 + 0.1 * rating()) * marketing_mult(L)
	if avg:
		return lam * avg_daypart_mult()
	lam *= float(daypart().mult)
	if s.weather == "Rain":
		lam *= float(cfg.weather.rain[ch])
	if s.event.type == "celebrity" and float(s.event.left) > 0.0:
		lam *= float(cfg.random_events.celebrity.demand_mult)
	return lam

## Rating: 0-5, rolling over the last 200 customers with a prior so one bad
## rush can't crash it (spec 4.3). Fame: cumulative, only grows; gates use it.
func rating() -> float:
	var pn := float(cfg.rating_prior.n)
	return 5.0 * (float(s.ring_sum) + pn * float(cfg.rating_prior.value)) / (float(s.ring.size()) + pn)

func _push_rating(v: float) -> void:
	var w := int(cfg.rating_window)
	if s.ring.size() < w:
		s.ring.append(v)
		s.ring_sum += v
	else:
		var i := int(s.ring_idx)
		s.ring_sum += v - float(s.ring[i])
		s.ring[i] = v
		s.ring_idx = (i + 1) % w

func _outcome(v: float, kind: int) -> void:
	var reps := int(cfg.critic.weight) if kind == 2 else 1
	for i in reps:
		_push_rating(v)
	s.fame += v * float(reps)
	if kind == 2:
		events.append({"type": "critic", "good": v >= 1.0})

func _pay(amount: float, src: String, where: String) -> void:
	amount *= legacy_mult()
	s.coins += amount
	s.lifetime += amount
	s.stats["coins_" + src] = float(s.stats.get("coins_" + src, 0.0)) + amount
	events.append({"type": "coins", "amount": amount, "where": where})

## Coins from outside the sim loop (offline, chests, debug). No legacy bonus.
func grant(amount: float) -> void:
	s.coins += amount
	s.lifetime += amount
	s.stats.coins_other += amount

func _served(ch: String, kind: int, frac: float) -> void:
	s.stats.meals += 1
	s.stats["served_" + ch] += 1
	_outcome(1.0 if frac > 0.3 else 0.5, kind)

func _lost(ch: String, kind: int, why: String) -> void:
	if why == "balk":
		s.stats.lost_balk += 1
	else:
		s.stats.lost_renege += 1
		_outcome(0.0, kind)
	events.append({"type": why, "where": ch})


# ---------------------------------------------------------------- commands

func push_command(cmd_name: String, arg = null) -> void:
	_cmds.append([cmd_name, arg])

func _process_commands() -> void:
	var cmds := _cmds
	_cmds = []
	for c in cmds:
		match c[0]:
			"chop": _cmd_chop(int(c[1]))
			"table": _cmd_table(int(c[1]))
			"serve_take": _cmd_serve_take()
			"buy_crate": _cmd_buy_crate()
			"send_truck": _cmd_send_truck()
			"buy": buy_upgrade(str(c[1]))
			"move": move_chapter()
			"reserve": s.wood_reserve = clampf(float(c[1]), 0.0, pile_cap(s.levels))

func _cmd_chop(i: int) -> void:
	if i < 0 or i >= s.trees.size() or float(s.trees[i].hp) <= 0.0:
		return
	s.stats.chops += 1
	events.append({"type": "chop", "idx": i})
	_damage_tree(i, axe_damage(s.levels))

func _player_free() -> bool:
	if float(s.player.busy) > 0.0:
		events.append({"type": "busy", "where": "player"})
		return false
	return true

## Manual work is 1.5x faster than a level-1 worker (spec 2.4).
func _cmd_table(i: int) -> void:
	if i < 0 or i >= s.tables.size() or not _player_free():
		return
	var t: Dictionary = s.tables[i]
	var ms := float(cfg.manual_speed)
	if t.st == "dirty":
		t.st = "cleaning"
		s.player = {"busy": float(cfg.dine.clean_s) / ms, "task": "clean", "idx": i, "kind": 0, "frac": 1.0}
	elif t.st == "waiting_food" and not bool(chap().self_serve) and int(s.rack) > 0:
		s.rack -= 1
		t.st = "serving"
		s.player = {"busy": float(cfg.dine.serve_s) / ms, "task": "serve", "idx": i, "kind": 0, "frac": 1.0}

func _cmd_serve_take() -> void:
	if not unlocked("take") or s.take_q.is_empty() or int(s.rack) <= 0 or not _player_free():
		return
	var e: Array = s.take_q.pop_front()
	s.rack -= 1
	var frac := _frac_left("take", e)
	s.player = {"busy": float(cfg.take.serve_s) / float(cfg.manual_speed), "task": "take", "idx": -1, "kind": int(e[1]), "frac": frac}

func _cmd_buy_crate() -> void:
	var space := shelf_cap(s.levels) - float(s.ingredients)
	if space < 1.0:
		events.append({"type": "full", "where": "shelf"})
		return
	var amount := minf(float(cfg.ingredients.crate_size), floor(space))
	var cost := crate_cost()
	if s.coins >= cost:
		s.coins -= cost
		s.ingredients += amount
		s.stats.crates_bought += 1
		events.append({"type": "crate", "where": "shelf"})
	elif float(s.ingredients) < 1.0 and int(s.rack) == 0 and cooking_count() == 0:
		# Soft-lock guard: broke and nothing to sell -> a free crate.
		s.ingredients += amount
		events.append({"type": "free_crate", "where": "shelf"})
	else:
		events.append({"type": "poor", "where": "shelf"})

func _cmd_send_truck() -> void:
	if unlocked("truck") and s.truck.state == "bay" and float(s.truck.load) >= 1.0:
		_truck_depart()


# ---------------------------------------------------------------- upgrades & progression

func upgrade_cost(id: String) -> float:
	var u: Dictionary = _upg[id]
	return float(u.c0) * pow(float(u.g), lv(id))

func upgrade_info(id: String) -> Dictionary:
	return _upg[id]

func upgrade_state(id: String) -> Dictionary:
	var u: Dictionary = _upg[id]
	var cost := upgrade_cost(id)
	return {"locked": int(s.chapter) < int(u.ch), "maxed": lv(id) >= int(u.max),
		"cost": cost, "level": lv(id), "affordable": float(s.coins) >= cost}

func can_buy(id: String) -> bool:
	var st := upgrade_state(id)
	return not st.locked and not st.maxed and st.affordable

func buy_upgrade(id: String) -> bool:
	if not _upg.has(id) or not can_buy(id):
		return false
	s.coins -= upgrade_cost(id)
	s.levels[id] = lv(id) + 1
	s.stats.upgrades_bought += 1
	_sync()
	events.append({"type": "upgrade", "id": id})
	return true

func quest_list() -> Array:
	var out := []
	for q in chap().quests:
		var cur := 0.0
		if q.has("counter"):
			cur = float(s.stats[q.counter]) - float(s.chapter_start.get(q.counter, 0.0))
		else:
			cur = float(lv(q.level))
		out.append({"label": q.label, "cur": cur, "target": float(q.target), "done": cur >= float(q.target)})
	return out

## Gate = rating + fame + quests (+ a coin move cost). Coins alone never
## unlock a chapter (spec 6.1).
func gate() -> Dictionary:
	var g: Dictionary = chap().gate
	var qs := quest_list()
	var quests_ok := true
	for q in qs:
		if not q.done:
			quests_ok = false
	var rating_ok := rating() >= float(g.rating)
	var fame_ok := float(s.fame) >= float(g.fame)
	var last: bool = int(s.chapter) >= cfg.chapters.size()
	var cost := float(g.move_cost)
	var ready := rating_ok and fame_ok and quests_ok
	return {"rating": float(g.rating), "fame": float(g.fame), "rating_ok": rating_ok, "fame_ok": fame_ok,
		"quests": qs, "quests_ok": quests_ok, "cost": cost, "ready": ready, "last": last,
		"can_move": ready and not last and float(s.coins) >= cost, "can_prestige": ready and last}

func move_chapter() -> bool:
	var g := gate()
	if not g.can_move:
		return false
	s.coins -= g.cost
	s.chapter += 1
	s.chapter_start = s.stats.duplicate()
	_sync()
	events.append({"type": "chapter", "n": int(s.chapter)})
	return true

func venue_stage() -> String:
	var stages: Array = chap().stages
	var bought := float(s.stats.upgrades_bought) - float(s.chapter_start.get("upgrades_bought", 0.0))
	return str(stages[mini(stages.size() - 1, int(bought / 4.0))])

## LP = floor(sqrt(lifetime / divisor)) (spec 5.6); divisor is tiny in the
## prototype so New Venture can be tried after chapter 4.
func lp_total_preview() -> int:
	var all := float(s.legacy.lifetime_all) + float(s.lifetime)
	return maxi(int(s.legacy.lp), int(floor(sqrt(all / float(cfg.prestige.divisor)))))

func prestige() -> bool:
	if not gate().can_prestige:
		return false
	var legacy := {"lp": lp_total_preview(), "runs": int(s.legacy.runs) + 1,
		"lifetime_all": float(s.legacy.lifetime_all) + float(s.lifetime)}
	var meta_keep: Dictionary = s.meta
	new_game(int(s.seed) + 7919, legacy)
	s.meta = meta_keep
	events.append({"type": "prestige"})
	return true


# ---------------------------------------------------------------- the tick

func step() -> void:
	events.clear()
	var d := day_index()
	if d != int(s.day):
		_start_day(d)
	_process_commands()
	_update_event()
	_update_trees()
	_update_supplier()
	_update_truck()
	_update_oven()
	_arrivals()
	# Rotate channel order so no channel always gets first pick of the rack.
	var start := int(s.tick) % 4
	for k in 4:
		match CHANNELS[(start + k) % 4]:
			"dine": _update_dine()
			"take": _update_take()
			"drive": _update_drive()
			"delivery": _update_delivery()
	_update_player()
	_update_rush()
	s.sold_recent = float(s.sold_recent) * exp(-dt / float(cfg.wood.sell_tau_s))
	s.tick += 1


## Fixed random seed per in-game day (spec 4.1).
func _start_day(d: int) -> void:
	s.day = d
	rng.seed_with(int(s.seed) ^ ((d * 0x9E3779B1) & 0xFFFFFFFF))
	s.weather = "Rain" if unlocked("weather") and rng.randf01() < float(cfg.weather.rain_chance) else "Clear"
	s.event = {"type": "", "left": 0.0, "at": -1.0, "done": true}
	if unlocked("random_events"):
		s.event.at = 0.1 + 0.8 * rng.randf01()
		s.event.type = "power_cut" if rng.randf01() < 0.5 else "celebrity"
		s.event.done = false
	events.append({"type": "day", "n": d})


func _update_event() -> void:
	var ev: Dictionary = s.event
	if not bool(ev.done) and day_frac() >= float(ev.at):
		ev.done = true
		ev.left = float(cfg.random_events[ev.type].duration_s)
		events.append({"type": "event", "kind": ev.type})
	if float(ev.left) > 0.0:
		ev.left = float(ev.left) - dt


func _update_trees() -> void:
	for t in s.trees:
		if float(t.hp) <= 0.0:
			t.regrow = float(t.regrow) - dt
			if float(t.regrow) <= 0.0:
				var fresh := _new_tree(_roll_golden())
				t.merge(fresh, true)
	var n := lv("lumberjack")
	if n > 0:
		for i in s.trees.size():
			if float(s.trees[i].hp) > 0.0:
				_damage_tree(i, lj_dps(s.levels) * n * dt)
				break


## Golden oak about 1 per 50 trees, with bad-luck protection: the chance
## rises with every normal tree and is guaranteed by 2x the average.
func _roll_golden() -> bool:
	s.since_golden += 1
	var every := float(cfg.trees.golden_every)
	var p := float(s.since_golden) * PI / (2.0 * every * every)
	if float(s.since_golden) >= 2.0 * every or rng.randf01() < p:
		s.since_golden = 0
		return true
	return false


func _damage_tree(i: int, dmg: float) -> void:
	var t: Dictionary = s.trees[i]
	t.hp = float(t.hp) - dmg
	if float(t.hp) <= 0.0:
		var logs := float(cfg.trees.logs) * (float(cfg.trees.golden_mult) if bool(t.golden) else 1.0)
		var cap := pile_cap(s.levels)
		var added := minf(logs, cap - float(s.wood))
		s.wood = minf(cap, float(s.wood) + logs)
		t.hp = 0.0
		t.regrow = regrow_time(s.levels)
		s.stats.trees_felled += 1
		events.append({"type": "fall", "idx": i, "golden": bool(t.golden), "logs": logs, "wasted": logs - maxf(0.0, added)})


func _update_supplier() -> void:
	if not has_supplier(s.levels):
		return
	var cap := shelf_cap(s.levels)
	if float(s.ingredients) >= cap * float(cfg.ingredients.supplier_threshold):
		return
	var unit := ingredient_unit_cost(s.levels)
	var amount := minf(cap - float(s.ingredients), floor(float(s.coins) / unit))
	if amount >= 1.0:
		s.coins -= amount * unit
		s.ingredients += amount
		s.stats.supplier_used += 1
		events.append({"type": "supplier", "where": "shelf"})


func _update_truck() -> void:
	if not unlocked("truck"):
		return
	var tr: Dictionary = s.truck
	if tr.state == "bay":
		var surplus := float(s.wood) - float(s.wood_reserve)
		var cap := truck_cap(s.levels)
		var amt := minf(minf(surplus, float(cfg.truck.load_per_s) * dt), cap - float(tr.load))
		if amt > 0.0:
			s.wood -= amt
			tr.load = float(tr.load) + amt
		if float(tr.load) >= cap - 0.001:
			_truck_depart()
	else:
		tr.t = float(tr.t) - dt
		if float(tr.t) <= 0.0:
			_pay(float(tr.pay), "truck", "truck")
			tr.state = "bay"
			tr.load = 0.0
			s.stats.truck_trips += 1


func _truck_depart() -> void:
	var tr: Dictionary = s.truck
	tr.pay = float(tr.load) * wood_price()
	s.sold_recent = float(s.sold_recent) + float(tr.load)
	tr.state = "away"
	tr.t = float(cfg.truck.trip_s)
	events.append({"type": "truck_departs", "where": "truck"})


func _update_oven() -> void:
	var speed := 1.0
	if s.event.type == "power_cut" and float(s.event.left) > 0.0:
		speed = float(cfg.random_events.power_cut.cook_mult)
	var slots: Array = s.oven
	for i in slots.size():
		if float(slots[i]) >= 0.0:
			slots[i] = float(slots[i]) - dt * speed
			if float(slots[i]) <= 0.0:
				slots[i] = -1.0
				s.rack += 1
	var per := float(cfg.wood.per_dish)
	var cap := rack_cap(s.levels)
	for i in slots.size():
		if float(slots[i]) < 0.0 and float(s.wood) >= per and float(s.ingredients) >= 1.0 \
				and int(s.rack) + cooking_count() < cap:
			s.wood -= per
			s.ingredients -= 1.0
			slots[i] = cook_time(s.levels)


func _arrivals() -> void:
	var ch_n := int(s.chapter)
	for ch in CHANNELS:
		var n := rng.poisson(demand(ch) * dt)
		for k in n:
			var kind := 0
			if ch_n >= int(cfg.vip.from_chapter) and rng.randf01() < float(cfg.vip.chance):
				kind = 1
			elif ch == "dine" and ch_n >= int(cfg.critic.from_chapter) and rng.randf01() < float(cfg.critic.chance):
				kind = 2
			var q: Array = s[ch + "_q"]
			if q.size() >= int(cfg[ch].queue_limit):
				_lost(ch, kind, "balk")  # walks past: a visible lost sale
			else:
				q.append([int(s.tick), kind])


func _frac_left(ch: String, e: Array) -> float:
	var pm := patience_max(ch, int(e[1]))
	return clampf(1.0 - (float(int(s.tick) - int(e[0])) * dt) / pm, 0.0, 1.0)


func _renege(ch: String) -> void:
	var q: Array = s[ch + "_q"]
	var i := 0
	while i < q.size():
		if _frac_left(ch, q[i]) <= 0.0:
			var e: Array = q[i]
			q.remove_at(i)
			_lost(ch, int(e[1]), "renege")
		else:
			i += 1


func _update_dine() -> void:
	_renege("dine")
	var d: Dictionary = cfg.dine
	var q: Array = s.dine_q
	var self_serve := bool(chap().self_serve)
	for t in s.tables:
		if q.is_empty():
			break
		if t.st == "free":
			var e: Array = q.pop_front()
			var pm := patience_max("dine", int(e[1]))
			t.st = "waiting_food"
			t.kind = int(e[1])
			t.pmax = pm
			t.pat = pm * _frac_left("dine", e)
	for i in s.tables.size():
		var t: Dictionary = s.tables[i]
		match t.st:
			"waiting_food", "serving":
				t.pat = float(t.pat) - dt * float(d.seated_patience_rate)
				if t.st == "waiting_food":
					if self_serve and int(s.rack) > 0:
						s.rack -= 1
						t.st = "eating"
						t.t = float(d.eat_s)
					elif float(t.pat) <= 0.0:
						_lost("dine", int(t.kind), "renege")
						t.merge(_free_table(), true)
			"eating":
				t.t = float(t.t) - dt
				if float(t.t) <= 0.0:
					var frac := clampf(float(t.pat) / float(t.pmax), 0.0, 1.0)
					var p := price_for("dine", int(t.kind))
					_pay(p, "dishes", "table%d" % i)
					_pay(p * float(d.tip_max) * frac, "tips", "table%d" % i)
					_served("dine", int(t.kind), frac)
					t.st = "dirty"
					t.t = float(d.self_clean_s)
			"dirty":
				if self_serve:  # early venues: guests tidy up slowly
					t.t = float(t.t) - dt
					if float(t.t) <= 0.0:
						t.merge(_free_table(), true)
	# Waiters: serve ready food > clean table (spec 2.4)
	var ws := waiter_speed(s.levels)
	for w in s.waiters:
		if float(w.busy) > 0.0:
			w.busy = float(w.busy) - dt
			if float(w.busy) <= 0.0:
				_finish_table_task(str(w.task), int(w.idx))
		if float(w.busy) <= 0.0:
			var task := _pick_waiter_task()
			if not task.is_empty():
				w.task = task.task
				w.idx = task.idx
				w.busy = float(task.time) / ws


func _pick_waiter_task() -> Dictionary:
	var d: Dictionary = cfg.dine
	if int(s.rack) > 0:
		for i in s.tables.size():
			if s.tables[i].st == "waiting_food":
				s.rack -= 1
				s.tables[i].st = "serving"
				return {"task": "serve", "idx": i, "time": float(d.serve_s)}
	for i in s.tables.size():
		if s.tables[i].st == "dirty":
			s.tables[i].st = "cleaning"
			return {"task": "clean", "idx": i, "time": float(d.clean_s)}
	return {}


func _finish_table_task(task: String, i: int) -> void:
	if i < 0 or i >= s.tables.size():
		return
	var t: Dictionary = s.tables[i]
	if task == "serve" and t.st == "serving":
		t.st = "eating"
		t.t = float(cfg.dine.eat_s)
	elif task == "clean" and t.st == "cleaning":
		t.merge(_free_table(), true)


func _update_take() -> void:
	if not unlocked("take"):
		return
	_renege("take")
	var q: Array = s.take_q
	for c in s.cashiers:
		if float(c.busy) > 0.0:
			c.busy = float(c.busy) - dt
			if float(c.busy) <= 0.0:
				_pay(price_for("take", int(c.kind)), "dishes", "take")
				_served("take", int(c.kind), float(c.frac))
		if float(c.busy) <= 0.0 and not q.is_empty() and int(s.rack) > 0:
			var e: Array = q.pop_front()
			s.rack -= 1
			c.kind = int(e[1])
			c.frac = _frac_left("take", e)
			c.busy = float(cfg.take.serve_s)


## Drive-through: order window -> pickup window in series (spec 4.2).
func _update_drive() -> void:
	if not unlocked("drive"):
		return
	_renege("drive")
	var dc: Dictionary = cfg.drive
	var spd := dt_speed(s.levels)
	var pu: Dictionary = s.drive_pickup
	if not pu.is_empty():
		if not bool(pu.food):
			if int(s.rack) >= int(dc.dishes):
				s.rack -= int(dc.dishes)
				pu.food = true
		else:
			pu.t = float(pu.t) - dt
			if float(pu.t) <= 0.0:
				_pay(price_for("drive", int(pu.kind)) * float(dc.dishes), "dishes", "drive")
				_served("drive", int(pu.kind), float(pu.frac))
				s.drive_pickup = {}
	var od: Dictionary = s.drive_order
	if not od.is_empty():
		if float(od.t) > 0.0:
			od.t = float(od.t) - dt
		if float(od.t) <= 0.0 and s.drive_pickup.is_empty():
			s.drive_pickup = {"kind": od.kind, "frac": od.frac, "food": false, "t": float(dc.pickup_s) / maxf(spd, 0.01)}
			s.drive_order = {}
	if s.drive_order.is_empty() and not s.drive_q.is_empty() and spd > 0.0:
		var e: Array = s.drive_q.pop_front()
		s.drive_order = {"kind": int(e[1]), "frac": _frac_left("drive", e), "t": float(dc.order_s) / spd}


## Delivery: order board -> packers -> bikes; coins arrive when the bike returns.
func _update_delivery() -> void:
	if not unlocked("delivery"):
		return
	_renege("delivery")
	var dc: Dictionary = cfg.delivery
	var q: Array = s.delivery_q
	for p in s.packers:
		if float(p.busy) > 0.0:
			p.busy = float(p.busy) - dt
			if float(p.busy) <= 0.0:
				s.del_ready.append({"kind": int(p.kind), "frac": float(p.frac)})
		if float(p.busy) <= 0.0 and not q.is_empty() and int(s.rack) >= int(dc.dishes):
			var e: Array = q.pop_front()
			s.rack -= int(dc.dishes)
			p.kind = int(e[1])
			p.frac = _frac_left("delivery", e)
			p.busy = float(dc.pack_s)
	for b in s.bikes:
		if float(b.away) > 0.0:
			b.away = float(b.away) - dt
			if float(b.away) <= 0.0:
				_pay(float(b.pay), "dishes", "delivery")
				_served("delivery", int(b.kind), float(b.frac))
		if float(b.away) <= 0.0 and not s.del_ready.is_empty():
			var o: Dictionary = s.del_ready.pop_front()
			b.kind = int(o.kind)
			b.frac = float(o.frac)
			b.pay = price_for("delivery", int(o.kind)) * float(dc.dishes) - float(dc.fuel_cost)
			b.away = float(dc.trip_s)


func _update_player() -> void:
	var p: Dictionary = s.player
	if float(p.busy) <= 0.0:
		return
	p.busy = float(p.busy) - dt
	if float(p.busy) > 0.0:
		return
	match str(p.task):
		"clean", "serve":
			_finish_table_task(str(p.task), int(p.idx))
		"take":
			_pay(price_for("take", int(p.kind)), "dishes", "take")
			_served("take", int(p.kind), float(p.frac))
	p.task = ""


func _update_rush() -> void:
	var dp := daypart()
	var lost := float(s.stats.lost_balk) + float(s.stats.lost_renege)
	var r: Dictionary = s.rush
	if bool(dp.rush) and not bool(r.active):
		s.rush = {"active": true, "lost": lost, "served": float(s.stats.meals)}
	elif not bool(dp.rush) and bool(r.active):
		if lost == float(r.lost) and float(s.stats.meals) > float(r.served):
			s.stats.rush_clean += 1
			events.append({"type": "rush_ok", "where": "dine_q"})
		r.active = false


# ---------------------------------------------------------------- throughput model

## Spec 3.6, with units fixed: every stage is in dish-equivalents per second.
## R_sales = min(min(chop, cook), sum over channels of min(capacity, demand)).
## avg=true uses the average daypart (hint + offline); manual=true assumes the
## player helps with half their attention at 1.5x speed (live play only).
func rates(L = null, avg := true, manual := true) -> Dictionary:
	if L == null:
		L = s.levels
	var c := chap()
	var d: Dictionary = cfg.dine
	var logs_per_hp := float(cfg.trees.logs) / float(cfg.trees.hp)
	var wood_s := _l(L, "lumberjack") * lj_dps(L) * logs_per_hp
	var manual_wood := float(cfg.manual_tap_rate) * axe_damage(L) * logs_per_hp * 0.5 if manual else 0.0
	# Forest regrowth cap: trees x logs per regrow cycle (+ golden oak bonus).
	var golden_bonus := 1.0 + (float(cfg.trees.golden_mult) - 1.0) / float(cfg.trees.golden_every)
	var forest_cap := float(cfg.trees.count) * float(cfg.trees.logs) * golden_bonus / regrow_time(L)
	wood_s = minf(wood_s, forest_cap)
	var chop := minf(wood_s + manual_wood, forest_cap) / float(cfg.wood.per_dish)
	var cook := float(oven_slots(L)) / cook_time(L)
	var att := 0.5 * float(cfg.manual_speed)
	var ws := waiter_speed(L)
	var W := _l(L, "helper")
	var dine_cap := 0.0
	if bool(c.self_serve):
		var clean_t := float(d.clean_s) / ws if W > 0 else float(d.self_clean_s)
		dine_cap = float(tables_count(L)) / (float(d.eat_s) + clean_t)
	else:
		var work := float(d.serve_s) + float(d.clean_s)
		var table_cap := float(tables_count(L)) / (float(d.eat_s) + work / maxf(ws, 0.01))
		var staff_cap := W * ws / work if W > 0 else (att / work if manual else 0.0)
		dine_cap = minf(table_cap, staff_cap)
	var take_cap := 0.0
	if unlocked("take"):
		var C := _l(L, "cashier")
		take_cap = C / float(cfg.take.serve_s) if C > 0 else (att / float(cfg.take.serve_s) if manual else 0.0)
	var drive_cap := 0.0
	if channel_open("drive", L):
		drive_cap = dt_speed(L) / maxf(float(cfg.drive.order_s), float(cfg.drive.pickup_s))
	var del_cap := 0.0
	if channel_open("delivery", L):
		del_cap = minf(_l(L, "packers") / float(cfg.delivery.pack_s), _l(L, "bikes") / float(cfg.delivery.trip_s))
	var caps := {"dine": dine_cap, "take": take_cap, "drive": drive_cap, "delivery": del_cap}
	var lam := {}
	var dishes := {}
	var total := 0.0
	for ch in CHANNELS:
		lam[ch] = demand(ch, L, avg)
		dishes[ch] = minf(caps[ch], lam[ch]) * dishes_per_order(ch)
		total += dishes[ch]
	var supply := minf(chop, cook)
	var sales := minf(supply, total)
	var scale := sales / total if total > 0.0 else 0.0
	var income := 0.0
	for ch in CHANNELS:
		var dd: float = dishes[ch] * scale
		var p := price_for(ch, 0, L)
		income += dd * p
		if ch == "dine":
			income += dd * p * float(d.tip_max) * 0.6
		if ch == "delivery":
			income -= dd / dishes_per_order(ch) * float(cfg.delivery.fuel_cost)
	income -= sales * ingredient_unit_cost(L)
	income *= legacy_mult()
	var bn := "demand"
	if total <= 0.0:
		bn = "no customers"
	elif supply < total:
		bn = "wood (chopping)" if chop < cook else "cooking"
	else:
		var worst := 0.05
		for ch in CHANNELS:
			if lam[ch] > 0.0 and (lam[ch] - caps[ch]) / lam[ch] > worst:
				worst = (lam[ch] - caps[ch]) / lam[ch]
				bn = ch
	return {"chop": chop, "cook": cook, "wood_s": wood_s, "forest_cap": forest_cap, "caps": caps, "lam": lam, "dishes": dishes,
		"total": total, "supply": supply, "sales": sales, "income": income, "bottleneck": bn}


# ---------------------------------------------------------------- best next action

## Tiered: blockers > chapter gate > best upgrade by coins/hour per coin (4.6).
func best_action() -> Dictionary:
	var L: Dictionary = s.levels
	var c := chap()
	var cooking := cooking_count()
	if float(s.ingredients) < 1.0 and cooking == 0 and int(s.rack) == 0 and not has_supplier(L):
		return {"kind": "tap", "target": "shelf", "text": "Out of ingredients! Tap the shelf to buy a crate"}
	if float(s.wood) < float(cfg.wood.per_dish) and cooking == 0 and lv("lumberjack") == 0:
		return {"kind": "tap", "target": "forest", "text": "Out of wood! Tap trees to chop"}
	if lv("helper") == 0:
		for t in s.tables:
			if t.st == "waiting_food" and not bool(c.self_serve) and int(s.rack) > 0:
				return {"kind": "tap", "target": "tables", "text": "Tap waiting tables to serve them"}
			if t.st == "dirty" and (not bool(c.self_serve) or not s.dine_q.is_empty()):
				return {"kind": "tap", "target": "tables", "text": "Tap dirty tables to clean them"}
	if unlocked("take") and lv("cashier") == 0 and not s.take_q.is_empty() and int(s.rack) > 0:
		return {"kind": "tap", "target": "counter", "text": "Tap the counter to serve takeaway"}
	var g := gate()
	if g.can_move:
		return {"kind": "move", "text": "Venue ready! Tap to move to chapter %d" % (int(s.chapter) + 1)}
	if g.can_prestige:
		return {"kind": "prestige", "text": "Empire complete! Start a New Venture (Venue tab)"}

	# Gate quests that need a purchase (e.g. "Hire the supplier") come next.
	for q in c.quests:
		if q.has("level") and lv(q.level) < int(q.target) and _upg.has(q.level):
			var qst := upgrade_state(q.level)
			if not qst.locked and not qst.maxed:
				return {"kind": "buy" if qst.affordable else "save", "id": q.level, "gain": 0.0,
					"cost": qst.cost, "bottleneck": "venue goal", "quest": true}

	var base := rates(L, true, true)
	var auto_share := float(cfg.hint.automation_share)
	scores.clear()
	var vals := {}
	for u in cfg.upgrades:
		var id: String = u.id
		var st := upgrade_state(id)
		if st.locked or st.maxed:
			continue
		var L2 := L.duplicate()
		L2[id] = int(st.level) + 1
		var r2 := rates(L2, true, true)
		var gain: float = r2.income - base.income
		# First hire of a role frees the player's hands: value that time.
		if int(st.level) == 0 and id in ["lumberjack", "helper", "cashier", "supplier"]:
			gain = maxf(gain, base.income * auto_share)
		# Tie-break when two stations are equally slow: reward local capacity.
		var local := 0.0
		for k in ["chop", "cook"]:
			local += maxf(0.0, r2[k] - base[k]) / maxf(base[k], 0.000001)
		for ch in CHANNELS:
			local += maxf(0.0, r2.caps[ch] - base.caps[ch]) / maxf(base.caps[ch], 0.000001)
		local = minf(local, 2.0)
		scores[id] = gain * 3600.0
		vals[id] = (gain * 3600.0 + local * maxf(base.income, 0.01) * 60.0) / float(st.cost)
	# 2-step lookahead for upgrades worth nothing alone (e.g. packer needs a
	# bike): value the pair, split over both costs.
	var pair_with := {}
	for id in vals.keys():
		if scores[id] > 1.0:
			continue
		for id2 in vals.keys():
			if id2 == id:
				continue
			var L3 := L.duplicate()
			L3[id] = lv(id) + 1
			L3[id2] = lv(id2) + 1
			var syn: float = (rates(L3, true, true).income - base.income) * 3600.0 - maxf(0.0, scores[id2])
			if syn <= 1.0:
				continue
			var v := syn / (upgrade_cost(id) + upgrade_cost(id2))
			if v > vals[id]:
				vals[id] = v
				scores[id] = syn
				pair_with[id] = id2
	if vals.is_empty():
		return {"kind": "none", "text": "Everything here is maxed. Work on the venue goals."}
	var best_id := ""
	for id in vals:
		if best_id == "" or vals[id] > vals[best_id]:
			best_id = id
	var pick := best_id
	if not upgrade_state(best_id).affordable:
		# Don't make the player wait if a nearly-as-good upgrade is affordable.
		var alt := ""
		for id in vals:
			if upgrade_state(id).affordable and vals[id] >= vals[best_id] * float(cfg.hint.affordable_fallback):
				if alt == "" or vals[id] > vals[alt]:
					alt = id
		if alt != "":
			pick = alt
	var pst := upgrade_state(pick)
	return {"kind": "buy" if pst.affordable else "save", "id": pick, "gain": scores.get(pick, 0.0),
		"cost": pst.cost, "bottleneck": base.bottleneck, "pair": pair_with.get(pick, "")}


# ---------------------------------------------------------------- offline

## Coarse-step fast-forward (60 s steps) with stock tracking, so an empty wood
## pile or shelf stops income offline just like online. Same rate model as the
## hint, no manual work, capped and at offline efficiency (spec 5.5, 8.3).
## Returns coins to grant; the caller decides (collect / watch ad to double).
func offline_fast_forward(seconds: float) -> Dictionary:
	var L: Dictionary = s.levels
	seconds = maxf(0.0, seconds)  # clock rolled back: grant nothing
	var t := minf(seconds, offline_cap_s(L))
	var r := rates(L, true, false)
	var per := float(cfg.wood.per_dish)
	var supplier := has_supplier(L)
	var net_per_dish: float = r.income / r.sales if r.sales > 0.0 else 0.0
	var wood := float(s.wood)
	var ing := float(s.ingredients)
	var dishes := 0.0
	var remaining := t
	while remaining > 0.0:
		var h := minf(float(cfg.offline.step_s), remaining)
		wood = minf(pile_cap(L), wood + r.wood_s * h)
		var can: float = minf(r.cook * h, r.total * h)
		can = minf(can, wood / per)
		if not supplier:
			can = minf(can, ing)
		wood -= can * per
		if not supplier:
			ing -= can
		dishes += can
		remaining -= h
	var coins := dishes * net_per_dish * offline_eff(L)
	s.wood = wood
	s.ingredients = ing
	var timers := 0.0
	if s.truck.state == "away":
		timers += float(s.truck.pay) * legacy_mult()
		s.truck.state = "bay"
		s.truck.load = 0.0
		s.stats.truck_trips += 1
	for b in s.bikes:
		if float(b.away) > 0.0:
			timers += float(b.pay) * legacy_mult()
			b.away = 0.0
	if seconds >= regrow_time(L):
		for i in s.trees.size():
			if float(s.trees[i].hp) <= 0.0:
				s.trees[i] = _new_tree(false)
	# Customers who were waiting have gone home; nobody is mid-task.
	for ch in CHANNELS:
		s[ch + "_q"].clear()
	for i in s.tables.size():
		s.tables[i] = _free_table()
	for w in s.waiters:
		w.busy = 0.0
	s.player.busy = 0.0
	s.tick = int(s.tick) + int(seconds * float(cfg.tick_hz))
	return {"away": seconds, "counted": t, "dishes": dishes, "coins": coins, "timers": timers,
		"eff": offline_eff(L), "cap": offline_cap_s(L)}
