class_name CBSecondary
extends RefCounted
## Secondary motion: tails, ears, fingers and other bone chains that MOVE BY THEMSELVES from how the character moves (inertia, drag,
## gravity, a spring back to the animated pose) without being animated. Godot's SpringBoneSimulator3D does the physics; this file
## reads the chains from data/secondary.json and sets them up per fighter, with the stiffness / drag / gravity of EVERY joint
## separately, so a chain can be stiff at the root and loose at the tip (the same idea as the jewelry chains: fixed bone length,
## gravity, damping, no animation needed).
##
##   {"chains": {"tail": {"enabled": true, "root": "tail", "end": "tail3", "extend": 0.3, "strength": 1.0,
##                        "stiffness": [1.2, 0.8, 0.4], "drag": [0.2, 0.25, 0.3], "gravity": [0.4, 0.5, 0.6]}},
##    "fighters": {"vix": {"tail": {"strength": 1.4}}}}
##
## strength = how much of the simulation is mixed over the animation (0 = off, 1 = full); stiffness = how hard a joint returns to the
## animated pose (higher = stiffer); drag = how fast its swing dies out; gravity = pull (down). Arrays give one value per joint from
## root to end; a single number applies to all joints. `extend` simulates a tip beyond the end bone (metres, rig units).
## Studio: SECONDARY tab. Turn it all off with the "secondary" setting (Options).

const DATA := "res://game/packs/city_breaker/data/secondary.json"
static var _data: Dictionary = {}


static func data(force: bool = false) -> Dictionary:
	if _data.is_empty() or force:
		_data = {"chains": {}, "fighters": {}}
		var f := FileAccess.open(DATA, FileAccess.READ)
		if f != null:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			f.close()
			if typeof(parsed) == TYPE_DICTIONARY:
				_data = parsed
	return _data


## one chain's spec for one fighter: the shared chain with that fighter's overrides on top
static func spec(key: String, chain: String) -> Dictionary:
	var d := data()
	var out: Dictionary = (d.get("chains", {}) as Dictionary).get(chain, {}).duplicate(true)
	var over: Dictionary = ((d.get("fighters", {}) as Dictionary).get(key, {}) as Dictionary).get(chain, {})
	for k in over:
		out[k] = over[k]
	return out


static func all_specs(key: String) -> Dictionary:
	var out: Dictionary = {}
	for c in (data().get("chains", {}) as Dictionary):
		out[c] = spec(key, str(c))
	return out


static func save_data(d: Dictionary) -> int:
	var f := FileAccess.open(DATA, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(d, "  "))
	f.close()
	_data = d
	return OK


## the value for joint j from a number or an array (the last entry repeats)
static func at(v: Variant, j: int, fallback: float) -> float:
	if v is Array:
		var a: Array = v
		return float(a[mini(j, a.size() - 1)]) if not a.is_empty() else fallback
	if v == null:
		return fallback
	return float(v)


## set up one SpringBoneSimulator3D per enabled chain under the skeleton; returns {chain: node}
static func build(skel: Skeleton3D, key: String) -> Dictionary:
	if not bool(data().get("enabled", true)):
		return {}
	return build_specs(skel, all_specs(key))


static func build_specs(skel: Skeleton3D, specs: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	if skel == null:
		return out
	for name in specs:
		var sp: Dictionary = specs[name]
		if not bool(sp.get("enabled", true)):
			continue
		if skel.find_bone(str(sp.get("root", ""))) < 0 or skel.find_bone(str(sp.get("end", ""))) < 0:
			continue
		var sim := SpringBoneSimulator3D.new()
		sim.name = "spring_" + str(name)
		skel.add_child(sim)
		sim.setting_count = 1
		sim.set_root_bone_name(0, str(sp["root"]))
		sim.set_end_bone_name(0, str(sp["end"]))
		var ext := float(sp.get("extend", 0.0))
		sim.set_extend_end_bone(0, ext > 0.0)
		if ext > 0.0:
			sim.set_end_bone_direction(0, SpringBoneSimulator3D.BONE_DIRECTION_FROM_PARENT)
			sim.set_end_bone_length(0, ext)
		sim.set_individual_config(0, true)
		for j in sim.get_joint_count(0):
			sim.set_joint_stiffness(0, j, at(sp.get("stiffness"), j, 1.0))
			sim.set_joint_drag(0, j, at(sp.get("drag"), j, 0.2))
			sim.set_joint_gravity(0, j, at(sp.get("gravity"), j, 0.3))
			sim.set_joint_gravity_direction(0, j, Vector3(0.0, -1.0, 0.0))
			sim.set_joint_radius(0, j, float(sp.get("radius", 0.0)))
			sim.set_joint_rotation_axis(0, j, SpringBoneSimulator3D.ROTATION_AXIS_ALL)
		sim.influence = clampf(float(sp.get("strength", 1.0)), 0.0, 1.0)
		out[name] = sim
	return out


static func clear(skel: Skeleton3D) -> void:
	for c in skel.get_children():
		if c is SpringBoneSimulator3D:
			skel.remove_child(c)
			c.queue_free()


## after a teleport / respawn the chains must not swing across the stage
static func reset(skel: Skeleton3D) -> void:
	if skel == null:
		return
	for c in skel.get_children():
		if c is SpringBoneSimulator3D:
			(c as SpringBoneSimulator3D).reset()
