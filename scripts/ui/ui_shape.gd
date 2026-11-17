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


func make_clickable() -> UIShape:
	clickable = true
	return self


var _press_pos := Vector2.ZERO
var _down := false


var _touch_idx := -1


func _gui_input(e: InputEvent) -> void:
	if not clickable:
		return
	# extra fingers (index >= 1) get no emulated mouse events, so handle them here
	# (e.g. tapping a button with one thumb while the other still holds the joystick)
	if e is InputEventScreenTouch and e.index >= 1:
		if e.pressed:
			_touch_idx = e.index
			_down = true
			_press_pos = e.position
			var tw0 := create_tween()
			tw0.tween_property(self, "scale", Vector2(0.94, 0.94), 0.06)
		elif _down and e.index == _touch_idx:
			_touch_idx = -1
			_down = false
			accept_event()
			var tw1 := create_tween()
			tw1.tween_property(self, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			if Rect2(Vector2.ZERO, size).grow(24.0).has_point(e.position):
				if disabled:
					Sfx.play("click", -10.0, 0.7)
				else:
					Sfx.play("click")
					pressed.emit()
			return
		accept_event()
		return
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			_down = true
			_press_pos = e.position
			var tw := create_tween()
			tw.tween_property(self, "scale", Vector2(0.94, 0.94), 0.06)
		elif _down:
			_down = false
			accept_event()          # before emitting: a handler may free this button (modal rebuild/close)
			var tw2 := create_tween()
			tw2.tween_property(self, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			if Rect2(Vector2.ZERO, size).grow(24.0).has_point(e.position):   # a finger that rolls a little off still counts
				if disabled:
					Sfx.play("click", -10.0, 0.7)
				else:
					Sfx.play("click")
					pressed.emit()
			return
		accept_event()
