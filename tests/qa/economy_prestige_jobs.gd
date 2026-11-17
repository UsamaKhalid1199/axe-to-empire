extends SceneTree
## QA1: daily-job rewards fixed at refresh time survive a New Empire (coins reset to 0).
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var g = root.get_node("Game")
	g.saving_enabled = false
	g.venue = 5; g.unlocked = 6; g.venues = []; g.prestige = 0
	g.cfg = g.chapter_cfg(5)
	g.levels = {"tool": 3, "bag": 4, "boots": 3, "fire": 14, "menu": 14, "dining": 14, "sign": 14, "station": 14}
	g.stats.play_s = 3600.0 * 5
	g.jobs_day = ""
	g.refresh_jobs()
	g.chapter_done = true
	g.coins = 0
	g.start_new_empire()
	var cost_ch1 := 0
	for b in g.cfg.builds: cost_ch1 += int(b.cost)
	for j in g.jobs:
		print("after New Empire, venue=%d job %s goal=%d reward=%d (all chapter-1 builds cost %d)" % [g.venue, j.id, j.goal, j.reward, cost_ch1])
	quit()
