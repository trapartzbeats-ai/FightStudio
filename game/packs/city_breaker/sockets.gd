class_name CBSockets
extends RefCounted
## Effect sockets for a fighter (data/sockets.json): named points on bones. Each is a Node3D under a BoneAttachment3D, so it
## follows the animation by itself; "ground" sockets are computed on demand (the bone's x/z on the floor under the fighter).
##   var n := CBSockets.build(fighter)        # {name: Node3D | spec}
##   fighter.socket("fist_R")                 # Node3D to parent a looping effect to
##   fighter.socket_pos("ground_L")           # world position for a one-shot burst

const DATA := "res://game/packs/city_breaker/data/sockets.json"
static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open(DATA, FileAccess.READ)
		if f != null:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			f.close()
			if typeof(parsed) == TYPE_DICTIONARY:
				_data = parsed
	return _data


## spec for one socket on one fighter: the shared spec with that fighter's overrides on top
static func spec(key: String, name: String) -> Dictionary:
	var d := data()
	var out: Dictionary = (d.get("sockets", {}) as Dictionary).get(name, {}).duplicate()
	var over: Dictionary = ((d.get("fighters", {}) as Dictionary).get(key, {}) as Dictionary).get(name, {})
	for k in over:
		out[k] = over[k]
	return out


static func build(fighter: Node3D, skel: Skeleton3D, key: String, markers: bool = false) -> Dictionary:
	var specs: Dictionary = {}
	for name in (data().get("sockets", {}) as Dictionary):
		specs[name] = spec(key, str(name))
	return build_specs(skel, specs, markers)


## build sockets from explicit specs {name: spec} (the Studio edits specs live and rebuilds)
static func build_specs(skel: Skeleton3D, specs: Dictionary, markers: bool = false) -> Dictionary:
	var out: Dictionary = {}
	if skel == null:
		return out
	for name in specs:
		var sp: Dictionary = specs[name]
		var bone: int = skel.find_bone(str(sp.get("bone", "")))
		if bone < 0:
			push_warning("CBSockets: no bone %s for socket %s" % [sp.get("bone", ""), name])
			continue
		if bool(sp.get("ground", false)):
			out[name] = sp   # resolved on demand
			continue
		var att := BoneAttachment3D.new()
		att.name = "sock_" + str(name)
		att.bone_name = str(sp["bone"])
		skel.add_child(att)
		var node := Node3D.new()
		node.name = str(name)
		node.position = offset(skel, bone, sp)
		att.add_child(node)
		if markers:
			var mi := MeshInstance3D.new()
			mi.name = "marker"
			var sph := SphereMesh.new()
			sph.radius = 0.035
			sph.height = 0.07
			mi.mesh = sph
			var mat := StandardMaterial3D.new()
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.albedo_color = Color(1.0, 0.2, 0.9)
			mat.no_depth_test = true
			mi.material_override = mat
			node.add_child(mi)
		out[name] = node
	return out


## A socket's ZONE: {"zone": {"radius": 0.25, "falloff": "smooth"}} in its spec is an area around the point. Effects scatter inside it
## and the Studio's proportional pose uses it, so one sub-point can move everything around it.
static func zone_radius(sp: Dictionary) -> float:
	return float((sp.get("zone", {}) as Dictionary).get("radius", 0.0))


static func zone_falloff(sp: Dictionary) -> String:
	return str((sp.get("zone", {}) as Dictionary).get("falloff", "smooth"))


## strength 1 at the centre -> 0 at the edge: t = distance / radius (clamped)
static func falloff(kind: String, t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	match kind:
		"linear":
			return 1.0 - t
		"sharp":
			return (1.0 - t) * (1.0 - t)
		"constant":
			return 1.0
		_:
			return 1.0 - t * t * (3.0 - 2.0 * t)


## remove the BoneAttachment3D sockets from a skeleton (before a rebuild)
static func clear(skel: Skeleton3D) -> void:
	for c in skel.get_children():
		if c is BoneAttachment3D and str(c.name).begins_with("sock_"):
			skel.remove_child(c)
			c.queue_free()


static func save_data(d: Dictionary) -> int:
	var f := FileAccess.open(DATA, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(d, "  "))
	f.close()
	_data = d
	return OK


## the socket's offset in its bone's own axes, from the rest pose: toward the `to` bone by `t`, plus `extra`
static func offset(skel: Skeleton3D, bone: int, sp: Dictionary) -> Vector3:
	var o := Vector3.ZERO
	var to_name := str(sp.get("to", ""))
	if to_name != "":
		var to_idx := skel.find_bone(to_name)
		if to_idx >= 0:
			var rest := skel.get_bone_global_rest(bone)
			o = rest.basis.inverse() * (skel.get_bone_global_rest(to_idx).origin - rest.origin) * float(sp.get("t", 0.0))
	if bool(sp.get("sole", false)):
		# the bottom of the foot: straight down from the bone to the floor, measured on this rig's rest pose, so it fits every fighter
		var rest_b := skel.get_bone_global_rest(bone)
		o += rest_b.basis.inverse() * Vector3(0.0, -rest_b.origin.y, 0.0)
	var ex: Array = sp.get("extra", [0, 0, 0])
	return o + Vector3(float(ex[0]), float(ex[1]), float(ex[2]))
