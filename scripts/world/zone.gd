class_name Zone
extends Node3D
## Ground pad the player stands on: drop zones, pickup zones, build pads, stations.

var id := ""
var kind := ""            # sell, pile, rack, serve, coins, shop, crew, gate, build
var size := Vector2(2, 2)
var mat: ShaderMaterial
var label: Label3D
var icon: Sprite3D
var tick := 0.0           # caller-owned timer
var occupied := false


func setup(zone_id: String, zone_kind: String, sz: Vector2, color: Color, text := "", icon_path := "", dashed := false) -> Zone:
	id = zone_id
	kind = zone_kind
	size = sz
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = sz
	mi.mesh = pm
	mi.position.y = 0.025
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mat = Art.shader_mat("res://shaders/zone.gdshader")
	mat.set_shader_parameter("size", sz)
	mat.set_shader_parameter("col", color)
	mat.set_shader_parameter("dashed", 1.0 if dashed else 0.0)
	mat.render_priority = -1
	mi.material_override = mat
	add_child(mi)
	label = Label3D.new()
	label.font = UI.font_bold()
	label.font_size = 96
	label.pixel_size = 0.0042
	label.outline_size = 18
	label.outline_modulate = Color(0.08, 0.05, 0.02, 0.85)
	label.modulate = Color(1, 1, 1)
	label.rotation.x = -PI / 2
	label.position = Vector3(0.0, 0.05, 0.0)
	label.shaded = false
	label.double_sided = false
	add_child(label)
	if icon_path != "":
		icon = Sprite3D.new()
		icon.texture = load(icon_path)
		icon.pixel_size = 0.0045
		icon.rotation.x = -PI / 2
		icon.position = Vector3(0, 0.04, -0.15)
		icon.shaded = false
		add_child(icon)
	set_text(text)
	return self


func set_text(t: String) -> void:
	label.text = t
	if icon:
		icon.position.z = -0.22 if t != "" else 0.0
		label.position.z = 0.28 if icon else 0.0


func set_progress(p: float) -> void:
	mat.set_shader_parameter("progress", clampf(p, 0.0, 1.0))


func set_active(on: bool) -> void:
	occupied = on
	mat.set_shader_parameter("active", 1.0 if on else 0.0)


func contains(p: Vector3) -> bool:
	var l := p - global_position
	return absf(l.x) <= size.x * 0.5 and absf(l.z) <= size.y * 0.5
