extends SceneTree
## Walking-transition timing: walks back and forth 5 times between three places (1 -> 0 -> 1 -> 2 -> 1 ...),
## then once into a place never visited (3), and reports per crossing:
##   black  ms the screen is fully black (Fade alpha 1), measured from outside main.gd
##   total  ms from the walk starting (fade out) to the fade-in finishing
##   build  main.gd's own build ms (world swap + HUD rebind)
##   stall  the slowest frame in the first second after the fade-in (ms), and frames in that second
## Run: $G --headless --path . -s res://tests/qa/cross_timing.gd
## Desktop headless target: black well under 200 ms, no frame over ~50 ms after arriving.
var fails := 0
var g


func ok(c: bool, msg: String) -> void:
	print(("PASS " if c else "FAIL ") + msg)
	if not c:
		fails += 1


func _initialize() -> void:
	_run.call_deferred()


func _wait(n: int) -> void:
	for i in n:
		await process_frame


func _ready_scene() -> void:
	while current_scene == null or current_scene.get("hud") == null or current_scene.get_node_or_null("LoadingScreen") != null \
			or current_scene.get("crossing"):
		await process_frame


func _full(k: int) -> Dictionary:
	var b := {"campfire": true, "tables_1": true, "shop": true, "crew_hut": true, "fire_2": true, "tables_2": true}
	if String(g.chapters[k].get("special", {}).get("type", "")) != "":
		b["special"] = true
	return b


func _fade_alpha() -> float:
	var f = current_scene.get_node_or_null("Fade")
	if f == null:
		return -1.0
	var c = f.get_child(0)
	return c.color.a * c.modulate.a


## One crossing toward `side` (-1 west, +1 east). Returns {black, total, build, stall, frames}.
func _cross(side: int) -> Dictionary:
	var w = current_scene.world
	var v0: int = g.venue
	var Plot = load("res://scripts/world/plot.gd")
	w.player.global_position = Vector3(Plot.west(g.venue) + 0.2 if side < 0 else Plot.east(g.venue) - 0.2, 0, 11.5)
	w._cross_armed = true
	var t_start := Time.get_ticks_usec()
	w._cross(side)
	var t_black := -1
	var t_unblack := -1
	while true:
		await process_frame
		var a := _fade_alpha()
		var now := Time.get_ticks_usec()
		if t_black < 0 and a >= 0.999:
			t_black = now
		elif t_black >= 0 and t_unblack < 0 and a < 0.999:
			t_unblack = now
		if not current_scene.crossing:
			break
		if now - t_start > 20_000_000:
			break
	var t_end := Time.get_ticks_usec()
	if t_unblack < 0:
		t_unblack = t_end
	# the first second after arriving: slowest frame
	var worst := 0.0
	var frames := 0
	var last := Time.get_ticks_usec()
	while Time.get_ticks_usec() - t_end < 1_000_000:
		await process_frame
		var now2 := Time.get_ticks_usec()
		worst = maxf(worst, (now2 - last) / 1000.0)
		last = now2
		frames += 1
	return {"moved": g.venue != v0, "black": (t_unblack - t_black) / 1000.0 if t_black >= 0 else -1.0,
		"total": (t_end - t_start) / 1000.0, "build": float(current_scene.last_cross_ms), "stall": worst, "frames": frames,
		"to": g.venue}


func _run() -> void:
	g = root.get_node("Game")
	g.saving_enabled = false
	g.offline_reward = 0
	g.settings.story = false
	g.coins = 5000000; g.served = 0; g.pad_paid = {}; g.chapter_done = true; g.prestige = 0
	g.venue = 0; g.unlocked = 1; g.venues = []; g.vserved = 0; g.cfg = g.chapter_cfg(0)
	g.reno = {}; g.bigday = {"won": true}; g.seen = {"task_init": true}; g.task_i = 13; g.task_base = 0; g.golden_n = 0
	g.built = _full(0)
	g.crew = {"lumberjack": 3, "waiter": 2, "cook": 1}
	g.woodpile = 10; g.counter_coins = 0
	g.levels = {"tool": 3, "bag": 2, "boots": 1, "fire": 0, "menu": 0, "dining": 0, "sign": 0, "station": 0}
	g.unlocked = 4
	g.jobs_day = ""; g.refresh_jobs()
	for k in [2, 1]:
		g.travel(k)
		g.built = _full(k)
		g.crew = {"lumberjack": 3, "waiter": 2, "cook": 1}
		g.chapter_done = true; g.bigday = {"won": true}; g.task_i = 13; g.seen["task_init"] = true
	var tb := Time.get_ticks_usec()
	change_scene_to_file("res://scenes/main.tscn")
	await _ready_scene()
	print("BOOT %.0f ms" % ((Time.get_ticks_usec() - tb) / 1000.0))
	await _wait(10)
	# 1 -> 0 -> 1 -> 2 -> 1, five times (20 crossings)
	var plan := [1, -1, -1, 1]
	var rows: Array = []
	for rep in 5:
		for side in plan:
			var r := await _cross(side)
			rows.append(r)
			print("CROSSING %2d -> %d  black %6.1f ms  total %6.1f ms  build %6.1f ms  stall %6.1f ms (%d frames in 1 s)" % [
				rows.size(), r.to, r.black, r.total, r.build, r.stall, r.frames])
			ok(r.moved, "crossing %d moved" % rows.size())
	# first visit: 1 -> 2 -> 3 (3 is owned but never visited)
	await _cross(-1)
	var fv := await _cross(-1)
	print("FIRST VISIT -> %d  black %6.1f ms  total %6.1f ms  build %6.1f ms  stall %6.1f ms" % [fv.to, fv.black, fv.total, fv.build, fv.stall])
	ok(fv.moved and g.venue == 3, "walked into a new place")
	# MAP travel 3 -> 0 (tap to playable)
	var tm := Time.get_ticks_usec()
	current_scene.travel_to(0)
	await _wait(2)
	await _ready_scene()
	var map_ms := (Time.get_ticks_usec() - tm) / 1000.0
	print("MAP 3 -> 0  %6.1f ms" % map_ms)
	ok(g.venue == 0, "MAP travel arrived")
	var blacks: Array = []
	var stalls: Array = []
	for r in rows:
		blacks.append(r.black)
		stalls.append(r.stall)
	blacks.sort()
	stalls.sort()
	var avg := 0.0
	for b in blacks:
		avg += b
	avg /= blacks.size()
	print("SUMMARY black avg %.1f ms  median %.1f  max %.1f | stall median %.1f  max %.1f | first visit black %.1f | MAP %.0f ms" % [
		avg, blacks[blacks.size() / 2], blacks[-1], stalls[stalls.size() / 2], stalls[-1], fv.black, map_ms])
	ok(blacks[blacks.size() / 2] < 200.0, "median black under 200 ms on desktop (%.1f)" % blacks[blacks.size() / 2])
	var Plot = load("res://scripts/world/plot.gd")
	Plot.finish_jobs()
	print("FAILS=%d" % fails)
	quit()
