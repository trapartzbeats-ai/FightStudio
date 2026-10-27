extends Node
## Does the spring chain follow the character? godot --path . res://game/packs/city_breaker/tools/secondary_probe.tscn
func _run(label: String, spec_over: Dictionary, move: bool) -> void:
	var ps := load(CBRoster.model_path("vix")) as PackedScene
	var m := ps.instantiate() as Node3D
	add_child(m)
	var sk: Skeleton3D = m.find_children("*", "Skeleton3D", true, false)[0]
	var ap: AnimationPlayer = m.find_children("*", "AnimationPlayer", true, false)[0]
	ap.play("fightIdle")
	var specs := {"tail": {"enabled": true, "root": "tail", "end": "tail3", "extend": 0.3, "strength": 1.0}}
	for k in spec_over:
		specs["tail"][k] = spec_over[k]
	var sims := CBSecondary.build_specs(sk, specs) if not spec_over.has("off") else {}
	await get_tree().process_frame
	var att := BoneAttachment3D.new()
	att.bone_name = "tail3"
	sk.add_child(att)
	var lo := 99.0
	var hi := -99.0
	for i in 120:
		if move:
			m.position.x = sin(float(i) * 0.15) * 1.5
		await get_tree().physics_frame
		await get_tree().process_frame
		var rel := att.global_position - m.global_position
		lo = minf(lo, rel.x)
		hi = maxf(hi, rel.x)
	print("SECP ", label, " tail3 x relative to the body: min %.3f max %.3f  (spread %.3f)  sims %d" % [lo, hi, hi - lo, sims.size()])
	m.queue_free()
	await get_tree().process_frame

func _ready() -> void:
	await _run("no springs, body moves", {"off": true}, true)
	await _run("springs default, body moves", {}, true)
	await _run("springs soft (stiff .05, grav 1), body moves", {"stiffness": 0.05, "gravity": 1.0, "drag": 0.05}, true)
	await _run("springs soft, body still", {"stiffness": 0.05, "gravity": 1.0, "drag": 0.05}, false)
	get_tree().quit()
