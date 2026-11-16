extends SceneTree
## Captures the loading screen (also used to make the boot splash): -- <out.png> [progress]
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var ls = load("res://scripts/ui/loading_screen.gd").new()
	root.add_child(ls)
	for i in 3: await process_frame
	var pr := float(args[1]) if args.size() > 1 else 0.0
	ls.set_status("Loading…" if pr == 0.0 else "Planting the forest…", pr)
	ls.sync()
	if pr < 0.0:   # splash: art + logo only
		ls.card.visible = false
	for i in 3: await process_frame
	root.get_texture().get_image().save_png(args[0])
	quit()
