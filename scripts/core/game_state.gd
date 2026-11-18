extends Node
## Persistent game state + economy rules. No scene nodes; the world reads and writes through here.

signal coins_changed(value: int)
signal state_changed            # anything upgrade/build/crew related
signal rating_changed(value: float)
signal toast(text: String)
signal jobs_changed
signal story(beats: Array)          # story cards to show (portrait + line)
signal task_changed
signal offline_ready                # away earnings computed after a resume

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
var levels := {"tool": 0, "bag": 0, "boots": 0, "fire": 0, "menu": 0, "dining": 0, "sign": 0, "station": 0}
## "Pro" gear levels bought after a tool / backpack / boots track is maxed (priced per chapter).
var pro := {"tool": 0, "bag": 0, "boots": 0}
const PRO_MAX := 10
var crew := {"lumberjack": 0, "waiter": 0, "cook": 0}
var rating_hist: Array = []         # last 40 scores (1..5)
var stats := {"trees": 0, "logs": 0, "served": 0, "earned": 0, "sold": 0, "play_s": 0.0, "lost": 0, "walkouts": 0, "golden": 0, "bigdays": 0}
var chapter_done := false
var ftue := 0
var woodpile := 0
var rack := 0
var counter_coins := 0
var sp: Dictionary = {}             # the active venue's signature-station state (fuel, raft, van, ...)
## Per-venue long-term state (stashed with the venue): renovation in progress, Big Day, stars,
## story cards seen, task chain position.
var reno: Dictionary = {}           # {"id": station, "end": unix} while a milestone level is being built
var bigday: Dictionary = {}         # {"won": bool, "clean": bool, "tries": int}
var seen: Dictionary = {}           # story beat key -> true
var task_i := 0
var task_base := 0                  # counter value when the current task started (serve / golden)
var golden_n := 0                   # golden trees felled at this venue
var walkouts := 0
var story_data: Dictionary = {}
var mute := false
## Player settings beyond sound on/off.
var settings := {"music": true, "sfx": true, "vibration": true, "show_fps": false, "story": true}
## Player profile: wardrobe (owned / equipped outfit pieces), name. See scripts/core/wardrobe.gd.
var profile := {"owned": ["shirt_orange", "hat_none", "hat_hardhat", "pants_dark"], "equipped": {"shirt": "shirt_orange", "hat": "hat_hardhat", "pants": "pants_dark"}}
signal profile_changed
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
var chest_day := ""                 # the day the streak chest was last opened

var last_save_unix := 0
var offline_reward := 0             # computed on load, shown by UI
var _cc_cache := {}                 # read-only chapter configs for background venues (stars, rates)


## Cached chapter config for read-only use; callers must not modify it.
func _cc(k: int) -> Dictionary:
	if not _cc_cache.has(k):
		_cc_cache[k] = chapter_cfg(k)
	return _cc_cache[k]
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
	story_data = JSON.parse_string(FileAccess.get_file_as_string("res://data/story.json"))
	cfg = chapter_cfg(0)
	load_game()
	cfg = chapter_cfg(venue)
	refresh_jobs()


func _process(delta: float) -> void:
	if _in_background:
		return
	stats.play_s += delta
	_empire_tick(delta)
	if Engine.time_scale != 1.0:
		_skew += delta - delta / Engine.time_scale
	_reno_t -= delta
	if _reno_t <= 0.0:
		_reno_t = 0.5
		_reno_tick()
	_save_timer += delta
	if _save_timer > 8.0:
		_save_timer = 0.0
		save_game()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST \
			or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		save_game()
	if not OS.has_feature("mobile"):
		return
	if what == NOTIFICATION_APPLICATION_PAUSED:
		if not _in_background:
			_in_background = true
			get_tree().paused = true
			AudioServer.set_bus_mute(0, true)
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		if _in_background:
			_in_background = false
			get_tree().paused = false
			AudioServer.set_bus_mute(0, mute)
			_compute_offline(last_save_unix)
			last_save_unix = int(Time.get_unix_time_from_system())
			_reno_tick()
			refresh_jobs()                  # a new day may have started while the app was in the background
			if offline_reward > 0:
				offline_ready.emit()


## Phone locked / app in the background: the game truly stops (no ticking, no sound).
## On return the away payout is computed once from the time we were gone.
var _in_background := false
var _reno_t := 0.0
var _skew := 0.0


## Unix time that also follows Engine.time_scale (only differs from the wall clock in sped-up tests).
func now() -> int:
	return int(Time.get_unix_time_from_system() + _skew)


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
	for key in ch.get("crowd", {}):
		c.customers[key] = ch.crowd[key]
	if not c.customers.has("order_bonus"):
		c.customers["order_bonus"] = 0
	for key in c.stations:
		if c.stations[key] is Dictionary and c.stations[key].has("c0"):
			c.stations[key].c0 = float(c.stations[key].c0) * m
	c.gate.coins = int(round(float(c.gate.coins) * m))
	c.gate.served = int(c.gate.served) + 40 * k
	return c


const VENUE_KEYS := ["built", "pad_paid", "crew", "woodpile", "rack", "counter_coins", "rating_hist", "vserved", "chapter_done", "sp",
	"reno", "bigday", "seen", "task_i", "task_base", "golden_n", "walkouts"]
## Per-venue station levels (kitchen = "fire"). Tools, backpack and boots belong to the player.
const STATIONS := ["fire", "menu", "dining", "sign", "station"]
const STATION_CFG := {"fire": "kitchen", "menu": "menu", "dining": "dining", "sign": "sign", "station": "station"}


func _snapshot() -> Dictionary:
	return {"built": built.duplicate(true), "pad_paid": pad_paid.duplicate(true), "crew": crew.duplicate(true),
		"woodpile": woodpile, "rack": rack, "counter_coins": counter_coins, "rating_hist": rating_hist.duplicate(),
		"vserved": vserved, "chapter_done": chapter_done, "fire": levels.fire, "menu": levels.menu,
		"dining": levels.dining, "sign": levels.sign, "station": levels.station, "sp": sp.duplicate(true),
		"reno": reno.duplicate(), "bigday": bigday.duplicate(), "seen": seen.duplicate(), "task_i": task_i,
		"task_base": task_base, "golden_n": golden_n, "walkouts": walkouts}


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
	for key in STATIONS:
		levels[key] = int(d.get(key, 0))
	sp = d.get("sp", {}).duplicate(true)
	reno = d.get("reno", {}).duplicate()
	bigday = d.get("bigday", {}).duplicate()
	if chapter_done and not bigday.get("won", false):
		bigday["won"] = true          # finished before Big Days existed
	seen = d.get("seen", {}).duplicate()
	task_i = int(d.get("task_i", 0))
	task_base = int(d.get("task_base", 0))
	golden_n = int(d.get("golden_n", 0))
	walkouts = int(d.get("walkouts", 0))


## Switch the active venue. The scene must be rebuilt afterwards (main.gd does it).
func travel(k: int) -> bool:
	if k == venue or k < 0 or k >= unlocked:
		return false
	_stash()
	var first: bool = k >= venues.size() or venues[k].is_empty()
	_rescale_jobs(chapter_mult(venue), chapter_mult(k))
	venue = k
	_unstash(k)
	cfg = chapter_cfg(k)
	if first and k > 0:
		_head_start()
	_rates_t = 0.0
	save_game()
	return true


## Daily jobs were rolled for one chapter's prices; keep them fair when the scale changes.
func _rescale_jobs(m_old: float, m_new: float) -> void:
	var f := m_new / maxf(0.001, m_old)
	if absf(f - 1.0) < 0.001:
		return
	for j in jobs:
		j.reward = maxi(10, int(round(float(j.reward) * f / 10.0)) * 10)
		if j.id == "earn" and not j.claimed:
			var old_goal := int(j.goal)
			j.goal = maxi(1, int(round(float(j.goal) * f)))
			j.prog = mini(int(j.prog), int(j.goal))
			j.text = String(j.text).replace(str(old_goal), str(j.goal))
	jobs_changed.emit()


## First arrival at a new venue: the crew you brought sets up the cooker, one lumberjack comes along
## and there is a little firewood, so a new chapter starts from your empire, not from nothing.
func _head_start() -> void:
	built["campfire"] = true
	crew.lumberjack = maxi(crew.lumberjack, 1)
	woodpile = maxi(woodpile, 12)
	head_start_note = true


var head_start_note := false
var refund_note := 0                # cash returned to an old save (shown once)


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
	var cc := _cc(k)
	var cr: Dictionary = d.get("crew", {})
	var b: Dictionary = d.get("built", {})
	var lv := {}
	for key in STATIONS:
		lv[key] = int(d.get(key, 0))
	return _rate(int(cr.get("lumberjack", 0)), int(cr.get("waiter", 0)), int(cr.get("cook", 0)), b, lv, cc) \
		* _special_mult(k, b, lv.station) * star_mult(k)


## Crew income bonus once the chapter's signature station is built (grows with its level).
func _special_mult(k: int, b: Dictionary, st_lv := -1) -> float:
	if not b.has("special"):
		return 1.0
	if st_lv < 0:
		st_lv = levels.station
	return 1.0 + float(special_def(k).get("bonus", 0.0)) * (1.0 + 0.06 * st_lv)


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
	levels = {"tool": 0, "bag": 0, "boots": 0, "fire": 0, "menu": 0, "dining": 0, "sign": 0, "station": 0}
	pro = {"tool": 0, "bag": 0, "boots": 0}
	_unstash(0)
	_cc_cache.clear()
	cfg = chapter_cfg(0)
	jobs_day = ""
	refresh_jobs()
	_rates.clear()
	refresh_stars()
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
	var t: Dictionary = cfg.tools[levels.tool]
	if int(pro.tool) > 0:
		t = t.duplicate()
		t["interval"] = float(t.interval) / (1.0 + 0.1 * int(pro.tool))   # Pro: +10% chop speed per level
	return t


func bag_cap() -> int:
	return int(cfg.bag[levels.bag].cap) + 6 * int(pro.bag)


func speed_mult() -> float:
	return float(cfg.boots[levels.boots].mult) + 0.04 * int(pro.boots)


## Price of the next Pro level: grows per level and with the chapter you're in.
func pro_cost(track: String) -> int:
	var arr: Array = cfg.tools if track == "tool" else cfg[track]
	var last := float(arr[arr.size() - 1].cost)
	return int(round(last * pow(1.5, int(pro[track]) + 1) * chapter_mult(venue) / 10.0)) * 10


func cook_time() -> float:
	return kitchen_cook(cfg, levels.fire) / (1.0 + 0.3 * crew.cook)


## Station formulas (shared by the live venue and background-rate estimates).
static func kitchen_cook(cc: Dictionary, lv: int) -> float:
	return float(cc.fire[0].cook) * pow(0.95, lv)


static func menu_price(cc: Dictionary, lv: int) -> float:
	return float(cc.menu[0].price) * (1.0 + 0.08 * lv) * pow(1.2, lv / 5)


func dish_price() -> int:
	return int(round(menu_price(cfg, levels.menu) * sign_price() * income_mult() * star_mult(venue)))


## Recipe names step up as the menu grows (levels 7, 13, 19).
func dish_name() -> String:
	var i := 0
	for th in [7, 13, 19]:
		if levels.menu >= th:
			i += 1
	return cfg.menu[mini(i, cfg.menu.size() - 1)].name


func dining_patience() -> float:
	return 1.0 + 0.03 * levels.dining


func seated_tip() -> float:
	return float(cfg.customers.seated_tip) + 0.03 * levels.dining


func sign_demand() -> float:
	return 1.0 + 0.04 * levels.sign


## A famous place charges more: the signboard also adds +2% to every dish per level.
func sign_price(lv := -1) -> float:
	return 1.0 + 0.02 * (levels.sign if lv < 0 else lv)


# ---------------------------------------------------------------- station levels + renovations

## Task data names stations by their config id ("kitchen"); levels use "fire".
func station_key(id: String) -> String:
	var k = STATION_CFG.find_key(id)
	return String(k) if k != null else id


func station_def(key: String) -> Dictionary:
	var d: Dictionary = cfg.stations[STATION_CFG[key]]
	if key == "station" and special_type() != "":
		d = d.duplicate()
		d["name"] = String(special_def().get("name", d.name))   # one name everywhere: "Drive-thru window", ...
	return d


func station_max() -> int:
	return int(cfg.stations.max)


## Real seconds a milestone level takes to build (0 for instant levels).
func reno_seconds(to_lv: int) -> int:
	return int(cfg.stations.milestones.get(str(to_lv), 0))


func station_cost(key: String) -> int:
	var d := station_def(key)
	return int(round(float(d.c0) * pow(float(d.g), levels[key])))


func station_locked(key: String) -> String:
	if key == "station" and not built.has("special"):
		return "Build the " + String(special_def().get("name", "station")).to_lower() + " first" if special_type() != "" else "No signature station here"
	if not built.has("campfire"):
		return "Build the " + String(build_def("campfire").name).to_lower() + " first"
	if levels[key] >= station_max() - 1:
		return "MAX"
	if not reno.is_empty():
		return "Renovating" if reno.id == key else "Builders busy"
	return ""


## Buys the next level. Milestone levels start a timed renovation instead of applying at once.
func station_upgrade(key: String) -> bool:
	if station_locked(key) != "":
		return false
	var to := int(levels[key]) + 1          # stored index; the level shown to players is index + 1
	if not spend(station_cost(key)):
		return false
	var secs := reno_seconds(to + 1)
	if secs > 0:
		reno = {"id": key, "end": now() + secs, "to": to}
		fire_story("renovation")
	else:
		levels[key] = to
	job_progress("upgrade")
	state_changed.emit()
	task_changed.emit()
	save_game()
	return true


func reno_left() -> int:
	if reno.is_empty():
		return 0
	return maxi(0, int(reno.end) - now())


## Cash to finish a renovation right now (shrinks as it nears completion).
func reno_rush_cost() -> int:
	if reno.is_empty():
		return 0
	return maxi(1, int(round(float(station_cost(reno.id)) * 0.6 * float(reno_left()) / maxf(1.0, float(reno_seconds(int(reno.to) + 1))))))


func reno_rush() -> bool:
	if reno.is_empty() or not spend(reno_rush_cost()):
		return false
	reno.end = 0
	_reno_tick()
	return true


func _reno_tick() -> void:
	if reno.is_empty() or reno_left() > 0:
		return
	var key: String = reno.id
	levels[key] = int(reno.to)
	reno = {}
	toast.emit("%s reached level %d!" % [String(station_def(key).name), levels[key] + 1])
	state_changed.emit()
	task_changed.emit()
	save_game()


# ---------------------------------------------------------------- stars (per venue)

## ★1 Big Day won · ★2 4.5★ held after serving twice the gate's guests · ★3 every station 15+ and a clean Big Day.
func stars(k := -1) -> Array:
	if k < 0 or k == venue:
		return _stars_of(bigday, levels, vserved, rating(), cfg)
	if k >= venues.size() or venues[k].is_empty():
		return [false, false, false]
	var d: Dictionary = venues[k]
	var lv := {}
	for key in STATIONS:
		lv[key] = int(d.get(key, 0))
	var rh: Array = d.get("rating_hist", [])
	var r := 4.5
	if not rh.is_empty():
		r = 0.0
		for x in rh:
			r += float(x)
		r /= rh.size()
	return _stars_of(d.get("bigday", {}), lv, int(d.get("vserved", 0)), r, _cc(k), special_type(k) != "")


func _stars_of(bd: Dictionary, lv: Dictionary, served_n: int, r: float, cc: Dictionary, has_special := special_type() != "") -> Array:
	var s1: bool = bd.get("won", false)
	var s2: bool = bd.get("star2", false) or (s1 and served_n >= int(cc.gate.served) * 2 and r >= 4.5)
	var all15 := true
	for key in STATIONS:
		if key == "station" and not has_special:
			continue
		if int(lv.get(key, 0)) < 14:          # level 15 shown = index 14
			all15 = false
	var s3: bool = s1 and bd.get("clean", false) and all15
	return [s1, s2, s3]


func star_count(k := -1) -> int:
	return stars(k).count(true)


func total_stars() -> int:
	var n := 0
	for k in unlocked:
		n += star_count(k)
	return n


## Every star anywhere: +4% income everywhere.
func star_mult(_k := -1) -> float:
	return 1.0 + 0.04 * _star_cache


var _star_cache := 0


func refresh_stars() -> void:
	if bigday.get("won", false) and not bigday.get("star2", false) and vserved >= int(cfg.gate.served) * 2 and rating() >= 4.5:
		bigday["star2"] = true
		toast.emit("★ New star: 4.5★ rating held!")
	var n := 0
	for k in unlocked:
		n += star_count(k)
	_star_cache = n


# ---------------------------------------------------------------- Big Day

func big_day_def() -> Dictionary:
	return chapter().get("big_day", {})


## The Big Day opens once the venue is fully built (the gate's build checklist).
func big_day_ready() -> bool:
	return gate_status().built and not bigday.get("won", false)


## After a win with walkouts the Big Day can be replayed for the clean-run third star.
func big_day_replayable() -> bool:
	return gate_status().built and not bigday.get("clean", false)


func big_day_result(won: bool, clean: bool) -> void:
	bigday["tries"] = int(bigday.get("tries", 0)) + 1
	if won:
		var first: bool = not bigday.get("won", false)
		bigday["won"] = true
		if clean:
			bigday["clean"] = true
		if first:
			fire_story("bigday_win")
	else:
		fire_story("bigday_fail", true)
	refresh_stars()
	state_changed.emit()
	task_changed.emit()
	save_game()


# ---------------------------------------------------------------- story cards

## Queues the beats for `on` (chapter + common) that haven't been shown at this venue.
func fire_story(on: String, repeat := false) -> void:
	if story_data.is_empty():
		return
	var out: Array = []
	var ch: Dictionary = story_data.chapters.get(String(chapter().id), {})
	var i := 0
	for b in ch.get("beats", []) + story_data.common:
		i += 1
		if b.on != on:
			continue
		var key := "%s:%d" % [on, i]
		if seen.has(key) and not repeat:
			continue
		seen[key] = true
		out.append(b)
	if not out.is_empty():
		story.emit(out)


func character(id: String) -> Dictionary:
	return story_data.characters.get(id, {"name": id, "role": ""})


# ---------------------------------------------------------------- chapter task chain

func tasks() -> Array:
	if story_data.is_empty():
		return []
	return story_data.chapters.get(String(chapter().id), {}).get("tasks", [])


func current_task() -> Dictionary:
	var ts := tasks()
	return ts[task_i] if task_i < ts.size() else {}


func task_text(t: Dictionary) -> String:
	match String(t.t):
		"build": return "Build: " + String(build_def(t.id).get("name", t.id))
		"serve": return "Serve %d %s" % [int(t.n), String(chapter().guests)]
		"hire": return "Hire a " + String(cfg.crew[t.id].name).to_lower()
		"level": return "%s to level %d" % [String(station_def(station_key(t.id)).name), int(t.n)]
		"golden": return "Chop a golden tree"
		"bigday": return "Win the Big Day: " + String(big_day_def().get("name", ""))
	return ""


## [progress, goal]
func task_progress(t: Dictionary) -> Array:
	match String(t.t):
		"build": return [1 if built.has(t.id) else 0, 1]
		"serve": return [mini(vserved - task_base, int(t.n)), int(t.n)]
		"hire": return [mini(int(crew.get(t.id, 0)), 1), 1]
		"level": return [mini(int(levels[station_key(t.id)]) + 1, int(t.n)), int(t.n)]
		"golden": return [mini(golden_n - task_base, 1), 1]
		"bigday": return [1 if bigday.get("won", false) else 0, 1]
	return [0, 1]


func task_done() -> bool:
	var t := current_task()
	if t.is_empty():
		return false
	var p := task_progress(t)
	return p[0] >= p[1]


func task_reward(t: Dictionary) -> int:
	return int(float(t.get("r", 1)) * dish_price() * 2.0)


func claim_task() -> void:
	if not task_done():
		return
	add_coins(task_reward(current_task()), false)
	task_i += 1
	_task_start()
	task_changed.emit()
	save_game()


func _task_start() -> void:
	var t := current_task()
	if t.is_empty():
		return
	seen["task_init"] = true
	match String(t.t):
		"serve": task_base = vserved
		"golden": task_base = golden_n


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
		if int(pro[track]) >= PRO_MAX:
			return {}
		return {"pro": int(pro[track]) + 1, "cost": pro_cost(track)}
	return arr[lv + 1]


func buy_upgrade(track: String) -> bool:
	var nxt := next_upgrade(track)
	if nxt.is_empty() or not spend(int(nxt.cost)):
		return false
	if nxt.has("pro"):
		pro[track] = int(pro[track]) + 1
	else:
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
	if crew.values().reduce(func(a, b): return a + b, 0) == 1 or not seen.has("hired_any"):
		seen["hired_any"] = true
		fire_story("hired")
	state_changed.emit()
	task_changed.emit()
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
	if built.has(id) or id == "gate":
		return 0
	var cost := int(build_def(id).cost)
	var left := cost - int(pad_paid.get(id, 0))
	if left <= 0:                       # already paid in full (e.g. a cost changed in an update)
		complete_build(id)
		return 0
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
	fire_story("built:" + id)
	if big_day_ready():
		fire_story("bigday_ready")
	state_changed.emit()
	task_changed.emit()
	save_game()


func gate_status() -> Dictionary:
	var g: Dictionary = cfg.gate
	return {
		"coins": coins >= int(g.coins), "rating": rating() >= float(g.rating),
		"served": vserved >= int(g.served),
		"built": built.has("tables_2") and built.has("crew_hut") and (special_type() == "" or built.has("special")),
		"bigday": bigday.get("won", false),
	}


func gate_ready() -> bool:
	var s := gate_status()
	return s.coins and s.rating and s.served and s.built and s.bigday


func open_next_venue() -> void:
	if not gate_ready():
		return
	# the savings goal is a target, not a fee: your cash comes with you to the next place
	chapter_done = true
	built["gate"] = true
	if venue + 1 < chapters.size():
		unlocked = maxi(unlocked, venue + 2)
	_rates.clear()
	state_changed.emit()
	save_game()


## Sustained coins per second the crew can make without the player (min of the chain).
func passive_rate() -> float:
	return _rate(crew.lumberjack, crew.waiter, crew.cook, built, levels, cfg) * _special_mult(venue, built) * star_mult()


func _rate(lj: int, waiters: int, cooks: int, b: Dictionary, lv: Dictionary, cc: Dictionary) -> float:
	var fire_lv := int(lv.get("fire", 0))
	var menu_lv := int(lv.get("menu", 0))
	if lj == 0 or not b.has("campfire"):
		return 0.0
	var w: Dictionary = cc.worker
	# lumberjack cycle: chop carry logs + walk ~ 2 x 9 m
	var cycle := float(w.carry) * float(w.chop_interval) + 18.0 / float(w.speed) + 1.5
	var logs_s: float = lj * float(w.carry) / cycle
	var nf := (1 if b.has("campfire") else 0) + (1 if b.has("fire_2") else 0)
	var cook_s: float = nf / (kitchen_cook(cc, fire_lv) / (1.0 + 0.3 * cooks))
	var serve_s: float
	if waiters > 0:
		serve_s = waiters * float(w.get("waiter_carry", w.carry)) / (14.0 / float(w.speed) + 2.0)
	else:
		serve_s = 0.0
	var c: Dictionary = cc.customers
	var nt := (2 if b.has("tables_1") else 0) + (2 if b.has("tables_2") else 0)
	var demand_s: float = (1.0 + nt * float(c.per_table_bonus) + (nf - 1) * 0.2 + fire_lv * 0.14 + menu_lv * 0.10 + cooks * 0.12) 		* (1.0 + 0.04 * int(lv.get("sign", 0))) / float(c.interval)
	var dishes_s: float = min(logs_s * float(cc.dishes_per_log), cook_s, serve_s, demand_s)
	if dishes_s <= 0.0:
		# no waiter: logs still sell at the truck via lumberjacks? No: they only feed the pile.
		return 0.0
	var sign_lv := int(lv.get("sign", 0))
	var tips := 1.0 + (float(c.seated_tip) + 0.03 * int(lv.get("dining", 0))) * (0.5 if nt > 0 else 0.0)   # about half the guests sit and tip
	return dishes_s * menu_price(cc, menu_lv) * (1.0 + 0.02 * sign_lv) * tips * income_mult()


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
	chest_claimed = chest_day == today
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
		var units := goal / 10 if j.id == "earn" else goal      # "earn" goals are cash, not items
		var menu_k := minf(4.0, menu_price(cfg, levels.menu) / maxf(1.0, menu_price(cfg, 0)))
		var reward := int(round((60 + units * 4) * float(j.reward_mult) * menu_k * chapter_mult(venue) / 10.0) * 10)
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
	return int(round(float(cfg.streak_rewards[clampi(streak - 1, 0, 6)]) * chapter_mult(venue)))


func claim_chest() -> void:
	if chest_claimed or not jobs.all(func(x): return x.claimed):
		return
	chest_claimed = true
	chest_day = _today()
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
		"streak_last_day": streak_last_day, "chest_claimed": chest_claimed, "chest_day": chest_day, "mute": mute, "quality": quality, "quality_auto": quality_auto,
		"sp": sp, "venue": venue, "unlocked": unlocked, "venues": _venues_for_save(), "vserved": vserved, "prestige": prestige,
		"t": int(Time.get_unix_time_from_system()), "lv2": true, "settings": settings, "profile": profile, "pro": pro, "offline_reward": offline_reward, "gate_refund": true,
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
	chest_day = String(d.get("chest_day", jobs_day if chest_claimed else ""))
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
	for k in d.get("settings", {}):
		settings[k] = d.settings[k]
	var pd: Dictionary = d.get("pro", {})
	for k in pro:
		pro[k] = clampi(int(pd.get(k, 0)), 0, PRO_MAX)
	var pr: Dictionary = d.get("profile", {})
	if pr.has("owned") and pr.has("equipped"):
		profile = pr
	# saves from before station levels: old 4-step kitchen/menu map onto the 25-level scale
	if not d.get("lv2", false):
		levels.fire = [0, 4, 9, 14][clampi(int(levels.fire), 0, 3)]
		levels.menu = [0, 2, 4, 6][clampi(int(levels.menu), 0, 3)]
		for vd in venues:
			if vd is Dictionary and not vd.is_empty():
				if vd.get("chapter_done", false) and not vd.has("task_i"):
					vd["task_i"] = 13
				vd["fire"] = [0, 4, 9, 14][clampi(int(vd.get("fire", 0)), 0, 3)]
				vd["menu"] = [0, 2, 4, 6][clampi(int(vd.get("menu", 0)), 0, 3)]
	# per-venue long-term state lives in the venue snapshot
	if venue < venues.size() and venues[venue] is Dictionary and not venues[venue].is_empty():
		var vd2: Dictionary = venues[venue]
		vd2["fire"] = levels.fire
		vd2["menu"] = levels.menu
		_unstash(venue)
	if chapter_done:
		built["gate"] = true
		bigday["won"] = true
		if not d.get("lv2", false):
			task_i = maxi(task_i, tasks().size())
	for vd3 in venues:
		if vd3 is Dictionary and vd3.get("chapter_done", false):
			var b3: Dictionary = vd3.get("bigday", {})
			b3["won"] = true
			vd3["bigday"] = b3
	for key in STATIONS:
		levels[key] = clampi(int(levels[key]), 0, station_max() - 1)
	offline_reward = int(d.get("offline_reward", 0))
	_cc_cache.clear()
	# gates used to charge their savings goal; give that money back once to saves from before the fix
	if not d.get("gate_refund", false) and unlocked > 1:
		var back := 0
		var paid_gates := unlocked - 1 + (1 if chapter_done and venue == unlocked - 1 and venue == chapters.size() - 1 else 0)
		for k in paid_gates:
			back += int(chapter_cfg(k).gate.coins)
		coins += back
		refund_note = back
	cfg = chapter_cfg(venue)
	refresh_stars()
	_compute_offline(int(d.t))


func _compute_offline(t_saved: int) -> void:
	var now := int(Time.get_unix_time_from_system())
	var away := now - t_saved
	var o: Dictionary = cfg.offline
	if not bool(o.get("enabled", true)):   # you earn while you play: nothing piles up while the app is closed
		return
	if away < int(o.min_away_s):        # also guards clock rollback (negative)
		return
	var cap_h := minf(float(o.cap_max_h), float(o.cap_hours) + float(o.cap_per_venue_h) * (unlocked - 1))
	var capped: int = mini(away, int(cap_h * 3600.0))
	cfg = chapter_cfg(venue)
	var rate := passive_rate()
	for k in unlocked:
		if k != venue:
			rate += venue_rate(k) * VENUE_EFFICIENCY
	if rate <= 0.0:
		return
	offline_seconds = capped
	offline_reward += int(rate * capped * float(o.efficiency))


func offline_cap_hours() -> float:
	var o: Dictionary = cfg.offline
	return minf(float(o.cap_max_h), float(o.cap_hours) + float(o.cap_per_venue_h) * (unlocked - 1))


func claim_offline() -> void:
	if offline_reward > 0:
		add_coins(offline_reward, false)
	offline_reward = 0


func reset_all() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(BACKUP_PATH))
	get_tree().reload_current_scene.call_deferred()
	coins = 0; served = 0; built = {}; pad_paid = {}
	crew = {"lumberjack": 0, "waiter": 0, "cook": 0}
	rating_hist = []; chapter_done = false; ftue = 0; woodpile = 0; rack = 0; counter_coins = 0; sp = {}
	venue = 0; unlocked = 1; venues = []; vserved = 0; prestige = 0; cfg = chapter_cfg(0)
	stats = {"trees": 0, "logs": 0, "served": 0, "earned": 0, "sold": 0, "play_s": 0.0, "lost": 0, "walkouts": 0, "golden": 0, "bigdays": 0}
	reno = {}; bigday = {}; seen = {}; task_i = 0; task_base = 0; golden_n = 0; walkouts = 0; _star_cache = 0
	levels = {"tool": 0, "bag": 0, "boots": 0, "fire": 0, "menu": 0, "dining": 0, "sign": 0, "station": 0}
	pro = {"tool": 0, "bag": 0, "boots": 0}
	jobs_day = ""; refresh_jobs()
