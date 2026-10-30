extends CBMatch
## Real matches, measured (RMT Wrap C3): two CPUs fight on a stage and every frame, on the pose you see, it counts limbs inside
## the stage's solid decks, limbs inside the other fighter's body and trunks overlapping. Changes nothing.
##   godot --headless --fixed-fps 60 --path . res://game/packs/city_breaker/tools/match_clash.tscn -- [--pair=vix:carter]
##       [--stage=marina] [--frames=1800] [--no-wraps] [--out=C:/Dev/wrap_out/match_clash.txt]   (one pair per run; appends a line)
## With --no-wraps the clips play as keyed (the before); without it the Body Solve runs against the body, the stage and the
## other fighter (the after).

var _pairs: Array = [["vix", "carter"]]
var _stage := "marina"
var _frames := 1800
var _out := "C:/Dev/wrap_out/match_clash.txt"
var _bodies := {}   # fighter -> RmtWrapBody (measuring only, so the before has capsules too)
var _deep_prints := 0     # --debug: print the first few deep stage contacts in full


func _ready() -> void:
	set_physics_process(false)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--pair="):
			_pairs = [Array(a.substr(7).split(":"))]
		elif a.begins_with("--stage="):
			_stage = a.substr(8)
		elif a.begins_with("--frames="):
			_frames = int(a.substr(9))
		elif a.begins_with("--out="):
			_out = a.substr(6)
		elif a == "--debug":
			_deep_prints = 3
	_run.call_deferred()


func _run() -> void:
	var lines: PackedStringArray = ["wraps %s, stage %s, %d frames per pair, depths over 2 cm (feet 4 cm)" % ["on" if CBWraps.enabled else "OFF (as keyed)", _stage, _frames]]
	var total := {"stage": 0, "body": 0, "trunk": 0, "frames": 0}
	for pr in _pairs:
		start({"p1": pr[0], "p2": pr[1], "stage": _stage, "stocks": 99, "cpu_p1": 3, "cpu_p2": 3, "items": 0, "seed": 7})
		set_physics_process(false)
		phase = "fight"
		for f in fighters:
			(f as CBFighter).freeze(false)
		cam._intro = 0
		_bodies.clear()
		for f in fighters:
			var ft := f as CBFighter
			_bodies[ft] = RmtWrapBody.new(RmtWrapBody.load_wrap(CBWraps.WRAPS % ft.key), ft.skel)
		var c := {"stage": 0, "body": 0, "trunk": 0}
		var worst := {"stage": [0.0, ""], "body": [0.0, ""], "trunk": [0.0, ""]}
		for n in _frames:
			await get_tree().physics_frame
			_step()
			var m := _measure()
			for k in m:
				if float(m[k][0]) > 0.0:
					c[k] = int(c[k]) + 1
					if float(m[k][0]) > float(worst[k][0]):
						worst[k] = m[k]
		var line := "%s vs %s: frames with limbs in the stage %d, in the other body %d, trunks overlapping %d  (worst %.0f cm %s | %.0f cm %s | %.0f cm)" % [
			pr[0], pr[1], c["stage"], c["body"], c["trunk"], float(worst["stage"][0]) * 100.0, worst["stage"][1],
			float(worst["body"][0]) * 100.0, worst["body"][1], float(worst["trunk"][0]) * 100.0]
		print(line)
		lines.append(line)
		# the fight itself (positions, damage, stocks): identical with and without the wraps when they only change what you see
		var game := PackedStringArray()
		for f in fighters:
			var ft := f as CBFighter
			game.append("%s x %.4f y %.4f %.1f%% stocks %d" % [ft.key, ft.global_position.x, ft.global_position.y, ft.percent, ft.stocks])
		lines.append("  game at the end: " + " | ".join(game))
		for k in c:
			total[k] = int(total[k]) + int(c[k])
		total["frames"] = int(total["frames"]) + _frames
	var fo := FileAccess.open(_out, FileAccess.READ_WRITE) if FileAccess.file_exists(_out) else FileAccess.open(_out, FileAccess.WRITE)
	fo.seek_end()
	fo.store_string("\n".join(lines) + "\n")
	fo.close()
	get_tree().quit()


## this frame, on the pose you see: {"stage": [depth, what], "body": [...], "trunk": [...]}
func _measure() -> Dictionary:
	var out := {"stage": [0.0, ""], "body": [0.0, ""], "trunk": [0.0, ""]}
	var space := get_world_3d().direct_space_state
	var caps := {}
	for f in fighters:
		caps[f] = (_bodies[f] as RmtWrapBody).capsules()
	for f in fighters:
		var ft := f as CBFighter
		if not ft.alive:
			continue
		var body: RmtWrapBody = _bodies[ft]
		var mine: Array = caps[ft]
		for i in body.pieces.size():
			var cp: Array = mine[i]
			var id := str(body.pieces[i]["id"])
			# the stage's solid decks
			var allow := 0.04 if id.begins_with("foot") else 0.02
			var cs := CapsuleShape3D.new()
			cs.radius = float(cp[2])
			cs.height = (cp[0] as Vector3).distance_to(cp[1]) + 2.0 * float(cp[2])
			var y := ((cp[1] as Vector3) - (cp[0] as Vector3)).normalized() if (cp[0] as Vector3).distance_to(cp[1]) > 1e-5 else Vector3.UP
			var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
			var q := PhysicsShapeQueryParameters3D.new()
			q.shape = cs
			q.transform = Transform3D(Basis(x, y, x.cross(y)), ((cp[0] as Vector3) + (cp[1] as Vector3)) * 0.5)
			q.collision_mask = 1
			q.exclude = [ft.get_rid()]
			var res := space.collide_shape(q, 2)
			for k in res.size() / 2:
				var d := ((res[k * 2 + 1] as Vector3) - (res[k * 2] as Vector3)).length() - allow
				if _deep_prints > 0 and d > 0.3:
					_deep_prints -= 1
					print("DEEP %s %s %s: fighter at %s grounded %s, capsule a %s b %s r %.3f, contact %s -> %s" % [ft.key, CBFighter.St.keys()[ft.st], id,
						str(ft.global_position), ft.grounded, str(cp[0]), str(cp[1]), float(cp[2]), str(res[k * 2]), str(res[k * 2 + 1])])
				if d > float(out["stage"][0]):
					out["stage"] = [d, "%s %s %s" % [ft.key, CBFighter.St.keys()[ft.st], id]]
			# the other fighter's body (limbs, head, tails into it; a grab partner is left out)
			if int(body.pieces[i]["rank"]) < 2:
				continue
			for o in fighters:
				var of := o as CBFighter
				if of == ft or not of.alive or ft.catch_target == of or of.catch_target == ft:
					continue
				for oc in caps[of]:
					var ov := RmtCapsule.overlap(cp[0], cp[1], cp[2], oc[0], oc[1], oc[2])
					var d2 := float(ov["depth"]) - 0.02
					if d2 > float(out["body"][0]):
						out["body"] = [d2, "%s %s %s" % [ft.key, CBFighter.St.keys()[ft.st], id]]
	# trunks (grounded, as the jostle sees them)
	if fighters.size() >= 2:
		var a := fighters[0] as CBFighter
		var b := fighters[1] as CBFighter
		if a.alive and b.alive and a.grounded and b.grounded:
			var t := _trunks(caps[a], _bodies[a], caps[b], _bodies[b]) - 0.02
			if t > 0.0:
				out["trunk"] = [t, ""]
	return out


func _trunks(ca: Array, ba: RmtWrapBody, cb: Array, bb: RmtWrapBody) -> float:
	var worst := 0.0
	for i in ca.size():
		if int(ba.pieces[i]["rank"]) > 1:
			continue
		for j in cb.size():
			if int(bb.pieces[j]["rank"]) > 1:
				continue
			var x: Array = ca[i]
			var y: Array = cb[j]
			var o := RmtCapsule.overlap(Vector3((x[0] as Vector3).x, (x[0] as Vector3).y, 0.0), Vector3((x[1] as Vector3).x, (x[1] as Vector3).y, 0.0), x[2],
				Vector3((y[0] as Vector3).x, (y[0] as Vector3).y, 0.0), Vector3((y[1] as Vector3).x, (y[1] as Vector3).y, 0.0), y[2])
			worst = maxf(worst, float(o["depth"]))
	return worst
