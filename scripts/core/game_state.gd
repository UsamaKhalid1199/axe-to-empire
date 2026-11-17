extends Node
## Persistent game state + economy rules. No scene nodes; the world reads and writes through here.

signal coins_changed(value: int)
signal state_changed            # anything upgrade/build/crew related
signal rating_changed(value: float)
signal toast(text: String)
signal jobs_changed

const SAVE_PATH := "user://save_v2.json"
const BACKUP_PATH := "user://save_v2.bak"

var cfg: Dictionary = {}           # active chapter's config (base config scaled + themed)
var base_cfg: Dictionary = {}
var chapters: Array = []
var growth: Array = []

# empire: one venue per chapter. The active venue's state lives in the fields below;
# the others are stashed in `venues` and keep earning in the background.
var venue := 0                      # active chapter index
var unlocked := 1                   # chapters reachable
var venues: Array = []              # stashed per-venue state (index = chapter)
var vserved := 0                    # guests served at the active venue
var prestige := 0                   # completed empires: +50% income each
var _empire_acc := 0.0
var _rates: Array = []              # cached coins/s per venue
var _rates_t := 0.0
const VENUE_EFFICIENCY := 0.5       # background venues earn half of their crew rate

var coins: int = 0
var served: int = 0
var built: Dictionary = {}          # build id -> true
var pad_paid: Dictionary = {}       # build id -> coins paid so far
var levels := {"tool": 0, "bag": 0, "boots": 0, "fire": 0, "menu": 0}
var crew := {"lumberjack": 0, "waiter": 0, "cook": 0}
var rating_hist: Array = []         # last 40 scores (1..5)
var stats := {"trees": 0, "logs": 0, "served": 0, "earned": 0, "sold": 0, "play_s": 0.0}
var chapter_done := false
var ftue := 0
var woodpile := 0
var rack := 0
var counter_coins := 0
var sp: Dictionary = {}             # the active venue's signature-station state (fuel, raft, van, ...)
var mute := false
## Graphics: 0 smooth, 1 balanced, 2 beautiful. quality_auto lets the game drop a level when fps stays low.
var quality := 1
var quality_auto := true
const QUALITY_NAMES := ["Smooth", "Balanced", "Beautiful"]
const QUALITY_SCALE := [0.6, 0.75, 0.9]
var saving_enabled := true

# daily jobs
var jobs_day := ""
var jobs: Array = []                # [{id,text,goal,prog,reward,claimed}]
var streak := 0
var streak_last_day := ""
var chest_claimed := false

var last_save_unix := 0
var offline_reward := 0             # computed on load, shown by UI
var offline_seconds := 0
var _save_timer := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var f := FileAccess.open("res://data/game.json", FileAccess.READ)
	base_cfg = JSON.parse_string(f.get_as_text())
	var cf := FileAccess.open("res://data/chapters.json", FileAccess.READ)
	var cd: Dictionary = JSON.parse_string(cf.get_as_text())
	chapters = cd.chapters
	growth = cd.growth
	cfg = chapter_cfg(0)
	load_game()
	cfg = chapter_cfg(venue)
	refresh_jobs()


func _process(delta: float) -> void:
	stats.play_s += delta
	_empire_tick(delta)
	_save_timer += delta
	if _save_timer > 8.0:
		_save_timer = 0.0
		save_game()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST \
			or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		save_game()


# ---------------------------------------------------------------- chapters / empire

func chapter() -> Dictionary:
	return chapters[venue]


func chapter_mult(k: int) -> float:
	return float(growth[clampi(k, 0, growth.size() - 1)])


## Base config scaled by the chapter's growth factor and renamed to its theme.
func chapter_cfg(k: int) -> Dictionary:
	var ch: Dictionary = chapters[k]
	var m := chapter_mult(k)
	var c: Dictionary = base_cfg.duplicate(true)
	for b in c.builds:
		b.cost = int(round(float(b.cost) * m))
		if ch.builds.has(b.id):
			b.name = ch.builds[b.id]
		if b.id == "gate":
			b.name = chapters[k + 1].name if k + 1 < chapters.size() else "New Empire"
	for i in c.fire.size():
		c.fire[i].cost = int(round(float(c.fire[i].cost) * m))
	for i in c.menu.size():
		c.menu[i].cost = int(round(float(c.menu[i].cost) * m))
		c.menu[i].price = int(round(float(c.menu[i].price) * m))
		c.menu[i].name = ch.menu[i]
	for role in c.crew:
		var costs: Array = c.crew[role].costs
		for i in costs.size():
			costs[i] = int(round(float(costs[i]) * m))
	# the chapter's signature station is one more build pad, and the gate needs it
	var spc: Dictionary = ch.get("special", {})
	if not spc.is_empty():
		var gi: int = c.builds.size() - 1
		c.builds.insert(gi, {"id": "special", "name": spc.name, "cost": int(round(float(spc.cost) * m)),
			"requires": spc.requires, "desc": spc.desc})
		c.builds[gi + 1].requires = c.builds[gi + 1].requires + ["special"]
	c.log_sell_price = int(round(float(c.log_sell_price) * m))
	c.gate.coins = int(round(float(c.gate.coins) * m))
	c.gate.served = int(c.gate.served) + 40 * k
	return c


const VENUE_KEYS := ["built", "pad_paid", "crew", "woodpile", "rack", "counter_coins", "rating_hist", "vserved", "chapter_done", "sp"]


func _snapshot() -> Dictionary:
	return {"built": built.duplicate(true), "pad_paid": pad_paid.duplicate(true), "crew": crew.duplicate(true),
		"woodpile": woodpile, "rack": rack, "counter_coins": counter_coins, "rating_hist": rating_hist.duplicate(),
		"vserved": vserved, "chapter_done": chapter_done, "fire": levels.fire, "menu": levels.menu, "sp": sp.duplicate(true)}


func _stash() -> void:
	while venues.size() <= venue:
		venues.append({})
	venues[venue] = _snapshot()


func _unstash(k: int) -> void:
	var d: Dictionary = venues[k] if k < venues.size() else {}
	built = d.get("built", {}).duplicate(true)
	pad_paid = {}
	for key in d.get("pad_paid", {}):
		pad_paid[key] = int(d.pad_paid[key])
	crew = {"lumberjack": 0, "waiter": 0, "cook": 0}
	for key in d.get("crew", {}):
		crew[key] = int(d.crew[key])
	woodpile = int(d.get("woodpile", 0))
	rack = int(d.get("rack", 0))
	counter_coins = int(d.get("counter_coins", 0))
	rating_hist = d.get("rating_hist", []).duplicate()
	vserved = int(d.get("vserved", 0))
	chapter_done = bool(d.get("chapter_done", false))
	levels.fire = int(d.get("fire", 0))
	levels.menu = int(d.get("menu", 0))
	sp = d.get("sp", {}).duplicate(true)


## Switch the active venue. The scene must be rebuilt afterwards (main.gd does it).
func travel(k: int) -> bool:
	if k == venue or k < 0 or k >= unlocked:
		return false
	_stash()
	var first: bool = k >= venues.size() or venues[k].is_empty()
	venue = k
	_unstash(k)
	cfg = chapter_cfg(k)
	if first and k > 0:
		_head_start()
	_rates_t = 0.0
	save_game()
	return true


## First arrival at a new venue: the crew you brought sets up the cooker, one lumberjack comes along
## and there is a little firewood, so a new chapter starts from your empire, not from nothing.
func _head_start() -> void:
	built["campfire"] = true
	crew.lumberjack = maxi(crew.lumberjack, 1)
	woodpile = maxi(woodpile, 12)
	head_start_note = true


var head_start_note := false


## The active chapter's signature station type ("" for the first chapter).
func special_type(k := -1) -> String:
	var ch: Dictionary = chapters[venue if k < 0 else k]
	return String(ch.get("special", {}).get("type", ""))


func special_def(k := -1) -> Dictionary:
	return chapters[venue if k < 0 else k].get("special", {})


func is_last_chapter() -> bool:
	return venue >= chapters.size() - 1


## Coins/s a venue's crew makes on its own (state = stashed dict, k = chapter).
func venue_rate(k: int) -> float:
	if k == venue:
		return passive_rate()
	if k >= venues.size() or venues[k].is_empty():
		return 0.0
	var d: Dictionary = venues[k]
	var cc := chapter_cfg(k)
	var cr: Dictionary = d.get("crew", {})
	var b: Dictionary = d.get("built", {})
	return _rate(int(cr.get("lumberjack", 0)), int(cr.get("waiter", 0)), int(cr.get("cook", 0)), b,
		int(d.get("fire", 0)), int(d.get("menu", 0)), cc) * _special_mult(k, b)


## Crew income bonus once the chapter's signature station is built.
func _special_mult(k: int, b: Dictionary) -> float:
	if not b.has("special"):
		return 1.0
	return 1.0 + float(special_def(k).get("bonus", 0.0))


## Background income from every venue except the active one (coins/s, after efficiency).
func empire_rate() -> float:
	if _rates.size() != unlocked:
		_refresh_rates()
	var sum := 0.0
	for k in _rates.size():
		if k != venue:
			sum += _rates[k]
	return sum * VENUE_EFFICIENCY


func _refresh_rates() -> void:
	_rates.clear()
	for k in unlocked:
		_rates.append(venue_rate(k) if k != venue else 0.0)


func _empire_tick(delta: float) -> void:
	_rates_t -= delta
	if _rates_t <= 0.0:
		_rates_t = 3.0
		_refresh_rates()
	var r := empire_rate()
	if r <= 0.0:
		return
	_empire_acc += r * delta
	if _empire_acc >= 1.0:
		var n := int(_empire_acc)
		_empire_acc -= n
		add_coins(n)


func income_mult() -> float:
	return 1.0 + 0.5 * prestige


## After the final chapter: start a fresh empire with a permanent income bonus.
func start_new_empire() -> void:
	if not (is_last_chapter() and chapter_done):
		return
	prestige += 1
	venues = []
	venue = 0
	unlocked = 1
	coins = 0
	levels = {"tool": 0, "bag": 0, "boots": 0, "fire": 0, "menu": 0}
	_unstash(0)
	cfg = chapter_cfg(0)
	_rates.clear()
	save_game()


# ---------------------------------------------------------------- economy

func add_coins(n: int, count_as_earned := true) -> void:
	if n <= 0:
		return
	coins += n
	if count_as_earned:
		stats.earned += n
		job_progress("earn", n)
	coins_changed.emit(coins)


func spend(n: int) -> bool:
	if n > coins:
		return false
	coins -= n
	coins_changed.emit(coins)
	return true


func tool() -> Dictionary:
	return cfg.tools[levels.tool]


func bag_cap() -> int:
	return int(cfg.bag[levels.bag].cap)


func speed_mult() -> float:
	return float(cfg.boots[levels.boots].mult)


func cook_time() -> float:
	return float(cfg.fire[levels.fire].cook) / (1.0 + 0.3 * crew.cook)


func dish_price() -> int:
	return int(round(float(cfg.menu[levels.menu].price) * income_mult()))


func dish_name() -> String:
	return cfg.menu[levels.menu].name


func fires() -> int:
	return (1 if built.has("campfire") else 0) + (1 if built.has("fire_2") else 0)


func tables() -> int:
	return (2 if built.has("tables_1") else 0) + (2 if built.has("tables_2") else 0)


func rating() -> float:
	if rating_hist.is_empty():
		return 4.5
	var s := 0.0
	for r in rating_hist:
		s += r
	return s / rating_hist.size()


func add_rating(score: float) -> void:
	rating_hist.append(score)
	while rating_hist.size() > 40:
		rating_hist.pop_front()
	rating_changed.emit(rating())


## Upgrade tracks: tool, bag, boots, fire, menu. Returns the next level's dict or {} at max.
func next_upgrade(track: String) -> Dictionary:
	var arr: Array = cfg.tools if track == "tool" else cfg[track]
	var lv: int = levels[track]
	if lv + 1 >= arr.size():
		return {}
	return arr[lv + 1]


func buy_upgrade(track: String) -> bool:
	var nxt := next_upgrade(track)
	if nxt.is_empty() or not spend(int(nxt.cost)):
		return false
	levels[track] += 1
	state_changed.emit()
	save_game()
	return true


func crew_next_cost(role: String) -> int:
	var c: Dictionary = cfg.crew[role]
	if crew[role] >= int(c.max):
		return -1
	return int(c.costs[crew[role]])


func hire(role: String) -> bool:
	var cost := crew_next_cost(role)
	if cost < 0 or not spend(cost):
		return false
	crew[role] += 1
	state_changed.emit()
	save_game()
	return true


func build_def(id: String) -> Dictionary:
	for b in cfg.builds:
		if b.id == id:
			return b
	return {}


func build_available(id: String) -> bool:
	if built.has(id):
		return false
	for r in build_def(id).requires:
		if not built.has(r):
			return false
	return true


## Pays up to `amount` into a build pad. Returns coins actually moved.
func pay_pad(id: String, amount: int) -> int:
	var cost := int(build_def(id).cost)
	var left := cost - int(pad_paid.get(id, 0))
	var n: int = min(amount, left, coins)
	if n <= 0:
		return 0
	coins -= n
	pad_paid[id] = int(pad_paid.get(id, 0)) + n
	coins_changed.emit(coins)
	if int(pad_paid[id]) >= cost:
		complete_build(id)
	return n


func complete_build(id: String) -> void:
	built[id] = true
	pad_paid.erase(id)
	state_changed.emit()
	save_game()


func gate_status() -> Dictionary:
	var g: Dictionary = cfg.gate
	return {
		"coins": coins >= int(g.coins), "rating": rating() >= float(g.rating),
		"served": vserved >= int(g.served),
		"built": built.has("tables_2") and built.has("crew_hut") and (special_type() == "" or built.has("special")),
	}


func gate_ready() -> bool:
	var s := gate_status()
	return s.coins and s.rating and s.served and s.built


func open_next_venue() -> void:
	if not gate_ready():
		return
	spend(int(cfg.gate.coins))
	chapter_done = true
	built["gate"] = true
	if venue + 1 < chapters.size():
		unlocked = maxi(unlocked, venue + 2)
	_rates.clear()
	state_changed.emit()
	save_game()


## Sustained coins per second the crew can make without the player (min of the chain).
func passive_rate() -> float:
	return _rate(crew.lumberjack, crew.waiter, crew.cook, built, levels.fire, levels.menu, cfg) * _special_mult(venue, built)


func _rate(lj: int, waiters: int, cooks: int, b: Dictionary, fire_lv: int, menu_lv: int, cc: Dictionary) -> float:
	if lj == 0 or not b.has("campfire"):
		return 0.0
	var w: Dictionary = cc.worker
	# lumberjack cycle: chop carry logs + walk ~ 2 x 9 m
	var cycle := float(w.carry) * float(w.chop_interval) + 18.0 / float(w.speed) + 1.5
	var logs_s: float = lj * float(w.carry) / cycle
	var nf := (1 if b.has("campfire") else 0) + (1 if b.has("fire_2") else 0)
	var cook_s: float = nf / (float(cc.fire[fire_lv].cook) / (1.0 + 0.3 * cooks))
	var serve_s: float
	if waiters > 0:
		serve_s = waiters * float(w.carry) / (14.0 / float(w.speed) + 2.0)
	else:
		serve_s = 0.0
	var c: Dictionary = cc.customers
	var nt := (2 if b.has("tables_1") else 0) + (2 if b.has("tables_2") else 0)
	var demand_s: float = (1.0 + nt * float(c.per_table_bonus) + (nf - 1) * 0.3 + fire_lv * 0.14 + menu_lv * 0.1 + cooks * 0.12) / float(c.interval)
	var dishes_s: float = min(logs_s * float(cc.dishes_per_log), cook_s, serve_s, demand_s)
	if dishes_s <= 0.0:
		# no waiter: logs still sell at the truck via lumberjacks? No: they only feed the pile.
		return 0.0
	return dishes_s * float(cc.menu[menu_lv].price) * income_mult()


# ---------------------------------------------------------------- daily jobs

func _today() -> String:
	var d := Time.get_date_dict_from_system()
	return "%04d-%02d-%02d" % [d.year, d.month, d.day]


func _day_index() -> int:
	return int(Time.get_unix_time_from_system() / 86400.0)


func refresh_jobs() -> void:
	var today := _today()
	if jobs_day == today and jobs.size() == 3:
		return
	jobs_day = today
	chest_claimed = false
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(today)
	var pool: Array = cfg.jobs.duplicate()
	if not built.has("campfire"):
		pool = pool.filter(func(j): return j.id != "serve")
	jobs.clear()
	var days_played := mini(int(stats.play_s / 1800.0), 10)
	while jobs.size() < 3 and pool.size() > 0:
		var j: Dictionary = pool.pop_at(rng.randi_range(0, pool.size() - 1))
		var goal := int(j.base) + int(j.per_day) * days_played
		var goal_scaled := goal if j.id != "earn" else int(goal * chapter_mult(venue))
		var reward := int(round((60 + goal * 4) * float(j.reward_mult) * (1.0 + levels.menu * 0.4) * chapter_mult(venue) / 10.0) * 10)
		goal = goal_scaled
		jobs.append({"id": j.id, "text": String(j.text).replace("{n}", str(goal)), "goal": goal,
			"prog": 0, "reward": reward, "claimed": false})
	# streak: pause instead of reset if a day was missed (spec 7.2)
	jobs_changed.emit()


func job_progress(id: String, n := 1) -> void:
	var changed := false
	for j in jobs:
		if j.id == id and not j.claimed and j.prog < j.goal:
			j.prog = mini(j.prog + n, j.goal)
			changed = true
			if j.prog >= j.goal:
				toast.emit("Job done: " + j.text)
	if changed:
		jobs_changed.emit()


func claim_job(i: int) -> void:
	var j: Dictionary = jobs[i]
	if j.claimed or j.prog < j.goal:
		return
	j.claimed = true
	add_coins(int(j.reward), false)
	if jobs.all(func(x): return x.claimed):
		var today := _today()
		if streak_last_day != today:
			streak = (streak % 7) + 1
			streak_last_day = today
	jobs_changed.emit()
	save_game()


func jobs_claimable() -> int:
	var n := 0
	for j in jobs:
		if not j.claimed and j.prog >= j.goal:
			n += 1
	return n


func streak_reward() -> int:
	return int(cfg.streak_rewards[clampi(streak - 1, 0, 6)])


func claim_chest() -> void:
	if chest_claimed or not jobs.all(func(x): return x.claimed):
		return
	chest_claimed = true
	add_coins(streak_reward(), false)
	jobs_changed.emit()
	save_game()


# ---------------------------------------------------------------- save / load

func to_dict() -> Dictionary:
	return {
		"v": 2, "coins": coins, "served": served, "built": built, "pad_paid": pad_paid,
		"levels": levels, "crew": crew, "rating_hist": rating_hist, "stats": stats,
		"chapter_done": chapter_done, "ftue": ftue, "woodpile": woodpile, "rack": rack,
		"counter_coins": counter_coins, "jobs_day": jobs_day, "jobs": jobs, "streak": streak,
		"streak_last_day": streak_last_day, "chest_claimed": chest_claimed, "mute": mute, "quality": quality, "quality_auto": quality_auto,
		"sp": sp, "venue": venue, "unlocked": unlocked, "venues": _venues_for_save(), "vserved": vserved, "prestige": prestige,
		"t": int(Time.get_unix_time_from_system()),
	}


func _venues_for_save() -> Array:
	_stash()
	return venues


func save_game() -> void:
	if not saving_enabled:
		return
	var txt := JSON.stringify(to_dict())
	var tmp := SAVE_PATH + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(txt)
	f.close()
	var dir := DirAccess.open("user://")
	if FileAccess.file_exists(SAVE_PATH):
		dir.copy(SAVE_PATH, BACKUP_PATH)
	dir.rename(tmp, SAVE_PATH)
	last_save_unix = int(Time.get_unix_time_from_system())


func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	return d if d is Dictionary and d.get("v", 0) == 2 else {}


func load_game() -> void:
	var d := _read(SAVE_PATH)
	if d.is_empty():
		d = _read(BACKUP_PATH)
	if d.is_empty():
		return
	coins = int(d.coins)
	served = int(d.served)
	built = d.built
	pad_paid = d.pad_paid
	for k in d.levels:
		levels[k] = int(d.levels[k])
	for k in d.crew:
		crew[k] = int(d.crew[k])
	rating_hist = d.rating_hist
	for k in d.stats:
		stats[k] = float(d.stats[k]) if k == "play_s" else int(d.stats[k])
	chapter_done = d.chapter_done
	ftue = int(d.ftue)
	woodpile = int(d.woodpile)
	rack = int(d.rack)
	counter_coins = int(d.counter_coins)
	jobs_day = d.jobs_day
	jobs = d.jobs
	for j in jobs:
		j.goal = int(j.goal); j.prog = int(j.prog); j.reward = int(j.reward)
	streak = int(d.streak)
	streak_last_day = d.streak_last_day
	chest_claimed = d.chest_claimed
	mute = d.get("mute", false)
	quality = clampi(int(d.get("quality", 1)), 0, 2)
	quality_auto = bool(d.get("quality_auto", true))
	venue = int(d.get("venue", 0))
	prestige = int(d.get("prestige", 0))
	vserved = int(d.get("vserved", served))
	venues = d.get("venues", [])
	sp = d.get("sp", {})
	# saves from before the empire update: an opened gate unlocks chapter 2
	unlocked = int(d.get("unlocked", 2 if chapter_done else 1))
	if chapter_done:
		built["gate"] = true
	_compute_offline(int(d.t))


func _compute_offline(t_saved: int) -> void:
	var now := int(Time.get_unix_time_from_system())
	var away := now - t_saved
	var o: Dictionary = cfg.offline
	if away < int(o.min_away_s):        # also guards clock rollback (negative)
		return
	var capped: int = mini(away, int(float(o.cap_hours) * 3600.0))
	cfg = chapter_cfg(venue)
	var rate := passive_rate()
	for k in unlocked:
		if k != venue:
			rate += venue_rate(k) * VENUE_EFFICIENCY
	if rate <= 0.0:
		return
	offline_seconds = capped
	offline_reward = int(rate * capped * float(o.efficiency))


func claim_offline() -> void:
	if offline_reward > 0:
		add_coins(offline_reward, false)
	offline_reward = 0


func reset_all() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(BACKUP_PATH))
	get_tree().reload_current_scene.call_deferred()
	coins = 0; served = 0; built = {}; pad_paid = {}
	levels = {"tool": 0, "bag": 0, "boots": 0, "fire": 0, "menu": 0}
	crew = {"lumberjack": 0, "waiter": 0, "cook": 0}
	rating_hist = []; chapter_done = false; ftue = 0; woodpile = 0; rack = 0; counter_coins = 0; sp = {}
	venue = 0; unlocked = 1; venues = []; vserved = 0; prestige = 0; cfg = chapter_cfg(0)
	stats = {"trees": 0, "logs": 0, "served": 0, "earned": 0, "sold": 0, "play_s": 0.0}
	jobs_day = ""; refresh_jobs()
