extends SceneTree
## QA round 4: the player can never leave the playable area at a plot edge (real scene, joystick input).
## A phone tester walked east from the Lake into the Shack, stopped just inside the edge and walked back west:
## the edge was disarmed (no crossing until 1.2 m inside) but the road-gap wall was open, so the player walked out
## into the Lake's still picture and the void. Covers: turning back right after arriving at both edges (with and
## without a stop), holding the joystick continuously across an edge and back, the Lakeside plot's long east end,
## the end of the road, and the safety net (a player put outside is walked across or put back).
## Run: $G --headless --path . -s res://tests/qa/qa_r4_edge.gd
var fails := 0
var g
var Plot
var worst_out := 0.0          # metres past a plot edge / road wall seen while holding the stick
var worst_where := ""


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


func _w():
	return current_scene.world


## How far the player stands outside the play area of the place they are in (0 when inside).
func _outside() -> float:
	var w = _w()
	if w == null or not is_instance_valid(w) or w.player == null or current_scene.crossing:
		return 0.0
	var p: Vector3 = w.player.global_position
	var we: float = Plot.west(g.venue)
	var ee: float = Plot.east(g.venue)
	return maxf(maxf(we - p.x, p.x - ee), maxf(p.z - 14.0, -26.5 - p.z))


func _track() -> void:
	var o := _outside()
	if o > worst_out:
		worst_out = o
		worst_where = "venue %d at %s" % [g.venue, _w().player.global_position]


## Holds the stick at (dx, 0) for `secs` of game time (through any crossing), checking the bounds every frame.
## Returns the venues visited in order.
func _hold(dx: float, secs: float) -> Array:
	var seen: Array = [g.venue]
	var t := 0.0
	while t < secs:
		var w = _w()
		if w != null and is_instance_valid(w) and w.player != null and not current_scene.crossing:
			w.player.input_dir = Vector2(dx, 0)
			if seen[-1] != g.venue:
				seen.append(g.venue)
		_track()
		await physics_frame
		t += 1.0 / float(Engine.physics_ticks_per_second)
	await _ready_scene()
	if seen[-1] != g.venue:
		seen.append(g.venue)
	_w().player.input_dir = Vector2.ZERO
	await _wait(2)
	_track()
	return seen


## Walk from inside place `from` across its `side` edge (-1 west, +1 east). Returns true on arrival next door.
func _arrive(side: int) -> bool:
	var v0: int = g.venue
	var w = _w()
	var x: float = Plot.west(g.venue) + 3.0 if side < 0 else Plot.east(g.venue) - 3.0
	w.player.global_position = Vector3(x, 0, 11.5)
	w._cross_armed = true
	await _wait(3)
	var t := 0.0
	while g.venue == v0 and t < 5.0:
		w = _w()
		if not current_scene.crossing:
			w.player.input_dir = Vector2(float(side), 0)
		_track()
		await physics_frame
		t += 1.0 / float(Engine.physics_ticks_per_second)
	await _ready_scene()
	_w().player.input_dir = Vector2.ZERO
	return g.venue != v0


func _full(k: int) -> Dictionary:
	var b := {"campfire": true, "tables_1": true, "shop": true, "crew_hut": true, "fire_2": true, "tables_2": true}
	if String(g.chapters[k].get("special", {}).get("type", "")) != "":
		b["special"] = true
	return b


func _reset_worst() -> void:
	worst_out = 0.0
	worst_where = ""


func _run() -> void:
	g = root.get_node("Game")
	Plot = load("res://scripts/world/plot.gd")
	g.saving_enabled = false
	g.offline_reward = 0
	g.settings.story = false
	g.coins = 50000; g.served = 0; g.pad_paid = {}; g.chapter_done = true; g.prestige = 0
	g.venue = 0; g.unlocked = 1; g.venues = []; g.vserved = 0; g.cfg = g.chapter_cfg(0)
	g.reno = {}; g.bigday = {"won": true}; g.seen = {"task_init": true}; g.task_i = 13; g.task_base = 0; g.golden_n = 0
	g.built = _full(0)
	g.crew = {"lumberjack": 1, "waiter": 1, "cook": 0}
	g.woodpile = 10; g.counter_coins = 0
	g.levels = {"tool": 3, "bag": 2, "boots": 1, "fire": 0, "menu": 0, "dining": 0, "sign": 0, "station": 0}
	g.unlocked = 4
	g.jobs_day = ""; g.refresh_jobs()
	for k in [1, 2, 3, 1]:
		g.travel(k)
		g.built = _full(k)
		g.crew = {"lumberjack": 1, "waiter": 1, "cook": 0}
		g.chapter_done = true; g.bigday = {"won": true}; g.task_i = 13; g.seen["task_init"] = true
	change_scene_to_file("res://scenes/main.tscn")
	await _ready_scene()
	await _wait(5)
	ok(g.venue == 1, "starts at the Shack")

	# ---- 1. the tester's case: Lake -> Shack (west edge of the Shack), stop just inside, walk back west
	ok(await _arrive(-1) and g.venue == 2, "Shack -> Lake")
	ok(await _arrive(1) and g.venue == 1, "Lake -> Shack (arrives at the Shack's west edge)")
	var w = _w()
	var px: float = w.player.global_position.x
	print("INFO arrived at x=%.2f (edge %.1f), armed=%s" % [px, Plot.west(1), w._cross_armed])
	ok(px - Plot.west(1) >= 0.85, "arrival stands clear of the road-gap wall (%.2f m inside)" % (px - Plot.west(1)))
	_reset_worst()
	await _wait(8)           # stop for a moment within ~1 m of the edge
	var seen := await _hold(-1.0, 0.5)     # turn straight back: blocked (no bounce) ...
	ok(worst_out <= 0.0, "turning back right after arriving never leaves the plot (worst %.2f m %s)" % [worst_out, worst_where])
	ok(seen == [1], "a quick turn back does not bounce straight over (%s)" % [seen])
	seen = await _hold(-1.0, 3.0)          # ... but keep walking back and you do go back
	ok(worst_out <= 0.0, "pushing back at the edge never leaves the plot (worst %.2f m %s)" % [worst_out, worst_where])
	ok(g.venue == 2, "walking back west after a moment returns to the Lake (%s)" % [seen])

	# ---- 2. the other edge: Shack -> Lake (arrive at the Lake's long east end), turn back at once
	ok(await _arrive(1) and g.venue == 1, "Lake -> Shack again")
	ok(await _arrive(-1) and g.venue == 2, "Shack -> Lake (arrives at the Lake's east end, x %.1f)" % Plot.east(2))
	w = _w()
	px = w.player.global_position.x
	ok(Plot.east(2) - px >= 0.85, "Lake arrival clear of the wall (%.2f m inside its %.1f m east end)" % [Plot.east(2) - px, Plot.east(2)])
	_reset_worst()
	seen = await _hold(1.0, 0.4)
	ok(worst_out <= 0.0 and seen == [2], "Lake: turning back at once stays inside, no bounce (worst %.2f m, %s)" % [worst_out, seen])
	seen = await _hold(1.0, 3.0)
	ok(worst_out <= 0.0 and g.venue == 1, "Lake: keep walking east and you are back at the Shack (worst %.2f m, %s)" % [worst_out, seen])

	# ---- 3. holding the stick continuously across an edge and back
	w = _w()
	w.player.global_position = Vector3(Plot.west(1) + 4.0, 0, 11.5)
	w._cross_armed = true
	await _wait(3)
	_reset_worst()
	seen = await _hold(-1.0, 2.6)            # across into the Lake and on along its shore road
	ok(seen == [1, 2], "held stick: Shack -> Lake (%s)" % [seen])
	seen = await _hold(1.0, 4.0)             # straight back the other way, never letting go
	ok(seen == [2, 1], "held stick: and back into the Shack (%s)" % [seen])
	ok(worst_out <= 0.0, "held stick across and back never leaves the play area (worst %.2f m %s)" % [worst_out, worst_where])
	# and back and forth across the same edge a few times without letting go
	_reset_worst()
	for i in 3:
		await _hold(-1.0, 1.6)
		await _hold(1.0, 1.6)
	ok(worst_out <= 0.0, "back and forth across an edge x3 never leaves the play area (worst %.2f m %s)" % [worst_out, worst_where])

	# ---- 4. the Lake's long plot: its west edge (to the Lodge) and the whole shore road
	if g.venue != 2:
		await _arrive(-1)
	ok(g.venue == 2, "at the Lake")
	_reset_worst()
	w = _w()
	w.player.global_position = Vector3(Plot.east(2) - 3.0, 0, 11.5)
	await _wait(3)
	seen = await _hold(-1.0, 9.0)            # the full 47 m of road, east end to west edge and over
	ok(seen.has(3), "Lake: walking the whole road west reaches the Lodge (%s)" % [seen])
	ok(await _arrive(1) and g.venue == 2, "Lodge -> Lake (arrives at the Lake's west edge)")
	seen = await _hold(-1.0, 0.4)
	ok(worst_out <= 0.0 and seen == [2], "Lake west edge: quick turn back stays inside (worst %.2f m, %s)" % [worst_out, seen])

	# ---- 5. the end of the road (east of the Forest Camp) and a FOR SALE neighbour (west of the Lodge)
	g.unlocked = 4
	current_scene.travel_to(0)
	await _ready_scene()
	await _wait(5)
	ok(g.venue == 0, "MAP to the Forest Camp")
	w = _w()
	w.player.global_position = Vector3(Plot.east(0) - 2.0, 0, 11.5)
	await _wait(3)
	_reset_worst()
	seen = await _hold(1.0, 2.0)
	ok(worst_out <= 0.0 and seen == [0], "end of the road: pushing east stays inside (worst %.2f m)" % worst_out)

	# ---- 6. safety net: a player who somehow ends up outside is walked across (way open) or put back
	current_scene.travel_to(1)
	await _ready_scene()
	await _wait(5)
	ok(g.venue == 1, "MAP to the Shack")
	w = _w()
	w._cross_armed = false            # even disarmed
	w.player.global_position = Vector3(Plot.west(1) - 1.5, 0, 11.5)
	await _wait(3)
	await _ready_scene()
	ok(g.venue == 2, "past the open west edge: walked across to the Lake instead of standing in the void (venue %d)" % g.venue)
	current_scene.travel_to(0)
	await _ready_scene()
	await _wait(5)
	w = _w()
	w.player.global_position = Vector3(Plot.east(0) + 2.0, 0, 11.5)      # past the end of the road
	await _wait(3)
	var p: Vector3 = w.player.global_position
	ok(g.venue == 0 and p.x <= Plot.east(0) - 0.5, "past the end of the road: put back inside (x %.2f)" % p.x)
	w.player.global_position = Vector3(2.0, 0, 18.0)                         # beyond the south road wall
	await _wait(3)
	p = w.player.global_position
	ok(p.z <= 14.0, "beyond the south wall: put back on the road (z %.2f)" % p.z)
	w.player.global_position = Vector3(-3.0, 0, -30.0)                       # beyond the north wall
	await _wait(3)
	p = w.player.global_position
	ok(p.z >= -26.5, "beyond the north wall: put back inside (z %.2f)" % p.z)

	load("res://scripts/world/plot.gd").finish_jobs()
	print("RESULT qa_r4_edge fails=%d" % fails)
	quit(1 if fails > 0 else 0)
