class_name UI
## Shared UI helpers: fonts, colors, labels, icons, buttons.

const GOLD := Color("#F5C35B")
const GOLD_LIGHT := Color("#FFD978")
const INK := Color("#3A1F00")
const TEXT := Color(1, 1, 1, 0.96)
const MUTED := Color(1, 1, 1, 0.62)
const GREEN := Color("#8EE07A")
const RED := Color("#FF7A6A")
const CASH := Color("#7BE38A")          # green money

static var _fonts: Dictionary = {}


static func font_bold() -> Font:
	if not _fonts.has("b"):
		_fonts.b = load("res://assets/fonts/BarlowCondensed-Bold.ttf")
	return _fonts.b


static func font_semi() -> Font:
	if not _fonts.has("s"):
		_fonts.s = load("res://assets/fonts/BarlowCondensed-SemiBold.ttf")
	return _fonts.s


static func font_ui(weight := 500) -> Font:
	var k := "i%d" % weight
	if not _fonts.has(k):
		var fv := FontVariation.new()
		fv.base_font = load("res://assets/fonts/Inter.ttf")
		fv.variation_opentype = {"wght": weight}
		_fonts[k] = fv
	return _fonts[k]


static func theme() -> Theme:
	var t := Theme.new()
	t.default_font = font_ui(500)
	t.default_font_size = 24
	t.set_color("font_color", "Label", TEXT)
	return t


## Keeps a one-line label inside `max_w` pixels: shrinks the font down to `min_size`, then wraps.
static func fit(l: Label, max_w: float, size: int, min_size: int) -> void:
	var f: Font = l.get_theme_font("font")
	var s := size
	while s > min_size and f.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, s).x > max_w:
		s -= 2
	l.add_theme_font_size_override("font_size", s)
	var w := f.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, s).x
	if w > max_w:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = max_w
	else:
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
		l.custom_minimum_size.x = 0
	l.size = Vector2.ZERO


## After fit(): a wrapped label gets the narrowest width that keeps the same number of lines, so the lines
## come out even and the last one is never a lone word.
static func balance(l: Label) -> void:
	if l.autowrap_mode == TextServer.AUTOWRAP_OFF or l.custom_minimum_size.x <= 0.0:
		return
	var f: Font = l.get_theme_font("font")
	var fs: int = l.get_theme_font_size("font_size")
	var max_w := l.custom_minimum_size.x
	var n := _wrap_lines(l.text, f, fs, max_w)
	var lo := max_w * 0.4
	var hi := max_w
	for i in 12:
		var mid := (lo + hi) * 0.5
		if _wrap_lines(l.text, f, fs, mid) <= n:
			hi = mid
		else:
			lo = mid
	l.custom_minimum_size.x = minf(max_w, ceilf(hi) + 4.0)
	l.size = Vector2.ZERO


## Greedy word wrap: how many lines `text` takes at width `w`.
static func _wrap_lines(text: String, f: Font, fs: int, w: float) -> int:
	var lines := 1
	var cur := ""
	for word in text.split(" ", false):
		var t := word if cur == "" else cur + " " + word
		if cur != "" and f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > w:
			lines += 1
			cur = word
		else:
			cur = t
	return lines


static func label(text: String, size := 24, color := TEXT, font: Font = null, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if font:
		l.add_theme_font_override("font", font)
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func num(text: String, size := 34, color := TEXT) -> Label:
	var l := label(text, size, color, font_bold())
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.35))
	l.add_theme_constant_override("shadow_offset_y", 2)
	return l


static func icon(name: String, px := 48) -> TextureRect:
	var r := TextureRect.new()
	r.texture = load("res://assets/icons/%s.svg" % name)
	r.custom_minimum_size = Vector2(px, px)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


static func hbox(sep := 10) -> HBoxContainer:
	var b := HBoxContainer.new()
	b.add_theme_constant_override("separation", sep)
	b.alignment = BoxContainer.ALIGNMENT_CENTER
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


static func vbox(sep := 10) -> VBoxContainer:
	var b := VBoxContainer.new()
	b.add_theme_constant_override("separation", sep)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


## Gold/green/red pill button with optional icon and text.
static func button(text: String, style := "gold", icon_name := "", size := 30, min_w := 0.0) -> UIShape:
	var b := UIShape.new(style, 18.0, Vector4(22, 10, 22, 10)).make_clickable()
	var row := hbox(8)
	if icon_name != "":
		row.add_child(icon(icon_name, int(size * 1.15)))
	var col := INK if style in ["gold", "cream"] else Color.WHITE
	var l := label(text, size, col, font_bold(), HORIZONTAL_ALIGNMENT_CENTER)
	l.name = "Text"
	row.add_child(l)
	b.add_child(row)
	b.custom_minimum_size = Vector2(min_w, 68.0)
	return b


static func set_button_text(b: UIShape, text: String) -> void:
	var l: Label = b.find_child("Text", true, false)
	if l:
		l.text = text


static func fmt(n: float) -> String:
	var v := absf(n)
	for u in [[1e15, "Q"], [1e12, "T"], [1e9, "B"], [1e6, "M"]]:
		if v >= u[0]:
			return _trim("%.2f" % (n / u[0])) + u[1]
	if v >= 10_000:
		return _trim("%.1f" % (n / 1000.0)) + "K"
	if v >= 1000:
		return "%d,%03d" % [int(n) / 1000, int(n) % 1000]
	return str(int(n))


## "16.0" -> "16", "3.40" -> "3.4"
static func _trim(s: String) -> String:
	if s.contains("."):
		s = s.rstrip("0").rstrip(".")
	return s


## Money as shown to players: $1,250 · $12.5K · $3.40M
static func cash(n: float) -> String:
	return ("-$" if n < 0 else "$") + fmt(absf(n))


static func progress_bar(w: float, h: float) -> ProgressBar:
	var p := ProgressBar.new()
	p.custom_minimum_size = Vector2(w, h)
	p.show_percentage = false
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.4)
	bg.set_corner_radius_all(int(h / 2))
	var fg := StyleBoxFlat.new()
	fg.bg_color = GOLD
	fg.set_corner_radius_all(int(h / 2))
	p.add_theme_stylebox_override("background", bg)
	p.add_theme_stylebox_override("fill", fg)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p
