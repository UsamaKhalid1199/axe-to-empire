class_name Joystick
extends Control
## Floating joystick: touch anywhere in the play area, drag to run.

signal moved(v: Vector2)

const RADIUS := 92.0
const KNOB := 44.0

var active := false
var origin := Vector2.ZERO
var knob := Vector2.ZERO
var touch_id := -1
var hint_alpha := 1.0          # "Drag to move": stays until the player has really walked a few metres (Hud)
var blocked := false


var ui_hit: Callable          # returns true when a screen point is over a HUD button


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Touches are read here (not _gui_input) so they work the same on phones and desktop.
func _input(e: InputEvent) -> void:
	if blocked:
		if touch_id != -1:
			release()
		return
	if e is InputEventScreenTouch:
		e = make_input_local(e)
		if e.pressed and touch_id == -1:
			if ui_hit.is_valid() and ui_hit.call(e.position):
				return
			touch_id = e.index
			active = true
			origin = e.position
			knob = origin
			_emit()
			get_viewport().set_input_as_handled()
		elif not e.pressed and e.index == touch_id:
			release()
			get_viewport().set_input_as_handled()
	elif e is InputEventScreenDrag and e.index == touch_id:
		e = make_input_local(e)
		var d: Vector2 = e.position - origin
		if d.length() > RADIUS:
			# drag the base along so direction changes stay responsive
			origin += d - d.normalized() * RADIUS
			d = e.position - origin
		knob = origin + d
		_emit()
		get_viewport().set_input_as_handled()


func release() -> void:
	touch_id = -1
	active = false
	moved.emit(Vector2.ZERO)
	queue_redraw()


func _emit() -> void:
	var v := (knob - origin) / RADIUS
	if v.length() < 0.12:
		v = Vector2.ZERO
	moved.emit(v.limit_length(1.0))
	queue_redraw()


func _process(_d: float) -> void:
	if hint_alpha > 0.0 or active:
		queue_redraw()


func _draw() -> void:
	if active:
		_draw_stick(origin, knob, 1.0)
		if hint_alpha > 0.0:
			_draw_hint_text(origin)          # (a first touch alone does not teach it: keep the words under the thumb)
	elif hint_alpha > 0.0:
		var c := Vector2(size.x * 0.5, size.y - 260.0)
		var k := c + Vector2(sin(Time.get_ticks_msec() * 0.003) * 40.0, 0)
		_draw_stick(c, k, 0.7 * hint_alpha)
		_draw_hint_text(c)


func _draw_hint_text(c: Vector2) -> void:
	var f := UI.font_ui(600)
	var t := "Drag to move"
	var w := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
	var at := c + Vector2(-w * 0.5, RADIUS + 46)
	at.x = clampf(at.x, 12.0, maxf(12.0, size.x - w - 12.0))
	at.y = minf(at.y, size.y - 24.0)
	draw_string(f, at, t, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(1, 1, 1, 0.85 * hint_alpha))


func _draw_stick(o: Vector2, k: Vector2, a: float) -> void:
	draw_circle(o, RADIUS + 6, Color(0.05, 0.035, 0.02, 0.32 * a))
	draw_arc(o, RADIUS, 0, TAU, 64, Color(1, 1, 1, 0.28 * a), 3.0, true)
	draw_circle(k + Vector2(0, 5), KNOB, Color(0, 0, 0, 0.3 * a))
	draw_circle(k, KNOB, Color(0.94, 0.6, 0.1, a))
	draw_circle(k + Vector2(0, -4), KNOB - 5, Color(1.0, 0.78, 0.3, a))
	draw_circle(k + Vector2(-10, -14), KNOB * 0.35, Color(1, 0.95, 0.75, 0.55 * a))
