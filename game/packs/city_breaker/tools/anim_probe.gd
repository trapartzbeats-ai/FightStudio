extends Node
## Prints how a fighter's clips address the skeleton (track paths / types) and the rest rotations: godot --path . res://game/packs/city_breaker/tools/anim_probe.tscn
func _ready() -> void:
	var ps := load(CBRoster.model_path("vix")) as PackedScene
	var m := ps.instantiate() as Node3D
	add_child(m)
	var ap: AnimationPlayer = m.find_children("*", "AnimationPlayer", true, false)[0]
	var sk: Skeleton3D = m.find_children("*", "Skeleton3D", true, false)[0]
	print("PROBE ap path ", m.get_path_to(ap), " root of anims ", ap.root_node, " skeleton path ", m.get_path_to(sk))
	var a := ap.get_animation("jab")
	print("PROBE jab tracks ", a.get_track_count(), " len ", a.length)
	for i in mini(8, a.get_track_count()):
		print("PROBE track ", i, " ", a.track_get_type(i), " ", a.track_get_path(i), " keys ", a.track_get_key_count(i))
	var g := ap.get_animation("guard")
	print("PROBE guard tracks ", g.get_track_count(), " ", g.track_get_path(0), " type ", g.track_get_type(0), " interp ", g.track_get_interpolation_type(0))
	print("PROBE libs ", ap.get_animation_library_list())
	var i := sk.find_bone("kneeL")
	print("PROBE kneeL rest ", sk.get_bone_rest(i), " pose ", sk.get_bone_pose(i))
	get_tree().quit()
