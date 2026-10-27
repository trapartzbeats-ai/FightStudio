extends Node
## The hit reaction pushes the part that was hit, fades with distance, and settles: godot --path . res://game/packs/city_breaker/tools/react_check.tscn
var _fails := 0
func _ok(name: String, cond: bool, detail: String = "") -> void:
	if not cond:
		_fails += 1
	print("  ", "ok  " if cond else "FAIL", "  ", name, ("  (" + detail + ")") if detail != "" else "")

func _pos(att: BoneAttachment3D) -> Vector3:
	return att.global_position

func _ready() -> void:
	var ps := load(CBRoster.model_path("vix")) as PackedScene
	var m := ps.instantiate() as Node3D
	add_child(m)
	var sk: Skeleton3D = m.find_children("*", "Skeleton3D", true, false)[0]
	var ap: AnimationPlayer = m.find_children("*", "AnimationPlayer", true, false)[0]
	ap.play("fightIdle")
	ap.seek(0.3, true)
	ap.pause()   # a frozen pose, so only the reaction moves things
	var atts := {}
	for b in ["head", "chest", "footL", "handR", "hips"]:
		var a := BoneAttachment3D.new()
		a.bone_name = b
		sk.add_child(a)
		atts[b] = a
	var react := CBHitReact.attach(sk, "vix")
	for i in 20:
		await get_tree().process_frame
	var base := {}
	for b in atts:
		base[b] = _pos(atts[b])
	# a punch to the head from +X pushes the head toward +X
	var head_p: Vector3 = base["head"]
	react.impact(head_p + Vector3(-0.1, 0.0, 0.0), Vector3(1, 0, 0), 0.8)
	var peak := {}
	for b in atts:
		peak[b] = 0.0
	for i in 40:
		await get_tree().process_frame
		for b in atts:
			var d: Vector3 = _pos(atts[b]) - base[b]
			peak[b] = maxf(peak[b], d.length())
	_ok("the head is pushed", peak["head"] > 0.05, "%.3f m" % peak["head"])
	_ok("the chest follows, less than the head", peak["chest"] > 0.004 and peak["chest"] < peak["head"], "chest %.3f head %.3f" % [peak["chest"], peak["head"]])
	_ok("the foot, far from the blow, barely moves", peak["footL"] < peak["head"] * 0.3, "foot %.3f" % peak["footL"])
	# it settles
	for i in 150:
		await get_tree().process_frame
	var back: float = (_pos(atts["head"]) - base["head"]).length()
	_ok("the spring settles back to the animation", back < 0.02 and not react.is_busy(), "%.4f m, busy=%s" % [back, react.is_busy()])
	# recoil: the striking hand kicks back
	var hp: Vector3 = _pos(atts["handR"])
	react.recoil("handR", Vector3(-1, 0, 0), 0.9)
	var rp := 0.0
	for i in 30:
		await get_tree().process_frame
		rp = maxf(rp, (_pos(atts["handR"]) - hp).length())
	_ok("the attacker's hand recoils", rp > 0.02, "%.3f m" % rp)
	react.clear_state()
	print("\nREACT_CHECK failed=%d" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)
