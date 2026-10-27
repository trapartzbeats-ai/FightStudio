extends Node
## Prints a fighter's skeleton: bone, parent, rest origin (model space) and the direction to its first child in bone-local axes.
## godot --path . res://game/packs/city_breaker/tools/rig_probe.tscn -- --fighter=vix
func _ready() -> void:
	var key := "vix"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--fighter="):
			key = a.substr(10)
	var ps := load(CBRoster.model_path(key)) as PackedScene
	var m := ps.instantiate() as Node3D
	add_child(m)
	var sk: Skeleton3D = m.find_children("*", "Skeleton3D", true, false)[0]
	print("RIG ", key, " bones ", sk.get_bone_count())
	for i in sk.get_bone_count():
		var rest := sk.get_bone_global_rest(i)
		var kids := sk.get_bone_children(i)
		var dir := "-"
		if not kids.is_empty():
			var d := rest.basis.inverse() * (sk.get_bone_global_rest(kids[0]).origin - rest.origin)
			dir = "to %s local %s" % [sk.get_bone_name(kids[0]), str(snapped(d, Vector3.ONE * 0.001))]
		print("RIG %2d %-12s parent %-10s at %s  %s" % [i, sk.get_bone_name(i), sk.get_bone_name(sk.get_bone_parent(i)) if sk.get_bone_parent(i) >= 0 else "-", str(snapped(rest.origin, Vector3.ONE * 0.001)), dir])
	var ap: AnimationPlayer = m.find_children("*", "AnimationPlayer", true, false)[0]
	print("RIG clips ", ap.get_animation_list().size(), " ", Array(ap.get_animation_list()).slice(0, 40))
	get_tree().quit()
