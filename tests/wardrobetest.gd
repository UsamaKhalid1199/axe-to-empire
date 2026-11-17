extends SceneTree
## Wardrobe: catalog, buy/equip against Game.profile, star gate, and dressing a player rig.
func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var g = root.get_node("Game")
	g.saving_enabled = false
	var fails := 0
	g.profile = {"owned": ["shirt_orange", "hat_none", "pants_dark"], "equipped": {"shirt": "shirt_orange", "hat": "hat_none", "pants": "pants_dark"}}
	# catalog
	var cat := Wardrobe.catalog()
	if cat.size() < 15: print("FAIL catalog size ", cat.size()); fails += 1
	for s in Wardrobe.SLOTS:
		if Wardrobe.items_for(s).size() < 4: print("FAIL few items for ", s); fails += 1
	var ids := {}
	for it in cat:
		if ids.has(it.id): print("FAIL duplicate id ", it.id); fails += 1
		ids[it.id] = true
		if not it.slot in Wardrobe.SLOTS: print("FAIL bad slot ", it.id); fails += 1
		if (it.get("color", []) as Array).size() != 3: print("FAIL bad color ", it.id); fails += 1
	for d in Wardrobe.DEFAULTS.values():
		if Wardrobe.item(d).is_empty(): print("FAIL missing default ", d); fails += 1
	if Wardrobe.money(250000) != "250,000" or Wardrobe.money(500) != "500": print("FAIL money fmt ", Wardrobe.money(250000)); fails += 1
	# hats stay low-poly
	for it in Wardrobe.items_for("hat"):
		var t := Wardrobe.tri_count(Wardrobe.hat_mesh(it))
		if t > 200: print("FAIL hat tris ", it.id, " ", t); fails += 1
	# cash gate + buy
	g.coins = 100
	var r: String = Wardrobe.can_buy("pants_khaki")
	if r != "Need $2,000": print("FAIL cash gate reason '", r, "'"); fails += 1
	if Wardrobe.buy("pants_khaki"): print("FAIL bought without cash"); fails += 1
	g.coins = 5000
	var changed := [0]
	g.profile_changed.connect(func(): changed[0] += 1)
	if not Wardrobe.buy("pants_khaki"): print("FAIL buy"); fails += 1
	if g.coins != 3000: print("FAIL coins ", g.coins); fails += 1
	if not Wardrobe.owned("pants_khaki"): print("FAIL not owned"); fails += 1
	if Wardrobe.equipped("pants") != "pants_khaki": print("FAIL not equipped"); fails += 1
	if changed[0] < 1: print("FAIL no profile_changed"); fails += 1
	if Wardrobe.can_buy("pants_khaki") != "Owned": print("FAIL owned reason"); fails += 1
	if Wardrobe.buy("pants_khaki"): print("FAIL bought twice"); fails += 1
	# star gate (chef hat: stars only)
	g.coins = 10000000
	var need := Wardrobe.stars_needed("hat_chef")
	if g.total_stars() < need:
		r = Wardrobe.can_buy("hat_chef")
		if r != "Need %d ★" % need: print("FAIL star gate reason '", r, "'"); fails += 1
		if Wardrobe.buy("hat_chef"): print("FAIL star gate let it through"); fails += 1
		if Wardrobe.owned("hat_chef"): print("FAIL owned gated hat"); fails += 1
	else:
		print("NOTE stars already >= ", need, ", gate not exercised")
	# equip back / equip unowned
	if not Wardrobe.equip("pants_dark"): print("FAIL equip default"); fails += 1
	if Wardrobe.equip("shirt_gold_flannel"): print("FAIL equipped unowned"); fails += 1
	if Wardrobe.equipped("shirt") != "shirt_orange": print("FAIL shirt changed"); fails += 1
	Wardrobe.buy("hat_beanie")
	Wardrobe.buy("shirt_flannel_red")
	# rig: player auto-dresses and follows profile_changed
	var rig := CharacterRig.new()
	root.add_child(rig)
	rig.outfit("player")
	await process_frame
	if not rig.wears_outfit: print("FAIL rig not in outfit mode"); fails += 1
	if rig._hat == null or not rig._hat.visible: print("FAIL beanie not shown"); fails += 1
	var si: int = rig.body.mesh.surface_find_by_name("Shirt")
	if not (rig.body.get_surface_override_material(si) is ShaderMaterial): print("FAIL shirt not recoloured"); fails += 1
	if not (rig.body.get_surface_override_material(rig.body.mesh.surface_find_by_name("Vest")) is ShaderMaterial): print("FAIL flannel torso not recoloured"); fails += 1
	Wardrobe.equip("hat_none")
	Wardrobe.equip("shirt_orange")
	if rig._hat.visible: print("FAIL hat still visible after hat_none"); fails += 1
	if rig.body.mesh.surface_find_by_name("Vest") < 0: print("FAIL vest missing for hi-vis"); fails += 1
	# every item applies cleanly (shop preview path)
	for it in cat:
		Wardrobe.apply(rig, {it.slot: it.id})
	# crew stay untouched
	var crew := CharacterRig.new()
	root.add_child(crew)
	crew.outfit("lumberjack", 1)
	if crew.wears_outfit or crew._hat != null: print("FAIL crew wears outfit"); fails += 1
	await process_frame
	rig.queue_free(); crew.queue_free()
	await process_frame
	for it in Wardrobe.items_for("hat"): print("  hat ", it.id, " tris=", Wardrobe.tri_count(Wardrobe.hat_mesh(it)))
	print("WARDROBE fails=", fails, " items=", cat.size(), " stars=", g.total_stars())
	quit()
