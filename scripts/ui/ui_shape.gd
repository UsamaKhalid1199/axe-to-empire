class_name UIShape
extends PanelContainer
## Rounded panel/button drawn by ui_shape.gdshader: smoked glass, gold, green, red, dark.

signal pressed

const PAD := 22.0
const STYLES := {
	"glass": {"top": Color(0.071, 0.051, 0.035, 0.66), "bottom": Color(0.071, 0.051, 0.035, 0.74), "border": Color(1, 1, 1, 0.14), "glass": 1.0, "hl": 0.0},
	"glass_strong": {"top": Color(0.06, 0.045, 0.03, 0.84), "bottom": Color(0.05, 0.035, 0.025, 0.9), "border": Color(1, 1, 1, 0.12), "glass": 1.0, "hl": 0.0},
	"gold": {"top": Color("#FFD45E"), "bottom": Color("#F09A1A"), "border": Color(1, 0.95, 0.75, 0.6), "glass": 0.0, "hl": 0.5},
	"green": {"top": Color("#7CD36B"), "bottom": Color("#2E9447"), "border": Color(0.85, 1, 0.8, 0.5), "glass": 0.0, "hl": 0.45},
	"red": {"top": Color("#FF6B5B"), "bottom": Color("#C9281C"), "border": Color(1, 0.8, 0.75, 0.5), "glass": 0.0, "hl": 0.4},
	"dark": {"top": Color(1, 1, 1, 0.07), "bottom": Color(1, 1, 1, 0.04), "border": Color(1, 1, 1, 0.1), "glass": 0.0, "hl": 0.0},
	"cream": {"top": Color("#FFF6E4"), "bottom": Color("#F1DEBE"), "border": Color(1, 1, 1, 0.7), "glass": 0.0, "hl": 0.0},
}

var style := "glass"
var radius := 22.0
var shadow := 0.4
var clickable := false
var disabled := false:
	set(v):
		disabled = v
		_apply()
var _mat: ShaderMaterial


func _init(st := "glass", r := 22.0, margin := Vector4(20, 14, 20, 14)) -> void:
	style = st
	radius = r
	var sb := StyleBoxEmpty.new()
	sb.content_margin_left = margin.x
	sb.content_margin_top = margin.y
	sb.content_margin_right = margin.z
	sb.content_margin_bottom = margin.w
	add_theme_stylebox_override("panel", sb)
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://shaders/ui_shape_lite.gdshader") if OS.has_feature("mobile") else preload("res://shaders/ui_shape.gdshader")
	material = _mat
	_apply()
	resized.connect(_on_resized)
	mouse_filter = Control.MOUSE_FILTER_STOP


func set_style(st: String) -> void:
	style = st
	_apply()


func _apply() -> void:
	if _mat == null:
		return
	var s: Dictionary = STYLES[style]
	_mat.set_shader_parameter("top", s.top)
	_mat.set_shader_parameter("bottom", s.bottom)
	_mat.set_shader_parameter("border", s.border)
	_mat.set_shader_parameter("glass", s.glass)
	_mat.set_shader_parameter("highlight", s.hl)
	_mat.set_shader_parameter("radius", radius)
	_mat.set_shader_parameter("pad", PAD)
	_mat.set_shader_parameter("shadow", shadow)
	_mat.set_shader_parameter("dim", 0.75 if disabled else 0.0)
	if clickable:
		modulate = Color(0.78, 0.78, 0.78, 0.6) if disabled else Color.WHITE   # disabled buttons read as greyed out
	_on_resized()


func _on_resized() -> void:
	if _mat:
		_mat.set_shader_parameter("size", size)
	pivot_offset = size * 0.5
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2(-PAD, -PAD), size + Vector2(PAD, PAD) * 2.0), Color.WHITE)


func _notification(what: int) -> void:
	if what == NOTIFICATION_ENTER_TREE:
		_entered_ms = Time.get_ticks_msec()
	# a plain panel (row background, swatch frame) inside a scroll list must let drags through to the list
	if what == NOTIFICATION_ENTER_TREE and not clickable and mouse_filter == Control.MOUSE_FILTER_STOP and _scroll_parent() != null:
		mouse_filter = Control.MOUSE_FILTER_PASS


func make_clickable() -> UIShape:
	clickable = true
	return self


var _press_pos := Vector2.ZERO
var _down := false

const FRESH_MS := 350                      # double-tap guard window (see _fresh_block)
const FRESH_PX := 90.0                     # "the same spot" for a second tap
static var _last_tap_ms := -100000         # when any button last fired, where, and its rect
static var _last_tap_pos := Vector2.ZERO
static var _last_tap_rect := Rect2()
static var prev_tap_ms := -100000          # the tap before that (the HUD's side buttons check it)
static var prev_tap_pos := Vector2.ZERO
var _entered_ms := -100000
var _down_ms := 0
var _down_global := Vector2.ZERO


## True for the second tap of a quick double tap that lands on a button the first tap just built (a confirm
## screen's "Erase" where "Reset progress" was): built right after a tap (same or next frames), pressed within
## FRESH_MS of it, at about the same spot. Taps elsewhere go through, and so does a button rebuilt in the same
## place as the one just tapped (a list rebuilt after a buy takes repeat taps).
func _fresh_block() -> bool:
	if _entered_ms < _last_tap_ms or _entered_ms - _last_tap_ms > 120 or _down_ms - _last_tap_ms >= FRESH_MS:
		return false
	if _down_global.distance_to(_last_tap_pos) > FRESH_PX:
		return false
	var r := get_global_rect()
	return r.get_center().distance_to(_last_tap_rect.get_center()) > 12.0 or absf(r.size.x - _last_tap_rect.size.x) > 12.0


## Where the finger went down on this button (canvas coordinates).
func press_pos() -> Vector2:
	return _down_global


func _note_down(pos: Vector2) -> void:
	_down_ms = Time.get_ticks_msec()
	_down_global = get_global_transform() * pos


func _fire() -> void:
	if disabled:
		Sfx.play("click", -10.0, 0.7)
		return
	if _fresh_block():
		return
	prev_tap_ms = _last_tap_ms
	prev_tap_pos = _last_tap_pos
	_last_tap_ms = Time.get_ticks_msec()
	_last_tap_pos = _down_global
	_last_tap_rect = get_global_rect()
	Sfx.play("click")
	pressed.emit()


var _touch_idx := -1
var _scroller: ScrollContainer = null      # set once a press turned into a drag: the list we scroll instead

const DRAG_CANCEL := 12.0                  # px a finger may move on a button inside a list before it scrolls instead


func _scroll_parent() -> ScrollContainer:
	var p := get_parent()
	while p:
		if p is ScrollContainer:
			return p
		p = p.get_parent()
	return null


## A press that moved too far inside a scroll list: drop the press (no click on release) and scroll the list.
func _drag_check(pos: Vector2, rel: Vector2) -> void:
	if _scroller:
		if is_instance_valid(_scroller):
			_scroller.scroll_vertical -= int(round(rel.y))
			_scroller.scroll_horizontal -= int(round(rel.x))
		return
	if not _down or pos.distance_to(_press_pos) <= DRAG_CANCEL:
		return
	var sc := _scroll_parent()
	if sc == null:
		return                              # not in a list: a finger rolling off a little still clicks
	_down = false
	_scroller = sc
	create_tween().tween_property(self, "scale", Vector2.ONE, 0.12)
	var d := pos - _press_pos               # catch up with the part of the drag before the threshold
	sc.scroll_vertical -= int(round(d.y))
	sc.scroll_horizontal -= int(round(d.x))


func _gui_input(e: InputEvent) -> void:
	if not clickable:
		return
	if e is InputEventMouseMotion and (_down or _scroller) and _touch_idx == -1:
		_drag_check(e.position, e.relative)
		accept_event()
		return
	if e is InputEventScreenDrag and e.index >= 1 and e.index == _touch_idx:
		if _down and e.position.distance_to(_press_pos) > DRAG_CANCEL and _scroll_parent() != null:
			_down = false
			create_tween().tween_property(self, "scale", Vector2.ONE, 0.12)
		accept_event()
		return
	# extra fingers (index >= 1) get no emulated mouse events, so handle them here
	# (e.g. tapping a button with one thumb while the other still holds the joystick)
	if e is InputEventScreenTouch and e.index >= 1:
		if e.pressed:
			_touch_idx = e.index
			_down = true
			_press_pos = e.position
			_note_down(e.position)
			var tw0 := create_tween()
			tw0.tween_property(self, "scale", Vector2(0.94, 0.94), 0.06)
		elif e.index == _touch_idx and not _down:
			_touch_idx = -1                 # the press became a drag: no click
		elif _down and e.index == _touch_idx:
			_touch_idx = -1
			_down = false
			accept_event()
			var tw1 := create_tween()
			tw1.tween_property(self, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			if Rect2(Vector2.ZERO, size).grow(24.0).has_point(e.position):
				_fire()
			return
		accept_event()
		return
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			_down = true
			_scroller = null
			_press_pos = e.position
			_note_down(e.position)
			var tw := create_tween()
			tw.tween_property(self, "scale", Vector2(0.94, 0.94), 0.06)
		elif _scroller:
			_scroller = null        # the press became a scroll: no click
		elif _down:
			_down = false
			accept_event()          # before emitting: a handler may free this button (modal rebuild/close)
			var tw2 := create_tween()
			tw2.tween_property(self, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			if Rect2(Vector2.ZERO, size).grow(24.0).has_point(e.position):   # a finger that rolls a little off still counts
				_fire()
			return
		accept_event()
