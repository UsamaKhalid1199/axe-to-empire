extends SceneTree
## "Start new empire" asks first; "Keep playing" keeps everything.
var fails := 0
func ok(c: bool, msg: String) -> void:
	print(("PASS " if c else "FAIL ") + msg)
	if not c: fails += 1
func _initialize() -> void:
	_run.call_deferred()
func _find(n: Node, txt: String) -> Node:
	if n.has_method("get") and n.get("text") is String and String(n.get("text")).contains(txt):
		return n
	for c in n.get_children():
		var f := _find(c, txt)
		if f: return f
	return null
func _btn(n: Node) -> Node:
	while n and not n.has_signal("pressed"):
		n = n.get_parent()
	return n
func _run() -> void:
	var g = root.get_node("Game")
	g.saving_enabled = false
	g.settings.story = false
	change_scene_to_file("res://scenes/main.tscn")
	while current_scene == null or current_scene.get("hud") == null or current_scene.get_node_or_null("LoadingScreen") != null:
		await process_frame
	var hud = current_scene.hud
	g.venue = g.chapters.size() - 1; g.unlocked = g.chapters.size(); g.cfg = g.chapter_cfg(g.venue)
	g.chapter_done = true; g.coins = 123456; var pre: int = g.prestige
	hud.open_modal("complete")
	await process_frame; await process_frame
	var b := _btn(_find(hud.modal, "START NEW EMPIRE"))
	ok(b != null, "start button shown")
	b.pressed.emit()
	await process_frame; await process_frame; await process_frame
	ok(g.prestige == pre and g.coins == 123456, "first tap erases nothing")
	var keep := _btn(_find(hud.modal, "Keep playing"))
	ok(keep != null and _find(hud.modal, "Are you sure") != null, "confirm step with Keep playing")
	keep.pressed.emit()
	await process_frame; await process_frame; await process_frame
	ok(g.prestige == pre and g.coins == 123456 and _find(hud.modal, "START NEW EMPIRE") != null, "Keep playing goes back, nothing erased")
	print("PRESTIGE fails=%d" % fails)
	quit()
