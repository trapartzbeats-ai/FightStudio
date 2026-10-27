extends Node
## apply_pair puts the victim where the pair says and plays the reaction clip: godot --path . res://game/packs/city_breaker/tools/pair_check.tscn
var _fails := 0
func _ok(name: String, cond: bool, detail: String = "") -> void:
	if not cond:
		_fails += 1
	print("  ", "ok  " if cond else "FAIL", "  ", name, ("  (" + detail + ")") if detail != "" else "")

func _ready() -> void:
	var a := CBFighter.new()
	var b := CBFighter.new()
	add_child(a)
	add_child(b)
	a.setup("vix", 0)
	b.setup("carter", 1)
	await get_tree().process_frame
	a.global_position = Vector3(2.0, 0.0, 0.0)
	a.facing = 1.0
	b.global_position = Vector3(-5.0, 3.0, 0.0)
	b.apply_pair(a, {"reactor_clip": "hit_heavy", "dx": 0.9, "dy": 0.0, "dz": 0.0, "yaw": 180.0, "delay": 0})
	_ok("victim stands 0.9 m in front of the attacker", absf(b.global_position.x - 2.9) < 0.01 and absf(b.global_position.y) < 0.01, str(b.global_position))
	_ok("victim faces the attacker", b.facing == -1.0, str(b.facing))
	_ok("victim plays the reaction clip", b.anim.current_animation == "hit_heavy", b.anim.current_animation)
	_ok("victim is held in stun for the clip", b.stun > 20 and b.state == CBFighter.S.STUN, "stun=%d" % b.stun)
	b.apply_pair(a, {"reactor_clip": "no_such_clip"})
	_ok("an unknown reaction clip is ignored", b.global_position.x > 2.0)
	print("\nPAIR_CHECK failed=%d" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)
