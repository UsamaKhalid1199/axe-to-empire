class_name LoadingScreen
extends CanvasLayer
## Full-screen loader: golden-hour key art of the camp (slow zoom), rising embers, gold logo,
## and a frosted card with status, glowing progress bar and a tip.
## The boot splash (assets/splash.png) is this screen without the card, so launch flows straight in.

const GOLD := Color("#FFC94A")
const GOLD_DEEP := Color("#E8891A")
const CREAM := Color(1, 0.95, 0.86)
const TIPS := [
	"Stand next to a tree to swing your axe.",
	"Seated guests tip extra. Build picnic tables early.",
	"A bigger backpack means fewer trips to the woodpile.",
	"Hire a lumberjack to keep the woodpile full while you serve.",
	"The chainsaw cuts while you run.",
	"Stop on a pad to pay for it. Walking across costs nothing.",
	"Hotter fires and a better menu bring more hungry hikers.",
	"Happy guests pay 20% more. Don't keep them waiting!",
	"Stand at the counter: guests you serve yourself pay 25% more.",
	"Golden trees are worth a fortune. Chop them before they fade.",
	"Big upgrades take time to build. The place keeps running meanwhile.",
	"Your other places keep earning while you play. Walk over to collect.",
	"Cash waits on each counter for up to 20 minutes. Visit to collect it.",
	"Win the Big Day, then buy the land next door and expand.",
	"Three stars per place: every star adds income everywhere.",
	"A full line turns guests away. More fires and upgrades fix that.",
]

var card: Control
var _art: TextureRect
var _bar_fill: Panel
var _bar_glow: Panel
var _bar_back: Panel
var _status: Label
var _pct: Label
var _shown := 0.0
var _t := 0.0
var target := 0.0


func _init() -> void:
	layer = 100


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.clip_contents = true
	add_child(root)

	var bg := ColorRect.new()
	bg.color = Color("#120B06")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	_art = TextureRect.new()
	_art.texture = load("res://assets/keyart.png")
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_art.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(_art)
	# darken top (logo) and bottom (card) so text always reads
	root.add_child(_shade(0.0, 0.42, Color(0.07, 0.04, 0.02, 0.88), Color(0.07, 0.04, 0.02, 0.0)))
	root.add_child(_shade(0.5, 1.0, Color(0.06, 0.035, 0.02, 0.0), Color(0.06, 0.035, 0.02, 0.95)))
	root.add_child(_embers())

	# logo
	var logo := VBoxContainer.new()
	logo.set_anchors_preset(Control.PRESET_TOP_WIDE)
	logo.offset_top = 120
	logo.offset_bottom = 420
	logo.add_theme_constant_override("separation", -22)
	root.add_child(logo)
	var ic := UI.icon("axe", 120)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ic.custom_minimum_size = Vector2(120, 120)
	logo.add_child(ic)
	for line in [["AXE TO", 64], ["EMPIRE", 112]]:
		var l := UI.label(line[0], line[1], GOLD, UI.font_bold(), HORIZONTAL_ALIGNMENT_CENTER)
		l.add_theme_constant_override("outline_size", 14)
		l.add_theme_color_override("font_outline_color", Color(0.16, 0.07, 0.0, 1))
		l.add_theme_constant_override("shadow_offset_y", 8)
		l.add_theme_constant_override("shadow_outline_size", 14)
		l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
		l.add_theme_constant_override("line_spacing", -18)
		logo.add_child(l)
	var tag := PanelContainer.new()
	var ts := StyleBoxFlat.new()
	ts.bg_color = Color(0.08, 0.045, 0.02, 0.72)
	ts.border_color = Color(1, 0.8, 0.4, 0.35)
	ts.set_border_width_all(2)
	ts.set_corner_radius_all(20)
	ts.content_margin_left = 22
	ts.content_margin_right = 22
	ts.content_margin_top = 6
	ts.content_margin_bottom = 6
	tag.add_theme_stylebox_override("panel", ts)
	tag.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	tag.add_child(UI.label("CHOP  ·  COOK  ·  BUILD", 24, CREAM, UI.font_semi(), HORIZONTAL_ALIGNMENT_CENTER))
	logo.add_child(_gap(30))
	logo.add_child(tag)

	# bottom card
	card = PanelContainer.new()
	var cs := StyleBoxFlat.new()
	cs.bg_color = Color(0.07, 0.045, 0.025, 0.78)
	cs.border_color = Color(1, 1, 1, 0.12)
	cs.set_border_width_all(2)
	cs.set_corner_radius_all(26)
	cs.shadow_color = Color(0, 0, 0, 0.35)
	cs.shadow_size = 18
	cs.content_margin_left = 30
	cs.content_margin_right = 30
	cs.content_margin_top = 24
	cs.content_margin_bottom = 26
	card.add_theme_stylebox_override("panel", cs)
	card.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	card.offset_left = 40
	card.offset_right = -40
	card.offset_top = -300
	card.offset_bottom = -110
	root.add_child(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	card.add_child(col)
	var row := HBoxContainer.new()
	_status = UI.label("Loading…", 28, CREAM, UI.font_semi())
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_status)
	_pct = UI.label("0%", 30, GOLD, UI.font_bold())
	row.add_child(_pct)
	col.add_child(row)

	_bar_back = Panel.new()
	_bar_back.custom_minimum_size = Vector2(0, 26)
	_bar_back.add_theme_stylebox_override("panel", _flat(Color(0, 0, 0, 0.55), 13, Color(1, 0.85, 0.5, 0.22), 2))
	col.add_child(_bar_back)
	_bar_glow = Panel.new()
	_bar_glow.add_theme_stylebox_override("panel", _flat(Color(1.0, 0.7, 0.2, 0.0), 14, Color(0, 0, 0, 0), 0, Color(1.0, 0.65, 0.15, 0.55), 14))
	_bar_back.add_child(_bar_glow)
	_bar_fill = Panel.new()
	_bar_fill.add_theme_stylebox_override("panel", _flat(GOLD, 9))
	_bar_fill.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	_bar_back.add_child(_bar_fill)
	var deep := ColorRect.new()
	deep.color = Color(GOLD_DEEP, 0.5)
	deep.position = Vector2(0, 10)
	deep.size = Vector2(4000, 10)
	_bar_fill.add_child(deep)
	var shine := ColorRect.new()
	shine.color = Color(1, 1, 1, 0.28)
	shine.position = Vector2(0, 2)
	shine.size = Vector2(4000, 6)
	_bar_fill.add_child(shine)

	col.add_child(_gap(4))
	var tip_row := HBoxContainer.new()
	tip_row.add_theme_constant_override("separation", 12)
	var badge := PanelContainer.new()
	var bs := _flat(GOLD, 8)
	bs.content_margin_left = 10
	bs.content_margin_right = 10
	bs.content_margin_top = 1
	bs.content_margin_bottom = 1
	badge.add_theme_stylebox_override("panel", bs)
	badge.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	badge.add_child(UI.label("TIP", 20, Color("#3A1F05"), UI.font_bold()))
	tip_row.add_child(badge)
	var tip := UI.label(TIPS[randi() % TIPS.size()], 23, Color(1, 0.93, 0.82, 0.8), UI.font_ui(500))
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tip_row.add_child(tip)
	col.add_child(tip_row)

	var ver := UI.label("v" + str(ProjectSettings.get_setting("application/config/version", "")), 18, Color(1, 1, 1, 0.3), UI.font_ui(500), HORIZONTAL_ALIGNMENT_CENTER)
	ver.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	ver.offset_top = -56
	ver.offset_bottom = -30
	root.add_child(ver)


func _flat(c: Color, r: int, border := Color(0, 0, 0, 0), bw := 0, shadow := Color(0, 0, 0, 0), ss := 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(r)
	s.border_color = border
	s.set_border_width_all(bw)
	s.shadow_color = shadow
	s.shadow_size = ss
	return s


func _shade(a0: float, a1: float, c0: Color, c1: Color) -> TextureRect:
	var g := Gradient.new()
	g.set_color(0, c0)
	g.set_color(1, c1)
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0.5, 0)
	gt.fill_to = Vector2(0.5, 1)
	gt.width = 4
	gt.height = 128
	var tr := TextureRect.new()
	tr.texture = gt
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.anchor_left = 0
	tr.anchor_right = 1
	tr.anchor_top = a0
	tr.anchor_bottom = a1
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr


func _embers() -> Control:
	var holder := Control.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var p := CPUParticles2D.new()
	p.amount = 26
	p.lifetime = 5.0
	p.preprocess = 5.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(320, 20)
	p.direction = Vector2(0, -1)
	p.spread = 18
	p.gravity = Vector2(0, -12)
	p.initial_velocity_min = 40
	p.initial_velocity_max = 90
	p.scale_amount_min = 2.0
	p.scale_amount_max = 4.5
	p.angular_velocity_min = -40
	p.angular_velocity_max = 40
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.75, 0.3, 0.0))
	ramp.add_point(0.15, Color(1.0, 0.7, 0.25, 0.9))
	ramp.set_color(1, Color(1.0, 0.35, 0.05, 0.0))
	p.color_ramp = ramp
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	p.material = mat
	holder.add_child(p)
	holder.resized.connect(func(): p.position = Vector2(holder.size.x * 0.5, holder.size.y * 0.72))
	return holder


func _gap(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


func set_status(text: String, progress: float) -> void:
	_status.text = text
	target = clampf(progress, 0.0, 1.0)


func _process(delta: float) -> void:
	_t += delta
	_shown = move_toward(_shown, target, delta * 1.6)
	_draw_bar()
	# slow cinematic push-in on the key art
	var z := 1.0 + minf(_t, 30.0) * 0.0025
	_art.pivot_offset = _art.size * Vector2(0.45, 0.55)
	_art.scale = Vector2(z, z)


func _draw_bar() -> void:
	var w := maxf(0.0, _bar_back.size.x - 8.0)
	var fw := maxf(18.0, w * _shown)
	_bar_fill.position = Vector2(4, 4)
	_bar_fill.size = Vector2(fw, 18)
	_bar_glow.position = _bar_fill.position
	_bar_glow.size = _bar_fill.size
	_bar_glow.modulate.a = 0.6 + 0.4 * sin(_t * 3.0)
	_pct.text = "%d%%" % int(round(_shown * 100.0))


## Snap the bar to the target (used right before a long blocking step).
func sync() -> void:
	_shown = target
	_draw_bar()


func finish() -> void:
	set_status("Ready!", 1.0)
	sync()
	var tw := create_tween()
	for c in get_children():
		tw.parallel().tween_property(c, "modulate:a", 0.0, 0.5).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(queue_free)
