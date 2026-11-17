extends SceneTree
## QA #4: which events does a Control get for a 2nd-finger tap? (validates the suggested ScreenTouch fix)


class Probe extends Control:
	var log: Array = []
	func _gui_input(e: InputEvent) -> void:
		if e is InputEventScreenTouch:
			log.append("touch#%d %s" % [e.index, "down" if e.pressed else "up"])
		elif e is InputEventMouseButton:
			log.append("mouse %s" % ("down" if e.pressed else "up"))


func _initialize() -> void:
	_run.call_deferred()


func touch(idx: int, pos: Vector2, down: bool) -> void:
	var t := InputEventScreenTouch.new()
	t.index = idx
	t.position = pos
	t.pressed = down
	Input.parse_input_event(t)


func _run() -> void:
	var p := Probe.new()
	p.position = Vector2(100, 100)
	p.size = Vector2(200, 200)
	root.add_child(p)
	await process_frame
	var xf := root.get_final_transform()
	var c := xf * Vector2(200, 200)
	touch(0, c, true)
	for i in 3: await process_frame
	touch(0, c, false)
	for i in 3: await process_frame
	print("single finger: ", p.log)
	p.log.clear()
	touch(0, xf * Vector2(600, 900), true)     # thumb on joystick area
	for i in 3: await process_frame
	touch(1, c, true)
	for i in 3: await process_frame
	touch(1, c, false)
	for i in 3: await process_frame
	touch(0, xf * Vector2(600, 900), false)
	print("second finger while first held: ", p.log)
	quit()
