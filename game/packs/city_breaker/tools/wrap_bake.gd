extends SceneTree
## Bakes the Collision Wrap of every City Breaker fighter (RMT Wrap, WRAPS_PLAN.md part 1) from its model:
## data/wraps/<key>.collide.json, rules in data/wraps/wrap_rules.json.
##   godot --headless --path . --script res://game/packs/city_breaker/tools/wrap_bake.gd [-- --who=vix]

const RULES := "res://game/packs/city_breaker/data/wraps/wrap_rules.json"
const OUT := "res://game/packs/city_breaker/data/wraps/%s.collide.json"


## the shared rules with one fighter's overrides (rules.fighters[key]) merged in
static func rules_for(rules: Dictionary, key: String) -> Dictionary:
	var out := rules.duplicate(true)
	out.erase("fighters")
	var over: Dictionary = (rules.get("fighters", {}) as Dictionary).get(key, {})
	for k in over:
		if over[k] is Dictionary and out.get(k) is Dictionary:
			(out[k] as Dictionary).merge(over[k], true)
		else:
			out[k] = over[k]
	return out


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var who := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--who="):
			who = a.substr(6)
	var rules: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(RULES))
	rules.erase("note")
	for key in CBRoster.keys():
		if who != "" and key != who:
			continue
		var ps := load(CBRoster.model_path(key)) as PackedScene
		if ps == null:
			print("%s: no model" % key)
			continue
		var model := ps.instantiate() as Node3D
		root.add_child(model)
		var skel := model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		skel.reset_bone_poses()
		var wrap := RmtWrapFit.fit(model, skel, rules_for(rules, key))
		var f := FileAccess.open(OUT % key, FileAccess.WRITE)
		f.store_string(JSON.stringify(RmtWrapFit.to_json(wrap), " ", false))
		f.close()
		var ids: Array = []
		for p in wrap["pieces"]:
			ids.append("%s %.3f" % [p["id"], float(p["r"])])
		print("%s: %d pieces, %d pairs  |  %s" % [key, (wrap["pieces"] as Array).size(), (wrap["pairs"] as Array).size(), ", ".join(ids)])
		model.queue_free()
		await process_frame
	quit()
