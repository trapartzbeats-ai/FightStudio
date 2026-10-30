extends SceneTree
## Spring chains (tails, ears, crests, poms, fins) against the body, with the springs simulating (RMT Wrap C2). Each fighter
## runs a set of clips twice: springs free (as before) and springs with the wrap's colliders; after the springs move each frame
## it measures how deep any chain piece is inside the rest of the body. Changes nothing.
##   godot --headless --fixed-fps 60 --path . --script res://game/packs/city_breaker/tools/spring_clash.gd [-- --who=vix]

const CLIPS := ["a_wait", "a_walk", "a_run", "a_dash", "a_escape_f", "a_escape_b", "a_fsmash", "a_dash_attack", "a_jump_f", "a_land",
	"a_special_punch", "a_damage_fall", "w_walk", "w_run"]

var who := ""
var verbose := false
var _probe: CBWrapPose
var _chain := {}
var _last: Array = []    # clashes measured inside the last skeleton update (the springs' results only exist there)


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--who="):
			who = a.substr(6)
		elif a == "--verbose":
			verbose = true
	_run.call_deferred()


## inside the skeleton update, after the springs: chain pieces against the rest of the body
func _measure() -> void:
	var out: Array = []
	for x in _probe.body.clashes(0.01):
		if _chain.has(x["i"]) != _chain.has(x["j"]):
			out.append(x)
	_last = out


func _run() -> void:
	var fams: Array = ["tail", "ear", "crest", "pom", "fin"]
	var lines: PackedStringArray = []
	var pair_lines := {}
	for key in CBRoster.keys():
		if who != "" and key != who:
			continue
		var res := {}
		for collide in [false, true]:
			var fp := CBWrapPose.new(key, root)
			var sims := CBSecondary.build_specs(fp.skel, CBSecondary.all_specs(key), key, collide)
			if verbose:
				printerr("%s collide=%s sims=%s" % [key, collide, sims.keys()])
			var chain_pieces := {}
			for i in fp.body.pieces.size():
				var bn := fp.skel.get_bone_name(int(fp.body.pieces[i]["bone_idx"]))
				for name in sims:
					var sim: SpringBoneSimulator3D = sims[name]
					if not RmtWrapFit.family(sim.get_root_bone_name(0)) in fams:
						continue
					for j in sim.get_joint_count(0):
						if sim.get_joint_bone_name(0, j) == bn:
							chain_pieces[i] = true
			if chain_pieces.is_empty():
				fp.model.queue_free()
				break
			if verbose:
				printerr("chain pieces: %s" % str(chain_pieces.keys()))
			_probe = fp
			_chain = chain_pieces
			fp.skel.skeleton_updated.connect(_measure)
			var worst := 0.0
			var by_pair := {}
			var where := ""
			var bad := 0
			var frames := 0
			for nm in CLIPS:
				var c := CBAnim.clip(CBAnim.own(key, nm))
				if c.is_empty():
					continue
				CBSecondary.reset(fp.skel)
				var t0 := Time.get_ticks_msec()
				for f in int(c.get("frames", 0)) + 1:
					fp.pose(c, float(f), true)
					fp.skel.set_bone_pose_rotation(0, fp.skel.get_bone_pose_rotation(0))   # the skeleton updates (springs run) this frame
					_last = []
					await process_frame
					var w := 0.0
					var fams_hit := {}
					for x in _last:
						if collide and chain_pieces.has(x["i"]) != chain_pieces.has(x["j"]):
							var pk := "%s-%s" % [RmtWrapFit.family(str(fp.body.pieces[x["i"]]["id"])), RmtWrapFit.family(str(fp.body.pieces[x["j"]]["id"]))]
							fams_hit[pk] = true
						if chain_pieces.has(x["i"]) != chain_pieces.has(x["j"]):
							w = maxf(w, float(x["excess"]))
							if float(x["excess"]) > worst:
								worst = float(x["excess"])
								where = "%s f%d %s/%s" % [nm, f, fp.body.pieces[x["i"]]["id"], fp.body.pieces[x["j"]]["id"]]
					if w > 0.0:
						bad += 1
					for pk in fams_hit:
						by_pair[pk] = int(by_pair.get(pk, 0)) + 1
					frames += 1
				if verbose:
					printerr("  %s %s %s: %d frames in %d ms" % [key, "colliding" if collide else "free", nm, int(c.get("frames", 0)) + 1, Time.get_ticks_msec() - t0])
			res[collide] = [bad, frames, worst, where]
			if collide and not by_pair.is_empty():
				var ks: Array = by_pair.keys()
				ks.sort_custom(func(a: String, b: String) -> bool: return int(by_pair[a]) > int(by_pair[b]))
				var parts: PackedStringArray = []
				for pk in ks.slice(0, 6):
					parts.append("%s %d" % [pk, by_pair[pk]])
				pair_lines[key] = ", ".join(parts)
			fp.model.queue_free()
			await process_frame
		if res.size() == 2:
			var a: Array = res[false]
			var b: Array = res[true]
			var line := "%s: frames with a chain inside the body  free %d/%d (worst %.1f cm %s)  ->  colliding %d/%d (worst %.1f cm %s)" % [
				key, a[0], a[1], float(a[2]) * 100.0, a[3], b[0], b[1], float(b[2]) * 100.0, b[3]]
			if pair_lines.has(key):
				line += "
    still touching (frames): " + str(pair_lines[key])
			print(line)
			lines.append(line)
	DirAccess.make_dir_recursive_absolute("C:/Dev/wrap_out")
	var f := FileAccess.open("C:/Dev/wrap_out/spring_clash.txt", FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	quit()
