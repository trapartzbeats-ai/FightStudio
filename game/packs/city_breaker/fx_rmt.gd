class_name CBFxRmt
extends RefCounted
## Combat effects from the RMT Effects add-on, aimed with the fighter sockets (sockets.gd) and the table in data/fx.json.
##   CBFxRmt.event(world, "land", fighter.socket_pos("ground_L"))
##   CBFxRmt.hit(world, dmg, hit_point, away_x, knockback)
##   var fx := CBFxRmt.follow(fighter, "shield")      # looping effect riding a socket
##   CBFxRmt.unfollow(fx)

const DATA := "res://game/packs/city_breaker/data/fx.json"
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


static func event(world: Node, name: String, at: Vector3, scale_mul: float = 1.0, yaw_deg: float = 0.0) -> void:
	_play_list(world, data().get(name, []), at, scale_mul, yaw_deg)


static func hit(world: Node, dmg: float, at: Vector3, away_x: float, kb: float) -> void:
	var yaw := 0.0 if away_x >= 0.0 else 180.0
	for tier in (data().get("hit", []) as Array):
		if dmg <= float(tier["max_dmg"]):
			_play_list(world, tier["fx"], at, 1.0, yaw)
			break
	if kb >= 110.0:
		_play_list(world, data().get("big_launch", []), at, clampf(kb / 160.0, 0.8, 1.6), yaw)


static func _play_list(world: Node, list: Array, at: Vector3, scale_mul: float, yaw_deg: float) -> void:
	if world == null or not world.is_inside_tree():
		return
	for e in list:
		play_named(world, str(e[0]), at, float(e[1]) * scale_mul, yaw_deg)


## an RMT effect id OR a combo (data/fx_combos.json: a name -> [[effect id, scale, delay s], ...]) at a point
static func play_named(world: Node, name: String, at: Vector3, scale_mul: float = 1.0, yaw_deg: float = 0.0) -> void:
	if world == null or not world.is_inside_tree():
		return
	var combo: Array = combos().get(name, [])
	if combo.is_empty():
		var fx: Node3D = Rmtfx.play(name, at, Vector3(0.0, yaw_deg, 0.0))
		if fx != null:
			fx.scale = Vector3.ONE * scale_mul
		return
	for layer in combo:
		var id := str(layer[0])
		var sc := float(layer[1]) * scale_mul
		var delay := float(layer[2]) if layer.size() > 2 else 0.0
		if delay <= 0.0:
			play_named(world, id, at, sc, yaw_deg)
		else:
			world.get_tree().create_timer(delay).timeout.connect(func() -> void:
				if is_instance_valid(world) and world.is_inside_tree():
					play_named(world, id, at, sc, yaw_deg))


const COMBOS := "res://game/packs/city_breaker/data/fx_combos.json"
static var _combos: Dictionary = {}
static var _combos_loaded := false


static func combos(force: bool = false) -> Dictionary:
	if not _combos_loaded or force:
		_combos_loaded = true
		_combos = {}
		var f := FileAccess.open(COMBOS, FileAccess.READ)
		if f != null:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			f.close()
			if typeof(parsed) == TYPE_DICTIONARY:
				_combos = (parsed as Dictionary).get("combos", {})
	return _combos


static func save_combos() -> int:
	var f := FileAccess.open(COMBOS, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify({"note": "Effect combos made in the Studio: name -> [[RMT effect id, scale, delay seconds], ...]. Usable anywhere an effect id is (fx.json, clip cues).", "combos": combos()}, "  "))
	f.close()
	return OK


## play a clip cue (data/clip_fx.json) from a fighter: "burst" at the socket now, "follow" rides the socket for `dur` seconds
static func cue(world: Node, fighter: Node3D, c: Dictionary) -> void:
	var sock := str(c.get("socket", "mid"))
	var yaw := 0.0
	if fighter.has_method("socket_pos") and "facing" in fighter:
		yaw = 0.0 if float(fighter.facing) >= 0.0 else 180.0
	var id := str(c.get("fx", ""))
	var sc := float(c.get("scale", 1.0))
	if str(c.get("mode", "burst")) == "follow" and fighter.has_method("socket") and not combos().has(id):
		var node: Node3D = fighter.call("socket", sock)
		if node != null:
			var fx: Node3D = load("res://addons/rmt_effects/rmt_effect.gd").spawn(id, node, Vector3.ZERO)
			if fx != null:
				fx.scale = Vector3.ONE * sc
				fighter.get_tree().create_timer(maxf(float(c.get("dur", 0.5)), 0.05)).timeout.connect(func() -> void: unfollow(fx))
			return
	var at: Vector3 = fighter.call("socket_pos", sock) if fighter.has_method("socket_pos") else fighter.global_position
	if fighter.has_method("socket_zone"):
		at += scatter(fighter.call("socket_zone", sock))
	play_named(world, id, at, sc, yaw)


## a random point inside a socket zone ({radius, falloff}); closer to the centre more often when the falloff is not constant
static func scatter(zone: Dictionary) -> Vector3:
	var r := float(zone.get("radius", 0.0))
	if r <= 0.0:
		return Vector3.ZERO
	for i in 8:
		var p := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1))
		if p.length() <= 1.0 and randf() <= CBSockets.falloff(str(zone.get("falloff", "smooth")), p.length()):
			return p * r
	return Vector3.ZERO


## a looping effect parented to a fighter socket (follows every animation frame); null if the effect or socket is missing
static func follow(fighter: Node3D, name: String) -> Node3D:
	var spec: Array = (data().get("follow", {}) as Dictionary).get(name, [])
	if spec.is_empty() or not fighter.has_method("socket"):
		return null
	var sock: Node3D = fighter.call("socket", str(spec[1]))
	if sock == null and str(spec[1]).begins_with("ground"):
		sock = fighter   # ground sockets are floor points, not nodes: the fighter's own origin IS the zero point at the feet
	if sock == null:
		return null
	var node: Node3D = load("res://addons/rmt_effects/rmt_effect.gd").spawn(str(spec[0]), sock, Vector3.ZERO)
	if node != null:
		node.scale = Vector3.ONE * float(spec[2])
	return node


static func unfollow(node: Node3D) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node.has_method("stop"):
		node.call("stop")
	var tree := node.get_tree()
	if tree != null:
		tree.create_timer(0.8).timeout.connect(func() -> void:
			if is_instance_valid(node):
				node.queue_free())
	else:
		node.queue_free()
