extends SceneTree
## QA round 2, tester 1: save recovery copy (KEEP_PATH). The keep copy is never replaced by a lower-progress
## save, load falls back to it when main + backup are unreadable, and reset_all doesn't resurrect old progress.
## Backs up and restores the desktop profile's user:// save files.
## Run: $G --headless --path . -s res://tests/qa/qa_r2_t1_save.gd
var fails := 0
var g
var saved_files := {}


func ok(c: bool, msg: String) -> void:
	print(("PASS " if c else "FAIL ") + msg)
	if not c:
		fails += 1


func _initialize() -> void:
	_run.call_deferred()


func _txt(p: String) -> String:
	return FileAccess.get_file_as_string(p) if FileAccess.file_exists(p) else ""


func _write(p: String, s: String) -> void:
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string(s)
	f.close()


func _del(p: String) -> void:
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


func _state(prestige: int, earned: int, coins: int, unlocked: int) -> void:
	g.prestige = prestige
	g.stats.earned = earned
	g.coins = coins
	g.unlocked = unlocked


func _keep() -> Dictionary:
	return g._read(g.KEEP_PATH)


func _run() -> void:
	g = root.get_node("Game")
	g.set_process(false)
	g.settings.story = false
	var paths: Array = [g.SAVE_PATH, g.BACKUP_PATH, g.KEEP_PATH]
	for p in paths:
		saved_files[p] = _txt(p)
	g.saving_enabled = true

	# --- 1. keep never replaced by a lower-progress save (also after a "relaunch": _keep_score re-read)
	for p in paths:
		_del(p)
	g._keep_score = -1.0
	_state(2, 5_000_000, 777777, 6)
	g.save_game()
	ok(int(_keep().get("prestige", -1)) == 2, "keep written on first save (prestige %s)" % _keep().get("prestige"))
	_state(0, 10, 5, 1)
	g.save_game()
	ok(int(_keep().get("prestige", -1)) == 2 and int(_keep().coins) == 777777, "lower-progress save leaves keep alone (keep prestige %s coins %s)" % [_keep().get("prestige"), _keep().get("coins")])
	g._keep_score = -1.0           # relaunch
	g.save_game()
	ok(int(_keep().get("prestige", -1)) == 2, "after relaunch a lower save still leaves keep alone")
	# same prestige but less earned
	_state(2, 4_999_999, 1, 6)
	g.save_game()
	ok(int(_keep().coins) == 777777, "same prestige, less lifetime cash: keep alone")
	_state(2, 5_000_001, 42, 6)
	g.save_game()
	ok(int(_keep().coins) == 42, "more progress replaces keep (coins %s)" % _keep().get("coins"))
	# prestige dominates lifetime earnings
	_state(1, 900_000_000_000, 9, 6)
	g.save_game()
	ok(int(_keep().coins) == 42, "prestige 1 with huge earned doesn't beat prestige 2 (keep coins %s)" % _keep().get("coins"))

	# --- 2. load falls back to keep when main + backup are garbage
	_state(2, 5_000_001, 42, 6)
	g.save_game()
	_state(0, 3, 1, 1)
	g.save_game()                 # main + backup now low progress, keep has 42
	_write(g.SAVE_PATH, "\u0000\u0001garbage{{{")
	_write(g.BACKUP_PATH, "not json at all")
	g.coins = -1; g.prestige = -1
	g.load_game()
	ok(g.coins == 42 and g.prestige == 2 and g.unlocked == 6, "main+backup garbage -> keep loaded (coins %d prestige %d unlocked %d)" % [g.coins, g.prestige, g.unlocked])
	# truncated main (half-written) with a good backup -> backup, not keep
	_state(0, 3, 11, 1)
	g.save_game()
	_state(0, 4, 12, 1)
	g.save_game()                 # backup = coins 11, main = coins 12
	var m: String = _txt(g.SAVE_PATH)
	_write(g.SAVE_PATH, m.substr(0, m.length() / 2))
	g.coins = -1
	g.load_game()
	ok(g.coins == 11, "truncated main + good backup -> backup (coins %d)" % g.coins)
	# valid JSON but wrong shape
	_write(g.SAVE_PATH, "[1,2,3]")
	_write(g.BACKUP_PATH, "{\"v\": 1}")
	g.coins = -1
	g.load_game()
	ok(g.coins == 42, "JSON of the wrong shape in main+backup -> keep (coins %d)" % g.coins)
	# all three missing: state is left as is (no crash)
	for p in paths:
		_del(p)
	g.coins = 5
	g.load_game()
	ok(g.coins == 5, "no save files: load is a no-op")

	# --- 3. reset_all: the fresh game is what loads next, never the old progress
	g._keep_score = -1.0
	_state(3, 7_000_000, 123456, 6)
	g.venue = 0
	g.save_game()
	g.save_game()
	ok(int(_keep().get("prestige", -1)) == 3, "keep holds prestige 3 before reset")
	g.reset_all()
	await process_frame
	await process_frame
	ok(FileAccess.file_exists(g.SAVE_PATH), "reset wrote a fresh main save at once")
	var dm: Dictionary = g._read(g.SAVE_PATH)
	ok(int(dm.get("prestige", -1)) == 0 and int(dm.get("coins", -1)) == 0, "fresh main save: prestige %s coins %s" % [dm.get("prestige"), dm.get("coins")])
	ok(int(_keep().get("prestige", -1)) == 3, "reset leaves the recovery copy alone (prestige %s)" % _keep().get("prestige"))
	g.coins = 999; g.prestige = 9
	g.load_game()                 # relaunch
	ok(g.coins == 0 and g.prestige == 0 and g.unlocked == 1, "relaunch after reset loads the fresh game (coins %d prestige %d unlocked %d)" % [g.coins, g.prestige, g.unlocked])
	# play a little after reset, save several times: keep still the old empire, main the new one
	g._keep_score = -1.0
	g.add_coins(500)
	for i in 3:
		g.save_game()
	ok(int(_keep().get("prestige", -1)) == 3 and int(g._read(g.SAVE_PATH).coins) == 500, "after reset, saves go to main only; keep stays prestige 3")
	g.coins = 7
	g.load_game()
	ok(g.coins == 500 and g.prestige == 0, "relaunch again: still the new game (coins %d prestige %d)" % [g.coins, g.prestige])
	# reset with no backup: backup missing after reset? main exists, both readable
	ok(not FileAccess.file_exists(g.BACKUP_PATH) or int(g._read(g.BACKUP_PATH).get("prestige", 0)) == 0, "backup after reset never holds the old empire")
	# what a corrupt main+backup does after a reset (documented behaviour: the old progress comes back)
	_write(g.SAVE_PATH, "x")
	_write(g.BACKUP_PATH, "y")
	g.load_game()
	print("INFO after reset, main+backup corrupt -> loaded prestige %d coins %d (recovery copy = pre-reset progress)" % [g.prestige, g.coins])

	# --- restore the desktop profile
	g.saving_enabled = false
	for p in paths:
		if String(saved_files[p]) == "":
			_del(p)
		else:
			_write(p, saved_files[p])
	print("RESULT qa_r2_t1_save: %d fail(s)" % fails)
	quit()
