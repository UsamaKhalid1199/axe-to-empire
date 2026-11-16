extends SceneTree
func _init():
	for p in ["wooden_picnic_table","wooden_stool_01","wooden_bowl_01","rock_moss_set_01","stone_fire_pit","wooden_lantern_01"]:
		var n = load("res://assets/models/%s/%s.gltf" % [p,p]).instantiate()
		for c in n.get_children():
			if c is MeshInstance3D: print(p, " ", c.name, " pos=", c.position, " aabb=", c.get_aabb())
		n.free()
	quit()
