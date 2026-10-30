extends SceneTree
## Clash report (RMT Wrap C0): every clip a fighter plays, frame by frame, on its Collision Wrap. Lists each body part that goes
## into the fighter's own body deeper than it does at rest, and each part pushed under the floor in a planted clip. Lengths are
## world metres at the fighter's match height. Changes nothing.
##   godot --headless --path . --script res://game/packs/city_breaker/tools/body_clash.gd -- --out=C:/Dev/wrap_out [--who=vix] [--tol=0.01] [--solve]
## Writes <out>/body_clash.json (every clash) and <out>/body_clash.md (the summary, worst first); with --solve the Body Solve runs
## on every frame first (frames in order, as a match plays them) and the files are body_clash_solved.*

var out := "C:/Dev/wrap_out"
var who := ""
var tol := 0.01
var solve := false


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--who="):
			who = a.substr(6)
		elif a == "--solve":
			solve = true
		elif a.begins_with("--tol="):
			tol = float(a.substr(6))
	_run.call_deferred()


## the clips a fighter plays: its own a_<key>_*, the shared a_* it has no own version of, and the open-world w_*
static func clips_for(key: String, all: Array, keys: Array) -> Array:
	var out: Array = []
	for n in all:
		var name := str(n)
		if name.begins_with("a_%s_" % key) or name.begins_with("w_"):
			out.append(name)
		elif name.begins_with("a_"):
			var other := false
			for k in keys:
				if name.begins_with("a_%s_" % k):
					other = true
					break
			if not other and CBAnim.own(key, name) == name:
				out.append(name)
	return out


func _run() -> void:
	var t0 := Time.get_ticks_msec()
	var keys: Array = CBRoster.keys()
	var all := CBClipLib.list_clips()
	var report := {"tol": tol, "fighters": {}}
	var rows: Array = []        # every clash: [excess_cm, key, clip, kind, what, frames]
	var frames_total := 0
	var max_corr := 0.0
	var max_lift := 0.0
	var big := {}   # "fighter bone" -> largest correction (degrees) over 80
	var tag := "_solved" if solve else ""
	var rig: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CBWrapPose.RIG))
	var limits: Dictionary = rig.get("limits", {})
	for key in keys:
		if who != "" and key != who:
			continue
		var fp := CBWrapPose.new(key, root)
		var body := fp.body
		var fr := {"clips": 0, "clips_self": 0, "clips_floor": 0, "frames": 0}
		for name in clips_for(key, all, keys):
			var c := CBClipLib.load_clip(name)
			if c.is_empty():
				continue
			var n := int(c.get("frames", 0))
			var worst_self := {}    # "a|b" -> [excess, first, last, count]
			var worst_floor := {}   # piece id -> [excess, first, last, count]
			var worst_bend := {}    # "bone axis" -> [radians past the limit, first, last, count] (the clip's own keys)
			fp.solver.reset()
			if solve:
				for _w in 8:   # in a match the solve is already running when a clip starts: settle on frame 0 first
					fp.pose(c, 0.0, true)
			for f in n + 1:
				var planted := fp.pose(c, float(f), solve)
				if solve:
					var mc := float(fp.last_solve.get("max_corr", 0.0))
					if mc > deg_to_rad(80.0):
						var bk := "%s %s" % [key, fp.last_solve["max_corr_bone"]]
						big[bk] = maxf(float(big.get(bk, 0.0)), rad_to_deg(mc))
					max_corr = maxf(max_corr, mc)
					max_lift = maxf(max_lift, float(fp.last_solve.get("lift", 0.0)))
				var cl := fp.clashes(tol, planted)
				for x in cl["self"]:
					_note(worst_self, "%s|%s" % [body.pieces[x["i"]]["id"], body.pieces[x["j"]]["id"]], float(x["excess"]), f)
				for u in cl["floor"]:
					_note(worst_floor, str(body.pieces[u["i"]]["id"]), float(u["excess"]), f)
				if not solve:
					for bn in limits:
						if not fp.bones.has(bn):
							continue
						var e := CBClipLib.bone_rot(fp.last_pose, str(bn))
						for ai in 3:
							var ax: String = ["x", "y", "z"][ai]
							if (limits[bn] as Dictionary).has(ax):
								var r: Array = limits[bn][ax]
								var over := maxf(float(r[0]) - e[ai], e[ai] - float(r[1]))
								if over > 0.05:
									_note(worst_bend, "%s %s" % [bn, ax], over, f)
				frames_total += 1
				fr["frames"] = int(fr["frames"]) + 1
			fr["clips"] = int(fr["clips"]) + 1
			if not worst_self.is_empty():
				fr["clips_self"] = int(fr["clips_self"]) + 1
			if not worst_floor.is_empty():
				fr["clips_floor"] = int(fr["clips_floor"]) + 1
			for k in worst_self:
				var w: Array = worst_self[k]
				rows.append([snappedf(float(w[0]) * 100.0, 0.1), key, name, "self", k, "%d-%d (%d) worst %d" % [w[1], w[2], w[3], w[4]]])
			for k in worst_bend:
				var w3: Array = worst_bend[k]
				rows.append([snappedf(rad_to_deg(float(w3[0])), 0.1), key, name, "bend", k, "%d-%d (%d) worst %d" % [w3[1], w3[2], w3[3], w3[4]]])
			for k in worst_floor:
				var w2: Array = worst_floor[k]
				rows.append([snappedf(float(w2[0]) * 100.0, 0.1), key, name, "floor", k, "%d-%d (%d) worst %d" % [w2[1], w2[2], w2[3], w2[4]]])
		report["fighters"][key] = fr
		print("%s: %d clips, %d with self clashes, %d with floor clashes" % [key, fr["clips"], fr["clips_self"], fr["clips_floor"]])
		fp.model.queue_free()
		await process_frame
	rows.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) > float(b[0]))
	report["clashes"] = rows
	report["frames"] = frames_total
	report["seconds"] = (Time.get_ticks_msec() - t0) / 1000.0
	report["solve"] = solve
	report["max_corr_deg"] = rad_to_deg(max_corr)
	report["max_lift_m"] = max_lift
	report["big_corrections"] = big
	DirAccess.make_dir_recursive_absolute(out)
	var fj := FileAccess.open(out + "/body_clash%s.json" % tag, FileAccess.WRITE)
	fj.store_string(JSON.stringify(report, " ", false))
	fj.close()
	_write_md(report, rows, tag)
	print("%d frames in %.1f s -> %s" % [frames_total, report["seconds"], out])
	quit()


func _note(d: Dictionary, k: String, ex: float, f: int) -> void:
	if not d.has(k):
		d[k] = [ex, f, f, 1, f]
	else:
		var w: Array = d[k]
		if ex > float(w[0]):
			w[0] = ex
			w[4] = f
		w[2] = f
		w[3] = int(w[3]) + 1


## the family of a piece (handL -> hand) so pair types group across sides and fighters
static func family(id: String) -> String:
	return RmtWrapFit.family(id)


func _write_md(report: Dictionary, all_rows: Array, tag: String) -> void:
	var rows: Array = all_rows.filter(func(r: Array) -> bool: return str(r[3]) != "bend")
	var bends: Array = all_rows.filter(func(r: Array) -> bool: return str(r[3]) == "bend")
	var L: PackedStringArray = []
	L.append("# Body clash report (Collision Wrap)%s" % (" - with the Body Solve" if report["solve"] else " - clip poses as keyed"))
	L.append("")
	L.append("Every clip each fighter plays, every frame, on its Collision Wrap (`data/wraps/<key>.collide.json`). A **self** clash is a")
	L.append("body part going into the fighter's own body deeper than it does at rest; a **floor** clash is a part under the floor in a")
	L.append("planted clip. Depths in cm at match height, tolerance %.1f cm. Frames: first-last (how many)." % (float(report["tol"]) * 100.0))
	L.append("")
	L.append("| fighter | clips | with self clashes | with floor clashes | frames |")
	L.append("|---|---|---|---|---|")
	var tc := 0
	var ts := 0
	var tf := 0
	for k in report["fighters"]:
		var fr: Dictionary = report["fighters"][k]
		L.append("| %s | %d | %d | %d | %d |" % [k, fr["clips"], fr["clips_self"], fr["clips_floor"], fr["frames"]])
		tc += int(fr["clips"])
		ts += int(fr["clips_self"])
		tf += int(fr["clips_floor"])
	L.append("| **all** | **%d** | **%d** | **%d** | **%d** |" % [tc, ts, tf, report["frames"]])
	L.append("")
	# which kinds of parts clash most (pair families, counted once per clip)
	var fam := {}
	for r in rows:
		var kind := str(r[3])
		var what := str(r[4])
		var fk := ""
		if kind == "self":
			var ab := what.split("|")
			var fa := family(ab[0])
			var fb := family(ab[1])
			fk = "%s - %s" % [fa, fb] if fa <= fb else "%s - %s" % [fb, fa]
		else:
			fk = "%s under the floor" % family(what)
		if not fam.has(fk):
			fam[fk] = [0, 0.0]
		fam[fk][0] = int(fam[fk][0]) + 1
		fam[fk][1] = maxf(float(fam[fk][1]), float(r[0]))
	var fl: Array = fam.keys()
	fl.sort_custom(func(a: String, b: String) -> bool: return int(fam[a][0]) > int(fam[b][0]))
	L.append("## What clashes most")
	L.append("")
	L.append("| parts | clips | worst cm |")
	L.append("|---|---|---|")
	for k in fl.slice(0, 30):
		L.append("| %s | %d | %.1f |" % [k, fam[k][0], fam[k][1]])
	L.append("")
	L.append("## Worst 60")
	L.append("")
	L.append("| cm | fighter | clip | kind | parts | frames |")
	L.append("|---|---|---|---|---|---|")
	for r in rows.slice(0, 60):
		L.append("| %.1f | %s | %s | %s | %s | %s |" % [r[0], r[1], r[2], r[3], str(r[4]).replace("|", " / "), r[5]])
	if report["solve"]:
		L.insert(6, "Body Solve on: the largest correction on any bone was %.0f degrees, the largest lift off the floor %.0f cm." % [report["max_corr_deg"], float(report["max_lift_m"]) * 100.0])
		L.insert(7, "")
	if not bends.is_empty():
		L.append("")
		L.append("## Bends past natural limits (the clip's own keys)")
		L.append("")
		L.append("Joints the clip itself turns past the rig limits (`data/animator_rig.json`), in degrees past the limit. The Body Solve")
		L.append("never pushes these further; fixing them is a clip edit (Fight Studio clamps to the limits when you pose).")
		L.append("")
		var byb := {}
		for r in bends:
			var bk := RmtWrapFit.family(str(r[4]).split(" ")[0]) + " " + str(r[4]).split(" ")[1]
			if not byb.has(bk):
				byb[bk] = [0, 0.0]
			byb[bk][0] = int(byb[bk][0]) + 1
			byb[bk][1] = maxf(float(byb[bk][1]), float(r[0]))
		var bl: Array = byb.keys()
		bl.sort_custom(func(a: String, b: String) -> bool: return int(byb[a][0]) > int(byb[b][0]))
		L.append("| joint axis | clips | worst degrees |")
		L.append("|---|---|---|")
		for k in bl:
			L.append("| %s | %d | %.0f |" % [k, byb[k][0], byb[k][1]])
		L.append("")
		L.append("| degrees | fighter | clip | joint axis | frames |")
		L.append("|---|---|---|---|---|")
		for r in bends.slice(0, 40):
			L.append("| %.0f | %s | %s | %s | %s |" % [r[0], r[1], r[2], r[4], r[5]])
	var f := FileAccess.open(out + "/body_clash%s.md" % tag, FileAccess.WRITE)
	f.store_string("\n".join(L) + "\n")
	f.close()
