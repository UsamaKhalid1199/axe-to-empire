extends SceneTree
## QA1: refund-once on old saves, offline on load, daily jobs rollover. Restores the real save at the end.
var fails := 0
func ok(c: bool, msg: String) -> void:
	print(("PASS " if c else "FAIL ") + msg)
	if not c: fails += 1

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var g = root.get_node("Game")
	var keep := FileAccess.get_file_as_string(g.SAVE_PATH) if FileAccess.file_exists(g.SAVE_PATH) else ""
	var keepb := FileAccess.get_file_as_string(g.BACKUP_PATH) if FileAccess.file_exists(g.BACKUP_PATH) else ""
	g.saving_enabled = true
	# --- old save: unlocked 3, no gate_refund flag
	g.venue = 2; g.unlocked = 3; g.venues = [{"built": {"campfire": true}, "chapter_done": true}, {"built": {"campfire": true}, "chapter_done": true}]
	g.coins = 100; g.offline_reward = 0; g.chapter_done = false; g.built = {"campfire": true}
	g.crew = {"lumberjack": 0, "waiter": 0, "cook": 0}
	var d: Dictionary = g.to_dict()
	d.erase("gate_refund")
	var f := FileAccess.open(g.SAVE_PATH, FileAccess.WRITE); f.store_string(JSON.stringify(d)); f.close()
	g.load_game()
	var c1: int = g.coins
	ok(c1 == 100 + 4000 + 16000, "refund for 2 gates (coins=%d note=%d)" % [c1, g.refund_note])
	g.save_game()
	g.load_game()
	ok(g.coins == c1, "refund not paid twice after save+load (coins=%d)" % g.coins)
	# load without saving in between (crash within 8 s): coins in file still old -> no double either
	f = FileAccess.open(g.SAVE_PATH, FileAccess.WRITE); f.store_string(JSON.stringify(d)); f.close()
	g.load_game(); g.load_game()
	ok(g.coins == c1, "repeated loads of an old save refund once (coins=%d)" % g.coins)
	# --- offline accumulation over repeated loads of the same file
	g.venue = 0; g.unlocked = 1; g.venues = []; g.coins = 0; g.offline_reward = 0
	g.cfg = g.chapter_cfg(0)
	g.built = {"campfire": true, "tables_1": true, "tables_2": true, "fire_2": true, "shop": true, "crew_hut": true}
	g.crew = {"lumberjack": 3, "waiter": 2, "cook": 2}
	d = g.to_dict()
	d.t = int(Time.get_unix_time_from_system()) - 7200
	f = FileAccess.open(g.SAVE_PATH, FileAccess.WRITE); f.store_string(JSON.stringify(d)); f.close()
	g.load_game()
	var o1: int = g.offline_reward
	print("  offline after 2h away (ch1 full crew): %d" % o1)
	# --- daily jobs: jobs from yesterday, claimed today
	g.jobs_day = "2000-01-01"
	g.jobs = [{"id": "chop", "text": "x", "goal": 1, "prog": 1, "reward": 10, "claimed": false}, {"id": "sell", "text": "y", "goal": 1, "prog": 1, "reward": 10, "claimed": false}, {"id": "earn", "text": "z", "goal": 1, "prog": 1, "reward": 10, "claimed": false}]
	g.streak = 2; g.streak_last_day = ""; g.chest_claimed = false; g.coins = 0
	for i in 3: g.claim_job(i)
	g.claim_chest()
	var c_after := int(g.coins)
	print("  stale jobs claimed: coins=%d streak=%d chest_claimed=%s" % [c_after, g.streak, g.chest_claimed])
	g.refresh_jobs()   # what a restart does
	# yesterday's chest belongs to yesterday's jobs; today's chest needs today's three jobs first
	var c_before := int(g.coins)
	g.claim_chest()
	ok(int(g.coins) == c_before and not g.chest_claimed, "after the day rolls over, the new chest can't be claimed until today's jobs are done")
	# restore
	if keep != "":
		f = FileAccess.open(g.SAVE_PATH, FileAccess.WRITE); f.store_string(keep); f.close()
	if keepb != "":
		f = FileAccess.open(g.BACKUP_PATH, FileAccess.WRITE); f.store_string(keepb); f.close()
	print("FAILS=%d" % fails)
	quit()
